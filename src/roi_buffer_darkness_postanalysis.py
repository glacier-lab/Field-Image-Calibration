#%%
import pandas as pd
import matplotlib.pyplot as plt
import seaborn as sns

sns.set_theme(style="darkgrid", font_scale=1.5)
# %%
csv_path = r"C:\Users\au686295\GitHub\postdoc\Field-Image-Calibration\stat\roi_buffer_darkness_summary copy.csv"
df = pd.read_csv(csv_path)
ref_darkness = df[df["buffer_cm"] == 0]["mean_lightness"]
df["bias"] = df["mean_lightness"] - ref_darkness.values

#%%
fig, axs = plt.subplots(1, 2, figsize=(16, 8))
sns.barplot(data=df, x="buffer_cm", y="bias", ax=axs[0], color="#20206a")
axs[0].set_ylabel("Bias in mean lightness (vs buffer=0)")
axs[0].set_xlabel("Buffer (cm)")

sns.barplot(data=df, x="buffer_cm", y="std_lightness", ax=axs[1], color="#d54152")
axs[1].set_ylabel("Std of lightness")
axs[1].set_xlabel("Buffer (cm)")
# %%
