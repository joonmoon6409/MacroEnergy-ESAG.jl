# Supplementary Information — Techno-economic Parameters, Option 3: Moon et al. (2025) + BNEF

## S3.1 Overview

Option 3 adopts overnight capital costs from Moon et al. (2025), a Korea-specific LCOE study that derives OCC from domestic plant-level data and NREL ATB-aligned learning curves calibrated to Korean deployment targets. For technologies not covered by Moon et al. (specifically CCS), Option 1 BNEF values are retained.

This option is designed to test the sensitivity of model outcomes to Korea-specific cost assumptions versus global BNEF benchmarks. Moon et al. OCC values are generally higher than BNEF for conventional thermal technologies (gas, coal, nuclear) and lower for renewable technologies (offshore wind) — a pattern consistent with Korea's domestic construction cost premium and its maturing renewable sector.

All values are expressed in **2021 real USD per MW ($/MW)**.

---

## S3.2 Reference

> Moon, H.S., et al. (2025). Levelized cost of energy for Korean power generation technologies through 2050. *Energy Strategy Reviews*, 62, 101897. https://doi.org/10.1016/j.enestr.2025.101897

---

## S3.3 Data Sources by Technology

| Technology | Source | Basis |
|---|---|---|
| Gas CCGT | Moon et al. (2025) | National Assembly procurement data (2018–2024) + Lee et al. (2024) |
| Coal | Moon et al. (2025) | National Assembly procurement data (2020–2023) + Lee et al. (2024) |
| Solar PV | Moon et al. (2025) | Lee & Lim (2024, KEEI); NREL ATB-based nonlinear decline |
| Onshore Wind | Moon et al. (2025) | Weighted avg. of 73 projects (2019–2024); ATB Class 10 learning curve |
| Offshore Wind (fixed) | Moon et al. (2025) | Lee & Lim (2024); ATB Class 7 convergence by 2040 |
| Nuclear | Moon et al. (2025) | APR1400 actual construction costs (Saeul unit) |
| Gas CCS | BNEF 2024 | No Moon et al. estimate available |
| Coal CCS | BNEF 2024 | No Moon et al. estimate available |

---

## S3.4 Anchor Years and Interpolation/Extrapolation Methodology

### Anchor Values

Moon et al. (2025) report OCC values for a **2021 baseline** and a **2035 projection**, both in 2021 real USD/MW. These are used directly as anchor points.

| Technology | 2021 ($/MW) | 2035 ($/MW) | Moon et al. Note |
|---|---:|---:|---|
| Gas CCGT | 1,109,189 | 1,344,675 | 2023 OCC × +1.62%/yr trend |
| Coal | 1,481,161 | 1,795,463 | 2023 OCC × +1.62%/yr trend |
| Solar PV | 1,117,455 | 694,925 | NREL ATB-based nonlinear decline |
| Onshore Wind | 1,973,280 | 1,404,268 | ATB Class 10-aligned nonlinear learning curve |
| Offshore Wind | 4,791,426 | 2,936,371 | OCC converges to ATB Class 7 by 2040 |
| Nuclear | 2,931,565 | 3,965,782 | 2023 OCC × +2.55%/yr trend |

### Interpolation (2021–2035)

Annual values between the 2021 and 2035 anchors are obtained by **log-linear interpolation**, i.e., a constant compound annual growth (or decline) rate:

$$\text{OCC}(y) = \text{OCC}_{2021} \cdot \exp\!\left(\frac{\ln(\text{OCC}_{2035}/\text{OCC}_{2021})}{14} \cdot (y - 2021)\right)$$

### Extrapolation (2035–2050)

Post-2035 annual change rates are taken from Moon et al. (2025), Section 3.4.3:

| Technology | Annual rate (2035→2050) | Direction |
|---|---|---|
| Gas CCGT | +1.62%/yr | Increasing (domestic CCGT cost escalation) |
| Coal | +1.62%/yr | Increasing (domestic coal cost escalation) |
| Nuclear | +2.55%/yr | Increasing (safety, regulatory, and financing cost escalation) |
| Solar PV | −2.8%/yr | Decreasing (NREL ATB-based learning) |
| Onshore Wind | −1.8%/yr | Decreasing (ATB Class 10 learning) |
| Offshore Wind | −2.3%/yr | Decreasing (ATB Class 7-aligned convergence) |

The rising OCC trajectory for conventional thermal and nuclear technologies in Moon et al. reflects Korea-specific factors: aging domestic supply chains, increasing regulatory requirements, and real construction cost escalation observed in recent procurements.

---

## S3.5 Key OCC Values (2021 real $/MW)

| Technology | 2025 | 2030 | 2035 | 2040 | 2045 | 2050 | Source |
|---|---:|---:|---:|---:|---:|---:|---|
| Gas CCGT | 1,171,911 | 1,255,324 | 1,344,675 | 1,457,180 | 1,579,099 | 1,711,217 | Moon et al. |
| Coal | 1,564,878 | 1,676,210 | 1,795,463 | 1,945,684 | 2,108,475 | 2,284,885 | Moon et al. |
| Nuclear | 3,195,903 | 3,560,092 | 3,965,782 | 4,497,873 | 5,101,354 | 5,785,805 | Moon et al. |
| Solar PV | 975,640 | 823,405 | 694,925 | 602,933 | 523,119 | 453,870 | Moon et al. |
| Onshore Wind | 1,790,514 | 1,585,674 | 1,404,268 | 1,282,353 | 1,171,022 | 1,069,356 | Moon et al. |
| Offshore Wind | 4,165,878 | 3,497,508 | 2,936,371 | 2,613,869 | 2,326,787 | 2,071,235 | Moon et al. |
| Gas CCS | 1,718,028 | 1,208,525 | 1,182,953 | 1,182,953 | 1,182,953 | 1,182,953 | BNEF |
| Coal CCS | 2,509,255 | 2,402,347 | 2,028,809 | 2,028,809 | 2,028,809 | 2,028,809 | BNEF |

---

## S3.6 Comparison with BNEF (Option 1) — Selected Technologies, 2025

| Technology | Option 1 BNEF | Option 3 Moon et al. | Difference | Direction |
|---|---:|---:|---:|---|
| Gas CCGT | 695,602 | 1,171,911 | +68% | Moon higher |
| Coal | 1,164,761 | 1,564,878 | +34% | Moon higher |
| Nuclear | 2,885,794 | 3,195,903 | +11% | Moon higher |
| Solar PV | 875,920 | 975,640 | +11% | Moon higher |
| Onshore Wind | 1,969,493 | 1,790,514 | −9% | Moon lower |
| Offshore Wind | 4,797,850 | 4,165,878 | −13% | Moon lower |

These differences are consistent with findings reported in Moon et al. (2025, Table comparing "My Data" vs. BNEF): BNEF underestimates Korean domestic construction costs for thermal and nuclear technologies, while overestimating offshore wind costs relative to Korea-specific data.

---

## S3.7 Fixed and Variable O&M

FOM and VOM for all technologies in Option 3 are sourced from BNEF 2024 (same as Option 1), held constant across projection years. Moon et al. (2025) O&M values were not adopted due to differences in scope and to maintain comparability of non-OCC cost components across all three options.
