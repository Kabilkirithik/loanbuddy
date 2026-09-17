import numpy as np
import pytest
from src.layers.layer2_recapture import DigitalRecaptureValidator
from src.models import InspectionVerdict


def test_layer2_detects_moire_pattern():
    """Verify that synthetic periodic monitor subpixel grid triggers Moiré detection."""
    validator = DigitalRecaptureValidator()

    # Generate synthetic high-frequency periodic grid (screen subpixel matrix)
    size = 512
    x = np.arange(size)
    y = np.arange(size)
    xx, yy = np.meshgrid(x, y)
    # High frequency sinusoidal grid
    grid = (np.sin(2 * np.pi * xx / 4.0) + np.sin(2 * np.pi * yy / 4.0)) * 100 + 128
    screen_sim = np.clip(grid, 0, 255).astype(np.uint8)
    screen_bgr = np.stack([screen_sim, screen_sim, screen_sim], axis=-1)

    result = validator.evaluate(screen_bgr)
    assert result.local_moire_energy > 0.4
    assert result.screen_recapture_score > 0.4


def test_layer2_natural_image_baseline():
    """Verify that a natural smooth/noisy gradient passes without screen recapture flags."""
    validator = DigitalRecaptureValidator()

    # Generate a natural gradient with mild random noise
    grad = np.linspace(50, 200, 512, dtype=np.float32)
    natural_img = np.tile(grad, (512, 1)).astype(np.uint8)
    noise = np.random.normal(0, 5, (512, 512)).astype(np.int16)
    natural_img = np.clip(natural_img.astype(np.int16) + noise, 0, 255).astype(np.uint8)
    natural_bgr = np.stack([natural_img, natural_img, natural_img], axis=-1)

    result = validator.evaluate(natural_bgr)
    assert result.screen_recapture_detected is False
    assert result.local_moire_energy < 0.68
