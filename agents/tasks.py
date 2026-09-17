"""
Task definitions for the construction-loan disbursement crew.

The Fraud/Anomaly task uses `context=[parse_task]` so CrewAI automatically
passes the Document Agent's output into the Fraud Agent's prompt -- this is
how the two agents "talk" to each other in a sequential crew.
"""

from crewai import Task


def build_tasks(
    document_agent,
    vision_agent,
    fraud_agent,
    loan_doc_text: str,
    claimed_progress: str,
    elapsed_days: int,
    invoice_data: str,
    media_path: str = "building.png",
    expected_latitude: float = 12.9716,
    expected_longitude: float = 77.5946,
    live_latitude: float = 12.9716,
    live_longitude: float = 77.5946,
    loan_id: str = "LN-2026-SITE-01"
):
    # Task 1: Contract Analysis
    parse_task = Task(
        description=(
            f"Parse the following loan agreement / BOQ text and extract the "
            f"milestone-to-disbursement-percentage schedule:\n\n{loan_doc_text}"
        ),
        expected_output=(
            "A clear, itemized list of construction milestones and the "
            "disbursement percentage each one unlocks."
        ),
        agent=document_agent,
    )

    # Task 2: Physical Site Forensic Verification
    vision_task = Task(
        description=(
            f"Forensically inspect the user-submitted construction media at path '{media_path}' "
            f"for claimed milestone '{claimed_progress}' using the Site Vision Inspector tool.\n"
            f"Registered Loan Site Coordinates: ({expected_latitude}, {expected_longitude})\n"
            f"User Live GPS Telemetry: ({live_latitude}, {live_longitude})\n"
            f"Loan Application ID: {loan_id}\n\n"
            f"Evaluate all 3 security layers:\n"
            f"1. 3D depth and motion parallax (to rule out 2D screen/paper attacks)\n"
            f"2. Screen recapture, 2D-FFT Moiré grids, and C2PA generative AI markers (to rule out ChatGPT/DALL-E fakes)\n"
            f"3. GPS geofence compliance and LightGlue structural match against official satellite imagery.\n"
            f"Provide a clear forensic summary of each layer and state the physical verdict."
        ),
        expected_output=(
            "A structured visual audit summary detailing Layer 1 (Depth), Layer 2 (Recapture/GenAI), "
            "Layer 3 (Geospatial LightGlue), and the overall physical site authenticity verdict."
        ),
        agent=vision_agent,
    )

    # Task 3: Final Fraud & Disbursement Sign-off
    disbursement_task = Task(
        description=(
            f"You are the Chief Risk Officer making the final binding disbursement decision for "
            f"claimed milestone '{claimed_progress}'.\n"
            f"You must synthesize three streams of evidence:\n"
            f"1. The contract milestone schedule extracted by the Document Agent in Task 1.\n"
            f"2. The physical reality and forensic integrity audit from the Site Vision Agent in Task 2.\n"
            f"3. Construction timeline plausibility ({elapsed_days} days elapsed) and material invoices: '{invoice_data}' "
            f"using the Fraud Anomaly Checker tool.\n\n"
            f"Cross-reference all three. If the physical site fails (e.g. AI-generated image, 2D screen, "
            f"or GPS mismatch), OR if the timeline/invoices are anomalous, you MUST REJECT or FLAG FOR REVIEW. "
            f"If all three are fully verified, APPROVE the disbursement and state the exact unlocked percentage and amount."
        ),
        expected_output=(
            "A comprehensive Executive Disbursement Decision detailing:\n"
            "- Final Decision: APPROVED, FLAGGED FOR MANUAL REVIEW, or REJECTED\n"
            "- Unlocked Disbursement Percentage (from contract schedule)\n"
            "- Visual & Physical Integrity Assessment (from vision agent findings)\n"
            "- Financial & Timeline Plausibility Assessment\n"
            "- Clear rationale and recommended next action for the bank."
        ),
        agent=fraud_agent,
        context=[parse_task, vision_task],
    )

    return [parse_task, vision_task, disbursement_task]
