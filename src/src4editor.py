#%%
import pandas as pd
import matplotlib.pyplot as plt
import seaborn as sns

sns.set_theme(style="darkgrid", font_scale=1.5)
# %%
df = pd.read_excel(r"O:\Tech_ENVS-EMBI-Afdelingsdrev\Shunan\GlacierLab\Development\iCalibrateImages\data\sensitivity_test\height_sensitivity.xlsx")
# %%
fig, ax = plt.subplots(figsize=(6, 4))
sns.barplot(data=df, x="height", y="lightness", ax=ax)
# add error bars using the std column
for i, (index, row) in enumerate(df.iterrows()):
    ax.errorbar(x=i, y=row["lightness"], yerr=row["std"], fmt='none', c='black', capsize=5)
ax.set_xlabel("Height (cm)")
ax.set_ylabel("Lightness (L$^*$)")
fig.savefig(r"O:\Tech_ENVS-EMBI-Afdelingsdrev\Shunan\GlacierLab\Development\iCalibrateImages\data\sensitivity_test\height_sensitivity.png", dpi=300, bbox_inches='tight')
fig.savefig(r"O:\Tech_ENVS-EMBI-Afdelingsdrev\Shunan\GlacierLab\Development\iCalibrateImages\data\sensitivity_test\height_sensitivity.pdf", dpi=300, bbox_inches='tight')
# %%
