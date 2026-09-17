import os
import shutil
import tempfile
import json
import hashlib
import time
from typing import List, Optional
from fastapi import FastAPI, File, UploadFile, Form, Header, HTTPException, status
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import JSONResponse
import logging

from .config import settings
from .models import (
    LoanApplicationContext,
    GPSCoordinate,
    InspectionReport,
    SiteSchema,
    MilestoneSchema,
    CaptureEvidenceSchema,
    CaptureResponse
)
from .pipeline import SiteInspectionPipeline

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger("vision_agent.api")

app = FastAPI(
    title="Construction Site Inspection Verification Service",
    description="Automated 3-layer anti-fraud verification for construction loan site visits.",
    version="1.0.0"
)

# Enable CORS for Flutter web, emulator, and LAN devices
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

pipeline = SiteInspectionPipeline()

@app.on_event("startup")
def warmup_models():
    """Pre-warm neural models during server startup so client requests never wait for downloads."""
    try:
        logger.info("Pre-warming Depth-Anything-V2 neural model...")
        _ = pipeline.layer1.pipeline
        logger.info("Vision models warmed up and ready.")
    except Exception as e:
        logger.warning(f"Model pre-warm notice: {e}")

# In-memory registry to prevent reuse/replay attacks (SHA-256 deduplication)
SEEN_IMAGE_HASHES: set = set()

# Pre-registered sites catalogue (matching Flutter SiteRepository)
DEMO_SITES: List[SiteSchema] = [
    SiteSchema(
        id="site_8812",
        label="Plot 14, Bagayam",
        borrower_name="R. Selvakumar",
        loan_account_no="NBF-2291-0087",
        lat=12.9165,
        lng=79.1325,
        allowed_radius_meters=5000.0,
        milestones=[
            MilestoneSchema(
                id="ms_1",
                label="Foundation complete",
                tranche=1,
                amount_paise=45000000,
                status="approved"
            ),
            MilestoneSchema(
                id="ms_2",
                label="Ground floor slab",
                tranche=2,
                amount_paise=60000000,
                status="due",
                last_approved_photo_url=None
            ),
            MilestoneSchema(
                id="ms_3",
                label="Roofing",
                tranche=3,
                amount_paise=55000000,
                status="locked"
            )
        ]
    ),
    SiteSchema(
        id="site_9034",
        label="Shed extension, Kalinjur",
        borrower_name="Meena Traders",
        loan_account_no="NBF-2291-0143",
        lat=12.9498,
        lng=79.1602,
        allowed_radius_meters=90.0,
        milestones=[
            MilestoneSchema(
                id="ms_9",
                label="Steel frame erected",
                tranche=1,
                amount_paise=80000000,
                status="rejected",
                reviewer_note="The frame is clear but the surroundings do not match the registered plot. Shoot from the road-facing corner."
            )
        ]
    )
]


@app.get("/api/v1/health")
@app.get("/v1/health")
def health_check():
    return {
        "status": "online",
        "device": settings.DEVICE,
        "layers": {
            "layer1_depth": "Depth-Anything-V2",
            "layer2_recapture": "Sightengine/Hive + 2D FFT Moiré + C2PA",
            "layer3_geospatial": "ESRI Satellite Tiles + LightGlue"
        },
        "submitted_captures_count": len(SEEN_IMAGE_HASHES)
    }


@app.get("/v1/sites", response_model=List[SiteSchema])
@app.get("/api/v1/sites", response_model=List[SiteSchema])
def get_sites():
    """Returns lender-registered construction sites and milestones for the mobile client."""
    return DEMO_SITES


@app.post("/v1/captures", response_model=CaptureResponse, status_code=status.HTTP_201_CREATED)
async def submit_capture(
    evidence: str = Form(..., description="JSON-encoded CaptureEvidence metadata"),
    image: UploadFile = File(..., description="Stamped JPEG photo from SiteCheck mobile client"),
    x_image_sha256: Optional[str] = Header(None, alias="X-Image-SHA256")
):
    """
    Receives stamped progress photos and cryptographic evidence from the SiteCheck mobile client.
    Executes deduplication, SHA-256 integrity checks, and 3-Layer anti-fraud vision verification.
    """
    try:
        evidence_dict = json.loads(evidence)
        parsed_evidence = CaptureEvidenceSchema(**evidence_dict)
    except Exception as e:
        logger.warning("Failed to parse evidence JSON: %s", str(e))
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail=f"Invalid evidence format: {str(e)}"
        )

    # Read image contents into memory for hashing and temporary disk storage
    image_bytes = await image.read()
    computed_sha256 = hashlib.sha256(image_bytes).hexdigest()

    # 1. Header Integrity Check
    expected_hash = x_image_sha256 or parsed_evidence.image_sha256
    if expected_hash and expected_hash.lower() != computed_sha256.lower():
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST,
            detail="Image SHA-256 digest does not match the uploaded payload (tampering detected)."
        )

    # 2. Duplicate Detection (HTTP 409 Conflict)
    if computed_sha256 in SEEN_IMAGE_HASHES:
        raise HTTPException(
            status_code=status.HTTP_409_CONFLICT,
            detail="This photo has already been submitted. Take a new one."
        )

    # Mark hash as seen
    SEEN_IMAGE_HASHES.add(computed_sha256)

    # Resolve site details
    site_match = next((s for s in DEMO_SITES if s.id == parsed_evidence.site_id), None)
    expected_lat = site_match.lat if site_match else parsed_evidence.lat
    expected_lng = site_match.lng if site_match else parsed_evidence.lng
    borrower = site_match.borrower_name if site_match else "Registered Borrower"
    project = site_match.label if site_match else f"Site {parsed_evidence.site_id}"

    # Write temporary file for vision pipeline
    suffix = os.path.splitext(image.filename)[-1] or ".jpg"
    with tempfile.NamedTemporaryFile(delete=False, suffix=suffix) as temp_file:
        temp_file.write(image_bytes)
        temp_path = temp_file.name

    try:
        loan_context = LoanApplicationContext(
            loan_id=parsed_evidence.site_id,
            borrower_name=borrower,
            project_name=project,
            construction_stage=parsed_evidence.milestone_id,
            disbursement_amount_usd=50000.0,
            expected_location=GPSCoordinate(
                latitude=expected_lat,
                longitude=expected_lng
            )
        )

        live_gps = GPSCoordinate(
            latitude=parsed_evidence.lat,
            longitude=parsed_evidence.lng,
            accuracy_m=parsed_evidence.accuracy_meters
        )

        report = pipeline.run_inspection(
            media_input=temp_path,
            loan_context=loan_context,
            live_gps=live_gps
        )

        capture_ref = f"CAP-{parsed_evidence.site_id}-{int(time.time())}"
        return CaptureResponse(
            capture_ref=capture_ref,
            status=report.final_decision.value,
            report=report,
            message="Inspection completed successfully."
        )

    except Exception as e:
        logger.exception("Inspection verification failed")
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail=f"Verification pipeline failed: {str(e)}"
        )
    finally:
        if os.path.exists(temp_path):
            os.remove(temp_path)


@app.post("/api/v1/inspect", response_model=InspectionReport)
async def inspect_site(
    file: UploadFile = File(..., description="Keyframe image or construction site video file (mp4, jpg, png)"),
    loan_id: str = Form(...),
    borrower_name: str = Form(...),
    project_name: str = Form(...),
    construction_stage: str = Form("Foundation"),
    disbursement_amount_usd: float = Form(0.0),
    expected_latitude: float = Form(...),
    expected_longitude: float = Form(...),
    live_latitude: float = Form(...),
    live_longitude: float = Form(...),
    live_accuracy_m: float = Form(5.0)
):
    """Run full 3-layer site verification on submitted media and loan location context."""
    suffix = os.path.splitext(file.filename)[-1] or ".mp4"
    with tempfile.NamedTemporaryFile(delete=False, suffix=suffix) as temp_file:
        shutil.copyfileobj(file.file, temp_file)
        temp_path = temp_file.name

    try:
        loan_context = LoanApplicationContext(
            loan_id=loan_id,
            borrower_name=borrower_name,
            project_name=project_name,
            construction_stage=construction_stage,
            disbursement_amount_usd=disbursement_amount_usd,
            expected_location=GPSCoordinate(
                latitude=expected_latitude,
                longitude=expected_longitude
            )
        )

        live_gps = GPSCoordinate(
            latitude=live_latitude,
            longitude=live_longitude,
            accuracy_m=live_accuracy_m
        )

        report = pipeline.run_inspection(
            media_input=temp_path,
            loan_context=loan_context,
            live_gps=live_gps
        )

        return report

    except Exception as e:
        logger.exception("Inspection execution failed")
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail=f"Verification pipeline failed: {str(e)}"
        )
    finally:
        if os.path.exists(temp_path):
            os.remove(temp_path)

