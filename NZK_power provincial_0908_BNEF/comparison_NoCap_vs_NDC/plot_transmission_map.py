#!/usr/bin/env python3
"""
Inter-province transmission map for the NZK provincial model, NDC run:
2021 vs 2035 side by side.
-> comparison_NoCap_vs_NDC/maps/transmission_map_NDC_2021_vs_2035.png

Fixes vs the previous version of this figure:

  1. Legend units.  Previous legend said "18 / 43 / 71 MW"; the underlying
     values are 900 .. 71,340 MW.  The width variable had been divided by
     1000 and then labelled "MW".  Corridor capacities are GW-scale, so the
     legend is now in GW.
  2. Label collisions (Seoul/Incheon/Gyeonggi, Sejong/Daejeon/Chungbuk,
     Gyeongnam/Busan) fixed with per-node label offsets + leader lines;
     view cropped to the mainland+Jeju so there is no dead whitespace.
  3. The 2021 and 2035 panels are (correctly) near-identical: solved
     transmission capacity is flat across every myopic period
     (418,360 -> 418,361 MW, largest single-corridor change 0.1 MW) and
     equals the hard-coded 2021 existing_capacity, carried forward by the
     myopic link.  A callout on the 2035 panel states this so the pair is
     not misread as a plotting bug.

NOT fixed here (input-data issue, needs a real source):
  * The 2021 existing_capacity values themselves look too large - e.g.
    GWN<->CNB at 71.3 GW is ~80% of national peak demand on one corridor.
    Trace these back to the transmission input before using the map
    quantitatively.  Printed to stderr as a reminder.

Sources:
  assets/assets_2021/transmission_v2_2021.csv        - topology + 2021 existing
  results_002_NDC/results_period_1/capacity.csv      - solved capacity, 2021
  results_002_NDC/results_period_4/capacity.csv      - solved capacity, 2035
  comparison_NoCap_vs_NDC/maps/skorea-provinces.geojson
       (southkorea/southkorea-maps, KOSTAT 2018; auto-downloaded if absent)
"""
from __future__ import annotations
import csv
import sys
import urllib.request
from pathlib import Path

import geopandas as gpd
import matplotlib.pyplot as plt
import numpy as np
from matplotlib.lines import Line2D

ROOT = Path(__file__).resolve().parent.parent
MAPDIR = Path(__file__).resolve().parent / "maps"
RUN = ROOT / "results_002_NDC"
GEOJSON = MAPDIR / "skorea-provinces.geojson"
GEOJSON_URL = ("https://raw.githubusercontent.com/southkorea/southkorea-maps/"
               "master/kostat/2018/json/skorea-provinces-2018-geo.json")

# model province code  ->  geojson name_eng
CODE2ENG = {
    "SEL": "Seoul", "PUS": "Busan", "TAE": "Daegu", "INC": "Incheon",
    "KWJ": "Gwangju", "USN": "Ulsan", "SJG": "Sejongsi", "GGI": "Gyeonggi-do",
    "GWN": "Gangwon-do", "CNA": "Chungcheongnam-do", "CNB": "Chungcheongbuk-do",
    "DJJ": "Daejeon", "JNB": "Jeollabuk-do", "JNA": "Jeollanam-do",
    "GNB": "Gyeongsangbuk-do", "GNA": "Gyeongsangnam-do", "JEJ": "Jeju-do",
}
LABEL = {
    "SEL": "Seoul", "PUS": "Busan", "TAE": "Daegu", "INC": "Incheon",
    "KWJ": "Gwangju", "USN": "Ulsan", "SJG": "Sejong", "GGI": "Gyeonggi",
    "GWN": "Gangwon", "CNA": "Chungnam", "CNB": "Chungbuk", "DJJ": "Daejeon",
    "JNB": "Jeonbuk", "JNA": "Jeonnam", "GNB": "Gyeongbuk", "GNA": "Gyeongnam",
    "JEJ": "Jeju",
}
# crop box (lon/lat) - excludes far-east islets (Ulleungdo/Dokdo) that
# otherwise force a wide axis and big top/bottom whitespace
CROP = (125.4, 33.0, 129.9, 38.7)
# manual label nudges (degrees lon/lat) + alignment, for the crowded clusters
LABEL_OFFinfo = {
    #        dx,     dy,   ha,        va
    "SEL": (-0.50,  0.28, "right",  "bottom"),
    "INC": (-0.52, -0.18, "right",  "top"),
    "GGI": ( 0.60, -0.12, "left",   "center"),
    "GWN": ( 0.00,  0.42, "center", "bottom"),
    "SJG": (-0.52, -0.28, "right",  "top"),
    "DJJ": ( 0.44, -0.16, "left",   "center"),
    "JNB": (-0.44,  0.02, "right",  "center"),
    "CNB": ( 0.42,  0.16, "left",   "bottom"),
    "CNA": (-0.50,  0.05, "right",  "center"),
    "KWJ": (-0.44,  0.10, "right",  "center"),
    "JNA": (-0.36, -0.24, "right",  "top"),
    "GNA": (-0.10, -0.52, "center", "top"),
    "PUS": ( 0.40, -0.28, "left",   "top"),
    "USN": ( 0.44,  0.08, "left",   "center"),
    "TAE": ( 0.10, -0.42, "center", "top"),
    "GNB": ( 0.52,  0.12, "left",   "center"),
}
DEFAULT_OFF = (0.0, 0.34, "center", "bottom")


def ensure_geojson() -> None:
    if GEOJSON.exists():
        return
    print(f"downloading province boundaries -> {GEOJSON}", file=sys.stderr)
    GEOJSON.parent.mkdir(parents=True, exist_ok=True)
    urllib.request.urlretrieve(GEOJSON_URL, GEOJSON)


def vertex_to_code(v: str) -> str:
    # "elec_SEL" -> "SEL"
    return v.replace("elec_", "").strip()


def load_topology() -> list[dict]:
    f = ROOT / "assets" / "assets_2021" / "transmission_v2_2021.csv"
    out = []
    with open(f) as fh:
        for row in csv.DictReader(fh):
            out.append({
                "id": row["id"],
                "a": vertex_to_code(row["edges--transmission_edge--start_vertex"]),
                "b": vertex_to_code(row["edges--transmission_edge--end_vertex"]),
                "existing_2021": float(row["edges--transmission_edge--existing_capacity"]),
            })
    return out


def load_solved_capacity(period: str) -> dict[str, float]:
    f = RUN / period / "capacity.csv"
    cap = {}
    with open(f) as fh:
        for row in csv.DictReader(fh):
            if row["resource_type"].startswith("TransmissionLink") and row["variable"] == "capacity":
                cap[row["resource_id"]] = float(row["value"])
    return cap


def draw(ax, gdf, pos, edges, width_of, color_of, *, title, subtitle, bounds):
    gdf.plot(ax=ax, facecolor="#f3f3f0", edgecolor="#9a9a9a", linewidth=0.6, zorder=1)
    for e in edges:
        if e["a"] not in pos or e["b"] not in pos:
            continue
        (x1, y1), (x2, y2) = pos[e["a"]], pos[e["b"]]
        ax.plot([x1, x2], [y1, y2], lw=width_of(e), color=color_of(e),
                solid_capstyle="round", zorder=3, alpha=0.95)
    for code, (x, y) in pos.items():
        ax.plot(x, y, "o", ms=7, mfc="#f5d76e", mec="#333", mew=0.8, zorder=5)
        dx, dy, ha, va = LABEL_OFFinfo.get(code, DEFAULT_OFF)
        if (dx, dy) != (0.0, DEFAULT_OFF[1]):
            ax.plot([x, x + dx * 0.82], [y, y + dy * 0.82],
                    color="#555", lw=0.5, zorder=4)
        ax.annotate(LABEL[code], (x + dx, y + dy), ha=ha, va=va,
                    fontsize=8.5, fontweight="bold", zorder=6,
                    bbox=dict(boxstyle="round,pad=0.15", fc="white",
                              ec="none", alpha=0.75))
    minx, miny, maxx, maxy = bounds
    ax.set_xlim(minx, maxx)
    ax.set_ylim(miny, maxy)
    ax.set_title(f"{title}\n{subtitle}", fontsize=11.5, fontweight="bold", pad=4,
                 linespacing=1.5)
    ax.set_axis_off()
    ax.set_aspect("equal")


def main() -> None:
    ensure_geojson()
    gdf = gpd.read_file(GEOJSON)
    eng2idx = {row["name_eng"]: idx for idx, row in gdf.iterrows()}
    code_idx = {}
    for code, eng in CODE2ENG.items():
        if eng not in eng2idx:
            raise SystemExit(f"province '{eng}' ({code}) not found in geojson")
        code_idx[code] = eng2idx[eng]
    pos_proj = gdf.to_crs(5179).geometry.representative_point().to_crs(4326)
    pos = {code: (pos_proj.loc[idx].x, pos_proj.loc[idx].y)
           for code, idx in code_idx.items()}
    bounds = CROP

    topo = load_topology()
    cap21 = load_solved_capacity("results_period_1")   # 2021
    cap35 = load_solved_capacity("results_period_4")   # 2035
    for e in topo:
        e["cap21"] = cap21.get(e["id"], np.nan)
        e["cap35"] = cap35.get(e["id"], np.nan)
        e["delta"] = e["cap35"] - e["cap21"]

    t21, t35 = sum(e["cap21"] for e in topo), sum(e["cap35"] for e in topo)
    print(f"[info] transmission total  2021 = {t21:,.0f} MW   2035 = {t35:,.0f} MW   "
          f"Δ = {t35 - t21:+,.0f} MW  ({len(topo)} corridors)", file=sys.stderr)
    print(f"[info] largest single-corridor Δ 2021->2035 = "
          f"{max(abs(e['delta']) for e in topo):,.1f} MW", file=sys.stderr)
    print("[warn] 2021 existing_capacity inputs look oversized "
          "(max corridor 71.3 GW ~ 80% of national peak) - verify source "
          "before quantitative use.", file=sys.stderr)

    wmax = 11.0
    scale = wmax / (max(e["cap35"] for e in topo) / 1000.0)

    def width21(e):
        return max(0.6, e["cap21"] / 1000.0 * scale)

    def width35(e):
        return max(0.6, e["cap35"] / 1000.0 * scale)

    def color_cap(_e):
        return "#c0504d"

    fig, axes = plt.subplots(1, 2, figsize=(13, 7.3), constrained_layout=True)

    draw(axes[0], gdf, pos, topo, width21, color_cap, bounds=bounds,
         title="Transmission capacity — NDC 2021",
         subtitle=f"total {t21/1000:,.0f} GW across {len(topo)} corridors")
    draw(axes[1], gdf, pos, topo, width35, color_cap, bounds=bounds,
         title="Transmission capacity — NDC 2035",
         subtitle=f"total {t35/1000:,.0f} GW   (Δ vs 2021 = {t35 - t21:+,.0f} MW)")

    leg_gw = [10, 30, 70]
    handles = [Line2D([0], [0], color="#c0504d", lw=max(0.6, g * scale),
                      solid_capstyle="round", label=f"{g} GW") for g in leg_gw]
    axes[0].legend(handles=handles, title="corridor capacity", loc="lower right",
                   frameon=True, fontsize=8.5, title_fontsize=8.5,
                   borderpad=0.8, labelspacing=0.9, handlelength=3)

    axes[1].text(0.98, 0.02,
                 "No transmission expansion:\ncapacity is identical in every\n"
                 "myopic period (2021 = 2025 = 2030 = 2035),\n"
                 "carried forward from 2021 existing.",
                 transform=axes[1].transAxes, fontsize=8, va="bottom", ha="right",
                 bbox=dict(boxstyle="round", fc="#fff6e5", ec="#d0a24c", alpha=0.95))

    fig.suptitle("NZK provincial model — inter-province transmission, NDC (2021 vs 2035)",
                 fontsize=13, fontweight="bold")
    fig.text(0.5, -0.01,
             "Boundaries: southkorea-maps (KOSTAT 2018).  "
             "Source: results_002_NDC/results_period_{1,4}/capacity.csv (TransmissionLink).",
             ha="center", fontsize=7, color="#777")

    out = MAPDIR / "transmission_map_NDC_2021_vs_2035.png"
    fig.savefig(out, dpi=175, bbox_inches="tight")
    print(f"[ok] wrote {out}", file=sys.stderr)


if __name__ == "__main__":
    main()
