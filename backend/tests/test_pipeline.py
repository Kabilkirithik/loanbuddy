import numpy as np
import pytest
from src.pipeline import SiteInspectionPipeline
from src.models import (
    LoanApplicationContext,
    GPSCoordinate,
    FinalDecision,
    InspectionVerdict
)


def test_pipeline_end_to_end_rejection():
    """Verify that a flat image submission at wrong coordinates is decisively rejected."""
    pipeline = SiteInspectionPipeline()

    context = LoanApplicationContext(
        loan_id="LN-TEST-001",
        borrower_name="Acme Builders",
        project_name="Metro Heights Lot 4",
        construction_stage="Foundation",
        expected_location=GPSCoordinate(latitude=34.0522, longitude=-118.2437)
    )

    # Device reporting coordinate 5 km away
    bad_gps = GPSCoordinate(latitude=34.0900, longitude=-118.2437)

    # Flat image (screen presentation attack)
    flat_img = np.ones((480, 640, 3), dtype=np.uint8) * 200

    report = pipeline.run_inspection(
        media_input=flat_img,
        loan_context=context,
        live_gps=bad_gps
    )

    assert report.final_decision == FinalDecision.REJECTED
    assert report.layer1_depth.is_flat_surface is True
    assert report.layer3_geospatial.within_geofence is False
    assert len(report.flagged_reasons) > 0
