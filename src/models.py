from enum import Enum
from typing import List, Optional, Dict, Any
from pydantic import BaseModel, Field


class InspectionVerdict(str, Enum):
    PASSED = "PASSED"
    FAILED = "FAILED"
    WARNING = "WARNING"
    SKIPPED = "SKIPPED"


class FinalDecision(str, Enum):
    APPROVED = "APPROVED"
    FLAGGED_FOR_MANUAL_REVIEW = "FLAGGED_FOR_MANUAL_REVIEW"
    REJECTED = "REJECTED"


class GPSCoordinate(BaseModel):
    latitude: float = Field(..., ge=-90.0, le=90.0, description="Latitude in decimal degrees")
    longitude: float = Field(..., ge=-180.0, le=180.0, description="Longitude in decimal degrees")
    altitude_m: Optional[float] = Field(default=None, description="Altitude in meters above sea level")
    accuracy_m: Optional[float] = Field(default=None, description="Reported GPS horizontal accuracy in meters")


class LoanApplicationContext(BaseModel):
    loan_id: str = Field(..., description="Unique identifier for the loan application")
    borrower_name: str = Field(..., description="Borrower or developer name")
    project_name: str = Field(..., description="Construction project name or address")
    expected_location: GPSCoordinate = Field(..., description="Official registered coordinates from loan deeds")
    construction_stage: str = Field(
        default="Foundation",
        description="Target milestone to verify (e.g., Foundation, Plinth, Framing, Roofing, Finishing)"
    )
    disbursement_amount_usd: Optional[float] = Field(
        default=None,
        description="Requested disbursement amount pending stage approval"
    )


# Layer 1 Data Models
class Layer1DepthResult(BaseModel):
    verdict: InspectionVerdict
    is_flat_surface: bool = Field(
        ...,
        description="True if depth map indicates a 2D plane attack (e.g. phone/monitor screen or paper photo)"
    )
    depth_std_dev: float = Field(..., description="Normalized standard deviation of relative depth")
    plane_fit_r2: float = Field(..., description="R^2 correlation coefficient for 3D plane fit (higher = flatter)")
    parallax_score: Optional[float] = Field(
        default=None,
        description="Parallax motion variance score across consecutive video keyframes"
    )
    evaluated_frames_count: int = Field(default=1)
    details: Dict[str, Any] = Field(default_factory=dict)
    rejection_reasons: List[str] = Field(default_factory=list)


# Layer 2 Data Models
class Layer2RecaptureResult(BaseModel):
    verdict: InspectionVerdict
    screen_recapture_detected: bool = Field(
        ...,
        description="True if digital recapture (screen shooting, moiré pattern) was detected"
    )
    ai_generation_detected: bool = Field(
        ...,
        description="True if generative AI / deepfake synthesis artifacts were detected"
    )
    screen_recapture_score: float = Field(..., ge=0.0, le=1.0, description="Confidence score for screen recapture")
    ai_generation_score: float = Field(..., ge=0.0, le=1.0, description="Confidence score for AI-generated media")
    local_moire_energy: float = Field(..., ge=0.0, le=1.0, description="Local spectral peak energy from 2D FFT")
    provider_used: str = Field(..., description="Provider: 'sightengine', 'hive', or 'local_fallback'")
    details: Dict[str, Any] = Field(default_factory=dict)
    rejection_reasons: List[str] = Field(default_factory=list)


# Layer 3 Data Models
class Layer3GeospatialResult(BaseModel):
    verdict: InspectionVerdict
    gps_distance_meters: float = Field(..., description="Computed distance between live GPS and loan site")
    within_geofence: bool = Field(..., description="True if within configured tolerance radius")
    reference_source: str = Field(
        ...,
        description="Source of reference imagery: 'google_maps_satellite', 'google_maps_streetview', or 'cached_ref'"
    )
    total_keypoints_found: int = Field(default=0)
    lightglue_matches_count: int = Field(..., description="Number of matched structural keypoints")
    ransac_inliers_count: int = Field(..., description="Number of geometrically consistent inliers")
    structural_alignment_score: float = Field(
        ...,
        ge=0.0,
        le=1.0,
        description="Structural alignment confidence score"
    )
    details: Dict[str, Any] = Field(default_factory=dict)
    rejection_reasons: List[str] = Field(default_factory=list)


# Overall Pipeline Report
class InspectionReport(BaseModel):
    inspection_id: str
    loan_id: str
    final_decision: FinalDecision
    overall_confidence_score: float = Field(
        ...,
        ge=0.0,
        le=1.0,
        description="Aggregated integrity score across all three security layers"
    )
    executive_summary: str
    layer1_depth: Layer1DepthResult
    layer2_recapture: Layer2RecaptureResult
    layer3_geospatial: Layer3GeospatialResult
    flagged_reasons: List[str] = Field(default_factory=list)
    timestamp: str
    recommended_action: str


# Flutter Mobile Client Schemas (sitecheck integration)
class MilestoneSchema(BaseModel):
    id: str
    label: str
    tranche: int
    amount_paise: int
    status: str = "due"  # "locked", "due", "inReview", "approved", "rejected"
    last_approved_photo_url: Optional[str] = None
    reviewer_note: Optional[str] = None


class SiteSchema(BaseModel):
    id: str
    label: str
    borrower_name: str
    loan_account_no: str
    lat: float
    lng: float
    allowed_radius_meters: float = 75.0
    milestones: List[MilestoneSchema] = Field(default_factory=list)


class CaptureEvidenceSchema(BaseModel):
    site_id: str
    milestone_id: str
    lat: float
    lng: float
    accuracy_meters: float
    distance_from_site_meters: float
    mock_location_detected: bool
    captured_at_device: str
    device_model: str
    device_id: str
    image_sha256: str
    image_bytes: int
    borrower_note: Optional[str] = None


class CaptureResponse(BaseModel):
    capture_ref: str
    status: str
    report: Optional[InspectionReport] = None
    message: Optional[str] = None

