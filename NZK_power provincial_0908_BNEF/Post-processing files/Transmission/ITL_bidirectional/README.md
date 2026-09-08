# Bidirectional inter-province transmission capacities from Interface Transfer Limits

This folder is a **self-contained study/reproduction package** for how the file
`outputs/transmission_v2_2021_ITL_bidir.csv` was produced — the inter-province
transmission asset file for the NZK provincial model, with capacities set from
**Interface Transfer Limits (ITLs)** instead of raw thermal-rating sums.

*(A Korean version of this document is in `README_KO.md`.)*

---

## 1. Why not just add up line ratings?

The model has 17 provinces (zones) and 32 inter-province corridors. Each corridor
needs one number: how much power can flow across that province boundary.

The previous model file (`inputs/transmission_v2_2021_MODEL_TEMPLATE.csv`) set that
number to **the sum of the thermal (Rate A) ratings of every transmission line
crossing the boundary**, at all voltage levels. That overestimates deliverable
capacity, because:

* In a meshed AC network, power flow follows Kirchhoff's laws (loop flow). Some
  lines hit their rating before others, so the parallel circuits cannot all be
  loaded to nameplate simultaneously.
* No security de-rating: real operation must survive the loss of any single
  element (**N-1**), which limits the pre-contingency transfer well below the
  arithmetic sum.
* Direction matters: an interface can carry very different amounts each way.

Result for South Korea: the summed-ratings file totalled **≈418 GW** across the 32
corridors — about 4.6× national peak demand, with single corridors as large as
71 GW.

## 2. The method — NREL zonal Interface Transfer Limits

`reference/2308.03612v1_NREL_zonal_ITL_method.pdf`
Brown, Barrows, Wright, Brinkman, Dalvi, Zhang, Mai (NREL), *"A general method
for estimating zonal transmission interface limits from nodal network data"*,
arXiv:2308.03612 (2023).

For each interface between two zones, and each flow direction, solve a linear
program on a **DC power-flow (PTDF) representation of the nodal grid**:

```
        maximize (forward) / minimize (reverse)   Σ_{l ∈ crossing lines}  F(l)

subject to
        F(l) = Σ_b PTDF[l, b] · G(b)              # DC power flow (Kirchhoff)
        −rating(l) ≤ F(l) ≤ rating(l)  ∀ lines    # thermal limits, whole network
        G(b) ≥ 0   for generator buses            # injection can only add power
        G(b) ≤ 0   for load buses                 # withdrawal can only remove power
        G(b) = 0   for pure transmission buses
        Σ_b G(b) = 0                              # power balance
```

* `F(l)` = flow on line `l`; `G(b)` = net injection at bus `b`; both are decision
  variables. The `PTDF` matrix is built from line reactances + network topology.
* **`n-0`** ITL: all lines in service.
  **`n-1`** ITL: drop the crossing line carrying the largest flow, rebuild the
  PTDF, re-solve. (This is the paper's own simplification of a full N-1 sweep.)
* Interfaces are asymmetric, so the LP is run **both directions** independently.

The NREL paper ships a Julia package (`InterfaceLimits.jl`). The script here,
`compute_itl.py`, is an **independent Python re-implementation of the same LP**
(eqs. 1–4 of the paper). It is validated against the paper's 5-bus test system
(`compute_itl.py --validate` → interface 1‖2 = 719 MW, 2‖3 = 240, 1‖3 = 400).

## 3. The pipeline

```
  GIST nodal grid  (inputs/gist_data_newest/)
    bus.csv   → bus → province, bus type (gen / load / transmission)
    line.csv  → AC line reactance x_pu + rating rate_a_mva
    trafo2w.csv, trafo3w.csv → transformers (reactance, for the PTDF network)
        │
        │  compute_itl.py
        ▼
  outputs/province_ITL.csv
    per corridor:  Σ line ratings,  ITL n-0 (A→B / B→A),  ITL n-1 (A→B / B→A)
        │
        │  build_transmission_ITL.py   (+ HVDC from hvdc_lines.csv,
        │                                + distance/cost from the model template)
        ▼
  outputs/transmission_v2_2021_ITL_bidir.csv     ← the deliverable
  outputs/transmission_v2_2021_ITL_oneway.csv    ← directional variant, for reference
```

### How the single bidirectional number is chosen

A `TransmissionLink` in the model carries **one** capacity that must hold for flow
in **either** direction. So per corridor:

```
    existing_capacity  =  min( ITL_ac(A→B, n-1),  ITL_ac(B→A, n-1) )  +  HVDC(A↔B)
```

* `min(...)` of the two directional AC ITLs → a limit guaranteed in both
  directions (the conservative choice). To use `max` or the mean instead, change
  the one line marked in `build_transmission_ITL.py` (`ac_min = min(acs)`).
* **HVDC is added on top, not de-rated.** DC-link flow is scheduled by the
  converters and is not subject to AC loop flow, so it is additive (paper §2.3,
  and confirmed by Jesse). Jeju–Jeonnam = 900 MW (3 HVDC links); Dangjin–Godeok
  3000 MW is folded into the Gyeonggi–Chungnam corridor.
* `n-1` is the default AC contingency level (set `LEVEL = "itl_n0"` in
  `build_transmission_ITL.py` for the less conservative n-0).
* All non-capacity columns (`distance`, `loss_fraction`, `investment_cost`,
  `lifetime`, `wacc`, `max_capacity`, `can_expand`) are copied unchanged from
  `inputs/transmission_v2_2021_MODEL_TEMPLATE.csv`.

### Result

| | total across 32 corridors |
|---|---|
| old file (Σ thermal ratings, bidirectional) | 418 GW |
| **bidir ITL file (min-direction n-1 + HVDC)** | **171 GW** |
| oneway ITL file (both directions summed) | 399 GW |

Spot checks that the numbers are physically sane:

* **Gyeonggi–Seoul**: 29 GW → **14 GW**. Matches the well-known Seoul-metropolitan
  import limit of ~13–16 GW.
* **Gyeongnam–Ulsan**: 71 GW → **4 GW** (min direction). The 71 GW was an
  artifact of the Kori/Shin-Kori 765 kV nuclear switchyard sitting on the
  Busan/Ulsan/Gyeongnam tri-point; loop flow + N-1 removes most of it.

## 4. Files

```
README.md / README_KO.md          this document (EN / KO)
run_all.sh                        one command: validate → compute_itl → build

compute_itl.py                    the ITL solver (PTDF-LP, paper eqs. 1-4)
build_transmission_ITL.py         ITL + template + HVDC  →  transmission CSVs
build_province_transmission_capacity_DEMO.py
                                  shows how GIST's own province_transmission_capacity.csv
                                  is derived from bus.csv + line.csv (background reading)

inputs/
  transmission_v2_2021_MODEL_TEMPLATE.csv   current model transmission file (topology,
                                            distance, cost) — used only as a template
  [MACRO example] transmission asset.csv    the MacroEnergy example the template came from
  gist_data_newest/
    data/bus.csv line.csv trafo2w.csv trafo3w.csv gen.csv load.csv
    data/GIST_data_README.md                provenance of the GIST reconstruction
    results/total_results/province_transmission_capacity.csv   Σ ratings by corridor
    results/results_by_voltage/hvdc_lines.csv                  the 4 HVDC links

outputs/
  province_ITL.csv                          raw ITLs (n-0 & n-1, both directions)
  transmission_v2_2021_ITL_bidir.csv        ← MAIN: 32 rows, TransmissionLink
  transmission_v2_2021_ITL_oneway.csv       64 rows, OneWayTransmissionLink (directional)
  itl_run.log                               console log of the compute_itl.py run

reference/
  2308.03612v1_NREL_zonal_ITL_method.pdf    the NREL method paper
```

## 5. How to run

```bash
# quick check the solver reproduces the paper's 5-bus example
python3 compute_itl.py --validate

# full recompute (~15-20 min on a laptop) + rebuild the CSVs
bash run_all.sh
```

Dependencies: `python3`, `numpy`, `scipy` (HiGHS LP solver ships with scipy ≥1.9).

## 6. Caveats / limitations

* This is a **re-implementation** of the NREL method, not the `InterfaceLimits.jl`
  package. It passes the paper's 5-bus test, but has not been cross-checked
  against the package on a large system.
* **3-winding transformers** are approximated as a single HV↔MV branch
  (the tertiary winding carries no through-flow).
* **n-1** drops only the worst *interface-crossing* line, not every line in the
  network — the paper's own simplification (a true N-1 sweep is ~1000× costlier).
* Following the paper, bus injections are **not** capped by installed generation
  capacity or by observed load participation — the ITL is the *network's* physical
  capability. Adding those caps would lower the ITLs further.
* **No FACTS / phase-shifters** are modelled (the GIST data has 11 FACTS devices);
  including them could raise some ITLs.
* Missing / zero line reactances are set to a small default (1e-4 pu).
* `loss_fraction` is left at the template's flat 0.03 for every corridor — a
  pre-existing model issue, out of scope here.
* The GIST nodal reconstruction is itself a public-data model (~2024 network),
  not KEPCO's internal case. A gut-check with KEPCO transmission planners is still
  desirable.
* `OneWayTransmissionLink` (the directional variant) only exists in newer
  MacroEnergy releases; the bidirectional `TransmissionLink` file is the safe
  default.

## 7. References

1. Brown et al. (NREL), arXiv:2308.03612 (2023). Method paper. Code:
   `github.com/NREL-Sienna/InterfaceLimits.jl`
2. Li & Bo (2010), *Small test systems for power system economic studies*,
   IEEE PES GM — the 5-bus system used for validation.
3. GIST public-data Korean grid reconstruction — see
   `inputs/gist_data_newest/data/GIST_data_README.md`.
