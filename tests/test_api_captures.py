import io
import json
import hashlib
import numpy as np
import cv2
import pytest
from fastapi.testclient import TestClient
from src.api import app, SEEN_IMAGE_HASHES


@pytest.fixture
def client():
    # Clear seen hashes before tests
    SEEN_IMAGE_HASHES.clear()
    return TestClient(app)


@pytest.fixture
def sample_jpeg_bytes():
    # Generate a synthetic image (480x640)
    img = np.zeros((480, 640, 3), dtype=np.uint8)
    # Add some texture / gradient
    for y in range(480):
        img[y, :, :] = (y % 256, (y * 2) % 256, (y * 3) % 256)
    cv2.putText(img, "Site Inspection Test", (50, 200), cv2.FONT_HERSHEY_SIMPLEX, 1.2, (255, 255, 255), 2)
    success, encoded = cv2.imencode(".jpg", img)
    assert success
    return encoded.tobytes()


def test_health_endpoint(client):
    response = client.get("/v1/health")
    assert response.status_code == 200
    data = response.json()
    assert data["status"] == "online"
    assert "layers" in data


def test_get_sites_endpoint(client):
    response = client.get("/v1/sites")
    assert response.status_code == 200
    sites = response.json()
    assert len(sites) >= 2
    assert sites[0]["id"] == "site_8812"
    assert len(sites[0]["milestones"]) >= 1


def test_submit_capture_success_and_duplicate(client, sample_jpeg_bytes):
    img_hash = hashlib.sha256(sample_jpeg_bytes).hexdigest()

    evidence = {
        "site_id": "site_8812",
        "milestone_id": "ms_2",
        "lat": 12.9165,
        "lng": 79.1325,
        "accuracy_meters": 4.5,
        "distance_from_site_meters": 12.0,
        "mock_location_detected": False,
        "captured_at_device": "2026-09-17T06:00:00Z",
        "device_model": "Google Pixel 8",
        "device_id": "test-device-uuid",
        "image_sha256": img_hash,
        "image_bytes": len(sample_jpeg_bytes),
        "borrower_note": "Ground floor slab curing"
    }

    # First submission -> should succeed (201)
    response = client.post(
        "/v1/captures",
        data={"evidence": json.dumps(evidence)},
        files={"image": ("capture.jpg", io.BytesIO(sample_jpeg_bytes), "image/jpeg")},
        headers={"X-Image-SHA256": img_hash}
    )

    assert response.status_code == 201
    data = response.json()
    assert "capture_ref" in data
    assert data["capture_ref"].startswith("CAP-site_8812")
    assert "status" in data
    assert data["report"] is not None

    # Resubmission of exact same photo -> should be rejected as duplicate (409)
    dup_response = client.post(
        "/v1/captures",
        data={"evidence": json.dumps(evidence)},
        files={"image": ("capture.jpg", io.BytesIO(sample_jpeg_bytes), "image/jpeg")},
        headers={"X-Image-SHA256": img_hash}
    )
    assert dup_response.status_code == 409
    assert "already been submitted" in dup_response.json()["detail"]


def test_submit_capture_tampered_hash(client, sample_jpeg_bytes):
    # Pass forged SHA-256 header
    tampered_hash = "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855"

    evidence = {
        "site_id": "site_8812",
        "milestone_id": "ms_2",
        "lat": 12.9165,
        "lng": 79.1325,
        "accuracy_meters": 4.5,
        "distance_from_site_meters": 12.0,
        "mock_location_detected": False,
        "captured_at_device": "2026-09-17T06:00:00Z",
        "device_model": "Google Pixel 8",
        "device_id": "test-device-uuid",
        "image_sha256": tampered_hash,
        "image_bytes": len(sample_jpeg_bytes)
    }

    response = client.post(
        "/v1/captures",
        data={"evidence": json.dumps(evidence)},
        files={"image": ("capture.jpg", io.BytesIO(sample_jpeg_bytes), "image/jpeg")},
        headers={"X-Image-SHA256": tampered_hash}
    )

    assert response.status_code == 400
    assert "tampering detected" in response.json()["detail"]


def test_submit_capture_malformed_evidence(client, sample_jpeg_bytes):
    response = client.post(
        "/v1/captures",
        data={"evidence": "not a valid json"},
        files={"image": ("capture.jpg", io.BytesIO(sample_jpeg_bytes), "image/jpeg")}
    )
    assert response.status_code == 400
    assert "Invalid evidence format" in response.json()["detail"]
