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