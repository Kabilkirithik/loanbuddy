import numpy as np
import pytest
from src.layers.layer1_depth import DepthParallaxValidator
from src.models import InspectionVerdict


def test_layer1_detects_flat_surface():
    """Verify that an image representing a flat paper, wall of text, or screen attack is flagged."""
    validator = DepthParallaxValidator()

    # 1. Pure flat surface (wall or uniform screen)
    flat_screen = np.ones((480, 640, 3), dtype=np.uint8) * 180
    res_screen = validator.evaluate(flat_screen)
    assert res_screen.is_flat_surface is True
    assert res_screen.verdict == InspectionVerdict.FAILED
    assert len(res_screen.rejection_reasons) > 0

    # 2. Wall of text document (presentation attack with 2D text)
    import cv2
    doc = np.ones((480, 640, 3), dtype=np.uint8) * 245
    for y in range(40, 440, 30):
        cv2.putText(doc, 'Construction Site Loan Document Approval Stage', (40, y), cv2.FONT_HERSHEY_SIMPLEX, 0.6, (10, 10, 10), 1)

    res_doc = validator.evaluate(doc)
    assert res_doc.is_flat_surface is True
    assert res_doc.verdict == InspectionVerdict.FAILED
    assert len(res_doc.rejection_reasons) > 0


def test_layer1_evaluates_3d_features():
    """Verify that a scene with varied depth structure produces measurable variance."""
    validator = DepthParallaxValidator()

    # Create an image with foreground object and distant background
    scene = np.zeros((480, 640, 3), dtype=np.uint8)
    # Background sky
    scene[:240, :] = [230, 200, 150]
    # Ground
    scene[240:, :] = [60, 90, 40]
    # Foreground columns/rebar
    scene[100:400, 150:200] = [30, 30, 180]
    scene[80:400, 450:500] = [30, 30, 180]

    result = validator.evaluate(scene)
    assert result.depth_std_dev > 0.0
    assert result.plane_fit_r2 >= 0.0
