import cv2
import numpy as np
from PIL import Image
import torch
from typing import List, Optional, Tuple, Union, Dict, Any
import logging

from ..config import settings
from ..models import Layer1DepthResult, InspectionVerdict

logger = logging.getLogger("vision_agent.layer1_depth")


class DepthParallaxValidator:
    """Layer 1: Local Depth and Motion Parallax Validator.
    
    Verifies that the camera is viewing a real 3D physical construction scene
    rather than a flat 2D surface (e.g. tablet screen, computer monitor, printed photo).
    """

    def __init__(self, model_name: Optional[str] = None, device: Optional[str] = None):
        self.model_name = model_name or settings.DEPTH_MODEL_NAME
        self.device = device or settings.DEVICE
        self._pipeline = None

    def _get_depth_pipeline(self):
        """Lazy-load the Depth-Anything-V2 pipeline."""
        if self._pipeline is None:
            try:
                from transformers import pipeline
                logger.info(f"Loading depth estimation model: {self.model_name} on {self.device}")
                self._pipeline = pipeline(
                    task="depth-estimation",
                    model=self.model_name,
                    device=self.device if self.device != "cpu" else -1
                )
            except Exception as e:
                logger.warning(f"Could not load HuggingFace model {self.model_name}: {e}. Falling back to gradient depth analyzer.")
                self._pipeline = "FALLBACK"
        return self._pipeline

    def extract_keyframes_from_video(self, video_path: str, num_frames: int = 4) -> List[np.ndarray]:
        """Extract representative, sharp keyframes evenly distributed throughout video."""
        cap = cv2.VideoCapture(video_path)
        if not cap.isOpened():
            raise ValueError(f"Could not open video file: {video_path}")

        total_frames = int(cap.get(cv2.CAP_PROP_FRAME_COUNT))
        if total_frames <= 0:
            total_frames = 100

        interval = max(1, total_frames // (num_frames + 1))
        keyframes = []

        for i in range(1, num_frames + 1):
            frame_idx = min(i * interval, total_frames - 1)
            cap.set(cv2.CAP_PROP_POS_FRAMES, frame_idx)
            ret, frame = cap.read()
            if ret and frame is not None:
                keyframes.append(frame)

        cap.release()
        if not keyframes:
            raise ValueError(f"No valid frames could be decoded from video: {video_path}")
        return keyframes

    def estimate_depth(self, image: Union[np.ndarray, Image.Image]) -> np.ndarray:
        """Run depth estimation on a single frame, returning metric/relative 2D depth numpy array."""
        if isinstance(image, np.ndarray):
            pil_img = Image.fromarray(cv2.cvtColor(image, cv2.COLOR_BGR2RGB))
        else:
            pil_img = image

        orig_w, orig_h = pil_img.size
        # Optimize inference: Resize to Depth-Anything-V2 native 518px patch resolution
        if pil_img.width > 518 or pil_img.height > 518:
            infer_img = pil_img.copy()
            infer_img.thumbnail((518, 518), Image.Resampling.BILINEAR)
        else:
            infer_img = pil_img

        pipe = self._get_depth_pipeline()
        if pipe != "FALLBACK":
            try:
                with torch.inference_mode():
                    output = pipe(infer_img)
                if "predicted_depth" in output:
                    depth_tensor = output["predicted_depth"]
                    if isinstance(depth_tensor, torch.Tensor):
                        depth_map = depth_tensor.cpu().numpy().astype(np.float32)
                    else:
                        depth_map = np.array(depth_tensor, dtype=np.float32)
                else:
                    depth_map = np.array(output["depth"], dtype=np.float32)
            except Exception as e:
                logger.warning(f"Depth pipeline inference failed: {e}. Using fallback gradient depth.")
                depth_map = self._fallback_depth_estimate(infer_img)
        else:
            depth_map = self._fallback_depth_estimate(infer_img)

        # Restore original spatial resolution for pixel-aligned edge analysis
        if depth_map.shape[0] != orig_h or depth_map.shape[1] != orig_w:
            depth_map = cv2.resize(depth_map, (orig_w, orig_h), interpolation=cv2.INTER_LINEAR)

        return depth_map

    def _fallback_depth_estimate(self, image: Image.Image) -> np.ndarray:
        """Heuristic depth estimator based on multi-scale gradients and luminance falloff."""
        img_gray = np.array(image.convert("L"), dtype=np.float32)
        grad_x = cv2.Sobel(img_gray, cv2.CV_32F, 1, 0, ksize=3)
        grad_y = cv2.Sobel(img_gray, cv2.CV_32F, 0, 1, ksize=3)
        grad_mag = np.sqrt(grad_x**2 + grad_y**2)
        blur = cv2.GaussianBlur(grad_mag, (21, 21), 0)
        return blur

    def compute_depth_edge_coincidence(self, image_bgr: np.ndarray, depth_map: np.ndarray) -> float:
        """Measure coincidence between image visual contrast edges and depth step gradients.
        
        Real 3D structures have high depth gradients along structural visual edges (e.g. wall/sky border).
        Flat 2D surfaces (text documents, photos of blueprints, screens) have high visual contrast
        but low depth gradient along those edges (ratio < 1.05).
        """
        gray = cv2.cvtColor(image_bgr, cv2.COLOR_BGR2GRAY)
        img_edges = cv2.Canny(gray, 50, 150) > 0

        edge_pixels_count = int(np.sum(img_edges))
        if edge_pixels_count < 25:
            # Virtually featureless flat wall, paper, or blank screen
            return 0.0

        gy, gx = np.gradient(depth_map)
        depth_grad = np.sqrt(gx**2 + gy**2)

        edge_depth_grad = float(np.mean(depth_grad[img_edges]))
        overall_depth_grad = float(np.mean(depth_grad))

        if overall_depth_grad < 1e-6:
            return 0.0

        coincidence = edge_depth_grad / overall_depth_grad
        return float(coincidence)

    def compute_plane_fit_r2(self, depth_map: np.ndarray, subsample_step: int = 8) -> float:
        """Fit a 3D plane (Ax + By + C = Z) to depth map and compute R^2 score."""
        h, w = depth_map.shape
        sub_depth = depth_map[::subsample_step, ::subsample_step]
        sh, sw = sub_depth.shape

        xs, ys = np.meshgrid(np.linspace(0, 1, sw), np.linspace(0, 1, sh))
        x_flat = xs.flatten()
        y_flat = ys.flatten()
        z_flat = sub_depth.flatten()

        A = np.column_stack([x_flat, y_flat, np.ones_like(x_flat)])
        
        try:
            coeffs, residuals, rank, s = np.linalg.lstsq(A, z_flat, rcond=None)
            z_pred = A @ coeffs
            ss_res = np.sum((z_flat - z_pred) ** 2)
            ss_tot = np.sum((z_flat - np.mean(z_flat)) ** 2)
            if ss_tot < 1e-8:
                return 1.0
            r2 = max(0.0, float(1.0 - (ss_res / ss_tot)))
            return r2
        except Exception:
            return 0.0

    def compute_motion_parallax_score(self, frames: List[np.ndarray]) -> Optional[float]:
        """Compute residual parallax deviation when fitting a single homography between frames."""
        if len(frames) < 2:
            return None

        gray1 = cv2.cvtColor(frames[0], cv2.COLOR_BGR2GRAY)
        gray2 = cv2.cvtColor(frames[-1], cv2.COLOR_BGR2GRAY)

        pts1 = cv2.goodFeaturesToTrack(gray1, maxCorners=300, qualityLevel=0.01, minDistance=10)
        if pts1 is None or len(pts1) < 15:
            return None

        pts2, status, err = cv2.calcOpticalFlowPyrLK(gray1, gray2, pts1, None)
        valid1 = pts1[status == 1]
        valid2 = pts2[status == 1]

        if len(valid1) < 15:
            return None

        H, mask = cv2.findHomography(valid1, valid2, cv2.RANSAC, 3.0)
        if H is None:
            return 0.5

        pts1_homo = np.hstack([valid1.reshape(-1, 2), np.ones((len(valid1), 1))])
        pts2_proj = (H @ pts1_homo.T).T
        pts2_proj = pts2_proj[:, :2] / (pts2_proj[:, 2:3] + 1e-8)

        reproj_errors = np.linalg.norm(valid2.reshape(-1, 2) - pts2_proj, axis=1)
        diag = np.sqrt(gray1.shape[0]**2 + gray1.shape[1]**2)
        parallax_score = float(np.median(reproj_errors) / (diag * 0.01))
        return min(1.0, parallax_score)

    def evaluate(
        self,
        media_input: Union[str, np.ndarray, List[np.ndarray], Image.Image]
    ) -> Layer1DepthResult:
        """Run complete Layer 1 verification on video or image(s)."""
        rejection_reasons = []
        frames: List[np.ndarray] = []

        if isinstance(media_input, str):
            ext = media_input.lower().split(".")[-1]
            if ext in ["mp4", "mov", "avi", "mkv", "webm"]:
                frames = self.extract_keyframes_from_video(media_input)
            else:
                img = cv2.imread(media_input)
                if img is None:
                    raise ValueError(f"Could not load image: {media_input}")
                frames = [img]
        elif isinstance(media_input, list):
            frames = media_input
        elif isinstance(media_input, np.ndarray):
            frames = [media_input]
        elif isinstance(media_input, Image.Image):
            frames = [cv2.cvtColor(np.array(media_input), cv2.COLOR_RGB2BGR)]

        primary_frame = frames[0]
        raw_depth_map = self.estimate_depth(primary_frame)

        # Normalized depth for variance measurement
        min_v, max_v = float(np.min(raw_depth_map)), float(np.max(raw_depth_map))
        if max_v - min_v > 1e-6:
            norm_depth = (raw_depth_map - min_v) / (max_v - min_v)
        else:
            norm_depth = np.zeros_like(raw_depth_map)

        depth_std_dev = float(np.std(norm_depth))
        plane_fit_r2 = self.compute_plane_fit_r2(norm_depth)
        coincidence = self.compute_depth_edge_coincidence(primary_frame, raw_depth_map)

        # Motion parallax if multiple frames are available
        parallax_score = None
        if len(frames) >= 2:
            parallax_score = self.compute_motion_parallax_score(frames)

        # Evaluation criteria:
        # 1. Featureless or flat surface where depth edges fail to align with image contrast
        is_flat_coincidence = coincidence < settings.DEPTH_EDGE_COINCIDENCE_MIN
        # 2. Planar surface fit (screen or paper viewed at angle)
        is_planar_surface = plane_fit_r2 > settings.PLANE_FIT_R2_MAX_THRESHOLD
        # 3. Parallax check
        is_parallax_lacking = False
        if parallax_score is not None and parallax_score < settings.PARALLAX_MOTION_MIN_THRESHOLD:
            is_parallax_lacking = True

        if is_flat_coincidence:
            rejection_reasons.append(
                f"Depth-Edge Coincidence ({coincidence:.2f}) is below threshold ({settings.DEPTH_EDGE_COINCIDENCE_MIN:.2f}). "
                f"Visual edges lack corresponding physical 3D depth step changes, characteristic of a 2D presentation attack."
            )
        if is_planar_surface:
            rejection_reasons.append(
                f"Depth map conforms to a flat 2D plane with R^2 = {plane_fit_r2:.4f} "
                f"(threshold: {settings.PLANE_FIT_R2_MAX_THRESHOLD:.4f}), consistent with screen or paper attack."
            )
        if is_parallax_lacking:
            rejection_reasons.append(
                f"Lack of 3D motion parallax across video frames (score: {parallax_score:.4f}, "
                f"min: {settings.PARALLAX_MOTION_MIN_THRESHOLD:.4f}). Features move as a single rigid 2D plane."
            )

        is_flat = is_flat_coincidence or is_planar_surface or is_parallax_lacking
        verdict = InspectionVerdict.FAILED if is_flat else InspectionVerdict.PASSED

        return Layer1DepthResult(
            verdict=verdict,
            is_flat_surface=is_flat,
            depth_std_dev=round(depth_std_dev, 4),
            plane_fit_r2=round(plane_fit_r2, 4),
            parallax_score=round(parallax_score, 4) if parallax_score is not None else None,
            evaluated_frames_count=len(frames),
            details={
                "depth_edge_coincidence": round(coincidence, 3),
                "depth_min": round(min_v, 3),
                "depth_max": round(max_v, 3),
                "model_used": self.model_name if self._pipeline != "FALLBACK" else "heuristic_fallback"
            },
            rejection_reasons=rejection_reasons
        )
