# Construction Loan Site Inspection Vision Agent 🏗️🔍

An AI-powered anti-fraud inspection system that automates the physical visit of bankers to construction sites for loan approvals and stage disbursements by analyzing user-submitted videos and photos.

---

## The 3-Layer Local Defense Architecture

```
User Video / Photos + Live GPS
        │
        ▼
┌────────────────────────────────────────────────────────────────────────┐
│ Layer 1: Local Depth & Motion Parallax Check (Physical Reality)        │
│ • Model: Depth-Anything-V2 (Depth-Anything-V2-Small-hf via PyTorch)    │
│ • Metrics: Depth-Edge Coincidence, Plane Fitting (R²), Motion Parallax │
│ • Defense: Rejects 2D presentation attacks (screens, paper photos)     │
└────────────────────────────────────┬───────────────────────────────────┘
                                     │ Passed
                                     ▼
┌────────────────────────────────────────────────────────────────────────┐
│ Layer 2: Local Recapture & GenAI Artifact Check (Zero External APIs)   │
│ • C2PA Parser: Local JUMBF manifest inspector (OpenAI/DALL-E/Midjourney)│
│ • 2D-FFT Moiré: Subpixel periodic grid frequency spike detector        │
│ • Defense: Rejects monitor screen replays and AI-synthesized scenes    │
└────────────────────────────────────┬───────────────────────────────────┘
                                     │ Passed
                                     ▼
┌────────────────────────────────────────────────────────────────────────┐
│ Layer 3: Local Geospatial Identity Lock (Zero External APIs)           │
│ • GPS Geofencing: Haversine distance vs loan origination registry      │
│ • Reference Imagery: Free ESRI World Imagery High-Res Satellite Cache  │
│ • Structural Matching: Local LightGlue / SIFT keypoint inlier alignment│
│ • Defense: Rejects photos/videos filmed at wrong physical locations    │
└────────────────────────────────────┬───────────────────────────────────┘
                                     │
                                     ▼
┌────────────────────────────────────────────────────────────────────────┐
│ Composite Audit Engine: APPROVED / FLAGGED / REJECTED                  │
└────────────────────────────────────────────────────────────────────────┘
```

---

---

## Project Structure

```
vision_agent/ (Repository Root)
├── Dockerfile                  # Builds backend container
├── .dockerignore               # Ignores frontend and local python envs
├── docker-compose.yml          # Single-command local container orchestration
├── vercel.json                 # Configures Vercel to serve frontend/build/web
├── netlify.toml                # Configures Netlify to serve frontend/build/web
├── README.md                   # Full system documentation & quickstart
├── .gitignore                  # Git ignore rules for frontend & backend
│
├── backend/                    # 🐍 Python Vision Service & Risk Agents
│   ├── src/
│   │   ├── config.py           # Security thresholds and settings
│   │   ├── models.py           # Pydantic schemas for loans, layers, reports
│   │   ├── layers/
│   │   │   ├── layer1_depth.py    # Layer 1: Depth-Anything-V2 & Parallax
│   │   │   ├── layer2_recapture.py# Layer 2: C2PA Parser & 2D-FFT Moiré
│   │   │   └── layer3_geospatial.py# Layer 3: ESRI Satellite & LightGlue
│   │   ├── pipeline.py         # Multi-layer audit orchestrator
│   │   ├── api.py              # FastAPI REST API endpoints
│   │   └── cli.py              # Interactive CLI
│   ├── agents/                 # CrewAI Multi-Agent Disbursement Deliberation
│   ├── tests/                  # Unit and integration test suite
│   ├── cache/                  # Local satellite tile cache
│   ├── pyproject.toml          # uv dependency manifest
│   ├── uv.lock                 # Locked dependencies
│   ├── main.py                 # CLI entrypoint
│   └── run_test.py             # Custom media verification script
│
└── frontend/                   # 📱 Flutter Mobile & Web Client (SiteCheck)
    ├── lib/
    │   ├── main.dart           # App entrypoint & high-contrast outdoor palette
    │   ├── models.dart         # Site, Milestone, CaptureEvidence models
    │   ├── screens/            # Site list, Camera capture, and Review screens
    │   └── services/           # In-isolate stamp burn-in, location & outbox
    ├── android/                # Android native project
    ├── ios/                    # iOS native project (with permissions)
    ├── web/                    # Flutter web entrypoint
    ├── test/                   # Widget tests
    └── pubspec.yaml            # Flutter dependencies
```

---

## 🚀 Quickstart: Running Backend & Frontend

### 1. Start Backend API
```bash
cd backend
uv sync
uv run uvicorn src.api:app --host 0.0.0.0 --port 8000 --reload
```
* API Health: `http://localhost:8000/v1/health`
* Swagger UI Docs: `http://localhost:8000/docs`

Or run via Docker:
```bash
docker compose up --build
```

---

### 2. Run Frontend Client

```bash
cd frontend

# Run in Chrome Web browser:
flutter run -d chrome --dart-define=API_BASE_URL=http://localhost:8000

# Or build production web bundle for Vercel / Netlify:
flutter build web --dart-define=API_BASE_URL=https://<YOUR_BACKEND_URL>
```

---

### 3. Run Backend Automated Tests
```bash
cd backend
uv run pytest -v
```

---

### 4. Hosting & Deployment Guide

* **Frontend (Vercel / Netlify)**:
  * Deploy using `npx vercel deploy --prod frontend/build/web` (uses the root `vercel.json`).
  * Or drag and drop `frontend/build/web` onto Netlify Drop.
* **Backend (Railway / Render / Docker)**:
  * Connect your GitHub repo to Railway or Render.
  * The root `Dockerfile` automatically builds `backend/` and exposes port 8000.


