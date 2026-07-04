#%%
import pandas as pd
import matplotlib.pyplot as plt
import seaborn as sns
import numpy as np
from scipy import stats

sns.set_theme(style="darkgrid", font_scale=1.5)
#%%
filepath = r"C:\Users\au686295\OneDrive - Aarhus universitet\projects\PROMBIO\cellcount\Emily_2025_t5_cellcounts_final.xlsx"
df = pd.read_excel(filepath, sheet_name="BeaGR24_SF")
# drop rows with any missing values
df = df.dropna()
#%%
df["cell_log"] = np.log(df["Ancylonema Single cells in Filaments\n[mL-1]"])
fig, ax = plt.subplots(figsize=(7, 6))
sns.regplot(
    data=df,
    y='Darkness',
    x='cell_log',
    color="#106239", # victreebel
    ax=ax
)
statistics = stats.linregress(df['cell_log'], df['Darkness'])
# add statistics to the plot
ax.text(0.15, 0.25, f"r² = {statistics.rvalue**2:.2f}\np-value<0.001", transform=ax.transAxes, verticalalignment='top')
# ax.set_xlim(-9000, 1.2e5)
ax.set_ylabel("Lightness")
# print y-axis label with mL^{-1} in LaTeX format
ax.set_xlabel("log(Cell Concentration mL$^{-1}$)")

fig.savefig("Ancylonema_Single_cells_in_Filaments_vs_Lightness.png", dpi=300, bbox_inches='tight')
# %%
