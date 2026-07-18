# Supplementary Information — Techno-economic Parameters, Option 2: BNEF (non-CCS) + NREL ATB 2024 (CCS)

## S2.1 Overview

Option 2 is a hybrid parameter set that adopts NREL Annual Technology Baseline (ATB) 2024 overnight capital costs for carbon capture and storage (CCS) technologies, while retaining BNEF *New Energy Outlook 2024* values for all non-CCS technologies. This option is designed to test the sensitivity of model outcomes to the choice of CCS cost assumptions, given the wide divergence between BNEF and NREL ATB estimates for CCS.

All values are expressed in **2021 real USD per MW ($/MW)**.

---

## S2.2 Data Sources

| Technology Group | Source | Notes |
|---|---|---|
| Gas CCGT, Coal, Nuclear, Solar PV, Onshore Wind, Offshore Wind | BNEF *New Energy Outlook* 2024 | Same as Option 1 |
| Gas CCS | NREL ATB 2024, "NG 2-on-1 CC F-Frame 95% CCS, Moderate" scenario | Chart-read values, 2021 $/MW |
| Coal CCS | NREL ATB 2024, "Coal-95%-CCS, Moderate" scenario | Chart-read values, 2021 $/MW |

---

## S2.3 Non-CCS Technologies

All non-CCS OCC, FOM, and VOM values are identical to Option 1 (BNEF). Refer to Option 1 README (Section S1) for methodology and unit conversion details.

---

## S2.4 CCS Technology Assumptions (NREL ATB 2024)

### Data Extraction

CCS OCC values were read from NREL ATB 2024 cost comparison charts showing trajectories for BNEF, GNESTE, and NREL ATB under a "Moderate" scenario. The chart y-axis is labeled in $(2021)/MW, requiring no additional deflation adjustment.

Key data points extracted from charts:

| Technology | 2025 | 2030 | 2040 |
|---|---:|---:|---:|
| Gas CCS (NREL ATB Moderate) | 2,500,000 | 2,250,000 | 1,900,000 |
| Coal CCS (NREL ATB Moderate) | 5,200,000 | 4,900,000 | 4,200,000 |

### Interpolation and Extrapolation

Annual values between anchor years (2025–2030, 2030–2040) are obtained by **linear interpolation**. Values beyond 2040 (through 2050) are extrapolated by maintaining the 2030–2040 linear slope:

- Gas CCS: slope = −35,000 $/MW per year (2030→2040)
- Coal CCS: slope = −70,000 $/MW per year (2030→2040)

NREL ATB 2024 does not report CCS OCC values beyond 2040; extrapolation is therefore indicative and subject to greater uncertainty.

### Comparison with Option 1 (BNEF)

NREL ATB 2024 CCS costs are substantially higher than BNEF estimates, particularly in near-term years:

| Technology | Year | Option 1 (BNEF) | Option 2 (NREL ATB) | Ratio |
|---|---|---:|---:|---:|
| Gas CCS | 2025 | 1,718,028 | 2,500,000 | 1.45× |
| Gas CCS | 2035 | 1,182,953 | 2,075,000 | 1.75× |
| Gas CCS | 2050 | 1,182,953 | 1,550,000 | 1.31× |
| Coal CCS | 2025 | 2,509,255 | 5,200,000 | 2.07× |
| Coal CCS | 2035 | 2,028,809 | 4,550,000 | 2.24× |
| Coal CCS | 2050 | 2,028,809 | 3,500,000 | 1.73× |

The large discrepancy reflects fundamental differences in scope and methodology: NREL ATB 2024 is based on U.S. engineering cost estimates with full-chain capture infrastructure costing, while BNEF reflects global market-based learning curve projections calibrated to more optimistic deployment scenarios.

---

## S2.5 Key OCC Values (2021 real $/MW)

| Technology | 2025 | 2030 | 2035 | 2040 | 2045 | 2050 | Source |
|---|---:|---:|---:|---:|---:|---:|---|
| Gas CCGT | 695,602 | 695,602 | 695,602 | 695,602 | 695,602 | 695,602 | BNEF |
| Coal | 1,164,761 | 1,164,761 | 1,164,761 | 1,164,761 | 1,164,761 | 1,164,761 | BNEF |
| Nuclear | 2,885,794 | 2,833,578 | 2,781,362 | 2,729,147 | 2,676,931 | 2,624,715 | BNEF |
| Solar PV | 875,920 | 605,007 | 515,979 | 460,805 | 417,291 | 380,044 | BNEF |
| Onshore Wind | 1,969,493 | 1,589,710 | 1,504,512 | 1,467,700 | 1,440,460 | 1,407,651 | BNEF |
| Offshore Wind | 4,797,850 | 4,519,714 | 3,988,070 | 3,860,141 | 3,853,701 | 3,851,612 | BNEF |
| Gas CCS | 2,500,000 | 2,250,000 | 2,075,000 | 1,900,000 | 1,725,000 | 1,550,000 | NREL ATB 2024 |
| Coal CCS | 5,200,000 | 4,900,000 | 4,550,000 | 4,200,000 | 3,850,000 | 3,500,000 | NREL ATB 2024 |

---

## S2.6 Fixed and Variable O&M

FOM and VOM for all technologies are sourced from BNEF 2024 and held constant across years (see Option 1 README, Section S1.6). No NREL ATB O&M values are adopted in this option.
