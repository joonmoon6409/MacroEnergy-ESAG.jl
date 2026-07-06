"""
Capacity Expansion Analysis
Auto-generated after MacroEnergy run.
Produces national and province-level stacked bar charts.
"""
import pandas as pd
import matplotlib.pyplot as plt
import matplotlib.patches as mpatches
import numpy as np
from pathlib import Path

# ── Paths ──────────────────────────────────────────────────────────────────────
BASE_DIR = Path(__file__).parent
RESULTS_DIR = BASE_DIR / "results_002"
OUTPUT_DIR = BASE_DIR / "capacity_analysis"
OUTPUT_DIR.mkdir(exist_ok=True)

# ── Period → Year mapping ──────────────────────────────────────────────────────
PERIOD_YEARS = {1: 2021, 2: 2025, 3: 2030, 4: 2035}

# ── Province zones & display names ────────────────────────────────────────────
PROVINCE_ZONES = [
    "SEL", "PUS", "TAE", "INC", "KWJ", "DJJ", "USN", "SJG",
    "GGI", "GWN", "CNA", "CNB", "JNA", "JNB", "GNA", "GNB", "JEJ",
]
PROVINCE_NAMES = {
    "SEL": "Seoul",         "PUS": "Busan",          "TAE": "Daegu",
    "INC": "Incheon",       "KWJ": "Gwangju",        "DJJ": "Daejeon",
    "USN": "Ulsan",         "SJG": "Sejong",         "GGI": "Gyeonggi",
    "GWN": "Gangwon",       "CNA": "S.Chungcheong",  "CNB": "N.Chungcheong",
    "JNA": "S.Jeolla",      "JNB": "N.Jeolla",       "GNA": "S.Gyeongsang",
    "GNB": "N.Gyeongsang",  "JEJ": "Jeju",
}

# ── Technology stack order (bottom → top), labels, colors ─────────────────────
TECH_STACK = [
    ("Battery",       "Battery",       "#7B2FBE"),
    ("Offshore Wind", "Offshore Wind", "#2CA02C"),
    ("Onshore Wind",  "Onshore Wind",  "#17BECF"),
    ("Solar PV",      "Solar PV",      "#FFCF29"),
    ("Gas CCS",       "Gas (CCS)",     "#74B9FF"),
    ("Coal CCS",      "Coal (CCS)",    "#A07850"),
    ("Nuclear",       "Nuclear",       "#FD9F3A"),
    ("Gas CCGT",      "Gas (CCGT)",    "#2B6CB0"),
    ("Coal",          "Coal",          "#1A1A1A"),
]
TECH_ORDER  = [t[0] for t in TECH_STACK]
TECH_LABELS = {t[0]: t[1] for t in TECH_STACK}
TECH_COLORS = {t[0]: t[2] for t in TECH_STACK}

# Label text color per technology (white on dark, dark on light)
LABEL_COLORS = {
    "Coal":          "white",
    "Gas CCGT":      "white",
    "Nuclear":       "#333333",
    "Coal CCS":      "white",
    "Gas CCS":       "#333333",
    "Solar PV":      "#333333",
    "Onshore Wind":  "#333333",
    "Offshore Wind": "white",
    "Battery":       "white",
}


# ── Technology classification ──────────────────────────────────────────────────
def classify_tech(row):
    rt = row["resource_type"]
    rid = str(row["resource_id"])
    if rt == "ThermalPower{NaturalGas}":     return "Gas CCGT"
    if rt == "ThermalPower{Coal}":           return "Coal"
    if rt == "ThermalPower{Uranium}":        return "Nuclear"
    if rt == "ThermalPowerCCS{NaturalGas}":  return "Gas CCS"
    if rt == "ThermalPowerCCS{Coal}":        return "Coal CCS"
    if rt == "Battery":                      return "Battery"
    if rt == "VRE":
        if "offshore" in rid: return "Offshore Wind"
        if "onshore"  in rid: return "Onshore Wind"
        return "Solar PV"
    return None   # ThermalSteam, CO2Injection, Transmission → excluded


# ── Load all periods ───────────────────────────────────────────────────────────
frames = []
for period, year in PERIOD_YEARS.items():
    path = RESULTS_DIR / f"results_period_{period}" / "capacity.csv"
    if not path.exists():
        print(f"  [skip] {path} not found")
        continue
    df = pd.read_csv(path)
    df["period"] = period
    df["year"]   = year
    frames.append(df)

if not frames:
    raise FileNotFoundError(f"No capacity.csv files found in {RESULTS_DIR}")

raw = pd.concat(frames, ignore_index=True)
raw["technology"] = raw.apply(classify_tech, axis=1)

# Filter: provinces only, electricity commodity, known technologies, capacity variable
data = raw[
    raw["zone"].isin(PROVINCE_ZONES)
    & (raw["commodity"] == "Electricity")
    & raw["technology"].notna()
    & (raw["variable"] == "capacity")
].copy()

data["value_GW"] = data["value"] / 1000.0

years = sorted(data["year"].unique())


# ── Helper: draw stacked bars on an Axes ──────────────────────────────────────
def draw_stacked(ax, pivot_df, bar_width=0.55, label_min_gw=0.5, fontsize=9):
    """
    pivot_df: index=technology, columns=year (or x-label), values=GW
    """
    cols = list(pivot_df.columns)
    x    = np.arange(len(cols))

    bottoms = np.zeros(len(cols))
    for tech in TECH_ORDER:
        if tech not in pivot_df.index:
            continue
        vals = pivot_df.loc[tech].values.astype(float)
        bars = ax.bar(x, vals, bar_width, bottom=bottoms,
                      color=TECH_COLORS[tech], zorder=2)
        # Value labels
        for xi, (v, b) in enumerate(zip(vals, bottoms)):
            if v >= label_min_gw:
                ax.text(
                    xi, b + v / 2,
                    f"{v:.1f}",
                    ha="center", va="center",
                    fontsize=fontsize,
                    color=LABEL_COLORS.get(tech, "white"),
                    fontweight="bold",
                )
        bottoms = bottoms + vals

    ax.set_xticks(x)
    ax.set_xticklabels([str(c) for c in cols])
    ax.yaxis.grid(True, color="#E0E0E0", linewidth=0.7, zorder=0)
    ax.set_axisbelow(True)
    for spine in ["top", "right"]:
        ax.spines[spine].set_visible(False)


# ── Legend handles ─────────────────────────────────────────────────────────────
def make_legend_handles():
    return [
        mpatches.Patch(color=TECH_COLORS[t], label=TECH_LABELS[t])
        for t in reversed(TECH_ORDER)   # Coal on top in legend
        if t in TECH_COLORS
    ]


# ════════════════════════════════════════════════════════════════════════════════
# Figure 1 — National capacity by technology
# ════════════════════════════════════════════════════════════════════════════════
nat = (
    data.groupby(["year", "technology"])["value_GW"]
    .sum()
    .reset_index()
)
nat_pivot = nat.pivot(index="technology", columns="year", values="value_GW").fillna(0)

fig1, ax1 = plt.subplots(figsize=(8, 7))
fig1.patch.set_facecolor("white")

draw_stacked(ax1, nat_pivot, bar_width=0.55, label_min_gw=1.0, fontsize=10)

ax1.set_xlabel("Year", fontsize=11)
ax1.set_ylabel("Capacity (GW)", fontsize=11)
ax1.set_title(
    "Korea Power Sector: Installed Capacity by Technology",
    fontsize=13, fontweight="bold", pad=14,
)
ax1.text(
    0.0, 1.01,
    "MACRO Korea — Total Installed Capacity",
    transform=ax1.transAxes, fontsize=9, color="#666666",
)

ax1.legend(
    handles=make_legend_handles(),
    title="Technology", title_fontsize=9,
    fontsize=9, loc="upper right",
    frameon=True, framealpha=0.9, edgecolor="#CCCCCC",
)

fig1.tight_layout()
out1 = OUTPUT_DIR / "01_national_capacity.png"
fig1.savefig(out1, dpi=150, bbox_inches="tight", facecolor="white")
plt.close(fig1)
print(f"  Saved: {out1}")


# ════════════════════════════════════════════════════════════════════════════════
# Figure 2 — Province-level capacity (3 × 6 grid, one subplot per province)
# ════════════════════════════════════════════════════════════════════════════════
NCOLS = 6
NROWS = 3   # 3×6 = 18 slots for 17 provinces + shared legend

fig2, axes = plt.subplots(NROWS, NCOLS, figsize=(22, 12), sharey=False)
fig2.patch.set_facecolor("white")
fig2.suptitle(
    "Provincial Installed Capacity by Technology",
    fontsize=15, fontweight="bold", y=1.01,
)
fig2.text(
    0.5, 0.985,
    "MACRO Korea — Total Installed Capacity (GW)",
    ha="center", fontsize=10, color="#666666",
)

prov_data = (
    data.groupby(["zone", "year", "technology"])["value_GW"]
    .sum()
    .reset_index()
)

for idx, zone in enumerate(PROVINCE_ZONES):
    row, col = divmod(idx, NCOLS)
    ax = axes[row][col]

    sub = prov_data[prov_data["zone"] == zone]
    if sub.empty:
        ax.set_visible(False)
        continue

    pivot = sub.pivot(index="technology", columns="year", values="value_GW").fillna(0)
    # ensure all years present
    for y in years:
        if y not in pivot.columns:
            pivot[y] = 0.0
    pivot = pivot[sorted(pivot.columns)]

    draw_stacked(ax, pivot, bar_width=0.6, label_min_gw=2.0, fontsize=7)

    ax.set_title(PROVINCE_NAMES.get(zone, zone), fontsize=10, fontweight="bold", pad=4)
    ax.set_xlabel("")
    ax.tick_params(axis="x", labelsize=8)
    ax.tick_params(axis="y", labelsize=8)
    if col == 0:
        ax.set_ylabel("GW", fontsize=8)

# Last slot → legend
last_row, last_col = divmod(len(PROVINCE_ZONES), NCOLS)
ax_leg = axes[last_row][last_col]
ax_leg.axis("off")
ax_leg.legend(
    handles=make_legend_handles(),
    title="Technology", title_fontsize=9,
    fontsize=9, loc="center",
    frameon=True, framealpha=0.95, edgecolor="#CCCCCC",
)

# Hide any remaining empty axes
for idx in range(len(PROVINCE_ZONES) + 1, NROWS * NCOLS):
    row, col = divmod(idx, NCOLS)
    axes[row][col].set_visible(False)

fig2.tight_layout(rect=[0, 0, 1, 0.98])
out2 = OUTPUT_DIR / "02_province_capacity.png"
fig2.savefig(out2, dpi=150, bbox_inches="tight", facecolor="white")
plt.close(fig2)
print(f"  Saved: {out2}")


# ════════════════════════════════════════════════════════════════════════════════
# CSV exports
# ════════════════════════════════════════════════════════════════════════════════
# National pivot (GW)
nat_csv = nat_pivot.copy()
nat_csv.index.name = "Technology"
nat_csv.to_csv(OUTPUT_DIR / "national_capacity_GW.csv")

# Province pivot (zone × year per technology)
prov_csv = (
    prov_data
    .pivot_table(index=["zone", "technology"], columns="year", values="value_GW", aggfunc="sum")
    .fillna(0)
)
prov_csv.index.names = ["Zone", "Technology"]
prov_csv.to_csv(OUTPUT_DIR / "province_capacity_GW.csv")

print(f"  Saved: {OUTPUT_DIR / 'national_capacity_GW.csv'}")
print(f"  Saved: {OUTPUT_DIR / 'province_capacity_GW.csv'}")
print("Done.")
