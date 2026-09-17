import os
import uuid
from datetime import datetime, timezone
from typing import List, Optional, Union, Dict, Any
import numpy as np
from PIL import Image
import logging

from .config import settings
from .models import (
    LoanApplicationContext,
    GPSCoordinate,
    InspectionReport,
    Layer1DepthResult,
    Layer2RecaptureResult,
    Layer3GeospatialResult,
    InspectionVerdict,
    FinalDecision
)
from .layers.layer1_depth import DepthParallaxValidator
from .layers.layer2_recapture import DigitalRecaptureValidator
from .layers.layer3_geospatial import GeospatialValidator

logger = logging.getLogger("vision_agent.pipeline")


class SiteInspectionPipeline:
    """End-to-end Construction Site Loan Inspection Verification Pipeline.
    
    Coordinates the 3-Layer anti-fraud defense:
    - Layer 1: Local Depth & Motion Parallax Check (Depth-Anything-V2)
    - Layer 2: Digital Screen Recapture & AI Generation Check (Sightengine/Hive + 2D-FFT Moiré)
    - Layer 3: Geospatial Identity Lock (Google Maps Static API + LightGlue Structural Matcher)
    """

    def __init__(
        self,
        layer1_validator: Optional[DepthParallaxValidator] = None,
        layer2_validator: Optional[DigitalRecaptureValidator] = None,
        layer3_validator: Optional[GeospatialValidator] = None,
        fast_fail: Optional[bool] = None
    ):
        self.layer1 = layer1_validator or DepthParallaxValidator()
        self.layer2 = layer2_validator or DigitalRecaptureValidator()
        self.layer3 = layer3_validator or GeospatialValidator()
        self.fast_fail = fast_fail if fast_fail is not None else settings.FAST_FAIL

    def run_inspection(
        self,
        media_input: Union[str, List[np.ndarray], np.ndarray, Image.Image],
        loan_context: LoanApplicationContext,
        live_gps: GPSCoordinate,
        reference_image: Optional[Union[str, np.ndarray, Image.Image]] = None
    ) -> InspectionReport:
        """Execute all three verification layers on user-submitted site media."""
        inspection_id = f"INSP-{uuid.uuid4().hex[:8].upper()}"
        timestamp = datetime.now(timezone.utc).isoformat()
        all_reasons: List[str] = []

        logger.info(f"Starting inspection {inspection_id} for Loan ID: {loan_context.loan_id} ({loan_context.project_name})")

        # Extract or resolve primary keyframe for layers 2 & 3
        layer2_input = media_input
        if isinstance(media_input, str):
            ext = media_input.lower().split(".")[-1]
            if ext in ["mp4", "mov", "avi", "mkv", "webm"]:
                keyframes = self.layer1.extract_keyframes_from_video(media_input, num_frames=3)
                primary_keyframe = keyframes[0]
                layer2_input = primary_keyframe
            else:
                import cv2
                primary_keyframe = cv2.imread(media_input)
                keyframes = [primary_keyframe]
                layer2_input = media_input
        elif isinstance(media_input, list):
            keyframes = media_input
            primary_keyframe = keyframes[0]
            layer2_input = primary_keyframe
        elif isinstance(media_input, np.ndarray):
            primary_keyframe = media_input
            keyframes = [primary_keyframe]
            layer2_input = primary_keyframe
        elif isinstance(media_input, Image.Image):
            import cv2
            primary_keyframe = cv2.cvtColor(np.array(media_input), cv2.COLOR_RGB2BGR)
            keyframes = [primary_keyframe]
            layer2_input = media_input
        else:
            raise ValueError(f"Unsupported media input: {type(media_input)}")

        # ---------------------------------------------------------------------
        # LAYER 1: Local Depth & Motion Parallax Check
        # ---------------------------------------------------------------------
        logger.info(f"[{inspection_id}] Executing Layer 1: Depth & Parallax Check...")
        layer1_res = self.layer1.evaluate(media_input)
        if layer1_res.verdict == InspectionVerdict.FAILED:
            all_reasons.extend(layer1_res.rejection_reasons)
            if self.fast_fail:
                logger.warning(f"[{inspection_id}] Fast-fail triggered on Layer 1 failure.")
                return self._build_report(
                    inspection_id=inspection_id,
                    loan_context=loan_context,
                    layer1_res=layer1_res,
                    layer2_res=self._skipped_layer2(),
                    layer3_res=self._skipped_layer3(live_gps, loan_context.expected_location),
                    all_reasons=all_reasons,
                    timestamp=timestamp
                )

        # ---------------------------------------------------------------------
        # LAYER 2: Digital Recapture & GenAI Check
        # ---------------------------------------------------------------------
        logger.info(f"[{inspection_id}] Executing Layer 2: Digital Recapture & GenAI Check...")
        layer2_res = self.layer2.evaluate(layer2_input)
        if layer2_res.verdict == InspectionVerdict.FAILED:
            all_reasons.extend(layer2_res.rejection_reasons)
            if self.fast_fail:
                logger.warning(f"[{inspection_id}] Fast-fail triggered on Layer 2 failure.")
                return self._build_report(
                    inspection_id=inspection_id,
                    loan_context=loan_context,
                    layer1_res=layer1_res,
                    layer2_res=layer2_res,
                    layer3_res=self._skipped_layer3(live_gps, loan_context.expected_location),
                    all_reasons=all_reasons,
                    timestamp=timestamp
                )

        # ---------------------------------------------------------------------
        # LAYER 3: Geospatial Identity Lock
        # ---------------------------------------------------------------------
        logger.info(f"[{inspection_id}] Executing Layer 3: Geospatial Identity Lock...")
        layer3_res = self.layer3.evaluate(
            user_image=primary_keyframe,
            live_gps=live_gps,
            expected_gps=loan_context.expected_location,
            reference_image=reference_image
        )
        if layer3_res.verdict == InspectionVerdict.FAILED:
            all_reasons.extend(layer3_res.rejection_reasons)

        # ---------------------------------------------------------------------
        # Aggregated Decision & Report Generation
        # ---------------------------------------------------------------------
        return self._build_report(
            inspection_id=inspection_id,
            loan_context=loan_context,
            layer1_res=layer1_res,
            layer2_res=layer2_res,
            layer3_res=layer3_res,
            all_reasons=all_reasons,
            timestamp=timestamp
        )

    def _build_report(
        self,
        inspection_id: str,
        loan_context: LoanApplicationContext,
        layer1_res: Layer1DepthResult,
        layer2_res: Layer2RecaptureResult,
        layer3_res: Layer3GeospatialResult,
        all_reasons: List[str],
        timestamp: str
    ) -> InspectionReport:
        """Compute composite confidence score, overall decision, and recommended action."""
        
        # Calculate component scores [0.0, 1.0]
        s1 = 0.0 if layer1_res.is_flat_surface else 1.0
        s2 = max(0.0, 1.0 - max(layer2_res.screen_recapture_score, layer2_res.ai_generation_score))
        s3_geo = 1.0 if layer3_res.within_geofence else 0.0
        s3_align = layer3_res.structural_alignment_score
        s3 = 0.5 * s3_geo + 0.5 * s3_align

        # Weighted aggregate confidence score
        overall_score = round(0.35 * s1 + 0.30 * s2 + 0.35 * s3, 3)

        # Decision rules
        critical_failure = (
            layer1_res.is_flat_surface or
            layer2_res.screen_recapture_detected or
            layer2_res.ai_generation_detected or
            (not layer3_res.within_geofence and layer3_res.verdict != InspectionVerdict.SKIPPED)
        )

        structural_only_fail = (
            not critical_failure and
            layer3_res.verdict == InspectionVerdict.FAILED
        )

        if critical_failure:
            decision = FinalDecision.REJECTED
            action = "Reject loan stage approval immediately due to high-probability fraud/attack."
            summary = (
                f"INSPECTION REJECTED: Presentation attack or geofence violation detected for "
                f"loan {loan_context.loan_id} ({loan_context.borrower_name})."
            )
        elif structural_only_fail or overall_score < 0.70:
            decision = FinalDecision.FLAGGED_FOR_MANUAL_REVIEW
            action = "Flag for secondary review: dispatch site officer or request live banker video verification."
            summary = (
                f"MANUAL REVIEW REQUIRED: Geospatial coordinates valid, but structural alignment "
                f"confidence is below automated signoff threshold."
            )
        else:
            decision = FinalDecision.APPROVED
            action = f"Approve stage disbursement milestone ({loan_context.construction_stage})."
            summary = (
                f"INSPECTION VERIFIED: Physical 3D site authenticity, screen integrity, and "
                f"geospatial location successfully validated."
            )

        return InspectionReport(
            inspection_id=inspection_id,
            loan_id=loan_context.loan_id,
            final_decision=decision,
            overall_confidence_score=overall_score,
            executive_summary=summary,
            layer1_depth=layer1_res,
            layer2_recapture=layer2_res,
            layer3_geospatial=layer3_res,
            flagged_reasons=all_reasons,
            timestamp=timestamp,
            recommended_action=action
        )

    def _skipped_layer2(self) -> Layer2RecaptureResult:
        return Layer2RecaptureResult(
            verdict=InspectionVerdict.SKIPPED,
            screen_recapture_detected=False,
            ai_generation_detected=False,
            screen_recapture_score=0.0,
            ai_generation_score=0.0,
            local_moire_energy=0.0,
            provider_used="skipped",
            details={},
            rejection_reasons=[]
        )

    def _skipped_layer3(self, live_gps: GPSCoordinate, expected_gps: GPSCoordinate) -> Layer3GeospatialResult:
        return Layer3GeospatialResult(
            verdict=InspectionVerdict.SKIPPED,
            gps_distance_meters=0.0,
            within_geofence=True,
            reference_source="skipped",
            total_keypoints_found=0,
            lightglue_matches_count=0,
            ransac_inliers_count=0,
            structural_alignment_score=0.0,
            details={},
            rejection_reasons=[]
        )
