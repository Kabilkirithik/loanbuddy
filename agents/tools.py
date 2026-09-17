"""
Custom tools for the construction-loan disbursement crew.

- LoanAgreementParserTool: used by the Document/Contract Agent to turn a
  loan agreement / Bill of Quantities (BOQ) into a structured milestone
  schedule (milestone -> disbursement %).

- FraudCheckTool: used by the Fraud/Anomaly Agent to cross-check claimed
  construction progress against elapsed time, weather conditions, and
  material-purchase invoices submitted separately.

The Document Agent tool does real (if simple) regex-based extraction from
whatever document text is passed in. The Fraud Agent tool is still a
demo-stub with simple/mock rule-based logic so the crew is fully runnable
without needing a real weather API or invoicing system wired up yet.
"""

from typing import Type
from crewai.tools import BaseTool
from pydantic import BaseModel, Field


# ---------------------------------------------------------------------------
# Document / Contract Agent tool
# ---------------------------------------------------------------------------

class LoanAgreementInput(BaseModel):
    document_text: str = Field(
        ...,
        description="Raw text of the loan agreement / BOQ to parse for milestones."
    )


class LoanAgreementParserTool(BaseTool):
    name: str = "Loan Agreement Parser"
    description: str = (
        "Reads a loan agreement or Bill of Quantities (BOQ) and extracts the "
        "milestone-to-disbursement-percentage mapping, e.g. 'Foundation "
        "complete -> 20% disbursement'."
    )
    args_schema: Type[BaseModel] = LoanAgreementInput

    def _run(self, document_text: str) -> str:
        # Real (if simple) parsing: pull out "<milestone name> - <N>%" pairs
        # from the raw text using regex, instead of returning a hardcoded
        # schedule. This means the tool actually reflects whatever BOQ text
        # is passed in — different documents now produce different output.
        #
        # This still won't handle every possible BOQ phrasing/format (real
        # documents vary a lot), but it's genuine extraction rather than a
        # fixed stub. For production-grade parsing of arbitrary/scanned
        # documents, swap this for an LLM-based extraction prompt instead.
        import re

        # Matches things like: "Foundation work - 20% of loan amount."
        # Captures the milestone label and the percentage number.
        pattern = r"([A-Za-z0-9][A-Za-z0-9 /\-]*?)\s*-\s*(\d{1,3})%"
        matches = re.findall(pattern, document_text)

        if not matches:
            return (
                "Could not extract a milestone schedule from the provided "
                "document text — no '<milestone> - <percentage>%' pattern "
                "found. Please check the document format."
            )

        lines = ["Milestone Schedule (extracted from document):"]
        for milestone, pct in matches:
            milestone_clean = milestone.strip().rstrip(".")
            lines.append(f"- {milestone_clean}: {pct}% disbursement")

        return "\n".join(lines) + "\n"


# ---------------------------------------------------------------------------
# Fraud / Anomaly Agent tool
# ---------------------------------------------------------------------------

class FraudCheckInput(BaseModel):
    claimed_progress: str = Field(
        ..., description="The construction stage the borrower/contractor is claiming, e.g. 'Roofing complete'."
    )
    elapsed_days: int = Field(
        ..., description="Number of days elapsed since the loan/project start date."
    )
    invoice_data: str = Field(
        ..., description="Summary of material-purchase invoices submitted separately by the borrower."
    )


class FraudCheckTool(BaseTool):
    name: str = "Fraud Anomaly Checker"
    description: str = (
        "Cross-checks a claimed construction milestone against elapsed time "
        "and submitted material invoices to flag inconsistencies (e.g. a "
        "milestone claimed too early, or with no matching invoice trail)."
    )
    args_schema: Type[BaseModel] = FraudCheckInput

    def _run(self, claimed_progress: str, elapsed_days: int, invoice_data: str) -> str:
        # DEMO STUB — simple rule-based checks.
        # Replace with real logic later: pull a weather API for the project
        # location/date range, compare invoice line items and dates against
        # the claimed stage, etc.
        claim = claimed_progress.lower()
        flags = []

        # Rule 1: minimum time needed before a milestone is plausible
        min_days_required = {
            "foundation complete": 7,
            "1st floor slab cast": 20,
            "roofing complete": 45,
            "finishing work complete": 90,
        }
        for milestone, min_days in min_days_required.items():
            if milestone in claim and elapsed_days < min_days:
                flags.append(
                    f"Timeline anomaly: '{milestone}' claimed after only "
                    f"{elapsed_days} days, but this stage typically needs "
                    f"at least {min_days} days."
                )

        # Rule 2: no invoice evidence at all is suspicious for later-stage claims
        if not invoice_data.strip() and any(
            m in claim for m in ["roofing", "finishing"]
        ):
            flags.append(
                "No material invoice evidence submitted for a late-stage "
                "claim — unusual for this stage of construction."
            )

        if flags:
            return "ANOMALY DETECTED:\n" + "\n".join(f"- {f}" for f in flags)
        return "No anomaly detected. Progress timeline is consistent with elapsed time and invoices."


# ---------------------------------------------------------------------------
# Site Inspection Vision Agent tool
# ---------------------------------------------------------------------------

import sys
from pathlib import Path
_root_dir = str(Path(__file__).resolve().parent.parent)
if _root_dir not in sys.path:
    sys.path.insert(0, _root_dir)


class SiteInspectionInput(BaseModel):
    media_path: str = Field(
        ...,
        description="Path to the user-submitted construction site photo or video (e.g. 'building.png', 'site.mp4')."
    )
    construction_stage: str = Field(
        default="Foundation",
        description="The construction milestone claimed by the borrower (e.g. 'Foundation', 'Slab', 'Roofing', 'Finishing')."
    )
    expected_latitude: float = Field(
        default=12.9716,
        description="Official registered site latitude from loan agreement."
    )
    expected_longitude: float = Field(
        default=77.5946,
        description="Official registered site longitude from loan agreement."
    )
    live_latitude: float = Field(
        default=12.9716,
        description="Device live GPS latitude at time of capture."
    )
    live_longitude: float = Field(
        default=77.5946,
        description="Device live GPS longitude at time of capture."
    )
    loan_id: str = Field(
        default="LN-CREW-VERIFY",
        description="Loan application ID."
    )


class SiteInspectionTool(BaseTool):
    name: str = "Site Vision Inspector"
    description: str = (
        "Executes a 3-layer anti-fraud physical verification on submitted construction media: "
        "Layer 1 tests 3D depth & motion parallax with Depth-Anything-V2 to reject 2D screen/paper attacks; "
        "Layer 2 detects screen recapture, Moiré frequency grids, and C2PA GenAI (ChatGPT/DALL-E/Midjourney) fakes; "
        "Layer 3 verifies device GPS geofence and matches structural keypoints against satellite imagery via LightGlue."
    )
    args_schema: Type[BaseModel] = SiteInspectionInput

    def _run(
        self,
        media_path: str,
        construction_stage: str = "Foundation",
        expected_latitude: float = 12.9716,
        expected_longitude: float = 77.5946,
        live_latitude: float = 12.9716,
        live_longitude: float = 77.5946,
        loan_id: str = "LN-CREW-VERIFY"
    ) -> str:
        # Resolve media path if relative
        media_file = Path(media_path)
        if not media_file.is_absolute():
            # Check local agents dir first, then parent project dir
            local_cand = Path(__file__).parent / media_path
            parent_cand = Path(__file__).parent.parent / media_path
            if local_cand.exists():
                media_file = local_cand
            elif parent_cand.exists():
                media_file = parent_cand

        if not media_file.exists():
            return f"SITE INSPECTION ERROR: Media file '{media_path}' could not be found."

        from src.models import LoanApplicationContext, GPSCoordinate
        from src.pipeline import SiteInspectionPipeline

        loan_context = LoanApplicationContext(
            loan_id=loan_id,
            borrower_name="Loan Applicant",
            project_name="Loan Construction Site",
            construction_stage=construction_stage,
            expected_location=GPSCoordinate(
                latitude=expected_latitude,
                longitude=expected_longitude
            )
        )

        live_gps = GPSCoordinate(
            latitude=live_latitude,
            longitude=live_longitude
        )

        pipeline = SiteInspectionPipeline()
        report = pipeline.run_inspection(
            media_input=str(media_file),
            loan_context=loan_context,
            live_gps=live_gps
        )

        # Format structured findings for CrewAI agent reasoning
        c2pa_info = report.layer2_recapture.details.get("c2pa_provenance", {})
        c2pa_sigs = ", ".join(c2pa_info.get("signatures", [])) if c2pa_info.get("detected") else "None"

        summary = [
            f"SITE INSPECTION AUDIT REPORT ({report.inspection_id}):",
            f"- Final Physical Verdict: {report.final_decision.value}",
            f"- Overall Visual Integrity Score: {report.overall_confidence_score * 100:.1f}%",
            f"- Layer 1 (Depth & Motion Parallax): {report.layer1_depth.verdict.value} "
            f"(2D Flat Attack: {report.layer1_depth.is_flat_surface}, Depth StdDev: {report.layer1_depth.depth_std_dev}, "
            f"Plane R²: {report.layer1_depth.plane_fit_r2})",
            f"- Layer 2 (Recapture & GenAI): {report.layer2_recapture.verdict.value} "
            f"(Screen Recapture: {report.layer2_recapture.screen_recapture_detected}, "
            f"AI Generated: {report.layer2_recapture.ai_generation_detected}, "
            f"C2PA Signatures: {c2pa_sigs}, Moiré Energy: {report.layer2_recapture.local_moire_energy})",
            f"- Layer 3 (Geospatial Lock): {report.layer3_geospatial.verdict.value} "
            f"(Distance: {report.layer3_geospatial.gps_distance_meters:.1f}m, Geofence OK: {report.layer3_geospatial.within_geofence}, "
            f"Structural Matches: {report.layer3_geospatial.lightglue_matches_count}, Inliers: {report.layer3_geospatial.ransac_inliers_count})"
        ]

        if report.flagged_reasons:
            summary.append("- Flagged Security Violations:")
            for reason in report.flagged_reasons:
                summary.append(f"  * {reason}")

        summary.append(f"- Recommended Action: {report.recommended_action}")
        return "\n".join(summary)