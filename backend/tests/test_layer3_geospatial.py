import numpy as np
import cv2
import pytest
from src.layers.layer3_geospatial import GeospatialValidator
from src.models import GPSCoordinate, InspectionVerdict


def test_haversine_geofence_calculation():
    """Verify GPS distance calculation flags breaches accurately."""
    validator = GeospatialValidator()

    # Loan site: San Francisco City Hall
    site_gps = GPSCoordinate(latitude=37.7793, longitude=-122.4192)
    # Nearby device within 30 meters
    nearby_gps = GPSCoordinate(latitude=37.7795, longitude=-122.4192)
    dist_near = validator.calculate_haversine_distance_m(site_gps, nearby_gps)
    assert dist_near < 50.0

    # Far device: Oakland (~12 km away)
    far_gps = GPSCoordinate(latitude=37.8044, longitude=-122.2712)
    dist_far = validator.calculate_haversine_distance_m(site_gps, far_gps)
    assert dist_far > 10000.0


def test_layer3_geofence_violation_flagged():
    """Verify that a geofence breach triggers rejection."""
    validator = GeospatialValidator()

    site_gps = GPSCoordinate(latitude=37.7793, longitude=-122.4192)
    far_gps = GPSCoordinate(latitude=37.8044, longitude=-122.2712)

    # Simple synthetic image
    user_img = np.ones((400, 400, 3), dtype=np.uint8) * 100

    result = validator.evaluate(user_img, live_gps=far_gps, expected_gps=site_gps)
    assert result.within_geofence is False
    assert result.verdict == InspectionVerdict.FAILED
    assert any("Geofence Violation" in r for r in result.rejection_reasons)
