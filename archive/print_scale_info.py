"""
Print scale information for calibrated MAT images.

For each MAT file in a folder, the script tries to read:
- roiData.scaleInfo.pixelsPerCm
- roiData.scaleInfo.cmPerPixel

It prints per-image values and reports mean/std across valid files.
"""

from __future__ import annotations

import argparse
from pathlib import Path
from typing import Any, Dict, Iterable, Optional, Tuple

import numpy as np
from scipy.io import loadmat


DEFAULT_INPUT_FOLDER = Path(
    r"C:\Users\au686295\GitHub\data\iCalibrateImages\TCsupplementary\DP24"
)


def safe_loadmat(path: Path) -> Dict[str, Any]:
    try:
        return loadmat(str(path), simplify_cells=True)
    except TypeError:
        return loadmat(str(path), squeeze_me=True, struct_as_record=False)


def to_dict(obj: Any) -> Any:
    if isinstance(obj, dict):
        return {k: to_dict(v) for k, v in obj.items()}

    if hasattr(obj, "_fieldnames"):
        out = {}
        for name in obj._fieldnames:
            out[name] = to_dict(getattr(obj, name))
        return out

    return obj


def to_float_or_none(value: Any) -> Optional[float]:
    if value is None:
        return None

    arr = np.asarray(value)
    if arr.size == 0:
        return None

    scalar = float(np.ravel(arr)[0])
    if not np.isfinite(scalar):
        return None
    return scalar


def extract_scale_info(mat_data: Dict[str, Any]) -> Tuple[Optional[float], Optional[float]]:
    roi_data = mat_data.get("roiData")
    if not isinstance(roi_data, dict):
        return None, None

    scale_info = roi_data.get("scaleInfo")
    if not isinstance(scale_info, dict):
        return None, None

    pixels_per_cm = to_float_or_none(scale_info.get("pixelsPerCm"))
    cm_per_pixel = to_float_or_none(scale_info.get("cmPerPixel"))

    if pixels_per_cm is None and cm_per_pixel is not None and cm_per_pixel > 0:
        pixels_per_cm = 1.0 / cm_per_pixel
    if cm_per_pixel is None and pixels_per_cm is not None and pixels_per_cm > 0:
        cm_per_pixel = 1.0 / pixels_per_cm

    if pixels_per_cm is not None and pixels_per_cm <= 0:
        pixels_per_cm = None
    if cm_per_pixel is not None and cm_per_pixel <= 0:
        cm_per_pixel = None

    return pixels_per_cm, cm_per_pixel


def find_mat_files(folder: Path) -> Iterable[Path]:
    return sorted(folder.glob("*.mat"))


def main() -> None:
    parser = argparse.ArgumentParser(
        description="Print scale information (pixel resolution) from calibrated MAT images."
    )
    parser.add_argument(
        "--input-folder",
        type=Path,
        default=DEFAULT_INPUT_FOLDER,
        help="Folder containing calibrated MAT files.",
    )
    args = parser.parse_args()

    input_folder = args.input_folder
    if not input_folder.is_dir():
        raise FileNotFoundError(f"Input folder not found: {input_folder}")

    mat_files = list(find_mat_files(input_folder))
    if not mat_files:
        raise FileNotFoundError(f"No MAT files found in: {input_folder}")

    px_per_cm_values = []
    cm_per_px_values = []
    missing_count = 0

    print(f"Scanning {len(mat_files)} MAT files in: {input_folder}")
    print("=" * 88)

    for mat_path in mat_files:
        try:
            raw = safe_loadmat(mat_path)
            data = to_dict(raw)
            px_per_cm, cm_per_px = extract_scale_info(data)
        except Exception as exc:
            print(f"{mat_path.name}: ERROR reading scale info ({exc})")
            missing_count += 1
            continue

        if px_per_cm is None and cm_per_px is None:
            print(f"{mat_path.name}: scaleInfo missing")
            missing_count += 1
            continue

        px_text = "NaN" if px_per_cm is None else f"{px_per_cm:.6f}"
        cm_text = "NaN" if cm_per_px is None else f"{cm_per_px:.6f}"
        print(f"{mat_path.name}: pixelsPerCm={px_text}, cmPerPixel={cm_text}")

        if px_per_cm is not None:
            px_per_cm_values.append(px_per_cm)
        if cm_per_px is not None:
            cm_per_px_values.append(cm_per_px)

    print("=" * 88)
    print(f"Files processed: {len(mat_files)}")
    print(f"Files with missing/invalid scale info: {missing_count}")

    if px_per_cm_values:
        px_arr = np.asarray(px_per_cm_values, dtype=float)
        print(
            "pixelsPerCm mean={:.6f}, std={:.6f}, n={}".format(
                float(np.mean(px_arr)),
                float(np.std(px_arr, ddof=0)),
                px_arr.size,
            )
        )
    else:
        print("pixelsPerCm mean/std: no valid values")

    if cm_per_px_values:
        cm_arr = np.asarray(cm_per_px_values, dtype=float)
        print(
            "cmPerPixel mean={:.6f}, std={:.6f}, n={}".format(
                float(np.mean(cm_arr)),
                float(np.std(cm_arr, ddof=0)),
                cm_arr.size,
            )
        )
    else:
        print("cmPerPixel mean/std: no valid values")


if __name__ == "__main__":
    main()
