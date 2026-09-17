"""Interactive Test Runner for Construction Site Inspection Pipeline.

Simply edit MEDIA_PATH below (or pass it as an argument: python run_test.py your_video.mp4)
to test any construction site photo or video against all 3 security layers.
"""

import sys
import os
from pathlib import Path
from rich.console import Console
from rich.table import Table
from rich.panel import Panel

# ==============================================================================
# 🛠️ 1. CONFIGURE YOUR TEST MEDIA AND PARAMETERS HERE
# ==============================================================================
# Path to your video (.mp4, .mov, .avi) or photo (.png, .jpg, .jpeg)
MEDIA_PATH = "building.png"

# Optional: Path to reference satellite / architectural photo (leave None for auto-fetch/synthetic)
REFERENCE_IMAGE_PATH = None

# Official Registered Loan Project Coordinates
EXPECTED_LATITUDE = 12.9716
EXPECTED_LONGITUDE = 77.5946

# User Phone Live GPS (simulate matching or geofence breach)
LIVE_LATITUDE = 12.9716
LIVE_LONGITUDE = 77.5946

# Loan Application Metadata
LOAN_ID = "LN-2026-TEST-001"
BORROWER_NAME = "Apex Horizon Developers"
PROJECT_NAME = "Greenwood Heights Phase 3"
CONSTRUCTION_STAGE = "Slab / Framing"
DISBURSEMENT_AMOUNT_USD = 125000.0


# ==============================================================================
# 🚀 2. EXECUTION ENGINE
# ==============================================================================
def main():
    console = Console()

    # Allow CLI argument override if passed: python run_test.py my_video.mp4
    media_target = sys.argv[1] if len(sys.argv) > 1 else MEDIA_PATH
    media_file = Path(media_target)

    if not media_file.exists():
        console.print(f"[bold red]❌ Error: Media file not found:[/bold red] {media_file.resolve()}")
        console.print("[yellow]Tip: Put your video or photo in this directory and update MEDIA_PATH at the top of run_test.py[/yellow]")
        sys.exit(1)

    # Determine media type
    ext = media_file.suffix.lower()
    is_video = ext in [".mp4", ".mov", ".avi", ".mkv", ".webm"]
    media_type_str = "Video" if is_video else "Photo"

    console.print(Panel(
        f"[bold cyan]Inspection Test Runner[/bold cyan]\n"
        f"• Media: [bold yellow]{media_file.name}[/bold yellow] ({media_type_str})\n"
        f"• Loan ID: {LOAN_ID} ({BORROWER_NAME})\n"
        f"• Stage: {CONSTRUCTION_STAGE}\n"
        f"• Registered GPS: ({EXPECTED_LATITUDE:.4f}, {EXPECTED_LONGITUDE:.4f})\n"
        f"• Device Live GPS: ({LIVE_LATITUDE:.4f}, {LIVE_LONGITUDE:.4f})",
        title="Vision Agent Loan Inspection",
        border_style="cyan"
    ))

    # Import pipeline models
    from src.models import LoanApplicationContext, GPSCoordinate, FinalDecision, InspectionVerdict
    from src.pipeline import SiteInspectionPipeline

    loan_context = LoanApplicationContext(
        loan_id=LOAN_ID,
        borrower_name=BORROWER_NAME,
        project_name=PROJECT_NAME,
        construction_stage=CONSTRUCTION_STAGE,
        disbursement_amount_usd=DISBURSEMENT_AMOUNT_USD,
        expected_location=GPSCoordinate(
            latitude=EXPECTED_LATITUDE,
            longitude=EXPECTED_LONGITUDE
        )
    )

    live_gps = GPSCoordinate(
        latitude=LIVE_LATITUDE,
        longitude=LIVE_LONGITUDE
    )

    pipeline = SiteInspectionPipeline()

    with console.status(f"[bold green]Running 3-Layer Anti-Fraud Analysis on {media_file.name}...[/bold green]"):
        report = pipeline.run_inspection(
            media_input=str(media_file),
            loan_context=loan_context,
            live_gps=live_gps,
            reference_image=REFERENCE_IMAGE_PATH
        )

    # --------------------------------------------------------------------------
    # 📊 RESULTS TABLE
    # --------------------------------------------------------------------------
    table = Table(title=f"Verification Audit Trail — {report.inspection_id}")
    table.add_column("Layer", style="bold")
    table.add_column("Security Check", style="dim")
    table.add_column("Verdict", justify="center")
    table.add_column("Key Metrics & Findings", style="white")

    # Layer 1 Details
    l1 = report.layer1_depth
    l1_style = "green" if l1.verdict == InspectionVerdict.PASSED else "red"
    l1_metrics = (
        f"Depth StdDev: {l1.depth_std_dev} | Plane R²: {l1.plane_fit_r2}\n"
        f"Depth-Edge Coincidence: {l1.details.get('depth_edge_coincidence', 'N/A')}\n"
        f"Evaluated Frames: {l1.evaluated_frames_count} | 2D Flat Attack: {l1.is_flat_surface}"
    )
    if l1.parallax_score is not None:
        l1_metrics += f"\nMotion Parallax Residual: {l1.parallax_score}"
    table.add_row(
        "Layer 1",
        "Local Depth & Parallax\n(Depth-Anything-V2)",
        f"[{l1_style}]{l1.verdict.value}[/{l1_style}]",
        l1_metrics
    )

    # Layer 2 Details
    l2 = report.layer2_recapture
    l2_style = "green" if l2.verdict == InspectionVerdict.PASSED else "red"
    c2pa_info = l2.details.get("c2pa_provenance", {})
    l2_metrics = (
        f"Screen Recapture Score: {l2.screen_recapture_score} (Detected: {l2.screen_recapture_detected})\n"
        f"AI Generation Score: {l2.ai_generation_score} (Detected: {l2.ai_generation_detected})\n"
        f"Moiré Energy: {l2.local_moire_energy} | Provider: {l2.provider_used}"
    )
    if c2pa_info.get("detected"):
        sigs = ", ".join(c2pa_info.get("signatures", []))
        l2_metrics += f"\n[bold red]C2PA AI Signatures:[/bold red] {sigs}"
    table.add_row(
        "Layer 2",
        "Digital Recapture & GenAI\n(Sightengine/Hive + C2PA/FFT)",
        f"[{l2_style}]{l2.verdict.value}[/{l2_style}]",
        l2_metrics
    )

    # Layer 3 Details
    l3 = report.layer3_geospatial
    l3_style = "green" if l3.verdict == InspectionVerdict.PASSED else "red"
    table.add_row(
        "Layer 3",
        "Geospatial Identity Lock\n(Google Maps + LightGlue)",
        f"[{l3_style}]{l3.verdict.value}[/{l3_style}]",
        f"Distance from Site: {l3.gps_distance_meters}m (Geofence: {l3.within_geofence})\n"
        f"Structural Keypoint Matches: {l3.lightglue_matches_count} | Inliers: {l3.ransac_inliers_count}\n"
        f"Structural Match Score: {l3.structural_alignment_score} | Source: {l3.reference_source}"
    )

    console.print(table)

    # --------------------------------------------------------------------------
    # 🎯 FINAL VERDICT PANEL
    # --------------------------------------------------------------------------
    decision_color = {
        FinalDecision.APPROVED: "green",
        FinalDecision.FLAGGED_FOR_MANUAL_REVIEW: "yellow",
        FinalDecision.REJECTED: "red"
    }.get(report.final_decision, "white")

    verdict_text = (
        f"[bold {decision_color}]FINAL DECISION: {report.final_decision.value}[/bold {decision_color}]\n"
        f"Overall Integrity Score: {report.overall_confidence_score * 100:.1f}%\n"
        f"Executive Summary: {report.executive_summary}\n"
        f"Recommended Action: {report.recommended_action}"
    )

    if report.flagged_reasons:
        verdict_text += "\n\n[bold red]Flagged Violations / Security Alerts:[/bold red]\n"
        verdict_text += "\n".join(f"  • {reason}" for reason in report.flagged_reasons)

    console.print(Panel(
        verdict_text,
        title="Audit Decision",
        border_style=decision_color
    ))


if __name__ == "__main__":
    main()
