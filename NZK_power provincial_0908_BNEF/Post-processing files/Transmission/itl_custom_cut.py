#!/usr/bin/env python3
"""
ITL for a CUSTOM regional cut (group of provinces vs. everything else),
so we can compare against published regional transfer figures from the
11th / 10th Korean transmission plan.

Reuses compute_itl.py's solver.  A cut re-labels every province in the
group as zone "A" and every other province as zone "B", then runs the
same n-0 / n-1 PTDF-LP both directions.

Usage
  python3 itl_custom_cut.py GWN                 # East-coast (Gangwon) vs rest
  python3 itl_custom_cut.py GWN,GNB             # Gangwon + Gyeongbuk vs rest
  python3 itl_custom_cut.py SEL,INC,GGI         # Seoul metropolitan import
"""
import sys
import time
from pathlib import Path

import numpy as np

import compute_itl as C

HERE = Path(__file__).resolve().parent


def run(group_codes, data_dir="GIST/data_newest"):
    grp = set(group_codes)
    # province name -> code, to relabel zones
    name2code = C.CODE
    t0 = time.time()
    net, _ = C.load_gist(HERE / data_dir)
    island = C.largest_ac_island(net)
    net.island = island
    kind = list(net.bus_kind)
    for i in range(net.n_bus):
        if not island[i]:
            kind[i] = "trans"
    net.bus_kind = kind
    net.radial_reduce()

    # relabel: province in group -> "A", other real province -> "B", else None
    newz = []
    for z in net.bus_zone:
        c = name2code.get(z)
        newz.append("A" if c in grp else ("B" if c else None))
    net.bz = np.array(newz, dtype=object)

    ptdf0, mask0 = net.ptdf()
    f0, r0, n, wf, wr = C.interface_itl(net, "A", "B", ptdf0, mask0, want_worst=True)
    srate = float(net.rate[np.where(mask0 & (
        ((net.bz[net.f] == "A") & (net.bz[net.t] == "B")) |
        ((net.bz[net.f] == "B") & (net.bz[net.t] == "A"))))].sum())

    f1 = r1 = float("nan")
    if wf is not None:
        p, m = net.ptdf(drop_branch=wf)
        f1, _, _ = C.interface_itl(net, "A", "B", p, m)
    if wr is not None:
        p, m = net.ptdf(drop_branch=wr)
        _, r1, _ = C.interface_itl(net, "A", "B", p, m)

    g = "+".join(sorted(grp))
    print(f"\ncut  {{{g}}}  vs  rest      ({n} crossing AC lines, {time.time()-t0:.0f}s)")
    print(f"  sum of crossing line ratings : {srate:10,.0f} MW")
    print(f"  ITL n-0   {g} -> rest        : {f0:10,.0f} MW")
    print(f"  ITL n-0   rest -> {g}        : {r0:10,.0f} MW")
    print(f"  ITL n-1   {g} -> rest        : {f1:10,.0f} MW")
    print(f"  ITL n-1   rest -> {g}        : {r1:10,.0f} MW")
    return dict(group=g, sum_rate=srate, n0_out=f0, n0_in=r0, n1_out=f1, n1_in=r1)


if __name__ == "__main__":
    if len(sys.argv) < 2:
        print(__doc__)
        sys.exit(1)
    run([c.strip() for c in sys.argv[1].split(",")])
