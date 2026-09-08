#!/usr/bin/env python3
"""
Write transmission asset files with ITL-based capacities, in the EXACT
column schema of assets/assets_2021/transmission_v2_2021.csv.

Inputs
  province_ITL.csv                                  (from compute_itl.py)
  ../assets/assets_2021/transmission_v2_2021.csv    (schema + distance/cost template)
  GIST/<dataset>/results/results_by_voltage/hvdc_lines.csv   (DC links, added on top)

Outputs (same 19-column header as the template)
  transmission_v2_2021_ITL_oneway.csv   64 rows, Type=OneWayTransmissionLink,
        one row per direction, existing_capacity = ITL_ac(dir, n-1) + HVDC(corridor)
  transmission_v2_2021_ITL_bidir.csv    32 rows, Type=TransmissionLink,
        existing_capacity = min(ITL n-1 over the two directions) + HVDC
        (a single conservative bidirectional value, if you want to keep the
         current one-row-per-corridor structure)

DC is additive (scheduled flow, unaffected by AC loop flow) -- Brown et al.
2023 and Jesse's note.  Default AC contingency level = n-1.
"""
from __future__ import annotations
import csv
import math
from pathlib import Path

HERE = Path(__file__).resolve().parent
TMPL = HERE.parent / "assets/assets_2021/transmission_v2_2021.csv"
ITLCSV = HERE / "province_ITL.csv"
HVDCCSV = HERE / "GIST/data_newest/results/results_by_voltage/hvdc_lines.csv"
LEVEL = "itl_n1"          # "itl_n1" (security) or "itl_n0"

KMAP = {
    "서울특별시": "SEL", "부산광역시": "PUS", "대구광역시": "TAE", "인천광역시": "INC",
    "광주광역시": "KWJ", "대전광역시": "DJJ", "울산광역시": "USN", "세종특별자치시": "SJG",
    "경기도": "GGI", "강원도": "GWN", "강원특별자치도": "GWN", "충청북도": "CNB",
    "충청남도": "CNA", "전라북도": "JNB", "전북특별자치도": "JNB", "전라남도": "JNA",
    "경상북도": "GNB", "경상남도": "GNA", "제주특별자치도": "JEJ",
}


def read(path, enc="utf-8"):
    with open(path, encoding=enc) as fh:
        return list(csv.DictReader(fh)), csv.DictReader(open(path, encoding=enc)).fieldnames


def main():
    with open(TMPL) as fh:
        rd = csv.DictReader(fh)
        header = rd.fieldnames
        tmpl_rows = list(rd)

    # corridor (frozenset of codes) -> template row
    tmpl = {}
    for r in tmpl_rows:
        a = r["edges--transmission_edge--start_vertex"].replace("elec_", "")
        b = r["edges--transmission_edge--end_vertex"].replace("elec_", "")
        tmpl[frozenset((a, b))] = r

    # ITLs
    itl = {}
    with open(ITLCSV) as fh:
        for r in csv.DictReader(fh):
            itl[frozenset((r["code_a"], r["code_b"]))] = r

    # HVDC per corridor (summed rate_a_mva across the province boundary)
    hvdc = {}
    if HVDCCSV.exists():
        with open(HVDCCSV, encoding="utf-8-sig") as fh:
            for r in csv.DictReader(fh):
                a, b = KMAP.get(r["from_region"]), KMAP.get(r["to_region"])
                if a and b and a != b:
                    hvdc[frozenset((a, b))] = hvdc.get(frozenset((a, b)), 0.0) + float(r["rate_a_mva"])

    def dir_itl(rec, src, dst):
        if rec is None:
            return math.nan
        fwd = (rec["code_a"], rec["code_b"]) == (src, dst)
        v = float(rec[f"{LEVEL}_a_to_b" if fwd else f"{LEVEL}_b_to_a"])
        if math.isnan(v):                       # n-1 infeasible -> use n-0
            v = float(rec[f"itl_n0_a_to_b" if fwd else "itl_n0_b_to_a"])
        return v

    oneway, bidir = [], []
    for corr, t in tmpl.items():
        a = t["edges--transmission_edge--start_vertex"].replace("elec_", "")
        b = t["edges--transmission_edge--end_vertex"].replace("elec_", "")
        rec = itl.get(corr)
        dc = hvdc.get(corr, 0.0)

        # ---- one-way rows (two per corridor) ----
        for src, dst in ((a, b), (b, a)):
            ac = dir_itl(rec, src, dst)
            ac = 0.0 if math.isnan(ac) else ac        # HVDC-only corridor (Jeju)
            row = dict(t)   # copy all template fields (distance, cost, loss, ...)
            row["Type"] = "OneWayTransmissionLink"
            row["id"] = f"{src}_to_{dst}_transmission"
            row["edges--transmission_edge--start_vertex"] = f"elec_{src}"
            row["edges--transmission_edge--end_vertex"] = f"elec_{dst}"
            row["edges--transmission_edge--existing_capacity"] = round(ac + dc, 1)
            oneway.append(row)

        # ---- bidirectional row (one per corridor, conservative) ----
        acs = [dir_itl(rec, a, b), dir_itl(rec, b, a)]
        acs = [x for x in acs if not math.isnan(x)]
        ac_min = min(acs) if acs else 0.0
        rb = dict(t)
        rb["edges--transmission_edge--existing_capacity"] = round(ac_min + dc, 1)
        bidir.append(rb)

    def write(path, rows):
        rows = sorted(rows, key=lambda r: r["id"])
        with open(path, "w", newline="") as fh:
            w = csv.DictWriter(fh, fieldnames=header)
            w.writeheader()
            w.writerows(rows)
        tot = sum(float(r["edges--transmission_edge--existing_capacity"]) for r in rows)
        print(f"wrote {path.name:42} {len(rows):3} rows   Σexisting_capacity = {tot/1000:7.1f} GW")

    write(HERE / "transmission_v2_2021_ITL_oneway.csv", oneway)
    write(HERE / "transmission_v2_2021_ITL_bidir.csv", bidir)
    print(f"(AC level = {LEVEL}, + additive HVDC;  current model file = 418.4 GW bidirectional)")


if __name__ == "__main__":
    main()
