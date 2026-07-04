'''
This script performs a darkening analysis on glacier algae data. It reads in the data from an Excel file, 
processes it, and then fits a multiple linear regression model to predict lightness values based on cell 
concentration and cloud cover fraction. The results are visualized in a 1x2 subplot format, showing the
relationship between cell concentration and lightness, as well as the predicted versus actual lightness 
values. The script also calculates and prints relevant statistics such as R-squared, p-value, RMSE, MAE,
and the regression equation.

Shunan Feng (shunan.feng@envs.au.dk)
'''

#%%
import pandas as pd
import matplotlib.pyplot as plt
import seaborn as sns
import numpy as np
from scipy import stats
from sklearn.linear_model import LinearRegression
sns.set_theme(style="darkgrid", font_scale=1.5)

#%%
filepath ="../stat/LAIs.xlsx"
df = pd.read_excel(filepath, sheet_name="glacier_algae")
df = df.dropna(subset=["Total Ancylomena cells [mL-1]", "Lightness values", "cc_frac"])
df["cell_log"] = np.log(df["Total Ancylomena cells [mL-1]"])
df["ice_frac"] = 1 - df["cc_frac"]
df["algae_per_ice"] = df["Total Ancylomena cells [mL-1]"] * df["ice_frac"]
# %% use a multiple regression model to predict lightness from cell_log and ice_frac and cc frac

mdl = LinearRegression()

X = df[["cell_log", "cc_frac"]]
y = df["Lightness values"]
mdl.fit(X, y)

# evaluate the model
r_squared = mdl.score(X, y)
p_value = stats.linregress(mdl.predict(X), y).pvalue
coef_terms = [f"{coef:.4f}*{name}" for coef, name in zip(mdl.coef_, X.columns)]
rmse = np.sqrt(np.mean((mdl.predict(X) - y) ** 2))
mae = np.mean(np.abs(mdl.predict(X) - y))
# equation 
equation = f"Lightness = {mdl.intercept_:.4f} + ".join(coef_terms)
print(f"R-squared: {r_squared:.4f}")
print(f"p-value: {p_value:.4f}")
print(f"RMSE: {rmse:.4f}")
print(f"MAE: {mae:.4f}")
print(f"Equation: {equation}")

# %% 1 * 2 subplots, left: cell vs lightness, right: predict vs actual
fig, axs = plt.subplots(1, 2, figsize=(14, 6))
sns.regplot(
    data=df,
    y='Lightness values',
    x='cell_log',
    color="#20206a", # flareon
    ax=axs[0]
)


sns.regplot(
    x=y,
    y=mdl.predict(X),
    color="#d54152", # flareon
    ax=axs[1]
)
# add 1:1 line to the right plot
axs[1].plot([0, 1], [0, 1], 'k--', lw=2)
axs[1].set_xlim(0.5, 0.95)
axs[1].set_ylim(0.5, 0.95)

axs[0].set_ylabel("CIELAB Lightness (L*)/100")
axs[0].set_xlabel("log(Cell Concentration mL$^{-1}$)")
axs[1].set_ylabel("Predicted Lightness")
axs[1].set_xlabel("Actual Lightness")

# axs[0].set_aspect()
axs[1].set_aspect('equal')

# add statistics to the left plot
statistics = stats.linregress(df['cell_log'], df['Lightness values'])
axs[0].text(0.05, 0.95, f"a) r² = {statistics.rvalue**2:.3f} (p<0.001)", transform=axs[0].transAxes, verticalalignment='top')
# print equation of the left plot
print(f"Equation: Lightness = {statistics.intercept:.4f} + {statistics.slope:.4f}*log(Cell Concentration mL$^{-1}$)")
# add statistics to the right plot
statistics = stats.linregress(mdl.predict(X), y)
axs[1].text(0.05, 0.95, f"b) r² = {statistics.rvalue**2:.3f} (p<0.001)", transform=axs[1].transAxes, verticalalignment='top')
# print equation of the right plot
print(f"Equation: Lightness = {mdl.intercept_:.4f} + {mdl.coef_[0]:.4f}*log(Cell Concentration mL$^{-1}$) + {mdl.coef_[1]:.4f}*cc_frac")

fig.savefig("../print/darkening_analysis.png", dpi=300, bbox_inches='tight')
fig.savefig("../print/darkening_analysis.pdf", dpi=300, bbox_inches='tight')
# %%
