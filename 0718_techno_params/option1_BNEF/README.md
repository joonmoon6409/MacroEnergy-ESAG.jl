# Supplementary Information — Techno-economic Parameters, Option 1: BNEF (2024)

## S1.1 Overview

Option 1 adopts overnight capital costs (OCC) sourced exclusively from BloombergNEF (BNEF) *New Energy Outlook 2024*. This option serves as the baseline scenario for techno-economic assumptions in the NZK Power Sector Model.

All values are expressed in **2021 real USD per MW ($/MW)**, the native unit of the MacroEnergy.jl modeling framework used in this study. Fixed O&M (FOM) costs are in $/MW-yr; variable O&M (VOM) costs are in $/MWh.

---

## S1.2 Data Source

| Field | Detail |
|---|---|
| Primary source | BloombergNEF, *New Energy Outlook 2024* |
| Original units | 2024 real USD/kW |
| Converted units | 2021 real USD/MW |
| Coverage | 2025–2050 (annual) |

---

## S1.3 Unit Conversion Methodology

BNEF reports OCC in 2024 real USD/kW. Values were converted to 2021 real USD/MW as follows:

$$\text{OCC}_{2021,\$/\text{MW}} = \text{OCC}_{2024,\$/\text{kW}} \times 1{,}000 \times \frac{112.264}{129.0}$$

where 112.264 and 129.0 are the U.S. GDP implicit price deflators for 2021 and 2024, respectively (BEA, 2024), yielding a deflation factor of **0.8703**.

The factor of 1,000 converts from per-kW to per-MW units.

---

## S1.4 Technology-Specific Assumptions

### Conventional Generation (Coal, Gas CCGT)

OCC values are held constant over time, reflecting BNEF's assumption of mature, stable technology costs for conventional thermal generation. No learning-curve decline is applied.

### Carbon Capture and Storage (Gas CCS, Coal CCS)

CCS costs were provided directly by BNEF in 2021 real USD/MW and do not require unit conversion. Values reflect a declining cost trajectory as CCS technology matures:

- **Gas CCS**: 1,718,028 $/MW (2025) → 1,182,953 $/MW (2035 and beyond)
- **Coal CCS**: 2,509,255 $/MW (2025) → 2,028,809 $/MW (2035 and beyond)

### Nuclear

A modest linear OCC decline is assumed (~−0.5%/yr), reflecting BNEF's expectation of modest cost reductions from APR1400-class reactor construction learning. This is based on the BNEF 2024 global nuclear cost trajectory adjusted for Korean market conditions.

### Solar PV

A strong learning-curve decline is applied, consistent with BNEF's global PV cost trajectory. OCC declines from 875,920 $/MW in 2025 to 380,044 $/MW in 2050, representing a cumulative reduction of approximately 57%.

### Onshore Wind

OCC declines from 1,969,493 $/MW in 2025 to 1,407,651 $/MW in 2050 (~−29%). The trajectory reflects a moderation in learning rates for mature onshore wind markets.

### Offshore Wind (Fixed)

OCC declines steeply from 4,797,850 $/MW in 2025 to approximately 3,851,612 $/MW in 2050, reflecting a rapid convergence toward ATB-class costs by 2040, followed by near-stabilization.

---

## S1.5 Key OCC Values (2021 real $/MW)

| Technology | 2025 | 2030 | 2035 | 2040 | 2045 | 2050 |
|---|---:|---:|---:|---:|---:|---:|
| Gas CCGT | 695,602 | 695,602 | 695,602 | 695,602 | 695,602 | 695,602 |
| Coal | 1,164,761 | 1,164,761 | 1,164,761 | 1,164,761 | 1,164,761 | 1,164,761 |
| Nuclear | 2,885,794 | 2,833,578 | 2,781,362 | 2,729,147 | 2,676,931 | 2,624,715 |
| Solar PV | 875,920 | 605,007 | 515,979 | 460,805 | 417,291 | 380,044 |
| Onshore Wind | 1,969,493 | 1,589,710 | 1,504,512 | 1,467,700 | 1,440,460 | 1,407,651 |
| Offshore Wind (fixed) | 4,797,850 | 4,519,714 | 3,988,070 | 3,860,141 | 3,853,701 | 3,851,612 |
| Gas CCS | 1,718,028 | 1,208,525 | 1,182,953 | 1,182,953 | 1,182,953 | 1,182,953 |
| Coal CCS | 2,509,255 | 2,402,347 | 2,028,809 | 2,028,809 | 2,028,809 | 2,028,809 |

---

## S1.6 Fixed and Variable O&M

FOM and VOM values are sourced from BNEF 2024 and held constant across all projection years, as BNEF does not provide year-varying O&M projections.

| Technology | FOM ($/MW-yr) | VOM ($/MWh) |
|---|---:|---:|
| Gas CCGT | 15,274 | 1.82 |
| Coal | 15,816 | 1.55 |
| Nuclear | 199,087 | 10.34 |
| Solar PV | 19,800 | 0 |
| Onshore Wind | 40,000 | 0 |
| Offshore Wind | 63,000 | 0 |
| Gas CCS | 17,597 | 8.58 |
| Coal CCS | 53,714 | 19.14 |
