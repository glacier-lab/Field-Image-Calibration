'''
This script evaluates the performance of a random forest model on a test set and plots a confusion matrix.

confusion matrix for the random forest model on the test set
            white ice dark ice cryoconites
white ice   34        6        3
dark ice    7         31       0
cryoconites 0         2        28

'''

#%%
import numpy as np
import matplotlib.pyplot as plt
import seaborn as sns
import cmocean as cmo
sns.set_theme(style="darkgrid", font_scale=1.5)

#%% create and plot a confusion matrix
confusion_matrix = np.array([[34, 6, 3],
                            [7, 31, 0],
                            [0, 2, 28]])
# convert to ratios
confusion_matrix_ratios = confusion_matrix / confusion_matrix.sum(axis=1, keepdims=True)

fig, ax = plt.subplots(figsize=(8, 6))
sns.heatmap(ax=ax, data=confusion_matrix_ratios, annot=True, 
            vmin=0, vmax=1, cbar_kws={'label': 'Accuracy'},
            fmt=".2f", cmap=cmo.cm.ice_r, cbar=True, 
            xticklabels=["white ice", "dark ice", "cryoconites"], 
            yticklabels=["white ice", "dark ice", "cryoconites"])
ax.set_xlabel("Predicted")
ax.set_ylabel("True")

fig.savefig("../print/confusion_matrix.png", dpi=300, bbox_inches="tight")
fig.savefig("../print/confusion_matrix.pdf", dpi=300, bbox_inches="tight")

# print the total accuracy
total_accuracy = np.trace(confusion_matrix) / np.sum(confusion_matrix)
print(f"Total Accuracy: {total_accuracy:.2f}")