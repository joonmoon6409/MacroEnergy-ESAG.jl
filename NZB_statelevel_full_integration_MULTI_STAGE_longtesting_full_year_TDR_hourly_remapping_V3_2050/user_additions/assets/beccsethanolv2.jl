struct BECCSEthanolv2 <: AbstractAsset
    id::AssetId
    ethanol_transform::Transformation
    biomass_edge::Edge{<:Biomass}
    coinput_edge::Edge{<:Biomass}
    ethanol_edge::Edge{<:LiquidFuels}
    coproduct_edge::Edge{<:Commodity}
    elec_consumption_edge::Edge{<:Electricity}
    elec_production_edge::Edge{<:Electricity}
    co2_edge::Edge{<:CO2}
    co2_emission_edge::Edge{<:CO2}
    co2_captured_edge::Edge{<:CO2Captured}
end

function default_data(t::Type{BECCSEthanolv2}, id=missing, style="full")
    if style == "full"
        return full_default_data(t, id)
    else
        return simple_default_data(t, id)
    end
end

function full_default_data(::Type{BECCSEthanolv2}, id=missing)
    return OrderedDict{Symbol,Any}(
        :id => id,
        :transforms => @transform_data(
            :timedata => "Biomass",
            :constraints => Dict{Symbol,Bool}(
                :BalanceConstraint => true
            ),
            :ethanol_production => 0.0,
            :coproduct_production => 0.0,
            # co-input consumed per unit of MAIN biomass input (e.g. woodchips for process heat).
            # 0.0 => co-input flow is forced to zero by the balance.
            :coinput_rate => 0.0,
            :electricity_consumption => 0.0,
            :electricity_production => 0.0,
            :co2_content => 0.0,
            :emission_rate => 1.0,
            :capture_rate => 1.0
        ),
        :edges => Dict{Symbol,Any}(
            :biomass_edge => @edge_data(:commodity => "Biomass", :has_capacity => true, :can_expand => true, :can_retire => true, :constraints => Dict{Symbol,Bool}(:CapacityConstraint => true)),
            :coinput_edge => @edge_data(:commodity => "Biomass"),
            :ethanol_edge => @edge_data(:commodity => "LiquidFuels"),
            :coproduct_edge => @edge_data(:commodity => "Biomass"),
            :co2_edge => @edge_data(:commodity => "CO2", :co2_sink => missing),
            :co2_emission_edge => @edge_data(:commodity => "CO2", :co2_sink => missing),
            :elec_consumption_edge => @edge_data(:commodity => "Electricity"),
            :elec_production_edge => @edge_data(:commodity => "Electricity"),
            :co2_captured_edge => @edge_data(:commodity => "CO2Captured")
        )
    )
end

function simple_default_data(::Type{BECCSEthanolv2}, id=missing)
    return OrderedDict{Symbol,Any}(
        :id => id,
        :location => missing,
        :can_expand => true,
        :can_retire => true,
        :existing_capacity => 0.0,
        :ethanol_commodity => "LiquidFuels",
        :coinput_commodity => "Biomass",
        :coproduct_commodity => "Biomass",
        :co2_sink => missing,
        :ethanol_production => 0.0,
        :coproduct_production => 0.0,
        :coinput_rate => 0.0,
        :electricity_consumption => 0.0,
        :electricity_production => 0.0,
        :co2_content => 0.0,
        :emission_rate => 1.0,
        :capture_rate => 1.0,
        :investment_cost => 0.0,
        :fixed_om_cost => 0.0,
        :variable_om_cost => 0.0
    )
end

function make(asset_type::Type{BECCSEthanolv2}, data::AbstractDict{Symbol,Any}, system::System)
    id = AssetId(data[:id])
    location = as_symbol_or_missing(get(data, :location, missing))

    @setup_data(asset_type, data, id)

    transform_key = :transforms
    @process_data(
        transform_data,
        data[transform_key],
        [
            (data[transform_key], key),
            (data[transform_key], Symbol("transform_", key)),
            (data, Symbol("transform_", key)),
            (data, key),
        ]
    )
    ethanol_transform = Transformation(
        id = Symbol(id, "_", transform_key),
        timedata = system.time_data[Symbol(transform_data[:timedata])],
        location = location,
        constraints = transform_data[:constraints],
    )

    # Biomass Edge (main feedstock; carries the capacity constraint)
    biomass_edge_key = :biomass_edge
    @process_data(
        biomass_edge_data,
        data[:edges][biomass_edge_key],
        [
            (data[:edges][biomass_edge_key], key),
            (data[:edges][biomass_edge_key], Symbol("biomass_", key)),
            (data, Symbol("biomass_", key)),
            (data, key),
        ]
    )
    biomass_commodity = commodity_types()[Symbol(biomass_edge_data[:commodity])]
    @start_vertex(
        biomass_start,
        biomass_edge_data,
        biomass_commodity,
        [(biomass_edge_data, :start_vertex), (data, :location)],
    )
    biomass_edge = Edge(
        Symbol(id, "_", biomass_edge_key),
        biomass_edge_data,
        system.time_data[Symbol(biomass_edge_data[:commodity])],
        biomass_commodity,
        biomass_start,
        ethanol_transform,
    )

    # Co-Input Edge (secondary feedstock, e.g. woodchips for process heat)
    coinput_edge_key = :coinput_edge
    @process_data(
        coinput_edge_data,
        data[:edges][coinput_edge_key],
        [
            (data[:edges][coinput_edge_key], key),
            (data[:edges][coinput_edge_key], Symbol("coinput_", key)),
            (data, Symbol("coinput_", key)),
        ]
    )
    coinput_commodity = commodity_types()[Symbol(coinput_edge_data[:commodity])]
    @start_vertex(
        coinput_start,
        coinput_edge_data,
        coinput_commodity,
        [(coinput_edge_data, :start_vertex), (data, :location)],
    )
    coinput_edge = Edge(
        Symbol(id, "_", coinput_edge_key),
        coinput_edge_data,
        system.time_data[Symbol(coinput_edge_data[:commodity])],
        coinput_commodity,
        coinput_start,
        ethanol_transform,
    )

    # Ethanol Edge
    ethanol_edge_key = :ethanol_edge
    @process_data(
        ethanol_edge_data,
        data[:edges][ethanol_edge_key],
        [
            (data[:edges][ethanol_edge_key], key),
            (data[:edges][ethanol_edge_key], Symbol("ethanol_", key)),
            (data, Symbol("ethanol_", key)),
        ]
    )
    ethanol_commodity = commodity_types()[Symbol(ethanol_edge_data[:commodity])]
    @end_vertex(
        ethanol_end,
        ethanol_edge_data,
        ethanol_commodity,
        [(ethanol_edge_data, :end_vertex), (data, :location)],
    )
    ethanol_edge = Edge(
        Symbol(id, "_", ethanol_edge_key),
        ethanol_edge_data,
        system.time_data[Symbol(ethanol_edge_data[:commodity])],
        ethanol_commodity,
        ethanol_transform,
        ethanol_end,
    )

    # Co-Product Edge (was bagasse_edge)
    coproduct_edge_key = :coproduct_edge
    @process_data(
        coproduct_edge_data,
        data[:edges][coproduct_edge_key],
        [
            (data[:edges][coproduct_edge_key], key),
            (data[:edges][coproduct_edge_key], Symbol("coproduct_", key)),
            (data, Symbol("coproduct_", key)),
        ]
    )
    coproduct_commodity = commodity_types()[Symbol(coproduct_edge_data[:commodity])]
    @end_vertex(
        coproduct_end,
        coproduct_edge_data,
        coproduct_commodity,
        [(coproduct_edge_data, :end_vertex), (data, :location)],
    )
    coproduct_edge = Edge(
        Symbol(id, "_", coproduct_edge_key),
        coproduct_edge_data,
        system.time_data[Symbol(coproduct_edge_data[:commodity])],
        coproduct_commodity,
        ethanol_transform,
        coproduct_end,
    )

    # Electricity Consumption Edge
    elec_edge_key = :elec_consumption_edge
    @process_data(
        elec_edge_data,
        data[:edges][elec_edge_key],
        [
            (data[:edges][elec_edge_key], key),
            (data[:edges][elec_edge_key], Symbol("elec_consumption_", key)),
            (data[:edges][elec_edge_key], Symbol("elec_", key)),
            (data, Symbol("elec_consumption_", key)),
            (data, Symbol("elec_", key)),
        ]
    )
    @start_vertex(
        elec_start,
        elec_edge_data,
        Electricity,
        [(elec_edge_data, :start_vertex), (data, :location)],
    )
    elec_consumption_edge = Edge(
        Symbol(id, "_", elec_edge_key),
        elec_edge_data,
        system.time_data[:Electricity],
        Electricity,
        elec_start,
        ethanol_transform,
    )

    # Electricity Production Edge
    elec_prod_edge_key = :elec_production_edge
    @process_data(
        elec_prod_edge_data,
        data[:edges][elec_prod_edge_key],
        [
            (data[:edges][elec_prod_edge_key], key),
            (data[:edges][elec_prod_edge_key], Symbol("elec_production_", key)),
            (data, Symbol("elec_production_", key)),
        ]
    )
    @end_vertex(
        elec_prod_end,
        elec_prod_edge_data,
        Electricity,
        [(elec_prod_edge_data, :end_vertex), (data, :location)],
    )
    elec_production_edge = Edge(
        Symbol(id, "_", elec_prod_edge_key),
        elec_prod_edge_data,
        system.time_data[:Electricity],
        Electricity,
        ethanol_transform,
        elec_prod_end,
    )

    # CO2 Emission Edge
    co2_emission_key = :co2_emission_edge
    @process_data(
        co2_emission_data,
        data[:edges][co2_emission_key],
        [
            (data[:edges][co2_emission_key], key),
            (data[:edges][co2_emission_key], Symbol("co2_emission_", key)),
            (data, Symbol("co2_emission_", key)),
        ]
    )
    @end_vertex(
        co2_emission_end,
        co2_emission_data,
        CO2,
        [(co2_emission_data, :end_vertex), (data, :co2_sink), (data, :location)],
    )
    co2_emission_edge = Edge(
        Symbol(id, "_", co2_emission_key),
        co2_emission_data,
        system.time_data[:CO2],
        CO2,
        ethanol_transform,
        co2_emission_end,
    )

    # CO2 Captured Edge
    co2_captured_key = :co2_captured_edge
    @process_data(
        co2_captured_data,
        data[:edges][co2_captured_key],
        [
            (data[:edges][co2_captured_key], key),
            (data[:edges][co2_captured_key], Symbol("co2_captured_", key)),
            (data, Symbol("co2_captured_", key)),
        ]
    )
    @end_vertex(
        co2_captured_end,
        co2_captured_data,
        CO2Captured,
        [(co2_captured_data, :end_vertex), (data, :location)],
    )
    co2_captured_edge = Edge(
        Symbol(id, "_", co2_captured_key),
        co2_captured_data,
        system.time_data[:CO2Captured],
        CO2Captured,
        ethanol_transform,
        co2_captured_end,
    )

    # CO2 Edge (negative emissions)
    co2_edge_key = :co2_edge
    @process_data(
        co2_edge_data,
        data[:edges][co2_edge_key],
        [
            (data[:edges][co2_edge_key], key),
            (data[:edges][co2_edge_key], Symbol("co2_", key)),
            (data, Symbol("co2_", key)),
        ]
    )
    @start_vertex(
        co2_start,
        co2_edge_data,
        CO2,
        [(co2_edge_data, :start_vertex), (data, :co2_sink), (data, :location)],
    )
    co2_edge = Edge(
        Symbol(id, "_", co2_edge_key),
        co2_edge_data,
        system.time_data[:CO2],
        CO2,
        co2_start,
        ethanol_transform,
    )

    # Balance Data
    #
    # Sign convention (BalanceConstraint already signs flows by edge direction:
    # inflow +, outflow -). Both cases below resolve to
    #     <edge flow> = <parameter> * <biomass_edge flow>
    # with the parameter entered as a POSITIVE number in the input data:
    #   - OUTFLOW edge (transform -> node): coefficient +1.0
    #   - INFLOW  edge (node -> transform): coefficient -1.0
    ethanol_transform.balance_data = Dict(
        :ethanol_production => Dict(
            ethanol_edge.id => 1.0,
            biomass_edge.id => get(transform_data, :ethanol_production, 0.0),
        ),
        :coproduct_production => Dict(
            coproduct_edge.id => 1.0,
            biomass_edge.id => get(transform_data, :coproduct_production, 0.0),
        ),
        :coinput_ratio => Dict(
            coinput_edge.id => -1.0,
            biomass_edge.id => get(transform_data, :coinput_rate, 0.0),
        ),
        :elec_consumption => Dict(
            elec_consumption_edge.id => -1.0,
            biomass_edge.id => get(transform_data, :electricity_consumption, 0.0),
        ),
        :elec_production => Dict(
            elec_production_edge.id => 1.0,
            biomass_edge.id => get(transform_data, :electricity_production, 0.0),
        ),
        :negative_emissions => Dict(
            biomass_edge.id => get(transform_data, :co2_content, 0.0),
            co2_edge.id => -1.0,
        ),
        :emissions => Dict(
            biomass_edge.id => get(transform_data, :emission_rate, 1.0),
            co2_emission_edge.id => 1.0,
        ),
        :capture => Dict(
            biomass_edge.id => get(transform_data, :capture_rate, 1.0),
            co2_captured_edge.id => 1.0,
        )
    )

    return BECCSEthanolv2(
        id,
        ethanol_transform,
        biomass_edge,
        coinput_edge,
        ethanol_edge,
        coproduct_edge,
        elec_consumption_edge,
        elec_production_edge,
        co2_edge,
        co2_emission_edge,
        co2_captured_edge,
    )
end