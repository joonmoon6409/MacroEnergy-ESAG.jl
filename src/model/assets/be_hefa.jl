struct HEFA <: AbstractAsset
    id::AssetId
    hefa_transform::Transformation
    biomass_edge::Edge{<:Biomass}
    hydrogen_edge::Edge{<:Hydrogen}
    hvo_edge::Edge{<:LiquidFuels}
    saf_edge::Edge{<:LiquidFuels}
    elec_consumption_edge::Edge{<:Electricity}
    co2_edge::Edge{<:CO2}
    co2_emission_edge::Edge{<:CO2}
    co2_captured_edge::Edge{<:CO2Captured}
end

function default_data(t::Type{HEFA}, id=missing, style="full")
    if style == "full"
        return full_default_data(t, id)
    else
        return simple_default_data(t, id)
    end
end

function full_default_data(::Type{HEFA}, id=missing)
    return OrderedDict{Symbol,Any}(
        :id => id,
        :transforms => @transform_data(
            :timedata => "Biomass",
            :constraints => Dict{Symbol,Bool}(
                :BalanceConstraint => true,
            ),
            :hvo_production => 0.0,
            :saf_production => 0.0,
            :hydrogen_consumption => 0.0,
            :electricity_consumption => 0.0,
            :co2_content => 0.0,
            :emission_rate => 0.0,
            :capture_rate => 0.0,
        ),
        :edges => Dict{Symbol,Any}(
            :biomass_edge => @edge_data(
                :commodity => "Biomass",
                :has_capacity => true,
                :can_expand => true,
                :can_retire => true,
                :constraints => Dict{Symbol,Bool}(
                    :CapacityConstraint => true,
                ),
            ),
            :hydrogen_edge => @edge_data(
                :commodity => "Hydrogen",
            ),
            :hvo_edge => @edge_data(
                :commodity => "LiquidFuels",
            ),
            :saf_edge => @edge_data(
                :commodity => "LiquidFuels",
            ),
            :elec_consumption_edge => @edge_data(
                :commodity => "Electricity",
            ),
            :co2_edge => @edge_data(
                :commodity => "CO2",
                :co2_sink => missing,
            ),
            :co2_emission_edge => @edge_data(
                :commodity => "CO2",
                :co2_sink => missing,
            ),
            :co2_captured_edge => @edge_data(
                :commodity => "CO2Captured",
            ),
        ),
    )
end

function simple_default_data(::Type{HEFA}, id=missing)
    return OrderedDict{Symbol,Any}(
        :id => id,
        :location => missing,
        :can_expand => true,
        :can_retire => true,
        :existing_capacity => 0.0,
        :biomass_commodity => "Biomass",
        :hydrogen_commodity => "Hydrogen",
        :hvo_commodity => "LiquidFuels",
        :saf_commodity => "LiquidFuels",
        :co2_sink => missing,
        :hvo_production => 0.0,
        :saf_production => 0.0,
        :hydrogen_consumption => 0.0,
        :electricity_consumption => 0.0,
        :co2_content => 0.0,
        :emission_rate => 0.0,
        :capture_rate => 0.0,
        :investment_cost => 0.0,
        :fixed_om_cost => 0.0,
        :variable_om_cost => 0.0,
    )
end

function make(asset_type::Type{HEFA}, data::AbstractDict{Symbol,Any}, system::System)
    id = AssetId(data[:id])

    @setup_data(asset_type, data, id)

    # --- Transformation ---
    hefa_transform_key = :transforms
    @process_data(
        transform_data,
        data[hefa_transform_key],
        [
            (data[hefa_transform_key], key),
            (data[hefa_transform_key], Symbol("transform_", key)),
            (data, Symbol("transform_", key)),
            (data, key),
        ]
    )
    hefa_transform = Transformation(;
        id = Symbol(id, "_", hefa_transform_key),
        timedata = system.time_data[Symbol(transform_data[:timedata])],
        constraints = transform_data[:constraints],
    )

    # --- biomass_edge (input, capacity-bearing) ---
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
    commodity_symbol = Symbol(biomass_edge_data[:commodity])
    commodity = commodity_types()[commodity_symbol]
    @start_vertex(
        biomass_start_node,
        biomass_edge_data,
        commodity,
        [(biomass_edge_data, :start_vertex), (data, :location)],
    )
    biomass_end_node = hefa_transform
    biomass_edge = Edge(
        Symbol(id, "_", biomass_edge_key),
        biomass_edge_data,
        system.time_data[commodity_symbol],
        commodity,
        biomass_start_node,
        biomass_end_node,
    )

    # --- hydrogen_edge (input) ---
    hydrogen_edge_key = :hydrogen_edge
    @process_data(
        hydrogen_edge_data,
        data[:edges][hydrogen_edge_key],
        [
            (data[:edges][hydrogen_edge_key], key),
            (data[:edges][hydrogen_edge_key], Symbol("hydrogen_", key)),
            (data, Symbol("hydrogen_", key)),
        ]
    )
    commodity_symbol = Symbol(hydrogen_edge_data[:commodity])
    commodity = commodity_types()[commodity_symbol]
    @start_vertex(
        hydrogen_start_node,
        hydrogen_edge_data,
        commodity,
        [(hydrogen_edge_data, :start_vertex), (data, :location)],
    )
    hydrogen_end_node = hefa_transform
    hydrogen_edge = Edge(
        Symbol(id, "_", hydrogen_edge_key),
        hydrogen_edge_data,
        system.time_data[commodity_symbol],
        commodity,
        hydrogen_start_node,
        hydrogen_end_node,
    )

    # --- hvo_edge (output) ---
    hvo_edge_key = :hvo_edge
    @process_data(
        hvo_edge_data,
        data[:edges][hvo_edge_key],
        [
            (data[:edges][hvo_edge_key], key),
            (data[:edges][hvo_edge_key], Symbol("hvo_", key)),
            (data, Symbol("hvo_", key)),
        ]
    )
    commodity_symbol = Symbol(hvo_edge_data[:commodity])
    commodity = commodity_types()[commodity_symbol]
    hvo_start_node = hefa_transform
    @end_vertex(
        hvo_end_node,
        hvo_edge_data,
        commodity,
        [(hvo_edge_data, :end_vertex), (data, :location)],
    )
    hvo_edge = Edge(
        Symbol(id, "_", hvo_edge_key),
        hvo_edge_data,
        system.time_data[commodity_symbol],
        commodity,
        hvo_start_node,
        hvo_end_node,
    )

    # --- saf_edge (output) ---
    saf_edge_key = :saf_edge
    @process_data(
        saf_edge_data,
        data[:edges][saf_edge_key],
        [
            (data[:edges][saf_edge_key], key),
            (data[:edges][saf_edge_key], Symbol("saf_", key)),
            (data, Symbol("saf_", key)),
        ]
    )
    commodity_symbol = Symbol(saf_edge_data[:commodity])
    commodity = commodity_types()[commodity_symbol]
    saf_start_node = hefa_transform
    @end_vertex(
        saf_end_node,
        saf_edge_data,
        commodity,
        [(saf_edge_data, :end_vertex), (data, :location)],
    )
    saf_edge = Edge(
        Symbol(id, "_", saf_edge_key),
        saf_edge_data,
        system.time_data[commodity_symbol],
        commodity,
        saf_start_node,
        saf_end_node,
    )

    # --- elec_consumption_edge (input) ---
    elec_consumption_edge_key = :elec_consumption_edge
    @process_data(
        elec_consumption_edge_data,
        data[:edges][elec_consumption_edge_key],
        [
            (data[:edges][elec_consumption_edge_key], key),
            (data[:edges][elec_consumption_edge_key], Symbol("elec_consumption_", key)),
            (data, Symbol("elec_consumption_", key)),
        ]
    )
    @start_vertex(
        elec_start_node,
        elec_consumption_edge_data,
        Electricity,
        [(elec_consumption_edge_data, :start_vertex), (data, :location)],
    )
    elec_end_node = hefa_transform
    elec_consumption_edge = Edge(
        Symbol(id, "_", elec_consumption_edge_key),
        elec_consumption_edge_data,
        system.time_data[:Electricity],
        Electricity,
        elec_start_node,
        elec_end_node,
    )

    # --- co2_edge (input, negative emissions) ---
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
        co2_start_node,
        co2_edge_data,
        CO2,
        [(co2_edge_data, :start_vertex), (data, :co2_sink), (data, :location)],
    )
    co2_end_node = hefa_transform
    co2_edge = Edge(
        Symbol(id, "_", co2_edge_key),
        co2_edge_data,
        system.time_data[:CO2],
        CO2,
        co2_start_node,
        co2_end_node,
    )

    # --- co2_emission_edge (output) ---
    co2_emission_edge_key = :co2_emission_edge
    @process_data(
        co2_emission_edge_data,
        data[:edges][co2_emission_edge_key],
        [
            (data[:edges][co2_emission_edge_key], key),
            (data[:edges][co2_emission_edge_key], Symbol("co2_emission_", key)),
            (data, Symbol("co2_emission_", key)),
        ]
    )
    co2_emission_start_node = hefa_transform
    @end_vertex(
        co2_emission_end_node,
        co2_emission_edge_data,
        CO2,
        [(co2_emission_edge_data, :end_vertex), (data, :co2_sink), (data, :location)],
    )
    co2_emission_edge = Edge(
        Symbol(id, "_", co2_emission_edge_key),
        co2_emission_edge_data,
        system.time_data[:CO2],
        CO2,
        co2_emission_start_node,
        co2_emission_end_node,
    )

    # --- co2_captured_edge (output) ---
    co2_captured_edge_key = :co2_captured_edge
    @process_data(
        co2_captured_edge_data,
        data[:edges][co2_captured_edge_key],
        [
            (data[:edges][co2_captured_edge_key], key),
            (data[:edges][co2_captured_edge_key], Symbol("co2_captured_", key)),
            (data, Symbol("co2_captured_", key)),
        ]
    )
    co2_captured_start_node = hefa_transform
    @end_vertex(
        co2_captured_end_node,
        co2_captured_edge_data,
        CO2Captured,
        [(co2_captured_edge_data, :end_vertex), (data, :location)],
    )
    co2_captured_edge = Edge(
        Symbol(id, "_", co2_captured_edge_key),
        co2_captured_edge_data,
        system.time_data[:CO2Captured],
        CO2Captured,
        co2_captured_start_node,
        co2_captured_end_node,
    )

    # --- balance_data ---
    # biomass_edge를 기준(capacity-bearing)으로 모든 비율 표현
    #
    # :hvo_production      : biomass * hvo_production      == hvo_edge
    # :saf_production      : biomass * saf_production      == saf_edge
    # :hydrogen_consumption: biomass * hydrogen_consumption == hydrogen_edge (소비이므로 -1)
    # :elec_consumption    : biomass * electricity_consumption == elec_edge (소비이므로 -1)
    # :negative_emissions  : biomass * co2_content          == co2_edge (흡수이므로 -1)
    # :emissions           : biomass * emission_rate        == co2_emission_edge
    # :capture             : biomass * capture_rate         == co2_captured_edge
    hefa_transform.balance_data = Dict(
        :hvo_production => Dict(
            hvo_edge.id     => 1.0,
            biomass_edge.id => get(transform_data, :hvo_production, 0.0),
        ),
        :saf_production => Dict(
            saf_edge.id     => 1.0,
            biomass_edge.id => get(transform_data, :saf_production, 0.0),
        ),
        :hydrogen_consumption => Dict(
            hydrogen_edge.id => -1.0,
            biomass_edge.id  => get(transform_data, :hydrogen_consumption, 0.0),
        ),
        :elec_consumption => Dict(
            elec_consumption_edge.id => -1.0,
            biomass_edge.id          => get(transform_data, :electricity_consumption, 0.0),
        ),
        :negative_emissions => Dict(
            biomass_edge.id => get(transform_data, :co2_content, 0.0),
            co2_edge.id     => -1.0,
        ),
        :emissions => Dict(
            biomass_edge.id      => get(transform_data, :emission_rate, 0.0),
            co2_emission_edge.id => 1.0,
        ),
        :capture => Dict(
            biomass_edge.id      => get(transform_data, :capture_rate, 0.0),
            co2_captured_edge.id => 1.0,
        ),
    )

    return HEFA(
        id,
        hefa_transform,
        biomass_edge,
        hydrogen_edge,
        hvo_edge,
        saf_edge,
        elec_consumption_edge,
        co2_edge,
        co2_emission_edge,
        co2_captured_edge,
    )
end