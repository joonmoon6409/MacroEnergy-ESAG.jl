### === Version update from V1 ====



##### 1 Technoeconomic Parameter Update

Bioenergy tech technoeconomic parameter update ( More information in technology - google sheet : https://docs.google.com/spreadsheets/d/1jgqNvofYpfCuw\_iwABEbvDeRU9AzPWbl/edit?pli=1\&gid=1972933898#gid=1972933898 )



##### 2 MACRO asset structure update

EthanolPlant asset \[user\_additions/BECCSEthanolv2.jl] :

&#x20;   - Add Woodchip input(biomass input), Delete Bagasse co-production edge  -- No longer consider bagasse as a separate output commodity, Electricity production edge

&#x20;  - 1G2G ethanol plant, use sugarcane + sugarcane straw as inputs

BiodieselPlant asset \[user\_additions/beccsdieselv2.jl] : Add Woodchip input(biomass input), Electricity production edge

Biomassharvest asset \[user\_additions/biomasstransformation\_coprod.jl] : Split the main feedstock into the primary feedstock and residue co-product – Only used in Sugarcane/straw for now

&#x20;       e.g.,) Sugarcane supply curve--harvest -- sugarcane +sugarcane straw ( xx % production with collection/transport cost)

Adding biogasification asset \[user\_additions/biogasfiSNG.jl] : Biomass residue -> bio-SNG + Electricity



##### 3 Technology Pathway Update

Adding synthetic fuels pathway (from 2030)

Adding synthetic Natgas (from 2030)

Adding "Macauba oil to FAME" (from 2030)

Adding Biogasification – SNG (from 2030)

Naturalgas supply/demand pool structure update : Now there are fossil NG and non-fossil NG (h2+co2-SNG, bio-SNG) which can provide Natural gas demand. And newly added exogenous natural gas demand





##### 4 Supply Curve Update

Newly added Sugarcane straw (Tied to sugarcane), Corn stover, Forestry residue

Update RiceStraw supply curve : Aggregate the total supply amount per state (since constant price)

Residue cost update



\-- Sugarcane straw : (2025 USD) 55/dry tonne

\-- Corn stover : (2025 USD) 52/dry tonne

\-- Rice straw : (2025 USD) 54/dry tonne

\-- Forestry residue : (2025 USD) $50/dry tonne



\-- Sugarcane straw : 31 M dry tonne/yr  -- From Helena's number (cross checking with other refs)

\-- Corn stover : 100 M dry tonne/yr -- From Helena's number (cross checking with other refs)

\-- Rice straw : 6 M dry tonne -- From Helena's number (cross checking with other refs)

\-- Forestry residue : 21 dry tonne -- From SAFmaps





&#x20;More details in MASS doc



##### 5 etc.

Change "Macaw" to "Macauba"... :(

Remove "large" from plants name (Ethanol\_plant\_large --> Ethanol\_plant)

