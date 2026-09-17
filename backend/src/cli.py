import argparse
import sys
import os
from rich.console import Console
from rich.table import Table
from rich.panel import Panel

from .models import LoanApplicationContext, GPSCoordinate, FinalDecision, InspectionVerdict
from .pipeline import SiteInspectionPipeline


def main():
    console = Console()
    parser = argparse.ArgumentParser(
        description="Automated 3-Layer Construction Site Loan Inspection CLI"
    )
    parser.add_argument("--media", required=True, help="Path to video (mp4) or image (jpg/png)")
    parser.add_argument("--loan-id", default="LN-2026-8942", help="Loan Application ID")
    parser.add_argument("--borrower", default="Apex Horizon Developers", help="Borrower name")
    parser.add_argument("--project", default="Oakwood Residential Phase 2", help="Project name")
    parser.add_argument("--stage", default="Roofing", help="Construction stage")
    parser.add_argument("--expected-lat", type=float, default=37.7749, help="Expected site latitude")
    parser.add_argument("--expected-lng", type=float, default=-122.4194, help="Expected site longitude")
    parser.add_argument("--live-lat", type=float, default=37.7749, help="Device live latitude")
    parser.add_argument("--live-lng", type=float, default=-122.4194, help="Device live longitude")
    parser.add_argument("--ref-image", default=None, help="Optional manual reference image for Layer 3")

    args = parser.parse_args()

    if not os.path.exists(args.media):
        console.print(f"[bold red]Error: Media file not found: {args.media}[/bold red]")
        sys.exit(1)

    console.print(Panel(
        f"[bold cyan]Construction Loan Site Anti-Fraud Verification[/bold cyan]\n"
        f"Loan: {args.loan_id} | Stage: {args.stage}\n"
        f"Media: {args.media}",
        title="Vision Agent",
        border_style="cyan"
    ))

    loan_context = LoanApplicationContext(
        loan_id=args.loan_id,
        borrower_name=args.borrower,
        project_name=args.project,
        construction_stage=args.stage,
        expected_location=GPSCoordinate(
            latitude=args.expected_lat,
            longitude=args.expected_lng
        )
    )

    live_gps = GPSCoordinate(
        latitude=args.live_lat,
        longitude=args.live_lng
    )

    pipeline = SiteInspectionPipeline()
    with console.status("[bold green]Running 3-Layer Verification Pipeline...[/bold green]"):
        report = pipeline.run_inspection(
            media_input=args.media,
            loan_context=loan_context,
            live_gps=live_gps,
            reference_image=args.ref_image
        )

    # Display Layer Results Table
    table = Table(title=f"Inspection Audit Trail: {report.inspection_id}")
    table.add_column("Layer", style="bold")
    table.add_column("Security Check", style="dim")
    table.add_column("Verdict", justify="center")
    table.add_column("Key Metrics")

    # Layer 1
    l1 = report.layer1_depth
    l1_style = "green" if l1.verdict == InspectionVerdict.PASSED else "red"
    table.add_row(
        "Layer 1",
        "Local Depth & Parallax Check\n(Depth-Anything-V2)",
        f"[{l1_style}]{l1.verdict.value}[/{l1_style}]",
        f"StdDev: {l1.depth_std_dev} | Plane R²: {l1.plane_fit_r2}\nFlat Surface: {l1.is_flat_surface}"
    )

    # Layer 2
    l2 = report.layer2_recapture
    l2_style = "green" if l2.verdict == InspectionVerdict.PASSED else "red"
    table.add_row(
        "Layer 2",
        "Digital Recapture & AI Check\n(Sightengine/Hive + 2D FFT)",
        f"[{l2_style}]{l2.verdict.value}[/{l2_style}]",
        f"Screen Score: {l2.screen_recapture_score} | GenAI: {l2.ai_generation_score}\nMoiré Energy: {l2.local_moire_energy} ({l2.provider_used})"
    )

    # Layer 3
    l3 = report.layer3_geospatial
    l3_style = "green" if l3.verdict == InspectionVerdict.PASSED else "red"
    table.add_row(
        "Layer 3",
        "Geospatial Identity Lock\n(Google Maps + LightGlue)",
        f"[{l3_style}]{l3.verdict.value}[/{l3_style}]",
        f"Distance: {l3.gps_distance_meters}m (Geofence: {l3.within_geofence})\nMatches: {l3.lightglue_matches_count} | Inliers: {l3.ransac_inliers_count}\nAlign Score: {l3.structural_alignment_score}"
    )

    console.print(table)

    # Final Decision Panel
    decision_color = {
        FinalDecision.APPROVED: "green",
        FinalDecision.FLAGGED_FOR_MANUAL_REVIEW: "yellow",
        FinalDecision.REJECTED: "red"
    }.get(report.final_decision, "white")

    console.print(Panel(
        f"[bold {decision_color}]FINAL DECISION: {report.final_decision.value}[/bold {decision_color}]\n"
        f"Overall Confidence Score: {report.overall_confidence_score * 100:.1f}%\n"
        f"Summary: {report.executive_summary}\n"
        f"Recommended Action: {report.recommended_action}" +
        (f"\n\n[bold red]Flagged Reasons:[/bold red]\n" + "\n".join(f"• {r}" for r in report.flagged_reasons) if report.flagged_reasons else ""),
        title="Inspection Result",
        border_style=decision_color
    ))


if __name__ == "__main__":
    main()
