# Supplementary Information — Techno-economic Parameter Options

## Overview

This directory contains three sets of techno-economic parameters for the NZK Power Sector Model. Each option adopts different data sources for overnight capital costs (OCC) to enable sensitivity analysis on technology cost assumptions. The options differ primarily in their treatment of CCS and conventional generation costs; FOM and VOM are held constant at BNEF 2024 values across all three options to isolate OCC uncertainty.

| Option | Folder | OCC Source — Conventional/Renewables | OCC Source — CCS |
|---|---|---|---|
| **1** | `option1_BNEF/` | BNEF *New Energy Outlook* 2024 | BNEF 2024 |
| **2** | `option2_BNEF_NREL_ATB (CCS techs)/` | BNEF 2024 (same as Option 1) | NREL ATB 2024, Moderate scenario |
| **3** | `option3_Moon et al and BNEF/` | Moon et al. (2025), Korea-specific | BNEF 2024 |

All values are in **2021 real USD/MW**.

---

## OCC Comparison Table — All Options (2021 real $/MW)

### Gas CCGT

| Year | Option 1 (BNEF) | Option 2 (BNEF) | Option 3 (Moon et al.) |
|---:|---:|---:|---:|
| 2025 | 695,602 | 695,602 | 1,171,911 |
| 2030 | 695,602 | 695,602 | 1,255,324 |
| 2035 | 695,602 | 695,602 | 1,344,675 |
| 2040 | 695,602 | 695,602 | 1,457,180 |
| 2045 | 695,602 | 695,602 | 1,579,099 |
| 2050 | 695,602 | 695,602 | 1,711,217 |

> Option 3 is **+68% higher** than Options 1/2 in 2025, rising to **+146%** by 2050 due to the Korea-specific real cost escalation trend (+1.62%/yr) documented in Moon et al.

---

### Coal

| Year | Option 1 (BNEF) | Option 2 (BNEF) | Option 3 (Moon et al.) |
|---:|---:|---:|---:|
| 2025 | 1,164,761 | 1,164,761 | 1,564,878 |
| 2030 | 1,164,761 | 1,164,761 | 1,676,210 |
| 2035 | 1,164,761 | 1,164,761 | 1,795,463 |
| 2040 | 1,164,761 | 1,164,761 | 1,945,684 |
| 2045 | 1,164,761 | 1,164,761 | 2,108,475 |
| 2050 | 1,164,761 | 1,164,761 | 2,284,885 |

> Option 3 is **+34% higher** in 2025, reaching **+96%** by 2050.

---

### Nuclear

| Year | Option 1 (BNEF) | Option 2 (BNEF) | Option 3 (Moon et al.) |
|---:|---:|---:|---:|
| 2025 | 2,885,794 | 2,885,794 | 3,195,903 |
| 2030 | 2,833,578 | 2,833,578 | 3,560,092 |
| 2035 | 2,781,362 | 2,781,362 | 3,965,782 |
| 2040 | 2,729,147 | 2,729,147 | 4,497,873 |
| 2045 | 2,676,931 | 2,676,931 | 5,101,354 |
| 2050 | 2,624,715 | 2,624,715 | 5,785,805 |

> Option 3 (Moon et al.) assumes a +2.55%/yr real OCC escalation for nuclear, reflecting safety and regulatory cost increases documented in Korean construction data. Option 1/2 (BNEF) assumes a mild decline. By 2050, Option 3 nuclear OCC is **+121%** above Option 1.

---

### Solar PV

| Year | Option 1 (BNEF) | Option 2 (BNEF) | Option 3 (Moon et al.) |
|---:|---:|---:|---:|
| 2025 | 875,920 | 875,920 | 975,640 |
| 2030 | 605,007 | 605,007 | 823,405 |
| 2035 | 515,979 | 515,979 | 694,925 |
| 2040 | 460,805 | 460,805 | 602,933 |
| 2045 | 417,291 | 417,291 | 523,119 |
| 2050 | 380,044 | 380,044 | 453,870 |

> Both sources agree on a declining trajectory. Option 3 is **+11% higher** in 2025 (Korea domestic install cost premium) and **+19% higher** in 2050 (slower learning rate than BNEF global projection).

---

### Onshore Wind

| Year | Option 1 (BNEF) | Option 2 (BNEF) | Option 3 (Moon et al.) |
|---:|---:|---:|---:|
| 2025 | 1,969,493 | 1,969,493 | 1,790,514 |
| 2030 | 1,589,710 | 1,589,710 | 1,585,674 |
| 2035 | 1,504,512 | 1,504,512 | 1,404,268 |
| 2040 | 1,467,700 | 1,467,700 | 1,282,353 |
| 2045 | 1,440,460 | 1,440,460 | 1,171,022 |
| 2050 | 1,407,651 | 1,407,651 | 1,069,356 |

> Options converge near 2030. Moon et al. ultimately projects **−24% lower** OCC by 2050, reflecting stronger ATB Class 10 learning curve assumptions for Korean wind deployment.

---

### Offshore Wind (Fixed)

| Year | Option 1 (BNEF) | Option 2 (BNEF) | Option 3 (Moon et al.) |
|---:|---:|---:|---:|
| 2025 | 4,797,850 | 4,797,850 | 4,165,878 |
| 2030 | 4,519,714 | 4,519,714 | 3,497,508 |
| 2035 | 3,988,070 | 3,988,070 | 2,936,371 |
| 2040 | 3,860,141 | 3,860,141 | 2,613,869 |
| 2045 | 3,853,701 | 3,853,701 | 2,326,787 |
| 2050 | 3,851,612 | 3,851,612 | 2,071,235 |

> Moon et al. projects significantly faster offshore wind cost reductions, converging to ATB Class 7 by 2040 and reaching **−46% lower** OCC than BNEF by 2050.

---

### Gas CCS

| Year | Option 1 (BNEF) | Option 2 (NREL ATB) | Option 3 (BNEF) |
|---:|---:|---:|---:|
| 2025 | 1,718,028 | 2,500,000 | 1,718,028 |
| 2030 | 1,208,525 | 2,250,000 | 1,208,525 |
| 2035 | 1,182,953 | 2,075,000 | 1,182,953 |
| 2040 | 1,182,953 | 1,900,000 | 1,182,953 |
| 2045 | 1,182,953 | 1,725,000 | 1,182,953 |
| 2050 | 1,182,953 | 1,550,000 | 1,182,953 |

> Options 1 and 3 are identical for CCS (BNEF). Option 2 (NREL ATB) is **+45–75% higher** than BNEF across the projection period, reflecting NREL's full engineering-cost methodology vs. BNEF's market-based learning curve.

---

### Coal CCS

| Year | Option 1 (BNEF) | Option 2 (NREL ATB) | Option 3 (BNEF) |
|---:|---:|---:|---:|
| 2025 | 2,509,255 | 5,200,000 | 2,509,255 |
| 2030 | 2,402,347 | 4,900,000 | 2,402,347 |
| 2035 | 2,028,809 | 4,550,000 | 2,028,809 |
| 2040 | 2,028,809 | 4,200,000 | 2,028,809 |
| 2045 | 2,028,809 | 3,850,000 | 2,028,809 |
| 2050 | 2,028,809 | 3,500,000 | 2,028,809 |

> NREL ATB Coal CCS is **+107–127% higher** than BNEF in early years, declining to **+73%** by 2050 as NREL's learning curve assumption kicks in. This is the largest inter-option divergence in the parameter set and is expected to have the greatest impact on CCS capacity deployment in model results.

---

## Key Interpretation Notes

1. **Thermal/nuclear cost escalation (Option 3 only):** Moon et al. apply positive real OCC growth for gas, coal, and nuclear based on Korean domestic procurement trends. This is a fundamental departure from BNEF's assumption of stable or slightly declining conventional costs, and reflects Korea-specific regulatory, labor, and supply chain factors.

2. **CCS cost spread (Options 1/3 vs. 2):** The BNEF–NREL ATB spread for CCS is the largest source of inter-option uncertainty. NREL ATB CCS values represent U.S. engineering estimates with explicit capture infrastructure; BNEF values are derived from global learning curve projections. Both are plausible bounds, but neither is directly calibrated to Korean conditions.

3. **Renewable convergence:** By 2030–2035, onshore wind OCC values across all three options converge to within ~10%, suggesting that the model's renewable build decisions are less sensitive to parameter choice than thermal or CCS decisions.

4. **FOM/VOM:** Held constant at BNEF 2024 values in all three options. Differences in total LCOE across options therefore reflect OCC differences only.

---

## File Structure

```
techno_params/
├── README.md                                   ← This file (comparison table)
├── option1_BNEF/
│   ├── capex_params.csv
│   └── README.md                               ← Option 1 SI description
├── option2_BNEF_NREL_ATB (CCS techs)/
│   ├── capex_params.csv
│   └── README.md                               ← Option 2 SI description
└── option3_Moon et al and BNEF/
    ├── capex_params.csv
    └── README.md                               ← Option 3 SI description
```
