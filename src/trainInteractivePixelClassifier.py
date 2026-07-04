"""
Interactive pixel classifier training from calibrated MAT files.

Workflow:
1. Load all calibrated MAT files from a folder (no 100-image limit).
2. Let user define N classes and interactively click training pixels.
3. Train/test split of clicked samples.
4. Train Random Forest classifier.
5. Use confidence threshold so low-confidence predictions become
   class N+1: "Unclassified".
6. Save model, training data (including pixel coordinates), and diagnostics.

Dependencies:
- numpy
- scipy
- opencv-python
- scikit-learn
- pandas
- matplotlib
- seaborn
"""

from __future__ import annotations

import glob
import os
import pickle
from dataclasses import dataclass
from typing import Dict, List, Tuple

import cv2
import matplotlib.pyplot as plt
from matplotlib.colors import BoundaryNorm, ListedColormap
from matplotlib.patches import Patch
import numpy as np
import pandas as pd
import seaborn as sns
from scipy.io import loadmat
from sklearn.ensemble import RandomForestClassifier
from sklearn.metrics import classification_report, confusion_matrix
from sklearn.model_selection import train_test_split


@dataclass
class ImageData:
    mat_path: str
    img_rgb: np.ndarray
    img_bgr_u8: np.ndarray
    img_lab: np.ndarray
    roi_mask: np.ndarray


def _safe_loadmat(path: str) -> Dict:
    """Load .mat with broad scipy compatibility."""
    try:
        return loadmat(path, simplify_cells=True)
    except TypeError:
        return loadmat(path, squeeze_me=True, struct_as_record=False)


def _to_dict(obj):
    """Convert scipy mat-struct objects to nested dicts when needed."""
    if isinstance(obj, dict):
        return {k: _to_dict(v) for k, v in obj.items()}

    if hasattr(obj, "_fieldnames"):
        out = {}
        for name in obj._fieldnames:
            out[name] = _to_dict(getattr(obj, name))
        return out

    return obj


def load_mat_image(mat_path: str) -> ImageData:
    data = _to_dict(_safe_loadmat(mat_path))

    if "img_color_corrected" not in data:
        raise ValueError(f"Missing 'img_color_corrected' in: {mat_path}")

    img_rgb = np.asarray(data["img_color_corrected"], dtype=np.float32)
    if img_rgb.ndim != 3 or img_rgb.shape[2] != 3:
        raise ValueError(f"img_color_corrected is not HxWx3 in: {mat_path}")

    # Robust scaling to [0,1] if values are outside display range.
    img_min = float(np.nanmin(img_rgb))
    img_max = float(np.nanmax(img_rgb))
    if img_max > 1.0 or img_min < 0.0:
        denom = img_max - img_min
        if denom > 0:
            img_rgb = (img_rgb - img_min) / denom
        else:
            img_rgb = np.zeros_like(img_rgb)

    img_rgb = np.clip(img_rgb, 0.0, 1.0)

    img_bgr_u8 = cv2.cvtColor((img_rgb * 255).astype(np.uint8), cv2.COLOR_RGB2BGR)
    img_lab = cv2.cvtColor(img_bgr_u8, cv2.COLOR_BGR2LAB).astype(np.float32)

    h, w, _ = img_rgb.shape
    roi_mask = np.ones((h, w), dtype=bool)

    roi_data = data.get("roiData", None)
    if roi_data is not None and isinstance(roi_data, dict):
        lightness_values = roi_data.get("lightnessValues", None)
        if lightness_values is not None:
            arr = np.asarray(lightness_values)
            if arr.shape == (h, w):
                roi_mask = ~np.isnan(arr)

    return ImageData(
        mat_path=mat_path,
        img_rgb=img_rgb,
        img_bgr_u8=img_bgr_u8,
        img_lab=img_lab,
        roi_mask=roi_mask,
    )


class PixelSelector:
    def __init__(self, class_names: List[str]):
        self.class_names = class_names
        self.num_classes = len(class_names)
        self.current_class_idx = 0

        self.samples: List[Dict] = []
        self.class_colors = self._make_colors(self.num_classes)

        self.display_image = None
        self.image_data: ImageData | None = None

    @staticmethod
    def _make_colors(n: int) -> List[Tuple[int, int, int]]:
        # OpenCV uses BGR colors.
        palette = [
            (0, 255, 0),
            (255, 0, 0),
            (0, 0, 255),
            (255, 255, 0),
            (255, 0, 255),
            (0, 255, 255),
            (128, 255, 0),
            (255, 128, 0),
            (128, 0, 255),
            (0, 128, 255),
        ]
        if n <= len(palette):
            return palette[:n]
        out = []
        for i in range(n):
            out.append(palette[i % len(palette)])
        return out

    def _set_title(self):
        assert self.image_data is not None
        file_name = os.path.basename(self.image_data.mat_path)
        current_name = self.class_names[self.current_class_idx]
        status = (
            f"{file_name} | Class [{self.current_class_idx+1}/{self.num_classes}]: {current_name} | "
            "Left click: sample | [ / ]: class | s: next image | q: quit"
        )
        cv2.setWindowTitle("Pixel Selector", status)

    def mouse_callback(self, event, x, y, flags, param):
        if event != cv2.EVENT_LBUTTONDOWN:
            return

        if self.image_data is None:
            return

        h, w = self.image_data.roi_mask.shape
        if x < 0 or x >= w or y < 0 or y >= h:
            return

        if not self.image_data.roi_mask[y, x]:
            return

        rgb = self.image_data.img_rgb[y, x, :].astype(float)
        lab = self.image_data.img_lab[y, x, :].astype(float)

        sample = {
            "mat_path": self.image_data.mat_path,
            "class_index": int(self.current_class_idx),
            "class_name": self.class_names[self.current_class_idx],
            "x": int(x),
            "y": int(y),
            "rgb": rgb.tolist(),
            "lab": lab.tolist(),
        }
        self.samples.append(sample)

        color = self.class_colors[self.current_class_idx]
        cv2.circle(self.display_image, (x, y), 3, color, -1)
        cv2.imshow("Pixel Selector", self.display_image)

        print(
            f"Added sample #{len(self.samples)} | "
            f"class={sample['class_name']} | "
            f"pos=({x},{y}) | "
            f"LAB={np.round(lab, 2)}"
        )

    def select_pixels_from_image(self, image_data: ImageData) -> bool:
        self.image_data = image_data
        self.display_image = image_data.img_bgr_u8.copy()

        # Shade non-ROI pixels for visual feedback.
        non_roi = ~image_data.roi_mask
        if np.any(non_roi):
            overlay = self.display_image.copy()
            overlay[non_roi] = (70, 70, 70)
            self.display_image = cv2.addWeighted(self.display_image, 0.5, overlay, 0.5, 0)

        cv2.namedWindow("Pixel Selector", cv2.WINDOW_NORMAL)
        cv2.setMouseCallback("Pixel Selector", self.mouse_callback)
        self._set_title()

        print("\n" + "=" * 80)
        print(f"Image: {os.path.basename(image_data.mat_path)}")
        print("Controls: left-click sample | use number keys to switch classes | s next image | q quit")
        print("".join([f"\n  {i+1}. {name}" for i, name in enumerate(self.class_names)]))
        print("=" * 80)

        cv2.imshow("Pixel Selector", self.display_image)

        while True:
            key = cv2.waitKey(20) & 0xFF

            if key == ord("["):
                self.current_class_idx = (self.current_class_idx - 1) % self.num_classes
                print(f"Current class -> {self.class_names[self.current_class_idx]}")
                self._set_title()
            elif key == ord("]"):
                self.current_class_idx = (self.current_class_idx + 1) % self.num_classes
                print(f"Current class -> {self.class_names[self.current_class_idx]}")
                self._set_title()
            elif ord("1") <= key <= ord("9"):
                idx = key - ord("1")
                if idx < self.num_classes:
                    self.current_class_idx = idx
                    print(f"Current class -> {self.class_names[self.current_class_idx]}")
                    self._set_title()
            elif key == ord("s"):
                print("Next image.")
                cv2.destroyWindow("Pixel Selector")
                return True
            elif key == ord("q"):
                print("Quit requested.")
                cv2.destroyWindow("Pixel Selector")
                return False


def build_dataset(samples: List[Dict], class_names: List[str]):
    if len(samples) == 0:
        raise ValueError("No training samples collected.")

    X = np.array([s["lab"] for s in samples], dtype=np.float32)
    y = np.array([s["class_index"] for s in samples], dtype=np.int32)

    class_counts = {name: int(np.sum(y == i)) for i, name in enumerate(class_names)}
    missing = [name for name, count in class_counts.items() if count == 0]
    if missing:
        raise ValueError(f"Missing samples for classes: {missing}")

    metadata = pd.DataFrame(
        {
            "mat_path": [s["mat_path"] for s in samples],
            "class_index": [s["class_index"] for s in samples],
            "class_name": [s["class_name"] for s in samples],
            "x": [s["x"] for s in samples],
            "y": [s["y"] for s in samples],
            "L": [s["lab"][0] for s in samples],
            "a": [s["lab"][1] for s in samples],
            "b": [s["lab"][2] for s in samples],
            "R": [s["rgb"][0] for s in samples],
            "G": [s["rgb"][1] for s in samples],
            "B": [s["rgb"][2] for s in samples],
        }
    )

    return X, y, metadata, class_counts


def train_random_forest(
    X: np.ndarray,
    y: np.ndarray,
    class_names: List[str],
    seed: int,
    test_size: float,
    n_trees: int,
    unclassified_threshold: float,
):
    X_train, X_test, y_train, y_test = train_test_split(
        X,
        y,
        test_size=test_size,
        random_state=seed,
        stratify=y,
    )

    clf = RandomForestClassifier(
        n_estimators=n_trees,
        random_state=seed,
        n_jobs=-1,
        class_weight="balanced_subsample",
    )
    clf.fit(X_train, y_train)

    # Raw predictions
    y_pred_raw = clf.predict(X_test)
    y_prob = clf.predict_proba(X_test)
    y_conf = np.max(y_prob, axis=1)

    n = len(class_names)
    unclassified_index = n

    # n+1 class: unclassified
    y_pred_thresholded = y_pred_raw.copy()
    y_pred_thresholded[y_conf < unclassified_threshold] = unclassified_index

    raw_acc = float(np.mean(y_pred_raw == y_test))

    classified_mask = y_pred_thresholded != unclassified_index
    coverage = float(np.mean(classified_mask))
    if np.any(classified_mask):
        classified_acc = float(np.mean(y_pred_thresholded[classified_mask] == y_test[classified_mask]))
    else:
        classified_acc = 0.0

    target_names_n = list(class_names)
    target_names_n1 = list(class_names) + ["Unclassified"]

    report_raw = classification_report(
        y_test,
        y_pred_raw,
        labels=list(range(n)),
        target_names=target_names_n,
        zero_division=0,
    )

    report_thresholded = classification_report(
        y_test,
        y_pred_thresholded,
        labels=list(range(n + 1)),
        target_names=target_names_n1,
        zero_division=0,
    )

    cm_raw = confusion_matrix(y_test, y_pred_raw, labels=list(range(n)))
    cm_thresholded = confusion_matrix(y_test, y_pred_thresholded, labels=list(range(n + 1)))

    metrics = {
        "raw_accuracy": raw_acc,
        "coverage_after_threshold": coverage,
        "accuracy_on_classified_pixels": classified_acc,
        "n_train": int(len(X_train)),
        "n_test": int(len(X_test)),
        "report_raw": report_raw,
        "report_thresholded": report_thresholded,
        "confusion_raw": cm_raw,
        "confusion_thresholded": cm_thresholded,
        "unclassified_threshold": float(unclassified_threshold),
    }

    return clf, metrics, (X_train, X_test, y_train, y_test, y_pred_raw, y_pred_thresholded)


def save_diagnostics(out_dir: str, class_names: List[str], clf: RandomForestClassifier, metrics: Dict):
    os.makedirs(out_dir, exist_ok=True)

    # Raw confusion matrix (NxN)
    cm_raw = metrics["confusion_raw"]
    plt.figure(figsize=(8, 6))
    sns.heatmap(cm_raw, annot=True, fmt="d", cmap="Blues", xticklabels=class_names, yticklabels=class_names)
    plt.title("Confusion Matrix (Raw Predictions)")
    plt.xlabel("Predicted")
    plt.ylabel("True")
    plt.tight_layout()
    plt.savefig(os.path.join(out_dir, "confusion_matrix_raw.png"), dpi=150)
    plt.close()

    # Thresholded confusion matrix (N x N+1)
    cm_thr = metrics["confusion_thresholded"]
    cols = list(class_names) + ["Unclassified"]
    rows = list(class_names) + ["Unclassified"]
    plt.figure(figsize=(9, 6))
    sns.heatmap(cm_thr, annot=True, fmt="d", cmap="Oranges", xticklabels=cols, yticklabels=rows)
    plt.title("Confusion Matrix (Thresholded with Unclassified)")
    plt.xlabel("Predicted")
    plt.ylabel("True")
    plt.tight_layout()
    plt.savefig(os.path.join(out_dir, "confusion_matrix_thresholded.png"), dpi=150)
    plt.close()

    # Feature importance
    feat_names = ["L", "a", "b"]
    plt.figure(figsize=(6, 4))
    plt.bar(feat_names, clf.feature_importances_)
    plt.title("Feature Importance")
    plt.ylabel("Importance")
    plt.tight_layout()
    plt.savefig(os.path.join(out_dir, "feature_importance.png"), dpi=150)
    plt.close()


def classify_mat_image(
    model_data: Dict,
    mat_path: str,
    out_dir: str,
):
    image_data = load_mat_image(mat_path)
    h, w, _ = image_data.img_lab.shape

    X = image_data.img_lab.reshape(-1, 3)
    clf: RandomForestClassifier = model_data["classifier"]

    y_pred = clf.predict(X)
    y_prob = clf.predict_proba(X)
    y_conf = np.max(y_prob, axis=1)

    class_names = model_data["class_names"]
    threshold = model_data["unclassified_threshold"]
    n = len(class_names)
    unclassified_index = n

    y_pred_thr = y_pred.copy()
    y_pred_thr[y_conf < threshold] = unclassified_index

    pred_map = y_pred_thr.reshape(h, w)

    os.makedirs(out_dir, exist_ok=True)
    base = os.path.splitext(os.path.basename(mat_path))[0]

    # Save numpy map (raw prediction map; ROI mask is kept separate in MAT data)
    np.save(os.path.join(out_dir, f"{base}_pred_map.npy"), pred_map)

    # Save color visualization
    colors = np.array(
        [
            [0.0, 0.8, 0.0],
            [0.0, 0.2, 1.0],
            [1.0, 0.3, 0.0],
            [0.8, 0.0, 0.8],
            [0.2, 0.8, 0.8],
            [0.8, 0.8, 0.2],
            [0.6, 0.6, 0.6],
        ],
        dtype=np.float32,
    )
    n_colors_needed = n + 1
    if n_colors_needed > len(colors):
        extra = np.random.RandomState(0).rand(n_colors_needed - len(colors), 3).astype(np.float32)
        colors = np.vstack([colors, extra])

    pred_map_roi = np.ma.masked_where(~image_data.roi_mask, pred_map)
    cmap = ListedColormap(colors[:n_colors_needed])
    cmap.set_bad(alpha=0.0)  # transparent outside ROI (masked values)
    norm = BoundaryNorm(np.arange(-0.5, n_colors_needed + 0.5, 1), n_colors_needed)

    # Show ROI in the same style as training selection (dim outside ROI).
    input_rgb_vis = image_data.img_rgb.copy()
    non_roi = ~image_data.roi_mask
    if np.any(non_roi):
        gray_rgb = np.array([70, 70, 70], dtype=np.float32) / 255.0
        input_rgb_vis[non_roi] = 0.5 * input_rgb_vis[non_roi] + 0.5 * gray_rgb

    plt.figure(figsize=(12, 5))
    plt.subplot(1, 2, 1)
    plt.imshow(input_rgb_vis)
    plt.axis("off")
    plt.title("Input sRGB (ROI shown)")

    plt.subplot(1, 2, 2)
    # Classify using LAB, but visualize results over the sRGB image.
    plt.imshow(input_rgb_vis)
    plt.imshow(pred_map_roi, cmap=cmap, norm=norm, alpha=0.65)
    plt.axis("off")
    plt.title("Predicted Classes on sRGB (Unclassified is gray)")

    legend_names = class_names + ["Unclassified"]
    legend_handles = [
        Patch(facecolor=colors[i], edgecolor="black", label=legend_names[i])
        for i in range(n_colors_needed)
    ]
    plt.figlegend(
        handles=legend_handles,
        loc="lower center",
        ncol=min(4, n_colors_needed),
        frameon=False,
        fontsize=8,
    )
    plt.tight_layout()
    plt.savefig(os.path.join(out_dir, f"{base}_prediction.png"), dpi=150, transparent=True)
    plt.close()

    print(f"Saved prediction outputs for {base} to: {out_dir}")


def prompt_user_settings():
    default_folder = r"C:\Users\au686295\GitHub\data\AU\BeaImageColor2025\sites\calibrated_output"

    im_folder = input(f"MAT folder [{default_folder}]: ").strip()
    if im_folder == "":
        im_folder = default_folder

    num_classes = int(input("Number of classes (N): ").strip())
    if num_classes < 2:
        raise ValueError("Number of classes must be >= 2.")

    class_names_raw = input(
        "Class names (comma-separated, exactly N names): "
    ).strip()
    class_names = [x.strip() for x in class_names_raw.split(",") if x.strip()]
    if len(class_names) != num_classes:
        raise ValueError(f"Expected {num_classes} class names, got {len(class_names)}")

    seed = int(input("Random seed [42]: ").strip() or "42")
    test_size = float(input("Test split fraction [0.2]: ").strip() or "0.2")
    n_trees = int(input("RandomForest number of trees [300]: ").strip() or "300")
    threshold = float(input("Unclassified confidence threshold [0.60]: ").strip() or "0.60")

    default_model_path = os.path.join(im_folder, "rf_training_output", "vegetation_classifier_rf.pkl")
    model_output_path = input(f"Model output path [{default_model_path}]: ").strip()
    if model_output_path == "":
        model_output_path = default_model_path

    if not (0.0 <= threshold <= 1.0):
        raise ValueError("Threshold must be within [0,1].")

    return im_folder, class_names, seed, test_size, n_trees, threshold, model_output_path


def main():
    print("\nInteractive Random Forest training from calibrated MAT files")
    print("Unclassified will be class N+1 based on confidence threshold.\n")

    im_folder, class_names, seed, test_size, n_trees, threshold, model_output_path = prompt_user_settings()

    mat_files = sorted(glob.glob(os.path.join(im_folder, "*_roi_data.mat")))
    if len(mat_files) == 0:
        mat_files = sorted(glob.glob(os.path.join(im_folder, "*.mat")))

    if len(mat_files) == 0:
        raise FileNotFoundError(f"No MAT files found in folder: {im_folder}")

    print(f"\nFound {len(mat_files)} MAT files.")

    selector = PixelSelector(class_names)

    # Shuffle image order reproducibly.
    rng = np.random.RandomState(seed)
    idx = rng.permutation(len(mat_files))
    ordered_files = [mat_files[i] for i in idx]

    for i, mat_path in enumerate(ordered_files, start=1):
        print(f"\n[{i}/{len(ordered_files)}] {os.path.basename(mat_path)}")
        try:
            image_data = load_mat_image(mat_path)
        except Exception as exc:
            print(f"Skipping {mat_path}: {exc}")
            continue

        go_next = selector.select_pixels_from_image(image_data)
        if not go_next:
            break

    cv2.destroyAllWindows()

    X, y, metadata, class_counts = build_dataset(selector.samples, class_names)

    print("\nClass sample counts:")
    for name in class_names:
        print(f"  {name}: {class_counts[name]}")

    clf, metrics, split_data = train_random_forest(
        X=X,
        y=y,
        class_names=class_names,
        seed=seed,
        test_size=test_size,
        n_trees=n_trees,
        unclassified_threshold=threshold,
    )

    print("\n=== Model Metrics ===")
    print(f"Raw test accuracy: {metrics['raw_accuracy']:.4f}")
    print(f"Coverage after threshold: {metrics['coverage_after_threshold']:.4f}")
    print(f"Accuracy on classified pixels: {metrics['accuracy_on_classified_pixels']:.4f}")
    print("\nRaw report:\n")
    print(metrics["report_raw"])
    print("\nThresholded report (with Unclassified as N+1):\n")
    print(metrics["report_thresholded"])

    out_dir = os.path.join(im_folder, "rf_training_output")
    os.makedirs(out_dir, exist_ok=True)

    # Save diagnostics
    save_diagnostics(out_dir, class_names, clf, metrics)

    # Save training data (includes pixel coordinates and image paths)
    training_data_path = os.path.join(out_dir, "training_data.pkl")
    with open(training_data_path, "wb") as f:
        pickle.dump(
            {
                "class_names": class_names,
                "samples": selector.samples,
                "metadata_table": metadata,
                "class_counts": class_counts,
                "seed": seed,
            },
            f,
        )

    # Save model package
    model_path = model_output_path
    model_dir = os.path.dirname(model_path)
    if model_dir:
        os.makedirs(model_dir, exist_ok=True)
    model_data = {
        "classifier": clf,
        "class_names": class_names,
        "unclassified_class_name": "Unclassified",
        "unclassified_class_index": len(class_names),
        "unclassified_threshold": threshold,
        "feature_space": "LAB",
        "seed": seed,
        "n_trees": n_trees,
        "metrics": metrics,
    }
    with open(model_path, "wb") as f:
        pickle.dump(model_data, f)

    # Optional: classify one MAT file now
    ans = input("\nRun prediction on one MAT file now? [y/N]: ").strip().lower()
    if ans == "y":
        print("Select a file index:")
        for i, p in enumerate(ordered_files):
            print(f"  {i}: {os.path.basename(p)}")
        idx_str = input("Index [0]: ").strip() or "0"
        sel_idx = int(idx_str)
        sel_idx = max(0, min(sel_idx, len(ordered_files) - 1))
        classify_mat_image(model_data, ordered_files[sel_idx], out_dir)

    print("\nDone.")
    print(f"Training data: {training_data_path}")
    print(f"Model:         {model_path}")
    print(f"Diagnostics:   {out_dir}")


if __name__ == "__main__":
    main()

