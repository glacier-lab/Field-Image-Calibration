"""
Analyze how ROI buffering (growing/shrinking the ROI outline) affects darkness stats.

For each MAT file produced by the calibration app (containing roiData.mask,
roiData.scaleInfo.pixelsPerCm and img_color_corrected), this script:
- Builds the CIELAB Lightness map (L*/100) for the whole image.
- Steps the ROI boundary outward (positive buffer) or inward (negative buffer)
  by a given distance in cm. Buffering is done with a distance transform
  computed once per image, then thresholded per step (O(1) per step instead
  of re-running morphology with an ever-larger kernel).
- Prints the mean/std lightness ("darkness") and pixel count within the
  buffered ROI at each step, plus a summary aggregated across all images.
- Saves per-image and summary results as CSV files under stat/ for later
  plotting/analysis.
- Processes MAT files in parallel across worker processes.
"""

from __future__ import annotations

import argparse
import csv
import os
from concurrent.futures import ProcessPoolExecutor, as_completed
from pathlib import Path
from typing import Any, Dict, List, Optional, Tuple

import cv2
import numpy as np
from scipy.io import loadmat


DEFAULT_INPUT_FOLDER = Path(
    r"C:\Users\au686295\GitHub\data\iCalibrateImages\TCsupplementary\DP24"
)
DEFAULT_OUTPUT_FOLDER = Path(__file__).resolve().parent.parent / "stat"


def safe_loadmat(path: Path) -> Dict[str, Any]:
    try:
        return loadmat(str(path), simplify_cells=True)
    except TypeError:
        return loadmat(str(path), squeeze_me=True, struct_as_record=False)


def to_dict(obj: Any) -> Any:
    if isinstance(obj, dict):
        return {k: to_dict(v) for k, v in obj.items()}

    if hasattr(obj, "_fieldnames"):
        return {name: to_dict(getattr(obj, name)) for name in obj._fieldnames}

    return obj


def get_roi_mask(roi_data: Dict[str, Any], h: int, w: int) -> Optional[np.ndarray]:
    mask = roi_data.get("mask")
    if mask is not None:
        arr = np.asarray(mask)
        if arr.shape == (h, w):
            return arr.astype(bool)

    lightness_values = roi_data.get("lightnessValues")
    if lightness_values is not None:
        arr = np.asarray(lightness_values)
        if arr.shape == (h, w):
            return ~np.isnan(arr)

    return None


def get_pixels_per_cm(roi_data: Dict[str, Any]) -> Optional[float]:
    scale_info = roi_data.get("scaleInfo")
    if not isinstance(scale_info, dict):
        return None

    pixels_per_cm = scale_info.get("pixelsPerCm")
    cm_per_pixel = scale_info.get("cmPerPixel")

    if pixels_per_cm is not None:
        value = float(np.ravel(np.asarray(pixels_per_cm))[0])
        if value > 0:
            return value

    if cm_per_pixel is not None:
        value = float(np.ravel(np.asarray(cm_per_pixel))[0])
        if value > 0:
            return 1.0 / value

    return None


def compute_lightness(img_rgb: np.ndarray) -> np.ndarray:
    img = np.asarray(img_rgb, dtype=np.float32)
    img_min, img_max = float(np.nanmin(img)), float(np.nanmax(img))
    if img_max > 1.0 or img_min < 0.0:
        denom = img_max - img_min
        img = (img - img_min) / denom if denom > 0 else np.zeros_like(img)
    img = np.clip(img, 0.0, 1.0)

    img_bgr_u8 = cv2.cvtColor((img * 255).astype(np.uint8), cv2.COLOR_RGB2BGR)
    lab = cv2.cvtColor(img_bgr_u8, cv2.COLOR_BGR2LAB).astype(np.float32)
    # OpenCV encodes L* (0-100) as 0-255; rescale to 0-1 to match MATLAB's rgb2lab(...)/100.
    lightness = lab[:, :, 0] / 255.0
    return np.clip(lightness, 0.0, 1.0)


def compute_distance_maps(mask: np.ndarray) -> Tuple[np.ndarray, np.ndarray]:
    """Distance (in px) to the ROI boundary, computed once per image.

    dist_inside[y, x]  = distance to nearest non-ROI pixel (valid inside the ROI).
    dist_outside[y, x] = distance to nearest ROI pixel (valid outside the ROI).
    """
    mask_u8 = mask.astype(np.uint8)
    dist_inside = cv2.distanceTransform(mask_u8, cv2.DIST_L2, 5)
    dist_outside = cv2.distanceTransform(1 - mask_u8, cv2.DIST_L2, 5)
    return dist_inside, dist_outside


def buffer_mask(
    mask: np.ndarray,
    buffer_cm: float,
    pixels_per_cm: float,
    dist_inside: np.ndarray,
    dist_outside: np.ndarray,
) -> np.ndarray:
    radius_px = abs(buffer_cm) * pixels_per_cm
    if radius_px == 0:
        return mask
    if buffer_cm > 0:
        return mask | (dist_outside <= radius_px)
    return dist_inside >= radius_px


def find_mat_files(folder: Path) -> List[Path]:
    return sorted(folder.glob("*.mat"))


def save_csv(rows: List[Dict[str, Any]], out_path: Path) -> None:
    if not rows:
        print(f"No rows to save, skipping: {out_path}")
        return

    out_path.parent.mkdir(parents=True, exist_ok=True)
    with open(out_path, "w", newline="") as f:
        writer = csv.DictWriter(f, fieldnames=list(rows[0].keys()))
        writer.writeheader()
        writer.writerows(rows)
    print(f"Saved: {out_path}")


def process_one_file(mat_path: Path, buffer_steps: np.ndarray) -> Tuple[str, Optional[str], List[Dict[str, Any]]]:
    """Runs in a worker process: returns (filename, error_or_None, rows)."""
    try:
        data = to_dict(safe_loadmat(mat_path))
    except Exception as exc:
        return mat_path.name, f"ERROR loading MAT file ({exc})", []

    roi_data = data.get("roiData")
    img_rgb = data.get("img_color_corrected")
    if not isinstance(roi_data, dict) or img_rgb is None:
        return mat_path.name, "missing roiData or img_color_corrected, skipping", []

    img_rgb = np.asarray(img_rgb)
    if img_rgb.ndim != 3 or img_rgb.shape[2] != 3:
        return mat_path.name, "img_color_corrected is not HxWx3, skipping", []
    h, w = img_rgb.shape[:2]

    mask = get_roi_mask(roi_data, h, w)
    pixels_per_cm = get_pixels_per_cm(roi_data)
    if mask is None or pixels_per_cm is None:
        return mat_path.name, "missing ROI mask or scale info, skipping", []

    lightness = compute_lightness(img_rgb)
    dist_inside, dist_outside = compute_distance_maps(mask)

    rows: List[Dict[str, Any]] = []
    for buffer_cm in buffer_steps:
        buffer_cm = float(buffer_cm)
        buffered = buffer_mask(mask, buffer_cm, pixels_per_cm, dist_inside, dist_outside)
        vals = lightness[buffered]
        n_px = int(vals.size)
        if n_px == 0:
            continue

        rows.append(
            {
                "file": mat_path.name,
                "buffer_cm": buffer_cm,
                "mean_lightness": float(np.mean(vals)),
                "std_lightness": float(np.std(vals, ddof=0)),
                "n_px": n_px,
                "area_cm2": n_px / pixels_per_cm ** 2,
                "pixels_per_cm": pixels_per_cm,
            }
        )

    return mat_path.name, None, rows


def main() -> None:
    parser = argparse.ArgumentParser(
        description="Sweep ROI buffer distance (cm) and print mean/std lightness for each step."
    )
    parser.add_argument("--input-folder", type=Path, default=DEFAULT_INPUT_FOLDER)
    parser.add_argument("--buffer-min-cm", type=float, default=-8.5, help="Most negative (shrink) buffer distance in cm.")
    parser.add_argument("--buffer-max-cm", type=float, default=8.5, help="Most positive (grow) buffer distance in cm.")
    parser.add_argument("--buffer-step-cm", type=float, default=0.5, help="Step size in cm, e.g. 0.1 or 0.5.")
    parser.add_argument("--output-folder", type=Path, default=DEFAULT_OUTPUT_FOLDER, help="Folder to save CSV results in.")
    parser.add_argument("--workers", type=int, default=os.cpu_count()-2, help="Number of worker processes (files processed in parallel).")
    args = parser.parse_args()

    input_folder = args.input_folder
    if not input_folder.is_dir():
        raise FileNotFoundError(f"Input folder not found: {input_folder}")

    mat_files = find_mat_files(input_folder)
    if not mat_files:
        raise FileNotFoundError(f"No MAT files found in: {input_folder}")

    buffer_steps = np.arange(
        args.buffer_min_cm, args.buffer_max_cm + args.buffer_step_cm / 2, args.buffer_step_cm
    )

    # per_step[buffer_cm] -> list of (mean, std, n_pixels) across files
    per_step: Dict[float, List[Tuple[float, float, int]]] = {round(b, 6): [] for b in buffer_steps}
    per_image_rows: List[Dict[str, Any]] = []

    print(f"Scanning {len(mat_files)} MAT files in: {input_folder}")
    print(f"Buffer range: {args.buffer_min_cm} to {args.buffer_max_cm} cm, step {args.buffer_step_cm} cm")
    print(f"Workers: {args.workers}")
    print("=" * 88)

    with ProcessPoolExecutor(max_workers=args.workers) as executor:
        futures = {
            executor.submit(process_one_file, mat_path, buffer_steps): mat_path
            for mat_path in mat_files
        }
        for future in as_completed(futures):
            mat_path = futures[future]
            file_name, error, rows = future.result()
            if error is not None:
                print(f"{file_name}: {error}")
                continue

            print(f"{file_name}: {len(rows)} buffer steps processed")
            for row in rows:
                key = round(row["buffer_cm"], 6)
                per_step[key].append((row["mean_lightness"], row["std_lightness"], row["n_px"]))
                per_image_rows.append(row)

    print("=" * 88)
    print("Summary across all images (mean of per-image means, ddof=0):")
    summary_rows: List[Dict[str, Any]] = []
    for buffer_cm in buffer_steps:
        key = round(float(buffer_cm), 6)
        entries = per_step[key]
        if not entries:
            print(f"buffer={buffer_cm:+.2f} cm: no valid images")
            continue
        means = np.asarray([e[0] for e in entries], dtype=float)
        mean_of_means = float(np.mean(means))
        std_of_means = float(np.std(means, ddof=0))
        print(
            f"buffer={buffer_cm:+.2f} cm: mean={mean_of_means:.6f}, "
            f"std={std_of_means:.6f}, n_images={means.size}"
        )
        summary_rows.append(
            {
                "buffer_cm": buffer_cm,
                "mean_lightness": mean_of_means,
                "std_lightness": std_of_means,
                "n_images": means.size,
            }
        )

    save_csv(per_image_rows, args.output_folder / "roi_buffer_darkness_per_image.csv")
    save_csv(summary_rows, args.output_folder / "roi_buffer_darkness_summary.csv")


if __name__ == "__main__":
    main()
