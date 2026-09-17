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