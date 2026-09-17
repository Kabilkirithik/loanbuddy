"""
Agent definitions for the construction-loan disbursement crew.

Document/Contract Agent -> runs on Gemini (large context window, good for
    reading long loan agreements / BOQs, free tier via Google AI Studio).

Fraud/Anomaly Agent -> runs on Groq (fast inference, good for short
    reasoning/comparison calls, free tier via console.groq.com).

Both API keys are read from environment variables (see .env.example).
"""

import os
import litellm
from dotenv import load_dotenv
from crewai import Agent, LLM

from tools import LoanAgreementParserTool, FraudCheckTool

load_dotenv()

# Groq's API rejects request params it doesn't recognize (e.g. the
# 'cache_breakpoint' field CrewAI/LiteLLM adds for prompt-caching-capable
# providers). This tells LiteLLM to silently drop unsupported params
# instead of raising a BadRequestError.
litellm.drop_params = True

# ---------------------------------------------------------------------------
# LLMs
# ---------------------------------------------------------------------------

gemini_llm = LLM(
    model="gemini/gemini-3.1-flash-lite",
    api_key=os.getenv("GEMINI_API_KEY"),
)


# ---------------------------------------------------------------------------
# Agents
# ---------------------------------------------------------------------------

document_agent = Agent(
    role="Document/Contract Agent",
    goal=(
        "Parse the loan agreement / Bill of Quantities (BOQ) and extract a "
        "clear milestone-to-disbursement-percentage schedule that later "
        "agents can use to verify disbursement claims."
    ),
    backstory=(
        "You are a meticulous construction-finance contract analyst. You've "
        "reviewed hundreds of loan agreements and BOQs for NBFCs and banks, "
        "and you're excellent at pulling out exactly which construction "
        "milestone unlocks exactly what percentage of loan disbursement."
    ),
    tools=[LoanAgreementParserTool()],
    llm=gemini_llm,
    verbose=True,
    allow_delegation=False,
)

fraud_agent = Agent(
    role="Fraud/Anomaly Agent",
    goal=(
        "Detect inconsistencies between a claimed construction milestone and "
        "supporting evidence such as elapsed project time and submitted "
        "material-purchase invoices, so that disbursement is not released "
        "against a suspicious or premature claim."
    ),
    backstory=(
        "You are a sharp-eyed risk analyst at a construction lender who has "
        "seen every trick contractors use to claim progress that hasn't "
        "actually happened. You cross-check timelines and paperwork before "
        "anyone signs off on releasing funds."
    ),
    tools=[FraudCheckTool()],
    llm=gemini_llm,
    verbose=True,
    allow_delegation=False,
)
