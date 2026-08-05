=== Version update from V1 ====

1. Technoeconomic Parameter Update
- Bioenergy tech의 technoeconomic parameter 관련 대대적인 업데이트 -- Awaiting for update ( More information in technology - google sheet)
- Transmission economic parameter update (from Marlon)


2. MACRO asset structure update
: EthanolPlant asset : Add Woodchip input(biomass input), Delete Bagasse co-production edge  -- No longer consider bagasse as a separate output commodity


: 1G2G의 경우 sugarcane straw input 필요

: BiodieselPlant asset : Add Woodchip input(biomass input),  

: Biomassharvest asset : biomass feedstock 에 연결시 residue가 proportional 하게 생산되도록 사용. e.g.,) Sugarcane supply curve--harvest -- sugarcane +sugarcane straw (20% production with collection/transport cost)  -- collect rate=0.096 dry straw/wet sugarcane, (recovery+transport) 48.7 2025$/dry straw 


** Collect rate = 0.12(coprod)*0.4(recovery factor)*2(sugar usage)



3. Technology Pathway Update
- Adding synthetic pathway (from 2030)
- Adding synthetic Natgas (from 2030)
- Adding "Macauba oil to FAME" (from 2030)

-- Need to add biogasification 


4. Supply Curve Update

- Rescaling 2023 USD to 2025 USD

- Newly added Sugarcane straw (Tied to sugarcane), Corn stover, Forestry residue

- Update RiceStraw supply curve : Aggregate the total supply amount per state (since constant price)



5. etc. 

- Change "Macaw" to "Macauba"... :(
- Remove "large" from plants name (Ethanol_plant_large --> Ethanol_plant)
