"""Inspect LAB distribution for disp_cco training samples.

This script expects training_data.pkl saved by trainInteractivePixelClassifier.py,
which has a dict-like structure with keys including:
- class_names
- samples (list of dicts, each with lab/rgb/class_name/etc.)
"""

#%%
import os

import pandas as pd
import matplotlib.pyplot as plt
import seaborn as sns
from scipy import stats


def remove_outliers_mad(df: pd.DataFrame, column: str = "L") -> pd.DataFrame:
	"""Remove outliers using Median Absolute Deviation (MAD)."""
	median = df[column].median()
	mad = stats.median_abs_deviation(df[column], scale=1)

	# Scale factor for approximately normal distributions.
	mad_scaled = mad * 1.4826

	lower_bound = median - mad_scaled
	upper_bound = median + mad_scaled

	print(f"MAD bounds for {column}: {lower_bound:.4f} to {upper_bound:.4f}")
	print(f"Q75 ({column}): {df[column].quantile(0.75):.4f}")
	print(f"Q25 ({column}): {df[column].quantile(0.25):.4f}")

	filtered_df = df[(df[column] > lower_bound) & (df[column] < upper_bound)]
	print(f"Removed {len(df) - len(filtered_df)} outliers using MAD method")

	return filtered_df


def main():
	training_file = r"C:\Users\au686295\GitHub\data\AU\BGO_calibrated_output\rf_training_output\training_data.pkl"
	out_dir = os.path.dirname(training_file)

	training_data = pd.read_pickle(training_file)

	# Support dict-like payloads produced by the training script.
	if isinstance(training_data, dict):
		samples = training_data.get("samples", [])
	else:
		raise TypeError("training_data.pkl is expected to contain a dict with a 'samples' key.")

	if len(samples) == 0:
		raise ValueError("No samples found in training_data['samples'].")

	df = pd.DataFrame(samples)
	if "class_name" not in df.columns or "lab" not in df.columns:
		raise ValueError("Sample entries must contain 'class_name' and 'lab'.")

	# Normalize class naming variants.
	class_name_norm = df["class_name"].astype(str).str.strip().str.lower()
	is_disp_cco = class_name_norm.isin(["disp_cco", "dispersed cryoconite", "dispersed cryoconites"])
	df_cco = df.loc[is_disp_cco].copy()

	if df_cco.empty:
		raise ValueError("No disp_cco (or dispersed cryoconite) samples found.")

	# Expand LAB triplet into separate columns.
	lab_df = pd.DataFrame(df_cco["lab"].tolist(), columns=["L", "a", "b"])
	for col in ["L", "a", "b"]:
		lab_df[col] = pd.to_numeric(lab_df[col], errors="coerce")
	lab_df = lab_df.dropna(subset=["L", "a", "b"])

	if lab_df.empty:
		raise ValueError("disp_cco samples exist, but LAB values are missing/invalid.")

	# Theoretically in CIELAB, Lightness L* is bounded to [0, 100].
	# a* and b* are not bounded to [0, 100], so only L is clipped.
	n_low = int((lab_df["L"] < 0).sum())
	n_high = int((lab_df["L"] > 100).sum())
	lab_df["L"] = lab_df["L"].clip(0, 100)

	# Remove Lightness outliers using MAD.
	lab_df = remove_outliers_mad(lab_df, column="L")
	if lab_df.empty:
		raise ValueError("No samples left after MAD outlier removal on L.")

	print("disp_cco sample count:", len(lab_df))
	print(f"L clipping applied: below 0 -> {n_low}, above 100 -> {n_high}")
	print("\nLAB summary statistics (disp_cco):")
	print(lab_df[["L", "a", "b"]].describe().round(3))

	# --- Plot 1: Lightness distribution (main focus) ---
	plt.figure(figsize=(10, 6))
	sns.histplot(data=lab_df, x="L", bins=40, kde=True, color="#e63131")
	plt.title("Distribution of Lightness (L, clipped to [0,100]) for disp_cco")
	plt.xlabel("L (LAB)")
	plt.ylabel("Count")
	plt.tight_layout()
	lightness_png = os.path.join(out_dir, "disp_cco_lightness_distribution.png")
	plt.savefig(lightness_png, dpi=200)
	plt.show()

	# --- Plot 2: LAB marginal distributions ---
	fig, axes = plt.subplots(1, 3, figsize=(15, 4.5))
	sns.histplot(data=lab_df, x="L", bins=35, kde=True, ax=axes[0], color="#e63131")
	axes[0].set_title("L distribution")
	axes[0].set_xlabel("L")
	axes[0].set_ylabel("Count")

	sns.histplot(data=lab_df, x="a", bins=35, kde=True, ax=axes[1], color="#104a62")
	axes[1].set_title("a distribution")
	axes[1].set_xlabel("a")
	axes[1].set_ylabel("Count")

	sns.histplot(data=lab_df, x="b", bins=35, kde=True, ax=axes[2], color="#83deff")
	axes[2].set_title("b distribution")
	axes[2].set_xlabel("b")
	axes[2].set_ylabel("Count")

	plt.tight_layout()
	lab_hist_png = os.path.join(out_dir, "disp_cco_lab_distributions.png")
	plt.savefig(lab_hist_png, dpi=200)
	plt.show()

	# --- Plot 3: Pairwise LAB relationships ---
	pair = sns.pairplot(lab_df[["L", "a", "b"]], corner=True, plot_kws={"s": 12, "alpha": 0.6})
	pair.fig.suptitle("disp_cco LAB pairwise distribution", y=1.02)
	pair_png = os.path.join(out_dir, "disp_cco_lab_pairplot.png")
	pair.savefig(pair_png, dpi=200)
	plt.show()

	# --- Plot 4: LAB boxplot ---
	plt.figure(figsize=(8, 5))
	lab_long = lab_df[["L", "a", "b"]].melt(var_name="Channel", value_name="Value")
	sns.boxplot(data=lab_long, x="Channel", y="Value", palette=["#e63131", "#104a62", "#83deff"])
	plt.title("disp_cco LAB boxplot (L clipped to [0,100])")
	plt.tight_layout()
	box_png = os.path.join(out_dir, "disp_cco_lab_boxplot.png")
	plt.savefig(box_png, dpi=200)
	plt.show()

	print("\nSaved plots:")
	print("-", lightness_png)
	print("-", lab_hist_png)
	print("-", pair_png)
	print("-", box_png)


if __name__ == "__main__":
	main()

# %%
