'''
This script evaluates the performance of a random forest model on a test set and plots a confusion matrix.

confusion matrix for the random forest model on the test set
            white ice dark ice cryoconites
white ice   34        6        3
dark ice    7         31       0
cryoconites 0         2        28

'''

#%%
import pickle
import os
from typing import Any
import numpy as np
import matplotlib.pyplot as plt
import seaborn as sns
import cmocean as cmo
sns.set_theme(style="darkgrid", font_scale=1.5)

SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
PRINT_DIR = os.path.normpath(os.path.join(SCRIPT_DIR, "..", "print"))
os.makedirs(PRINT_DIR, exist_ok=True)

#%% create and plot a confusion matrix
confusion_matrix = np.array([[34, 6, 3],
                            [7, 31, 0],
                            [0, 2, 28]])
# convert to ratios
confusion_matrix_ratios = confusion_matrix / confusion_matrix.sum(axis=1, keepdims=True)

# Combined annotations: percentage for readability + count for sample support.
cm_annot = np.array(
    [
        [f"{p * 100:.1f}%\n(n={c})" for p, c in zip(row_p, row_c)]
        for row_p, row_c in zip(confusion_matrix_ratios, confusion_matrix)
    ]
)

# print the total accuracy
total_accuracy = np.trace(confusion_matrix) / np.sum(confusion_matrix)
print(f"Total Accuracy: {total_accuracy:.2f}")

#%% load predictor importance data and plot
model_path = r"E:\iCalibrateImages\data\BGO_calibrated_output\rf_training_output\vegetation_classifier_rf.pkl"


with open(model_path, "rb") as f:
    model_obj = pickle.load(f)

# Saved training script stores a dict with classifier under "classifier".
if isinstance(model_obj, dict) and "classifier" in model_obj:
    clf: Any = model_obj["classifier"]
    feature_space = str(model_obj.get("feature_space", "LAB")).upper()
else:
    clf = model_obj
    feature_space = "LAB"

feature_importances = np.asarray(clf.feature_importances_, dtype=float)
n_features = feature_importances.shape[0]

default_names = [f"Feature {i+1}" for i in range(n_features)]
if feature_space == "LAB" and n_features == 3:
    predictor_names = ["L*", "a*", "b*"]
elif feature_space == "RGB" and n_features == 3:
    predictor_names = ["R", "G", "B"]
else:
    predictor_names = default_names


order = np.argsort(feature_importances)[::-1]
sorted_names = [predictor_names[i] for i in order]
sorted_importances = feature_importances[order]

#%% combined figure: confusion matrix + predictor importance
fig, (ax_cm, ax_imp) = plt.subplots(1, 2, figsize=(14, 6), constrained_layout=True)

sns.heatmap(
    ax=ax_cm,
    data=confusion_matrix_ratios * 100,
    annot=cm_annot,
    vmin=0,
    vmax=100,
    cbar_kws={'label': 'Row-normalized percentage (%)'},
    fmt="",
    cmap="cmo.ice_r",
    cbar=True,
    xticklabels=["white ice", "dark ice", "cryoconites"],
    yticklabels=["white ice", "dark ice", "cryoconites"],
)
ax_cm.set_xlabel("Predicted")
ax_cm.set_ylabel("True")
ax_cm.text(-0.08, -0.1, "a) ", transform=ax_cm.transAxes, ha="center")
# ax_cm.set_title("a) Confusion Matrix (row-normalized)")

sns.barplot(x=sorted_importances, y=sorted_names, ax=ax_imp, palette="Blues_d")
ax_imp.set_xlabel("Importance")
ax_imp.set_ylabel("Predictor")
# ax_imp.set_title("b) Random Forest Predictor Importance")
ax_imp.set_xlim(0, max(1.0, float(np.max(sorted_importances) * 1.1)))
ax_imp.text(-0.08, -0.1, "b) ", transform=ax_imp.transAxes, ha="center")

for idx, value in enumerate(sorted_importances):
    ax_imp.text(value + 0.01, idx, f"{value:.2f}", va="center")

fig.savefig(os.path.join(PRINT_DIR, "rf_evaluation.png"), dpi=300, bbox_inches="tight")
fig.savefig(os.path.join(PRINT_DIR, "rf_evaluation.pdf"), dpi=300, bbox_inches="tight")

print("Predictor importances:")
for name, value in zip(sorted_names, sorted_importances):
    print(f"  {name}: {value:.4f}")

# %% summary of classifier performance, number of samples per class, and total accuracy
print("\nClassifier Performance Summary:")

for i, (class_name, n_samples) in enumerate(zip(["white ice", "dark ice", "cryoconites"], np.sum(confusion_matrix, axis=1))):
    print(f"  {class_name}: {n_samples} samples")

print(f"  Total Accuracy: {total_accuracy:.2f}")

print(f"  Total number of training samples: {model_obj.get('metrics', {}).get('n_train')}")
print(f"  Total number of test samples: {model_obj.get('metrics', {}).get('n_test')}")

# %%
'''
Classifier Performance Summary:
  white ice: 43 samples
  dark ice: 38 samples
  cryoconites: 30 samples
  Total Accuracy: 0.84
  Total number of training samples: 443
  Total number of test samples: 111
'''