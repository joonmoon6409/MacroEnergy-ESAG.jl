#!/usr/bin/env python3
"""
DEMO: how province_transmission_capacity.csv is produced from the raw GIST grid.

The real GIST pipeline lives in that project's codes/report/ (not shipped in
this folder).  This script reconstructs the same output from the three raw
inputs so the method is visible, and checks it against the shipped result.

Method
------
1.  bus.csv         -> bus_id : province  (the 'region' column)
2.  line.csv         (AC lines, in_service only)
        for each line, look up the province of from_bus and to_bus.
        if they differ  -> the line crosses that province-pair boundary;
                           add its rate_a_mva to that pair's total.
        if they are the same -> internal line (goes to the *internal*
                           file instead, not shown here).
        volt_class of the crossing = volt_class of the endpoint buses.
3.  dcline.csv / vscdcline.csv  (HVDC)
        map ac_from_bus / ac_to_bus to provinces the same way; the MW
        rating is the known project nameplate (300 / 400 / 200 / 3000),
        taken here from the already-derived hvdc_lines.csv.
4.  group by sorted (province_1, province_2), sum rate_a/b/c and count.

Run:  python3 build_province_transmission_capacity_DEMO.py [data_dir]
      default data_dir = GIST/data_newest
"""
from __future__ import annotations
import csv
import re
import sys
from collections import defaultdict
from pathlib import Path

HERE = Path(__file__).resolve().parent
DATA = HERE / (sys.argv[1] if len(sys.argv) > 1 else "inputs/gist_data_newest")
RAW = DATA / "data"
SHIPPED = DATA / "results/total_results/province_transmission_capacity.csv"
HVDC_DERIVED = DATA / "results/results_by_voltage/hvdc_lines.csv"

# provinces we keep; anything else ('수도권', '충청') is a broad-region
# label used only on the model's `inf*_LOCALITY_*` equivalent-source buses.
PROVINCES = {
    "서울특별시", "부산광역시", "대구광역시", "인천광역시", "광주광역시", "대전광역시",
    "울산광역시", "세종특별자치시", "경기도", "강원도", "강원특별자치도", "충청북도",
    "충청남도", "전라북도", "전북특별자치도", "전라남도", "경상북도", "경상남도",
    "제주특별자치도",
}

# inf*_LOCALITY_* buses carry region='수도권'/'충청'; the GIST pipeline
# resolves them to a real province by parsing the locality from the name.
LOCALITY2PROV = {
    "서울": "서울특별시", "김포": "경기도", "남양주": "경기도", "안산": "경기도",
    "안성": "경기도", "용인": "경기도", "파주": "경기도", "포천": "경기도",
    "동두천": "경기도", "성남": "경기도", "인천": "인천광역시", "당진": "충청남도",
    "아산": "충청남도",
}


def resolve_region(region: str, name: str) -> str:
    if region in PROVINCES:
        return region
    m = re.match(r"inf\d*_([^_]+)_", name)   # inf345_당진_900024 -> 당진
    return LOCALITY2PROV.get(m.group(1)) if m else None


def read_csv(path):
    with open(path, encoding="utf-8-sig") as fh:
        return list(csv.DictReader(fh))


def main() -> None:
    buses = read_csv(RAW / "bus.csv")
    bus_region = {r["bus"]: resolve_region(r["region"], r["name"]) for r in buses}
    bus_volt = {r["bus"]: r["volt_class"] for r in buses}

    # pair -> [sum_a, sum_b, sum_c, n]
    pair = defaultdict(lambda: [0.0, 0.0, 0.0, 0])
    pair_v = defaultdict(lambda: [0.0, 0.0, 0.0, 0])   # (volt, p1, p2)
    internal = defaultdict(lambda: [0.0, 0])
    unknown = [0.0, 0]

    # ---- 2. AC lines --------------------------------------------------
    for ln in read_csv(RAW / "line.csv"):
        if str(ln["in_service"]) not in ("1", "1.0", "True"):
            continue
        if ln["name"].startswith("HVDC_"):
            continue   # AC-equivalent of an HVDC link; counted from dcline instead
        ra = float(ln["rate_a_mva"]); rb = float(ln["rate_b_mva"]); rc = float(ln["rate_c_mva"])
        r1 = bus_region.get(ln["from_bus"])
        r2 = bus_region.get(ln["to_bus"])
        if r1 is not None and r1 == r2:
            internal[r1][0] += ra; internal[r1][1] += 1
            continue
        if r1 not in PROVINCES or r2 not in PROVINCES:
            unknown[0] += ra; unknown[1] += 1
            continue
        a, b = sorted((r1, r2))
        p = pair[(a, b)]
        p[0] += ra; p[1] += rb; p[2] += rc; p[3] += 1
        volt = bus_volt.get(ln["from_bus"]) or bus_volt.get(ln["to_bus"])
        pv = pair_v[(volt, a, b)]
        pv[0] += ra; pv[1] += rb; pv[2] += rc; pv[3] += 1

    # ---- 3. HVDC ----------------------------------------------------
    for h in read_csv(HVDC_DERIVED):
        r1, r2 = h["from_region"], h["to_region"]
        if r1 not in PROVINCES or r2 not in PROVINCES:
            continue
        a, b = sorted((r1, r2))
        ra = float(h["rate_a_mva"]); rb = float(h["rate_b_mva"]); rc = float(h["rate_c_mva"])
        p = pair[(a, b)]
        p[0] += ra; p[1] += rb; p[2] += rc; p[3] += 1
        pv = pair_v[("HVDC", a, b)]
        pv[0] += ra; pv[1] += rb; pv[2] += rc; pv[3] += 1

    # ---- 4. emit + verify -----------------------------------------
    rows = sorted(pair.items())
    print(f"data dir : {DATA.relative_to(HERE)}")
    print(f"{'region_1':<12}{'region_2':<12}{'rate_a_mva':>12}{'lines':>7}")
    for (a, b), (sa, sb, sc, n) in rows:
        print(f"{a:<12}{b:<12}{sa:>12,.0f}{n:>7}")
    tot = sum(v[0] for v in pair.values())
    print(f"{'TOTAL':<24}{tot:>12,.0f}   ({len(rows)} corridors)")
    print(f"internal-line provinces: {len(internal)}   "
          f"UNKNOWN/broad-region lines: {unknown[1]} ({unknown[0]:,.0f} MVA)")

    # compare to shipped file
    KMAP = str.maketrans("", "")
    shipped = {}
    for r in read_csv(SHIPPED):
        shipped[tuple(sorted((r["region_1"], r["region_2"])))] = float(r["total_rate_a_mva"])
    print("\n--- vs shipped province_transmission_capacity.csv ---")
    ok = True
    for (a, b), (sa, *_rest) in rows:
        exp = shipped.get((a, b))
        tag = "OK" if exp is not None and abs(exp - sa) < 1 else f"DIFF (shipped {exp})"
        if tag != "OK":
            ok = False
            print(f"  {a}-{b}: reconstructed {sa:,.0f}  {tag}")
    missing = set(shipped) - {k for k, _ in rows}
    for k in missing:
        ok = False
        print(f"  shipped has {k} = {shipped[k]:,.0f} but reconstruction does not")
    print("EXACT MATCH" if ok and not missing else "-> differences above")


if __name__ == "__main__":
    main()
