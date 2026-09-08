#!/usr/bin/env python3
"""
Build a directional transmission asset file for the NZK model from the
computed ITLs.

Input
  province_ITL.csv                         (from compute_itl.py; AC ITLs, MW)
  ../assets/assets_2021/transmission_v2_2021.csv   (topology + distance + cost template)
  GIST/<dataset>/results/results_by_voltage/hvdc_lines.csv   (DC links, added on top)

Output
  oneway_transmission_2021.csv

Each of the 32 province corridors becomes TWO OneWayTransmissionLink rows
(A->B and B->A).  Capacity per direction:

    existing_capacity(A->B) = ITL_ac(A->B) + HVDC(A<->B)

where ITL_ac is the n-1 (default) or n-0 AC interface transfer limit, and
HVDC is the summed rated capacity of DC links across that boundary (DC flow
is scheduled, unaffected by AC loop flow, so it is additive -- per
Brown et al. 2023 and Jesse's note).

Non-capacity fields (distance, loss_fraction, investment_cost, lifetime,
wacc, max_capacity, can_expand) are carried over from the existing
transmission_v2_2021.csv template.

NOTE on schema: this writes the advanced `edges--transmission_edge--*`
column style matching the current model file, with Type=OneWayTransmissionLink
and unidirectional=TRUE.  Confirm your MacroEnergy version accepts this
asset type (OneWayTransmissionLink was added in a later release; older
versions only have the bidirectional TransmissionLink).
"""
from __future__ import annotations
import argparse
import csv
from pathlib import Path

HERE = Path(__file__).resolve().parent
MODEL_TMPL = HERE.parent / "assets/assets_2021/transmission_v2_2021.csv"

KMAP = {
    "서울특별시": "SEL", "부산광역시": "PUS", "대구광역시": "TAE", "인천광역시": "INC",
    "광주광역시": "KWJ", "대전광역시": "DJJ", "울산광역시": "USN", "세종특별자치시": "SJG",
    "경기도": "GGI", "강원도": "GWN", "강원특별자치도": "GWN", "충청북도": "CNB",
    "충청남도": "CNA", "전라북도": "JNB", "전북특별자치도": "JNB", "전라남도": "JNA",
    "경상북도": "GNB", "경상남도": "GNA", "제주특별자치도": "JEJ",
}


def load_template():
    """corridor frozenset(codeA,codeB) -> dict(template row fields)."""
    rows = {}
    with open(MODEL_TMPL) as fh:
        for r in csv.DictReader(fh):
            a = r["edges--transmission_edge--start_vertex"].replace("elec_", "")
            b = r["edges--transmission_edge--end_vertex"].replace("elec_", "")
            rows[frozenset((a, b))] = r
    return rows


def load_itl(path):
    out = {}
    with open(path) as fh:
        for r in csv.DictReader(fh):
            out[frozenset((r["code_a"], r["code_b"]))] = r
    return out


def load_hvdc(path):
    """corridor -> summed HVDC rate_a_mva across that province boundary."""
    dc = {}
    if not path.exists():
        return dc
    with open(path, encoding="utf-8-sig") as fh:
        for r in fh_reader(fh):
            a = KMAP.get(r["from_region"]); b = KMAP.get(r["to_region"])
            if not a or not b or a == b:
                continue
            dc[frozenset((a, b))] = dc.get(frozenset((a, b)), 0.0) + float(r["rate_a_mva"])
    return dc


def fh_reader(fh):
    return csv.DictReader(fh)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--itl", default=str(HERE / "province_ITL.csv"))
    ap.add_argument("--dataset", default="GIST/data_newest")
    ap.add_argument("--contingency", choices=["n0", "n1"], default="n1")
    ap.add_argument("--out", default=str(HERE / "oneway_transmission_2021.csv"))
    args = ap.parse_args()

    tmpl = load_template()
    itl = load_itl(args.itl)
    hvdc = load_hvdc(HERE / args.dataset / "results/results_by_voltage/hvdc_lines.csv")

    cols = [
        "Type", "id",
        "edges--transmission_edge--has_capacity",
        "edges--transmission_edge--commodity",
        "edges--transmission_edge--unidirectional",
        "edges--transmission_edge--can_retire",
        "edges--transmission_edge--can_expand",
        "edges--transmission_edge--constraints--CapacityConstraint",
        "edges--transmission_edge--constraints--MaxCapacityConstraint",
        "edges--transmission_edge--start_vertex",
        "edges--transmission_edge--end_vertex",
        "edges--transmission_edge--distance",
        "edges--transmission_edge--loss_fraction",
        "edges--transmission_edge--max_capacity",
        "edges--transmission_edge--existing_capacity",
        "edges--transmission_edge--lifetime",
        "edges--transmission_edge--wacc",
        "edges--transmission_edge--investment_cost",
        "edges--transmission_edge--variable_om_cost",
        "edges--transmission_edge--fixed_om_cost",
        # bookkeeping (ignored by MacroEnergy, handy for review)
        "note--itl_ac_mw", "note--hvdc_mw",
    ]

    key = "itl_n1" if args.contingency == "n1" else "itl_n0"
    out_rows = []
    for corr, t in tmpl.items():
        a = t["edges--transmission_edge--start_vertex"].replace("elec_", "")
        b = t["edges--transmission_edge--end_vertex"].replace("elec_", "")
        rec = itl.get(corr)
        dc = hvdc.get(corr, 0.0)

        for src, dst in ((a, b), (b, a)):
            if rec is None:
                ac = 0.0
            else:
                # rec is stored with a fixed (code_a, code_b) orientation
                if (rec["code_a"], rec["code_b"]) == (src, dst):
                    ac = float(rec[f"{key}_a_to_b"])
                else:
                    ac = float(rec[f"{key}_b_to_a"])
                if ac != ac:      # NaN (n-1 infeasible) -> fall back to n-0
                    ac = float(rec[f"itl_n0_a_to_b" if (rec["code_a"], rec["code_b"]) == (src, dst)
                                   else "itl_n0_b_to_a"])
            cap = round(ac + dc, 1)
            row = {
                "Type": "OneWayTransmissionLink",
                "id": f"{src}_to_{dst}_transmission",
                "edges--transmission_edge--has_capacity": "TRUE",
                "edges--transmission_edge--commodity": "Electricity",
                "edges--transmission_edge--unidirectional": "TRUE",
                "edges--transmission_edge--can_retire": "FALSE",
                "edges--transmission_edge--can_expand": t["edges--transmission_edge--can_expand"],
                "edges--transmission_edge--constraints--CapacityConstraint": "TRUE",
                "edges--transmission_edge--constraints--MaxCapacityConstraint":
                    t["edges--transmission_edge--constraints--MaxCapacityConstraint"],
                "edges--transmission_edge--start_vertex": f"elec_{src}",
                "edges--transmission_edge--end_vertex": f"elec_{dst}",
                "edges--transmission_edge--distance": t["edges--transmission_edge--distance"],
                "edges--transmission_edge--loss_fraction": t["edges--transmission_edge--loss_fraction"],
                "edges--transmission_edge--max_capacity": t["edges--transmission_edge--max_capacity"],
                "edges--transmission_edge--existing_capacity": cap,
                "edges--transmission_edge--lifetime": t["edges--transmission_edge--lifetime"],
                "edges--transmission_edge--wacc": t["edges--transmission_edge--wacc"],
                "edges--transmission_edge--investment_cost": t["edges--transmission_edge--investment_cost"],
                "edges--transmission_edge--variable_om_cost": t["edges--transmission_edge--variable_om_cost"],
                "edges--transmission_edge--fixed_om_cost": t["edges--transmission_edge--fixed_om_cost"],
                "note--itl_ac_mw": round(ac, 1),
                "note--hvdc_mw": round(dc, 1),
            }
            out_rows.append(row)

    out_rows.sort(key=lambda r: r["id"])
    with open(args.out, "w", newline="") as fh:
        w = csv.DictWriter(fh, fieldnames=cols)
        w.writeheader()
        w.writerows(out_rows)

    tot = sum(float(r["edges--transmission_edge--existing_capacity"]) for r in out_rows)
    print(f"wrote {args.out}")
    print(f"  {len(out_rows)} one-way links, {args.contingency} ITL + additive HVDC")
    print(f"  total directional capacity = {tot/1000:,.1f} GW  "
          f"(sum over both directions of all corridors)")
    print(f"  vs current model file total (bidirectional) = 418.4 GW")


if __name__ == "__main__":
    main()
