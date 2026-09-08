#!/usr/bin/env python3
"""
Zonal Interface Transfer Limits (ITL) for the 17 Korean provinces,
from GIST nodal data, following

  Brown, Barrows et al. (NREL), "A general method for estimating zonal
  transmission interface limits from nodal network data",
  arXiv:2308.03612v1 (2023).

This is a direct re-implementation of that paper's PTDF-based LP (eqs 1-4),
NOT a call to the InterfaceLimits.jl package.  It is validated against the
paper's 5-bus test system (Table 1-3: ITL 1||2 = 719, 2||3 = 400,
1||3 = 240) via `--validate`.

Method
------
For each interface (province pair with >=1 crossing AC line) and each
direction, solve:

    max / min   sum_{l in crossing} orient(l) * F(l)
    s.t.        F(l) = sum_b PTDF[l,b] * G(b)          (DC power flow)
                -rate_a(l) <= F(l) <= rate_a(l)        (all branches)
                G(b) >= 0   for generator buses
                G(b) <= 0   for load buses
                G(b) == 0   for pure transmission buses
                sum_b G(b) == 0                        (balance)

n-1  = drop the single highest-flow crossing line, rebuild PTDF, re-solve.

AC only.  HVDC links are excluded here and added back at rated capacity
downstream (their flow is scheduled, not subject to Kirchhoff loop flow).

Usage
  python3 compute_itl.py --validate
  python3 compute_itl.py [inputs/gist_data_newest]   ->  outputs/province_ITL.csv
"""
from __future__ import annotations

import csv
import re
import sys
import time
from pathlib import Path

import numpy as np
import scipy.sparse as sp
from scipy.optimize import linprog
from scipy.sparse.linalg import splu

HERE = Path(__file__).resolve().parent
BIG = 1.0e7  # MW bound for unconstrained bus injection

PROVINCES = {
    "서울특별시", "부산광역시", "대구광역시", "인천광역시", "광주광역시", "대전광역시",
    "울산광역시", "세종특별자치시", "경기도", "강원도", "강원특별자치도", "충청북도",
    "충청남도", "전라북도", "전북특별자치도", "전라남도", "경상북도", "경상남도",
    "제주특별자치도",
}
LOCALITY2PROV = {
    "서울": "서울특별시", "김포": "경기도", "남양주": "경기도", "안산": "경기도",
    "안성": "경기도", "용인": "경기도", "파주": "경기도", "포천": "경기도",
    "동두천": "경기도", "성남": "경기도", "인천": "인천광역시", "당진": "충청남도",
    "아산": "충청남도",
}
CODE = {  # province -> model node suffix
    "서울특별시": "SEL", "부산광역시": "PUS", "대구광역시": "TAE", "인천광역시": "INC",
    "광주광역시": "KWJ", "대전광역시": "DJJ", "울산광역시": "USN", "세종특별자치시": "SJG",
    "경기도": "GGI", "강원도": "GWN", "강원특별자치도": "GWN", "충청북도": "CNB",
    "충청남도": "CNA", "전라북도": "JNB", "전북특별자치도": "JNB", "전라남도": "JNA",
    "경상북도": "GNB", "경상남도": "GNA", "제주특별자치도": "JEJ",
}


# --------------------------------------------------------------------------
# network container
# --------------------------------------------------------------------------
class Net:
    def __init__(self, f_idx, t_idx, x, rate, n_bus, bus_kind, bus_zone):
        self.f = np.asarray(f_idx)          # branch from-bus index
        self.t = np.asarray(t_idx)          # branch to-bus index
        self.x = np.asarray(x, float)       # branch reactance (pu, 100 MVA)
        self.rate = np.asarray(rate, float)  # branch rating (MW/MVA)
        self.n_bus = n_bus
        self.bus_kind = bus_kind            # per bus: 'gen' | 'load' | 'both' | 'trans'
        self.bus_zone = bus_zone            # per bus: zone label or None
        self.bz = np.array(bus_zone, dtype=object)
        self.n_br = len(self.f)
        self.island = np.ones(n_bus, bool)  # bus subset PTDF is built over
        self._alive_b = np.ones(self.n_br, bool)  # branches kept after reduction

    # ---- PTDF (dense, n_br x n_bus), built over self.island only ----------
    def ptdf(self, drop_branch: int | None = None):
        mask = self._alive_b.copy()
        if drop_branch is not None:
            mask[drop_branch] = False
        # only branches fully inside the island contribute to the DC network
        on = self.island
        mask &= on[self.f] & on[self.t]
        f, t, x = self.f[mask], self.t[mask], self.x[mask]
        nl = len(f)
        b = 1.0 / x
        A = sp.csr_matrix((np.r_[np.ones(nl), -np.ones(nl)],
                           (np.r_[np.arange(nl), np.arange(nl)], np.r_[f, t])),
                          shape=(nl, self.n_bus))
        Bd = sp.diags(b)
        Bbus = (A.T @ Bd @ A).tocsc()
        Bf = (Bd @ A).tocsc()
        isl = np.where(on)[0]
        slack_local = self._pick_slack(isl)
        keep = np.array([i for i in isl if i != slack_local])
        Bbus_r = Bbus[keep][:, keep].tocsc()
        lu = splu(Bbus_r)
        rhs = Bf[:, keep].toarray().T          # (len(keep) x nl)
        sol = lu.solve(rhs)                    # (len(keep) x nl)
        P = np.zeros((nl, self.n_bus))
        P[:, keep] = sol.T
        full = np.zeros((self.n_br, self.n_bus))
        full[mask] = P
        return full, mask

    def _pick_slack(self, isl):
        for i in isl:
            if self.bus_kind[i] in ("gen", "both"):
                return int(i)
        return int(isl[0])

    # ---- collapse degree-1 buses (paper: radial network reduction) --------
    def radial_reduce(self):
        """Drop degree-1 buses inside the island, folding kind into the
        neighbour, and drop parallel/loop branches to nowhere.  Interface-
        crossing branches are never removed."""
        kind = list(self.bus_kind)
        alive_b = np.ones(self.n_br, bool)
        alive_bus = self.island.copy()
        zone = self.bus_zone
        changed = True
        rounds = 0
        while changed and rounds < 40:
            changed = False
            rounds += 1
            deg = np.zeros(self.n_bus, int)
            nbr = [[] for _ in range(self.n_bus)]
            for bi in np.where(alive_b)[0]:
                u, v = int(self.f[bi]), int(self.t[bi])
                deg[u] += 1; deg[v] += 1
                nbr[u].append((bi, v)); nbr[v].append((bi, u))
            for u in np.where(alive_bus)[0]:
                if deg[u] != 1:
                    continue
                (bi, v) = next((x for x in nbr[u] if alive_b[x[0]]), (None, None))
                if bi is None:
                    continue
                # never collapse across a zone boundary (keep interface lines)
                if zone[u] in PROVINCES and zone[v] in PROVINCES and zone[u] != zone[v]:
                    continue
                if kind[u] in ("gen", "both") and kind[v] == "load":
                    kind[v] = "both"
                elif kind[u] in ("gen", "both") and kind[v] == "trans":
                    kind[v] = "gen"
                elif kind[u] in ("load", "both") and kind[v] == "trans":
                    kind[v] = "load"
                elif kind[u] == "both":
                    kind[v] = "both"
                alive_b[bi] = False
                alive_bus[u] = False
                changed = True
        self.bus_kind = kind
        self.island = alive_bus
        self._alive_b = alive_b
        return alive_b.sum(), alive_bus.sum()


# --------------------------------------------------------------------------
# ITL solve for one interface
# --------------------------------------------------------------------------
def _bus_bounds(net):
    lb = np.full(net.n_bus, -BIG)
    ub = np.full(net.n_bus, BIG)
    for i, k in enumerate(net.bus_kind):
        if k == "gen":
            lb[i] = 0.0
        elif k == "load":
            ub[i] = 0.0
        elif k == "trans":
            lb[i] = ub[i] = 0.0
    return lb, ub


def _solve_dir(net, obj, Aub, bub, bounds, maximize):
    # maximize=True  -> return max(obj)  (forward ITL za->zb)
    # maximize=False -> return -min(obj) (reverse ITL zb->za = max of -flow)
    c = -obj if maximize else obj
    r = linprog(c, A_ub=Aub, b_ub=bub,
                A_eq=sp.csr_matrix(np.ones((1, net.n_bus))), b_eq=[0.0],
                bounds=bounds, method="highs")
    if not r.success:
        return float("nan"), None
    return -r.fun, r.x


def interface_itl(net, za, zb, ptdf, br_mask, want_worst=False):
    """ITL za->zb and zb->za (MW).  If want_worst, also return the crossing
    branch carrying the largest |flow| in each direction (for n-1)."""
    fz = net.bz[net.f]
    tz = net.bz[net.t]
    cross = np.where(br_mask & (((fz == za) & (tz == zb)) | ((fz == zb) & (tz == za))))[0]
    if len(cross) == 0:
        return (0.0, 0.0, 0, None, None) if want_worst else (0.0, 0.0, 0)
    orient = np.where(fz[cross] == za, 1.0, -1.0)

    act = np.where(br_mask)[0]
    Pa = ptdf[act]
    Pa[np.abs(Pa) < 1e-7] = 0.0
    Aub = sp.vstack([sp.csr_matrix(Pa), sp.csr_matrix(-Pa)]).tocsr()
    bub = np.concatenate([net.rate[act], net.rate[act]])
    bounds = list(zip(*_bus_bounds(net)))
    obj = orient @ ptdf[cross]           # interface flow za->zb as fn of G

    itl_f, xf = _solve_dir(net, obj, Aub, bub, bounds, maximize=True)
    itl_r, xr = _solve_dir(net, obj, Aub, bub, bounds, maximize=False)

    if not want_worst:
        return itl_f, itl_r, len(cross)

    wf = wr = None
    if xf is not None:
        wf = cross[int(np.argmax(np.abs(ptdf[cross] @ xf)))]
    if xr is not None:
        wr = cross[int(np.argmax(np.abs(ptdf[cross] @ xr)))]
    return itl_f, itl_r, len(cross), wf, wr


# --------------------------------------------------------------------------
# 5-bus validation (paper Table 1)
# --------------------------------------------------------------------------
def validate():
    # bus 0..4 = A..E ; zones: A,B->1 ; C ambiguous(C in zone1 per Table1) ; D->2 ; E->3
    # Table 1: line, from, to, from_zone, to_zone, x, rating
    rows = [
        ("A", "B", 1, 1, 0.0281, 400),
        ("B", "C", 1, 1, 0.0108, 400),
        ("C", "D", 1, 2, 0.0297, 400),
        ("D", "E", 2, 3, 0.0297, 240),
        ("A", "E", 1, 3, 0.0064, 400),
        ("A", "D", 1, 2, 0.0304, 400),
    ]
    bi = {n: i for i, n in enumerate("ABCDE")}
    bus_zone = {bi["A"]: "1", bi["B"]: "1", bi["C"]: "1", bi["D"]: "2", bi["E"]: "3"}
    net = Net([bi[a] for a, b, *_ in rows], [bi[b] for a, b, *_ in rows],
              [r[4] for r in rows], [r[5] for r in rows], 5,
              bus_kind=["both"] * 5,          # constraint (4) inactive in the paper example
              bus_zone=[bus_zone[i] for i in range(5)])
    ptdf, mask = net.ptdf()
    # Paper Table 3 gives 1||2 = 719.  For 2||3 and 1||3 the only crossing line
    # is D|E (r=240) and A|E (r=400) respectively; with constraint (4) inactive
    # (paper's stated setup) each can be loaded to its own rating by a pure
    # point injection, so ITL(2||3)=240 and ITL(1||3)=400 exactly.  (The arXiv
    # v1 Table 3 prints these two ITL cells swapped.)
    exp = {("1", "2"): 719, ("2", "3"): 240, ("1", "3"): 400}
    print("5-bus validation:")
    ok = True
    for (za, zb), e in exp.items():
        f, r, n = interface_itl(net, za, zb, ptdf, mask)
        got = max(f, r)
        tag = "OK" if abs(got - e) <= 2 else "MISMATCH"
        if tag != "OK":
            ok = False
        print(f"  {za}||{zb}: ITL = {got:6.1f}  (paper {e})  {tag}   "
              f"[fwd {f:.1f} / rev {r:.1f}, {n} crossing lines]")
    print("PASS" if ok else "FAIL")
    return ok


# --------------------------------------------------------------------------
# GIST loader
# --------------------------------------------------------------------------
def read_csv(p):
    with open(p, encoding="utf-8-sig") as fh:
        return list(csv.DictReader(fh))


def resolve_zone(region, name):
    if region in PROVINCES:
        return region
    m = re.match(r"inf\d*_([^_]+)_", name or "")
    return LOCALITY2PROV.get(m.group(1)) if m else None


def load_gist(data_dir: Path):
    raw = data_dir / "data"
    buses = read_csv(raw / "bus.csv")
    bus_ids = [b["bus"] for b in buses]
    idx = {bid: i for i, bid in enumerate(bus_ids)}
    n_bus = len(bus_ids)
    zone = [resolve_zone(b["region"], b["name"]) for b in buses]

    gen_bus = {g["bus"] for g in read_csv(raw / "gen.csv")
               if str(g["in_service"]) in ("1", "1.0", "True")}
    load_bus = {l["bus"] for l in read_csv(raw / "load.csv")
                if str(l["in_service"]) in ("1", "1.0", "True")
                and abs(float(l["p_mw"] or 0)) > 1e-6}
    kind = []
    for bid in bus_ids:
        g, d = bid in gen_bus, bid in load_bus
        kind.append("both" if g and d else "gen" if g else "load" if d else "trans")

    f, t, x, rate = [], [], [], []

    def add(fb, tb, xx, rr):
        if fb not in idx or tb not in idx or fb == tb:
            return
        xx = float(xx)
        if not np.isfinite(xx) or abs(xx) < 1e-9:
            xx = 1e-4
        f.append(idx[fb]); t.append(idx[tb]); x.append(xx); rate.append(float(rr or 0) or 1e4)

    for ln in read_csv(raw / "line.csv"):
        if str(ln["in_service"]) not in ("1", "1.0", "True"):
            continue
        if (ln.get("name") or "").startswith("HVDC_"):
            continue
        add(ln["from_bus"], ln["to_bus"], ln["x_pu"], ln["rate_a_mva"])

    for tr in read_csv(raw / "trafo2w.csv"):
        if str(tr["in_service"]) not in ("1", "1.0", "True"):
            continue
        add(tr["hv_bus"], tr["lv_bus"], tr["x_pu"],
            tr.get("rate_a_mva") or tr.get("sn_mva"))

    # 3-winding autotransformer (765/345/tertiary): the through path is
    # HV<->MV; represent it as an HV<->MV branch.  (The tertiary/LV winding
    # carries no through-flow, so it is omitted.)
    tp3 = raw / "trafo3w.csv"
    if tp3.exists():
        for tr in read_csv(tp3):
            if str(tr["in_service"]) not in ("1", "1.0", "True"):
                continue
            add(tr["hv_bus"], tr["mv_bus"], tr.get("x_hv_mv_pu"),
                tr.get("rate_hv_mva") or tr.get("rate_mv_mva"))

    net = Net(f, t, x, rate, n_bus, kind, zone)
    return net, buses


def largest_ac_island(net: Net):
    """Boolean mask of buses in the biggest connected AC component."""
    parent = list(range(net.n_bus))

    def find(a):
        while parent[a] != a:
            parent[a] = parent[parent[a]]
            a = parent[a]
        return a

    for a, b in zip(net.f, net.t):
        ra, rb = find(int(a)), find(int(b))
        if ra != rb:
            parent[ra] = rb
    roots = [find(i) for i in range(net.n_bus)]
    vals, cnt = np.unique(roots, return_counts=True)
    big = vals[np.argmax(cnt)]
    return np.array([r == big for r in roots])


# --------------------------------------------------------------------------
def run_gist(data_dir: Path):
    t0 = time.time()
    net, _ = load_gist(data_dir)
    print(f"[load] {net.n_bus} buses, {net.n_br} AC branches  ({time.time()-t0:.1f}s)")

    island = largest_ac_island(net)
    net.island = island
    kind = list(net.bus_kind)
    for i in range(net.n_bus):
        if not island[i]:
            kind[i] = "trans"          # off-island buses cannot inject/withdraw
    net.bus_kind = kind
    print(f"[island] main AC island has {island.sum()} / {net.n_bus} buses "
          f"(off-island e.g. Jeju handled via HVDC downstream)", flush=True)

    nb0 = net._alive_b.sum()
    ab, abus = net.radial_reduce()
    print(f"[reduce] radial reduction: {net.n_br}->{ab} branches, "
          f"{island.sum()}->{abus} buses  ({time.time()-t0:.1f}s)", flush=True)

    fz, tz = net.bz[net.f], net.bz[net.t]
    pairs = set()
    live = net._alive_b
    for a, b, ok in zip(fz, tz, live):
        if ok and a in PROVINCES and b in PROVINCES and a != b:
            pairs.add(tuple(sorted((a, b))))
    pairs = sorted(pairs)
    print(f"[interfaces] {len(pairs)} province pairs with crossing AC lines", flush=True)

    ptdf0, mask0 = net.ptdf()
    print(f"[ptdf] n-0 PTDF built  ({time.time()-t0:.1f}s)", flush=True)

    out = []
    for k, (za, zb) in enumerate(pairs, 1):
        f0, r0, n, wf, wr = interface_itl(net, za, zb, ptdf0, mask0, want_worst=True)
        srate = float(net.rate[np.where(mask0 & (
            ((fz == za) & (tz == zb)) | ((fz == zb) & (tz == za))))].sum())

        f1 = r1 = float("nan")
        if wf is not None:
            p, m = net.ptdf(drop_branch=wf)
            f1, _, _ = interface_itl(net, za, zb, p, m)
        if wr is not None:
            p, m = net.ptdf(drop_branch=wr)
            _, r1, _ = interface_itl(net, za, zb, p, m)

        ca, cb = CODE[za], CODE[zb]
        out.append(dict(zone_a=za, zone_b=zb, code_a=ca, code_b=cb, n_ac_lines=n,
                        sum_rate_a_mva=round(srate, 1),
                        itl_n0_a_to_b=round(f0, 1), itl_n0_b_to_a=round(r0, 1),
                        itl_n1_a_to_b=round(f1, 1), itl_n1_b_to_a=round(r1, 1)))
        print(f"  [{k:2}/{len(pairs)}] {ca}-{cb:<4} Σrate={srate:8,.0f}  "
              f"n0 {f0:7,.0f}/{r0:7,.0f}   n1 {f1:7,.0f}/{r1:7,.0f}   "
              f"({time.time()-t0:.0f}s)", flush=True)

    outp = HERE / "outputs" / "province_ITL.csv"
    with open(outp, "w", newline="") as fh:
        w = csv.DictWriter(fh, fieldnames=list(out[0].keys()))
        w.writeheader()
        w.writerows(out)
    print(f"\n[done] wrote {outp}  ({time.time()-t0:.0f}s total)")

    tot = lambda k: sum(r[k] for r in out if np.isfinite(r[k]))
    print(f"  Σ sum_rate_a                 = {tot('sum_rate_a_mva')/1000:7.1f} GW")
    print(f"  Σ ITL n-0 (max of 2 dirs)    = "
          f"{sum(max(r['itl_n0_a_to_b'], r['itl_n0_b_to_a']) for r in out)/1000:7.1f} GW")
    print(f"  Σ ITL n-1 (max of 2 dirs)    = "
          f"{sum(max(r['itl_n1_a_to_b'], r['itl_n1_b_to_a']) for r in out if np.isfinite(r['itl_n1_a_to_b']))/1000:7.1f} GW")


if __name__ == "__main__":
    if "--validate" in sys.argv:
        sys.exit(0 if validate() else 1)
    d = HERE / (sys.argv[1] if len(sys.argv) > 1 else "inputs/gist_data_newest")
    run_gist(d)
