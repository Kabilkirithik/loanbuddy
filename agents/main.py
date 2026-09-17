"""
Run the construction-loan disbursement crew end-to-end, once per scenario
in a JSON file.

Usage:
    uv run main.py                  # uses claims.json (default)
    uv run main.py other_file.json  # use a different scenarios file

claims.json holds a LIST of scenarios, each with:
{
    "name": "Human-readable label for this scenario",
    "loan_doc_text": "...",
    "claimed_progress": "...",
    "elapsed_days": 10,
    "invoice_data": "..."
}

Running this script executes the full 2-agent crew once per scenario and
prints a clear verdict for each — so a single run demonstrates both the
"legitimate claim" and "fraudulent claim" paths back-to-back.

Make sure your .env file (see .env.example) has GEMINI_API_KEY set before
running (and GROQ_API_KEY if you're using Groq for the Fraud Agent).

Note: the free Gemini tier is rate-limited to a handful of requests per
minute. This script pauses briefly between scenarios to stay under that
limit — see PAUSE_BETWEEN_SCENARIOS_SECONDS below.
"""

import json
import sys
import time
from pathlib import Path

from crewai import Crew, Process

from agents import document_agent, fraud_agent
from tasks import build_tasks

# Brief pause between scenarios to avoid tripping the free-tier rate limit
# (Gemini's free tier allows only a few requests per minute). Increase this
# if you still see 429 errors; CrewAI will auto-retry on its own anyway.
PAUSE_BETWEEN_SCENARIOS_SECONDS = 15


def load_scenarios(json_path: str) -> list[dict]:
    """Load a list of claim scenarios from a JSON file.

    Expected JSON shape: a list of objects, each with keys:
        name, loan_doc_text, claimed_progress, elapsed_days, invoice_data
    """
    path = Path(json_path)
    if not path.exists():
        raise FileNotFoundError(
            f"Scenarios file not found: {json_path}\n"
            f"Expected a JSON file containing a list of scenario objects."
        )
    with open(path, "r", encoding="utf-8") as f:
        data = json.load(f)

    if not isinstance(data, list):
        raise ValueError(
            f"{json_path} must contain a JSON list of scenarios, "
            f"got {type(data).__name__} instead."
        )
    return data


def run_scenario(scenario: dict, index: int, total: int):
    name = scenario.get("name", f"Scenario {index}")
    print("\n" + "#" * 70)
    print(f"# SCENARIO {index}/{total}: {name}")
    print("#" * 70 + "\n")

    tasks = build_tasks(
        document_agent,
        fraud_agent,
        scenario["loan_doc_text"],
        scenario["claimed_progress"],
        scenario["elapsed_days"],
        scenario["invoice_data"],
    )

    crew = Crew(
        agents=[document_agent, fraud_agent],
        tasks=tasks,
        process=Process.sequential,
        verbose=True,
    )

    result = crew.kickoff()

    print("\n" + "=" * 60)
    print(f"VERDICT — {name}")
    print("=" * 60)
    print(result)
    print()


def main():
    json_path = sys.argv[1] if len(sys.argv) > 1 else "claims.json"
    print(f"Loading scenarios from: {json_path}")

    scenarios = load_scenarios(json_path)
    total = len(scenarios)
    print(f"Found {total} scenario(s) to run.\n")

    for i, scenario in enumerate(scenarios, start=1):
        run_scenario(scenario, i, total)
        if i < total:
            print(f"Pausing {PAUSE_BETWEEN_SCENARIOS_SECONDS}s before next scenario "
                  f"(free-tier rate limit)...")
            time.sleep(PAUSE_BETWEEN_SCENARIOS_SECONDS)

    print("\nAll scenarios complete.")


if __name__ == "__main__":
    main()