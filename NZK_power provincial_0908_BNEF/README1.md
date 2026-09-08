# Net Zero Korea — Power Sector Model

## Overview
Provincial-level capacity expansion and dispatch model for South Korea's power sector, built on MacroEnergy.jl.

## Temporal Coverage
- Base year: 2021
- Modeling periods: 2025, 2030, 2035 (5-year time steps)
- Temporal resolution: Hourly (8,760 hours per period), 
- Representative periods — 14 representative days (336 hours) per year. No Unit commitment
- Renewable availability: ERA5 hourly capacity factor data *(5km × 5km spatial resolution planned)*
- Renewable potential by province: 신재생에너지 백서 technical potential. 

## Spatial Resolution
Provincial-level nodal representation across 17 provinces:

| Code | Province |
|------|----------|
| SEL | Seoul |
| PUS | Busan |
| TAE | Daegu |
| INC | Incheon |
| KWJ | Gwangju |
| USN | Ulsan |
| SJG | Sejong |
| GGI | Gyeonggi |
| GWN | Gangwon |
| CNA | Chungnam |
| CNB | Chungbuk |
| DJJ | Daejeon |
| JNB | Jeonbuk |
| JNA | Jeonnam |
| GNB | Gyeongbuk |
| GNA | Gyeongnam |
| JEJ | Jeju |

## Inter-Regional Transmission
- Bidirectional transmission links modeled as `OneWayTransmissionLink` pairs between adjacent provinces
- 28 corridor pairs (56 directional links) reflecting major 345kV backbone topology
- Key corridors: SEL↔GGI↔INC (수도권 삼각), GGI↔GWN/CNB/CNA, GNB↔TAE/USN/GNA, JNA↔JEJ (HVDC 해저케이블)
- Each link carries: existing capacity (MW), loss fraction, investment cost (₩/kW), expansion option (`can_expand: true`)
- Jeju–Jeonnam link modeled with elevated loss fraction (0.015) reflecting HVDC subsea cable characteristics
- Transmission losses endogenous to dispatch optimization

## Techno-economic parameter
   
   Representative Technologies
- Thermal: Nuclear, Coal, Natural Gas (CCGT), Coal CHP, Natural Gas CHP
- Carbon capture: Coal CCS, Natural Gas CCS 
- Renewables: Utility-scale PV, Onshore Wind, Offshore Wind
- Storage: Battery ESS

CCS assumption
- CO2 injectivity constraints applied to reflect geological storage capacity limits

## Existing Capacity (2021 Base Year)
Provincial existing capacities sourced from:
- Coal: KEPCO/plant-level data (CNA 20.2 GW, GNA 9.3 GW, INC 6.8 GW dominant)
- Natural Gas: KEPCO statistics (GGI 11.5 GW, INC 8.1 GW dominant)
- Nuclear: Sited at PUS, GNB, JNA, USN only (total 24.5 GW)
- Solar PV: Provincial allocation from KNREC 2021 supply statistics (total ~18.2 GW)
- Onshore Wind: Concentrated in GWN, JNA, GNB, JEJ (total ~1,560 MW)
- Offshore Wind: Early-stage; JNB (서남해 시범), JNA, JEJ (탐라) (total ~125 MW)
- CHP (district heat): GGI dominant (8.2 GW natgas), sourced from KDHC data

## Policy Assumptions
- CO2 cap based on Korea's NDC sectoral targets for the power sector
- Capacity expansion restricted in Seoul (SEL) to reflect land use and siting constraints

## Solution Algorithm
- Myopic optimization (default); perfect foresight option available
- Solver: Gurobi (academic license)

## Change Log

### Provincial VRE Capacity Factors (2025-06-08 → updated in 0623)
Previously, all VRE assets used a single national-average capacity factor time series. Updated to province-specific hourly CF data sourced from ERA5 (2021, KST).

**Data source:** `2021_Provincial_CF/` folder
- `hourly_cf_solar_2021_KST.csv` — 16 province columns, 8,760 hours
- `hourly_cf_onwind_2021_KST.csv` — 16 province columns, 8,760 hours
- `hourly_cf_offwind-dc_2021_KST.csv` — 11 coastal province columns, 8,760 hours

**Files modified:**

- `system/availability.csv`
  - Added 51 new province-specific columns (17 provinces × 3 technologies)
  - Naming convention: `{PROVINCE_CODE}_solar`, `{PROVINCE_CODE}_onwind`, `{PROVINCE_CODE}_offwind-dc`
  - Original national columns (`KR_utilitypv`, `onwind`, `offwind-dc`) retained for backward compatibility
  - Total columns: 6 → 57

- `assets/assets_2021/VRE_21.csv`, `assets/assets_2025/VRE.csv`, `assets/assets_2030/VRE.csv`, `assets/assets_2035/VRE.csv`
  - `edges--edge--availability--timeseries--header` updated for all 51 VRE rows per file (204 rows total)
  - `utility_pv` rows: `KR_utilitypv` → `{PROVINCE_CODE}_solar`
  - `onshore_wind` rows: `onwind` → `{PROVINCE_CODE}_onwind`
  - `offshore_wind` rows: `offwind-dc` → `{PROVINCE_CODE}_offwind-dc`

**Special handling:**
- `Gyeongbuk/Daegu` in source data is split into GNB and TAE, both assigned identical CF values
- Inland provinces without offshore access (SEL, SJG, CNB, DJJ, KWJ) assigned CF = 0.0 for `offwind-dc`
- offshore_wind assets for all 17 provinces exist in the model; inland ones are effectively constrained by max_capacity = 0

### 2021 Base-Year Input Corrections (2026-08-27)

**Issue found:** several 2021 existing-capacity inputs contained province-code data entry errors or were inconsistent with a newly collected plant-level reference dataset (`province level_power (3).xlsx`, EPSIS/KHNP-sourced, provided by user). Cross-checked against real plant locations (e.g. Saeul NPP units are physically in Ulsan, not Daejeon; Sejong has no commercial LNG complex) and against the reference workbook's province-level summary tables.

**Files modified:**

- `assets/assets_2021/NaturalGasPower_21.csv`
  - `SJG_natgas_CCGT` and `GGI_natgas_CCGT` `existing_capacity` values were swapped (Sejong showed 11,689MW, Gyeonggi showed 848MW). Corrected: Sejong → 848MW, Gyeonggi → 11,689MW. Matches reference workbook exactly.

- `assets/assets_2021/nuclear_21.csv`
  - `DJJ_nuclear_power_plant` and `USN_nuclear_power_plant` `existing_capacity` values were swapped (Daejeon showed 2,800MW, Ulsan showed 0MW). Corrected: Daejeon → 0MW, Ulsan → 2,800MW (Saeul Units 1–2). Matches reference workbook exactly.

- `assets/assets_2021/coalpower_21.csv`
  - `Coal_power_plant_JNA` (Jeonnam) `existing_capacity` corrected from 1,168.6MW → 668.6MW to match reference workbook. National coal total: 36,328.7 → 35,828.7MW.

- `assets/assets_2021/VRE_21.csv`
  - `edges--edge--existing_capacity` for all 17 provinces replaced for both `_utility_pv` (Solar) and `_onshore_wind` rows, using the reference workbook's plant-level province summary instead of the previous KNREC-white-paper-based allocation.
  - Solar national total: 18,160.6 → 18,200.0MW (unchanged in aggregate, reallocated by province — e.g. Gangwon corrected down from 1,396.1MW to 688MW, Gyeonggi corrected up from 1,107.3MW to 1,376MW).
  - Onshore wind national total: 1,583.5 → 1,560.0MW (e.g. Incheon corrected from 49.0MW to 0MW, Gangwon corrected from 459.5MW to 580MW).

**Not modified (verified consistent, no changes needed):**
- Pumped hydro (7 plants, 4,700MW) — matches reference workbook exactly
- Offshore wind — matches reference workbook (JNB/JNA/JEJ only, 124.5MW total)
- Hydro reservoir — reference workbook uses a broader "수력에너지" definition (likely includes small/run-of-river hydro) than this model's 8-dam aggregation; left as-is pending scope reconciliation

**Note:** 2025/2030/2035 asset files are unaffected — `existing_capacity` for those periods is carried forward automatically from the prior period's solved capacity via myopic linking, not read from the hardcoded (mostly zero) values in those CSVs.

## Caveats / Open Issues (2026-08-27 session)

Things found or changed this session that are **not fully resolved** — flagging so results aren't over-interpreted before these are addressed.

- **VRE time alignment fix (`system/availability.csv`) is applied, but only for the province-specific solar/onwind/offwind columns.** Legacy national-average columns (`KR_utilitypv`, `onwind`, `offwind-dc`) were left untouched since no current asset references them — confirm before reusing those columns for anything.

- **Heat/Steam sector is structurally present but functionally inert.** 17 heat nodes exist with (flat, non-time-varying) demand, but there is no CHP or other Steam-supplying asset anywhere in `assets/`, and `max_nsd=1` / `price_nsd=0` means 100% of heat demand is unserved at zero cost in every period. Any "total energy served" or "total cost" figure implicitly excludes a meaningful heat sector. Do not interpret heat-related outputs until CHP is integrated (see To-Do list below).

- **Nuclear `can_expand` was changed to `TRUE` for 16/17 provinces (all but Seoul) from 2025 onward, with no `max_capacity` column present in `nuclear_XX.csv` at all** — i.e. new nuclear build is uncapped per province. In an NDC test run this produced ~17.6GW concentrated in a single province (Gyeonggi), which is not a realistic siting outcome. If nuclear expansion is meant to reflect real candidate sites, `max_capacity` + `MaxCapacityConstraint` columns need to be added (see prior conversation) before results are used for anything other than a rough what-if.

- **Transmission does not expand even when fully saturated.** In the NDC run, three corridors out of Gangwon (GGI↔GWN, GWN↔GNB, GWN↔CNB) hit 100% of existing capacity by 2035 despite `can_expand=TRUE` and no binding `max_capacity`, causing ~2.93TWh of local solar curtailment in Gangwon that is invisible in the national curtailment average (~4%). Root cause not yet identified — worth a follow-up before trusting province-level VRE siting results.

- **`system/demand_NDC.csv` is not usable as-is.** It only contains national-level columns (16 total) — it has not been run through `system/Demand_cal.R` to produce the province-level breakdown (`Demand_MW_25_SEL`, etc.) that `nodes_XXXX.json` requires. As of this session, `nodes_2021/25/30/35.json` still point to `system/demand.csv`, not `demand_NDC.csv` — confirm which demand file any given NDC run actually used before comparing results across runs.

- **Investment/O&M cost columns are most consistent with $/MW (and $/MWh for storage energy), not KRW/MW as originally assumed mid-session.** Recomputing at $/MW lines up with real-world per-kW costs for every technology (coal, gas, nuclear, solar, wind, battery) without any currency conversion; treating the same numbers as KRW required an ad hoc ÷1,330 conversion that fit less cleanly. Worth getting explicit confirmation of currency/unit from whoever built the original cost inputs.

- **Transmission `loss_fraction` is uniformly 0.03 for all 32 corridors**, including the Jeju–Jeonnam HVDC subsea link — this contradicts the loss-fraction description elsewhere in this README (0.015 for that link). This predates this session's changes and was not modified; flagged here since it surfaced during this session's transmission review.

- **New reference workbook (`province level_power (3).xlsx`) lives outside this project folder** (`~/Desktop/`), not under version control here. It has an internal date inconsistency (`Group energy` sheet labeled "Year 2025" while other sheets say "Year 2021") not otherwise investigated. If this file moves or is edited, the province-level corrections above cannot be re-derived from within this repo alone.

- **Hydro reservoir province allocation was intentionally left unreconciled.** The reference workbook's broader "수력에너지" total (1,815.25MW) includes scope (likely small-scale/run-of-river hydro) beyond this model's 8-dam `HydroRes` aggregation (1,549.0MW) — the two are not directly comparable without first resolving what should and shouldn't be in scope.

- **The blank-row corruption found in `NaturalGasPower_35.csv` was fixed for that one file only.** No systematic scan was run across all other asset CSVs for the same Excel-export artifact (trailing empty rows with CRLF line endings) — if a similar crash occurs when loading a different asset file, check for this pattern first.