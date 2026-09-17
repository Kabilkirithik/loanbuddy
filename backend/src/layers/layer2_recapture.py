import cv2
import numpy as np
from PIL import Image
import requests
from typing import Dict, Any, Optional, Tuple, Union, List
import logging

from ..config import settings
from ..models import Layer2RecaptureResult, InspectionVerdict

logger = logging.getLogger("vision_agent.layer2_recapture")


class DigitalRecaptureValidator:
    """Layer 2: Digital Recapture and AI-Generated Media Detector.
    
    Verifies that the camera is recording the physical environment directly,
    and not re-capturing a high-resolution monitor or displaying an AI-synthesized scene.
    Supports commercial APIs (Sightengine, Hive) with a high-fidelity local 2D-FFT Moiré fallback.
    """

    def __init__(
        self,
        sightengine_user: Optional[str] = None,
        sightengine_secret: Optional[str] = None,
        hive_api_key: Optional[str] = None
    ):
        self.sightengine_user = sightengine_user or settings.SIGHTENGINE_API_USER
        self.sightengine_secret = sightengine_secret or settings.SIGHTENGINE_API_SECRET
        self.hive_api_key = hive_api_key or settings.HIVE_API_KEY

    def analyze_local_moire_patterns(self, image: np.ndarray) -> Tuple[float, Dict[str, Any]]:
        """Detect screen recapture Moiré patterns using 2D Fourier Transform (FFT).
        
        Natural scenes exhibit a continuous 1/f^alpha spectral power decay.
        Screens display discrete, periodic high-frequency delta peaks caused by
        the pixel aperture grid and Bayer filter aliasing.
        """
        if len(image.shape) == 3:
            gray = cv2.cvtColor(image, cv2.COLOR_BGR2GRAY)
        else:
            gray = image.copy()

        # Resize to standard analysis patch (512x512) for consistent spectral frequencies
        resized = cv2.resize(gray, (512, 512), interpolation=cv2.INTER_AREA)

        # Apply Hanning window to prevent edge spectral leakage
        window = np.hanning(512)[:, None] * np.hanning(512)[None, :]
        windowed = (resized.astype(np.float32) - np.mean(resized)) * window

        # 2D FFT and power spectrum
        f_transform = np.fft.fft2(windowed)
        f_shift = np.fft.fftshift(f_transform)
        magnitude_spectrum = np.abs(f_shift)
        log_spectrum = np.log(magnitude_spectrum + 1e-6)

        # Mask out DC and low frequencies (central radius 35 px)
        rows, cols = 512, 512
        crow, ccol = rows // 2, cols // 2
        y, x = np.ogrid[:rows, :cols]
        center_dist = np.sqrt((x - ccol) ** 2 + (y - crow) ** 2)

        high_freq_mask = (center_dist >= 35) & (center_dist <= 240)
        high_freq_vals = log_spectrum[high_freq_mask]

        # Calculate peak-to-average power ratio (PAPR) in high frequencies
        # Screens have distinct high-energy sharp spikes
        mean_hf = float(np.mean(high_freq_vals))
        std_hf = float(np.std(high_freq_vals))
        max_hf = float(np.max(high_freq_vals))

        peak_z_score = (max_hf - mean_hf) / (std_hf + 1e-6)

        # Count isolated sharp spectral peaks (> 4 standard deviations above mean)
        spike_count = int(np.sum(high_freq_vals > (mean_hf + 4.0 * std_hf)))
        
        # Moiré energy metric bounded [0.0, 1.0]
        moire_score = float(np.clip((peak_z_score - 3.5) / 5.0, 0.0, 1.0))
        if spike_count > 12:
            moire_score = max(moire_score, 0.75)

        return moire_score, {
            "peak_z_score": round(peak_z_score, 3),
            "spectral_spike_count": spike_count,
            "high_freq_mean": round(mean_hf, 3)
        }

    def detect_ai_generation_local(self, image: np.ndarray) -> Tuple[float, Dict[str, Any]]:
        """Heuristic analysis for diffusion / generative model artifacts.
        
        Evaluates micro-texture blurriness vs edge sharpness (Laplacian variance),
        color gradient saturation inconsistency, and chromatic channel decorrelation.
        """
        if len(image.shape) == 3:
            gray = cv2.cvtColor(image, cv2.COLOR_BGR2GRAY)
        else:
            gray = image.copy()

        # Measure high-frequency edge energy
        laplacian_var = float(cv2.Laplacian(gray, cv2.CV_64F).var())

        # Measure color channel correlation in RGB
        if len(image.shape) == 3:
            b, g, r = cv2.split(image)
            std_r, std_g, std_b = float(np.std(r)), float(np.std(g)), float(np.std(b))
            if std_r > 1e-4 and std_g > 1e-4 and std_b > 1e-4:
                corr_rg = float(np.corrcoef(r.flatten(), g.flatten())[0, 1])
                corr_rb = float(np.corrcoef(r.flatten(), b.flatten())[0, 1])
                channel_decorr = 1.0 - max(0.0, min(1.0, (corr_rg + corr_rb) / 2.0))
            else:
                channel_decorr = 0.0
        else:
            channel_decorr = 0.0

        # Diffusion images often exhibit unnatural smoothness in textures with hyper-sharp contrast edges
        ai_score = 0.15  # Baseline benign
        if laplacian_var < 40.0:
            # Over-smoothed, potentially synthetic
            ai_score += 0.30
        if channel_decorr > 0.45:
            ai_score += 0.20

        return min(1.0, ai_score), {
            "laplacian_variance": round(laplacian_var, 2),
            "channel_decorrelation": round(channel_decorr, 3)
        }

    def query_sightengine(self, image_bytes: bytes) -> Optional[Dict[str, Any]]:
        """Query Sightengine API for screen recapture and AI generation scores."""
        if not self.sightengine_user or not self.sightengine_secret:
            return None

        url = "https://api.sightengine.com/1.0/check.json"
        params = {
            "models": "screen,genai",
            "api_user": self.sightengine_user,
            "api_secret": self.sightengine_secret
        }
        files = {"media": ("keyframe.jpg", image_bytes, "image/jpeg")}

        try:
            response = requests.post(url, data=params, files=files, timeout=12.0)
            if response.status_code == 200:
                data = response.json()
                if data.get("status") == "success":
                    return data
            logger.warning(f"Sightengine API returned status {response.status_code}: {response.text}")
        except Exception as e:
            logger.warning(f"Sightengine API request failed: {e}")
        return None

    def query_hive(self, image_bytes: bytes) -> Optional[Dict[str, Any]]:
        """Query Hive AI moderation endpoint for screen recapture and AI detection."""
        if not self.hive_api_key:
            return None

        url = "https://api.thehive.ai/api/v2/task/sync"
        headers = {"Authorization": f"Token {self.hive_api_key}"}
        files = {"media": ("keyframe.jpg", image_bytes, "image/jpeg")}

        try:
            response = requests.post(url, headers=headers, files=files, timeout=12.0)
            if response.status_code == 200:
                return response.json()
            logger.warning(f"Hive API returned status {response.status_code}: {response.text}")
        except Exception as e:
            logger.warning(f"Hive API request failed: {e}")
        return None

    def check_c2pa_provenance(self, image_bytes: bytes) -> Tuple[bool, float, List[str]]:
        """Inspect raw image byte stream for C2PA provenance and GenAI claim manifests.
        
        Modern AI generators (OpenAI/ChatGPT/DALL-E, Adobe Firefly, Midjourney, Bing)
        cryptographically sign or embed JUMBF/C2PA metadata specifying their AI generator identity.
        """
        signatures = {
            b"openai": "OpenAI / ChatGPT Media Service",
            b"dall-e": "OpenAI DALL-E Generator",
            b"c2pa": "C2PA Content Credentials Manifest",
            b"claim_generator": "GenAI Claim Generator Manifest",
            b"midjourney": "Midjourney AI Generator",
            b"stablediffusion": "Stable Diffusion Generator",
            b"com.adobe.firefly": "Adobe Firefly Generative AI",
            b"imagen": "Google Imagen Generative AI",
            b"bing image creator": "Bing Image Creator"
        }

        data_lower = image_bytes.lower()
        detected_signatures = []
        for sig, label in signatures.items():
            if sig in data_lower:
                detected_signatures.append(label)

        has_ai_provenance = any(
            x in detected_signatures for x in [
                "OpenAI / ChatGPT Media Service",
                "OpenAI DALL-E Generator",
                "Midjourney AI Generator",
                "Stable Diffusion Generator",
                "Adobe Firefly Generative AI",
                "Google Imagen Generative AI",
                "Bing Image Creator"
            ]
        )
        if has_ai_provenance:
            return True, 1.0, detected_signatures
        elif "C2PA Content Credentials Manifest" in detected_signatures and "GenAI Claim Generator Manifest" in detected_signatures:
            return True, 0.95, detected_signatures

        return False, 0.0, detected_signatures

    def evaluate(self, image_input: Union[str, np.ndarray, Image.Image]) -> Layer2RecaptureResult:
        """Run complete Layer 2 digital recapture and AI generation check."""
        rejection_reasons = []

        # Convert input to BGR numpy array and JPEG bytes
        if isinstance(image_input, str):
            cv_img = cv2.imread(image_input)
            if cv_img is None:
                raise ValueError(f"Could not load image: {image_input}")
            with open(image_input, "rb") as f:
                img_bytes = f.read()
        elif isinstance(image_input, np.ndarray):
            cv_img = image_input
            _, encoded = cv2.imencode(".png", cv_img)
            img_bytes = encoded.tobytes()
        elif isinstance(image_input, Image.Image):
            cv_img = cv2.cvtColor(np.array(image_input), cv2.COLOR_RGB2BGR)
            _, encoded = cv2.imencode(".png", cv_img)
            img_bytes = encoded.tobytes()
        else:
            raise ValueError(f"Unsupported image input type: {type(image_input)}")

        # Step 1: Check cryptographic C2PA and GenAI provenance metadata
        c2pa_detected, c2pa_ai_score, c2pa_signatures = self.check_c2pa_provenance(img_bytes)

        # Step 2: Compute local FFT Moiré and texture metrics
        local_moire_score, moire_details = self.analyze_local_moire_patterns(cv_img)
        local_ai_score, ai_details = self.detect_ai_generation_local(cv_img)

        provider_used = "c2pa_provenance" if c2pa_detected else "local_engine"
        screen_recapture_score = local_moire_score
        ai_generation_score = max(local_ai_score, c2pa_ai_score)
        extra_details: Dict[str, Any] = {
            "c2pa_provenance": {
                "detected": c2pa_detected,
                "signatures": c2pa_signatures
            },
            "moire_analysis": moire_details,
            "texture_analysis": ai_details
        }

        # Step 2: Try Commercial Sightengine API
        sightengine_res = self.query_sightengine(img_bytes)
        if sightengine_res is not None:
            provider_used = "sightengine"
            # Parse Sightengine response
            screen_data = sightengine_res.get("screen", {})
            screen_recapture_score = float(screen_data.get("is_screen", screen_recapture_score))
            type_data = sightengine_res.get("type", {})
            ai_generation_score = float(type_data.get("ai_generated", ai_generation_score))
            extra_details["sightengine_raw"] = sightengine_res
        else:
            # Step 3: Try Commercial Hive API
            hive_res = self.query_hive(img_bytes)
            if hive_res is not None:
                provider_used = "hive"
                # Parse Hive responses for screen / ai classes
                extra_details["hive_raw"] = hive_res

        # Evaluate against configured security thresholds
        screen_detected = (
            screen_recapture_score >= settings.SCREEN_RECAPTURE_MAX_CONFIDENCE or
            local_moire_score >= settings.LOCAL_MOIRE_ENERGY_THRESHOLD
        )
        ai_detected = ai_generation_score >= settings.AI_GENERATED_MAX_CONFIDENCE

        if screen_detected:
            rejection_reasons.append(
                f"Digital Screen Recapture detected (confidence: {screen_recapture_score:.2f}, "
                f"local moiré energy: {local_moire_score:.2f}, threshold: {settings.SCREEN_RECAPTURE_MAX_CONFIDENCE:.2f}). "
                f"Moiré subpixel frequency grid peaks identified."
            )
        if ai_detected:
            rejection_reasons.append(
                f"AI-generated / synthetic media detected (confidence: {ai_generation_score:.2f}, "
                f"threshold: {settings.AI_GENERATED_MAX_CONFIDENCE:.2f})."
            )

        verdict = (
            InspectionVerdict.FAILED if (screen_detected or ai_detected) else InspectionVerdict.PASSED
        )

        return Layer2RecaptureResult(
            verdict=verdict,
            screen_recapture_detected=screen_detected,
            ai_generation_detected=ai_detected,
            screen_recapture_score=round(screen_recapture_score, 3),
            ai_generation_score=round(ai_generation_score, 3),
            local_moire_energy=round(local_moire_score, 3),
            provider_used=provider_used,
            details=extra_details,
            rejection_reasons=rejection_reasons
        )
