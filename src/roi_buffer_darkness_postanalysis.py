#%%
import pandas as pd
import matplotlib.pyplot as plt
import seaborn as sns
from matplotlib.ticker import MultipleLocator

sns.set_theme(style="darkgrid", font_scale=1.5)
# %%
# csv_path = r"C:\Users\au686295\GitHub\postdoc\Field-Image-Calibration\stat\roi_buffer_darkness_summary.csv"
csv_path = r"C:\Users\au686295\GitHub\postdoc\Field-Image-Calibration\stat\roi_buffer_darkness_per_image.csv"
df = pd.read_csv(csv_path)
# baseline per file (buffer_cm == 0), broadcast back to every buffer step of that file
baseline = df[df["buffer_cm"] == 0].set_index("file")["mean_lightness"]
df["bias"] = df["mean_lightness"] - df["file"].map(baseline)

# %%
fig, ax = plt.subplots(1, 1, figsize=(16, 8))
sns.barplot(data=df, x="buffer_cm", y="bias", ax=ax, errorbar="sd")
ax.set_ylabel(r"$\Delta$ Mean L$^*$ (relative to 0 cm buffer)")
ax.set_xlabel("Buffer (cm)")
ax.xaxis.set_major_locator(MultipleLocator(2))  

fig.savefig(r"C:\Users\au686295\GitHub\postdoc\Field-Image-Calibration\print\roi_buffer_darkness_bias.png", dpi=300, bbox_inches="tight")
fig.savefig(r"C:\Users\au686295\GitHub\postdoc\Field-Image-Calibration\print\roi_buffer_darkness_bias.pdf", dpi=300, bbox_inches="tight")
# %% print statistics
print("Mean bias per buffer step:")
print(df.groupby("buffer_cm")["bias"].mean())
print("Standard deviation of bias per buffer step:")
print(df.groupby("buffer_cm")["bias"].std())