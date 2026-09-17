"""
Task definitions for the construction-loan disbursement crew.

The Fraud/Anomaly task uses `context=[parse_task]` so CrewAI automatically
passes the Document Agent's output into the Fraud Agent's prompt -- this is
how the two agents "talk" to each other in a sequential crew.
"""

from crewai import Task


def build_tasks(document_agent, fraud_agent, loan_doc_text, claimed_progress, elapsed_days, invoice_data):
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

    fraud_task = Task(
        description=(
            f"Using the milestone schedule extracted in the previous task, "
            f"check whether the claimed progress '{claimed_progress}' is "
            f"consistent with {elapsed_days} days elapsed since project "
            f"start, and with this submitted invoice data: '{invoice_data}'. "
            f"Use the Fraud Anomaly Checker tool to run the check, then "
            f"give a final verdict."
        ),
        expected_output=(
            "A verdict of either 'No anomaly detected' or 'ANOMALY DETECTED' "
            "with clear reasoning, referencing the relevant milestone and "
            "disbursement percentage from the schedule."
        ),
        agent=fraud_agent,
        context=[parse_task],
    )

    return [parse_task, fraud_task]
