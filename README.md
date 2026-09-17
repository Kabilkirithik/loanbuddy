# Construction Loan Site Inspection Vision Agent 🏗️🔍

An AI-powered anti-fraud inspection system that automates the physical visit of bankers to construction sites for loan approvals and stage disbursements by analyzing user-submitted videos and photos.

---

## The 3-Layer Defense Architecture

```
User Video / Photos + Live GPS
        │
        ▼
┌────────────────────────────────────────────────────────────────────────┐
│ Layer 1: Local Depth & Motion Parallax Check (Physical Reality)        │
│ • Model: Depth-Anything-V2 (Depth-Anything-V2-Small-hf)                │
│ • Metrics: Depth-Edge Coincidence, Plane Fitting (R²), Motion Parallax │
│ • Defense: Rejects 2D presentation attacks (screens, paper photos)     │
└────────────────────────────────────┬───────────────────────────────────┘
                                     │ Passed
                                     ▼
┌────────────────────────────────────────────────────────────────────────┐
│ Layer 2: Digital Recapture & GenAI Artifact Check                      │
│ • APIs: Sightengine & Hive AI moderation endpoints                     │
│ • Local Fallback: 2D-FFT Moiré frequency detector & texture analysis   │
│ • Defense: Rejects 4K monitor recapture and AI-synthesized scenes      │
└────────────────────────────────────┬───────────────────────────────────┘
                                     │ Passed
                                     ▼
┌────────────────────────────────────────────────────────────────────────┐
│ Layer 3: Geospatial Identity Lock                                      │
│ • GPS Geofencing: Haversine distance vs loan application registry      │
│ • Reference Imagery: Google Maps Static API (Satellite & Street View)  │
│ • Structural Matching: LightGlue structural keypoint inlier alignment  │
│ • Defense: Rejects videos filmed at wrong physical locations           │
└────────────────────────────────────┬───────────────────────────────────┘
                                     │
                                     ▼
┌────────────────────────────────────────────────────────────────────────┐
│ Composite Audit Engine: APPROVED / FLAGGED / REJECTED                  │
└────────────────────────────────────────────────────────────────────────┘
```

---

## Project Structure

```
vision_agent/
├── src/
│   ├── __init__.py
│   ├── config.py              # Security thresholds and API credentials
│   ├── models.py              # Pydantic schemas for loans, layers, reports
│   ├── layers/
│   │   ├── __init__.py
│   │   ├── layer1_depth.py    # Layer 1: Depth-Anything-V2 & Parallax
│   │   ├── layer2_recapture.py# Layer 2: Sightengine/Hive & 2D-FFT Moiré
│   │   └── layer3_geospatial.py# Layer 3: Google Maps & LightGlue
│   ├── pipeline.py            # End-to-end multi-layer orchestrator
│   ├── api.py                 # FastAPI REST API service
│   └── cli.py                 # Interactive terminal inspection CLI
├── tests/
│   ├── test_layer1_depth.py
│   ├── test_layer2_recapture.py
│   ├── test_layer3_geospatial.py
│   └── test_pipeline.py
├── main.py                    # Main executable entrypoint
└── pyproject.toml
```

---

## Installation

Using `uv` (recommended):
```bash
cd vision_agent
uv sync
```

---

## Configuration (`.env`)

You can customize thresholds and enable commercial API keys via environment variables or a `.env` file:

```ini
# Commercial Detection APIs (Optional; high-fidelity local fallbacks built-in)
INSPECT_SIGHTENGINE_API_USER=your_user_id
INSPECT_SIGHTENGINE_API_SECRET=your_secret_key
INSPECT_HIVE_API_KEY=your_hive_token

# Google Maps Static API
INSPECT_GOOGLE_MAPS_API_KEY=your_google_maps_key

# Security Thresholds
INSPECT_DEPTH_EDGE_COINCIDENCE_MIN=1.10
INSPECT_PLANE_FIT_R2_MAX_THRESHOLD=0.88
INSPECT_SCREEN_RECAPTURE_MAX_CONFIDENCE=0.55
INSPECT_AI_GENERATED_MAX_CONFIDENCE=0.60
INSPECT_GPS_TOLERANCE_METERS=100.0
INSPECT_LIGHTGLUE_MIN_INLIER_MATCHES=15
```

---

## Usage

### 1. Command Line Interface (CLI)

Run inspection on any site video or photo directly:

```bash
# Basic inspection against loan coordinates
uv run python main.py \
  --media path/to/site_video.mp4 \
  --loan-id LN-2026-8942 \
  --stage "Roofing" \
  --expected-lat 37.7749 \
  --expected-lng -122.4194 \
  --live-lat 37.7749 \
  --live-lng -122.4194
```

### 2. REST API Server

Start the verification server:
```bash
uv run uvicorn src.api:app --host 0.0.0.0 --port 8000 --reload
```

Submit an inspection request:
```bash
curl -X POST "http://localhost:8000/api/v1/inspect" \
  -F "file=@/path/to/construction_site.mp4" \
  -F "loan_id=LN-2026-8942" \
  -F "borrower_name=Apex Horizon Developers" \
  -F "project_name=Oakwood Residential Phase 2" \
  -F "construction_stage=Framing" \
  -F "disbursement_amount_usd=150000" \
  -F "expected_latitude=37.7749" \
  -F "expected_longitude=-122.4194" \
  -F "live_latitude=37.7749" \
  -F "live_longitude=-122.4194"
```

### 3. Automated Tests

Run the complete test suite:
```bash
uv run pytest -v
```
