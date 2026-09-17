import os
from pydantic_settings import BaseSettings, SettingsConfigDict
from pydantic import Field


class InspectionSettings(BaseSettings):
    """Configuration settings and anti-fraud thresholds for Construction Site Inspection."""

    # Layer 1: Depth & Parallax Thresholds
    DEPTH_STD_DEV_MIN_THRESHOLD: float = Field(
        default=0.08,
        description="Minimum normalized standard deviation of depth. Below this, flagged as flat surface."
    )
    PLANE_FIT_R2_MAX_THRESHOLD: float = Field(
        default=0.88,
        description="If R^2 of a fitted plane exceeds this, the depth map conforms to a flat 2D plane (screen/wall)."
    )
    DEPTH_EDGE_COINCIDENCE_MIN: float = Field(
        default=1.10,
        description="Ratio of depth gradient at image edges vs overall depth gradient. Real 3D scenes > 1.2; 2D screens/text < 1.0."
    )
    PARALLAX_MOTION_MIN_THRESHOLD: float = Field(
        default=0.03,
        description="Minimum motion parallax variance between foreground and background keyframes."
    )
    DEPTH_MODEL_NAME: str = Field(
        default="depth-anything/Depth-Anything-V2-Small-hf",
        description="HuggingFace model ID for Depth-Anything-V2."
    )

    # Layer 2: Digital Recapture & GenAI Thresholds
    SIGHTENGINE_API_USER: str = Field(default="", description="Sightengine API user ID")
    SIGHTENGINE_API_SECRET: str = Field(default="", description="Sightengine API secret")
    HIVE_API_KEY: str = Field(default="", description="Hive AI moderation API key")
    SCREEN_RECAPTURE_MAX_CONFIDENCE: float = Field(
        default=0.55,
        description="Maximum tolerated confidence for screen recapture before rejection."
    )
    AI_GENERATED_MAX_CONFIDENCE: float = Field(
        default=0.60,
        description="Maximum tolerated confidence for AI-generated / deepfake media."
    )
    LOCAL_MOIRE_ENERGY_THRESHOLD: float = Field(
        default=0.68,
        description="High-frequency periodic spectral peak ratio indicating monitor pixel grid / moiré."
    )

    # Layer 3: Geospatial Identity Lock Thresholds
    GOOGLE_MAPS_API_KEY: str = Field(default="", description="Google Maps Static / Street View API key")
    GPS_TOLERANCE_METERS: float = Field(
        default=100.0,
        description="Maximum allowable distance (meters) between live device GPS and registered site."
    )
    LIGHTGLUE_MIN_INLIER_MATCHES: int = Field(
        default=15,
        description="Minimum number of RANSAC inlier keypoint matches required between user photo and reference."
    )
    LIGHTGLUE_MIN_MATCH_CONFIDENCE: float = Field(
        default=0.35,
        description="Minimum structural matching confidence ratio."
    )

    # System & Execution
    DEVICE: str = Field(default="cpu", description="Inference device: 'cpu', 'mps', or 'cuda'")
    FAST_FAIL: bool = Field(
        default=False,
        description="If True, pipeline halts immediately upon the first layer failure. If False, runs all layers for audit."
    )

    model_config = SettingsConfigDict(
        env_prefix="INSPECT_",
        env_file=".env",
        extra="ignore"
    )


settings = InspectionSettings()
