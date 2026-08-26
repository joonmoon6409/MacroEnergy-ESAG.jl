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

## Representative Technologies
- Thermal: Nuclear, Coal, Natural Gas (CCGT), Coal CHP, Natural Gas CHP
- Carbon capture: Coal CCS, Natural Gas CCS 
- Renewables: Utility-scale PV, Onshore Wind, Offshore Wind
- Storage: Battery ESS

## Existing Capacity (2021 Base Year)
Provincial existing capacities sourced from:
- Coal: KEPCO/plant-level data (CNA 20.2 GW, GNA 9.3 GW, INC 6.8 GW dominant)
- Natural Gas: KEPCO statistics (GGI 11.5 GW, INC 8.1 GW dominant)
- Nuclear: Sited at PUS, GNB, JNA, USN only (total 24.5 GW)
- Solar PV: Provincial allocation from KNREC 2021 supply statistics (total ~18.2 GW)
- Onshore Wind: Concentrated in GWN, JNA, GNB, JEJ (total ~1,560 MW)
- Offshore Wind: Early-stage; JNB (서남해 시범), JNA, JEJ (탐라) (total ~125 MW)
- CHP (district heat): GGI dominant (8.2 GW natgas), sourced from KDHC data

## Solution Algorithm
- Myopic optimization (default); perfect foresight option available
- Solver: Gurobi (academic license)