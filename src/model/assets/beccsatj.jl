struct BECCSATJ <: AbstractAsset
    id::AssetId
    atj_transform::Transformation
    ethanol_edge::Edge{<:LiquidFuels}
    jetfuel_edge::Edge{<:LiquidFuels}
    elec_consumption_edge::Edge{<:Electricity}
    co2_edge::Edge{<:CO2}
    co2_emission_edge::Edge{<:CO2}
    co2_captured_edge::Edge{<:CO2Captured}
end

function default_data(t::Type{BECCSATJ}, id=missing, style="full")
    if style == "full"
        return full_default_data(t, id)
    else
        return simple_default_data(t, id)
    end
end

function full_default_data(::Type{BECCSATJ}, id=missing)
    return OrderedDict{Symbol,Any}(
        :id => id,
        :transforms => @transform_data(
            :timedata => "LiquidFuels",
            :constraints => Dict{Symbol,Bool}(
                :BalanceConstraint => true
            ),
            :jetfuel_production => 0.0,
            :electricity_consumption => 0.0,
            :electricity_production => 0.0,
            :co2_content => 0.0,
            :emission_rate => 1.0,
            :capture_rate => 1.0
        ),
        :edges => Dict{Symbol,Any}(
            :ethanol_edge => @edge_data(:commodity => "LiquidFuels", :has_capacity => true, :can_expand => true, :can_retire => true, :constraints => Dict{Symbol,Bool}(:CapacityConstraint => true)),
            :jetfuel_edge => @edge_data(:commodity => "LiquidFuels"),
            :co2_edge => @edge_data(:commodity => "CO2", :co2_sink => missing),
            :co2_emission_edge => @edge_data(:commodity => "CO2", :co2_sink => missing),
            :elec_consumption_edge => @edge_data(:commodity => "Electricity"),
            :co2_captured_edge => @edge_data(:commodity => "CO2Captured")
        )
    )
end

function simple_default_data(::Type{BECCSATJ}, id=missing)
    return OrderedDict{Symbol,Any}(
        :id => id,
        :location => missing,
        :can_expand => true,
        :can_retire => true,
        :existing_capacity => 0.0,
        :ethanol_commodity => "LiquidFuels",
        :jetfuel_commodity => "LiquidFuels",
        :co2_sink => missing,
        :jetfuel_production => 0.0,
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

function make(asset_type::Type{BECCSATJ}, data::AbstractDict{Symbol,Any}, system::System)
    id = AssetId(data[:id])

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
    atj_transform = Transformation(
        id = Symbol(id, "_", transform_key),
        timedata = system.time_data[Symbol(transform_data[:timedata])],
        constraints = transform_data[:constraints],
    )

    # Ethanol Edge (Input)
    ethanol_edge_key = :ethanol_edge
    @process_data(
        ethanol_edge_data,
        data[:edges][ethanol_edge_key],
        [
            (data[:edges][ethanol_edge_key], key),
            (data[:edges][ethanol_edge_key], Symbol("ethanol_", key)),
            (data, Symbol("ethanol_", key)),
            (data, key),
        ]
    )
    ethanol_commodity = commodity_types()[Symbol(ethanol_edge_data[:commodity])]
    @start_vertex(
        ethanol_start,
        ethanol_edge_data,
        ethanol_commodity,
        [(ethanol_edge_data, :start_vertex), (data, :location)],
    )
    ethanol_edge = Edge(
        Symbol(id, "_", ethanol_edge_key),
        ethanol_edge_data,
        system.time_data[Symbol(ethanol_edge_data[:commodity])],
        ethanol_commodity,
        ethanol_start,
        atj_transform,
    )

    # Jetfuel Edge (Output)
    jetfuel_edge_key = :jetfuel_edge
    @process_data(
        jetfuel_edge_data,
        data[:edges][jetfuel_edge_key],
        [
            (data[:edges][jetfuel_edge_key], key),
            (data[:edges][jetfuel_edge_key], Symbol("jetfuel_", key)),
            (data, Symbol("jetfuel_", key)),
        ]
    )
    jetfuel_commodity = commodity_types()[Symbol(jetfuel_edge_data[:commodity])]
    @end_vertex(
        jetfuel_end,
        jetfuel_edge_data,
        jetfuel_commodity,
        [(jetfuel_edge_data, :end_vertex), (data, :location)],
    )
    jetfuel_edge = Edge(
        Symbol(id, "_", jetfuel_edge_key),
        jetfuel_edge_data,
        system.time_data[Symbol(jetfuel_edge_data[:commodity])],
        jetfuel_commodity,
        atj_transform,
        jetfuel_end,
    )

    # Electricity Consumption Edge
    elec_edge_key = :elec_consumption_edge
    @process_data(
        elec_edge_data,
        data[:edges][elec_edge_key],
        [
            (data[:edges][elec_edge_key], key),
            (data[:edges][elec_edge_key], Symbol("elec_", key)),
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
        atj_transform,
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
        atj_transform,
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
        atj_transform,
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
        atj_transform,
    )

    # Balance Data
    atj_transform.balance_data = Dict(
        :jetfuel_production => Dict(
            jetfuel_edge.id => 1.0,
            ethanol_edge.id => get(transform_data, :jetfuel_production, 0.0),
        ),
        :elec_consumption => Dict(
            elec_consumption_edge.id => -1.0,
            ethanol_edge.id => get(transform_data, :electricity_consumption, 0.0),
        ),
        :negative_emissions => Dict(
            ethanol_edge.id => get(transform_data, :co2_content, 0.0),
            co2_edge.id => -1.0,
        ),
        :emissions => Dict(
            ethanol_edge.id => get(transform_data, :emission_rate, 1.0),
            co2_emission_edge.id => 1.0,
        ),
        :capture => Dict(
            ethanol_edge.id => get(transform_data, :capture_rate, 1.0),
            co2_captured_edge.id => 1.0,
        )
    )

    return BECCSATJ(
        id,
        atj_transform,
        ethanol_edge,
        jetfuel_edge,
        elec_consumption_edge,
        co2_edge,
        co2_emission_edge,
        co2_captured_edge,
    )
end