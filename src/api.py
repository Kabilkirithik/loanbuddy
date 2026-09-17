import os
import shutil
import tempfile
from fastapi import FastAPI, File, UploadFile, Form, HTTPException, status
from fastapi.responses import JSONResponse
import logging

from .config import settings
from .models import (
    LoanApplicationContext,
    GPSCoordinate,
    InspectionReport
)
from .pipeline import SiteInspectionPipeline

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger("vision_agent.api")

app = FastAPI(
    title="Construction Site Inspection Verification Service",
    description="Automated 3-layer anti-fraud verification for construction loan site visits.",
    version="1.0.0"
)

pipeline = SiteInspectionPipeline()


@app.get("/api/v1/health")
def health_check():
    return {
        "status": "online",
        "device": settings.DEVICE,
        "layers": {
            "layer1_depth": "Depth-Anything-V2",
            "layer2_recapture": "Sightengine/Hive + 2D FFT Moiré",
            "layer3_geospatial": "Google Maps Static + LightGlue"
        }
    }


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
