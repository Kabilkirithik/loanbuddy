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

from tools import LoanAgreementParserTool, FraudCheckTool, SiteInspectionTool

load_dotenv()
load_dotenv(Path(__file__).resolve().parent.parent / ".env")

# Groq's API rejects request params it doesn't recognize (e.g. the
# 'cache_breakpoint' field CrewAI/LiteLLM adds for prompt-caching-capable
# providers). This tells LiteLLM to silently drop unsupported params
# instead of raising a BadRequestError.
litellm.drop_params = True

# ---------------------------------------------------------------------------
# LLMs
# ---------------------------------------------------------------------------

gemini_llm = LLM(
    model="gemini/gemini-2.5-flash",
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

vision_agent = Agent(
    role="Site Inspection Vision Agent",
    goal=(
        "Forensically inspect user-submitted construction site media (photos/videos) "
        "and live GPS coordinates using the Site Vision Inspector tool to verify "
        "3D physical reality, detect 2D screen/AI-generated presentations, and confirm "
        "geospatial structural alignment."
    ),
    backstory=(
        "You are an expert AI field inspection engineer for construction loans. "
        "Acting as the banker's eyes on the ground, you execute multi-layer computer vision checks "
        "(monocular depth and motion parallax, C2PA generative AI & screen recapture detection, and "
        "Google Maps satellite structural matching) to guarantee the physical building actually "
        "exists and has not been faked or filmed at the wrong location."
    ),
    tools=[SiteInspectionTool()],
    llm=gemini_llm,
    verbose=True,
    allow_delegation=False,
)

fraud_agent = Agent(
    role="Fraud & Disbursement Risk Officer",
    goal=(
        "Cross-examine the contract milestone schedule from the Document Agent, "
        "the physical reality verification report from the Site Vision Agent, and the "
        "submitted material invoice records / project timeline to make the final "
        "authoritative disbursement recommendation (APPROVED, FLAGGED FOR REVIEW, or REJECTED)."
    ),
    backstory=(
        "You are a veteran Chief Risk Officer at a premier construction lender. "
        "You combine legal contract terms, forensic computer vision inspection reports, "
        "and financial invoice evidence to protect the bank against fraudulent, premature, "
        "or synthetic milestone claims before releasing capital."
    ),
    tools=[FraudCheckTool()],
    llm=gemini_llm,
    verbose=True,
    allow_delegation=False,
)
