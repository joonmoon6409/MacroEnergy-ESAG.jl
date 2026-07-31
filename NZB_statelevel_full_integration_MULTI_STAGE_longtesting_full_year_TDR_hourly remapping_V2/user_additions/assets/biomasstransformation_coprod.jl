struct BiomassTransformation_coprod <: AbstractAsset
    id::AssetId
    beccs_transform::Transformation 
    origin_edge::Edge{<:Biomass}
    general_edge::Edge{<:Biomass}
    coproduct_edge::Edge{<:Biomass}
    elec_production_edge::Edge{<:Electricity}
    elec_consumption_edge::Edge{<:Electricity}
    co2_edge::Edge{<:CO2}
    co2_emission_edge::Edge{<:CO2}
    co2_captured_edge::Edge{<:CO2Captured}
end

function default_data(t::Type{BiomassTransformation_coprod}, id=missing, style="full")
    if style == "full"
        return full_default_data(t, id)
    else
        return simple_default_data(t, id)
    end
end

function full_default_data(::Type{BiomassTransformation_coprod}, id=missing)
    return OrderedDict{Symbol,Any}(
        :id => id,
        :transforms => @transform_data(
            :timedata => "Biomass", #should this be :timedata => "origin"
            :constraints => Dict{Symbol,Bool}(
                :BalanceConstraint => true
            ),
            :transformation_rate => 0.0,
            # Secondary biomass output per unit of origin_edge input
            # (e.g. sugarcane -> sugarcane + sugarcane straw).
            # 0.0 => co-product flow is forced to zero by the balance.
            # NOTE: transformation_rate + coproduct_rate <= 1.0 is NOT enforced.
            :coproduct_rate => 0.0,
            :electricity_consumption => 0.0,
            :electricity_production => 0.0,
            :co2_content => 0.0,
            :emission_rate => 1.0,
            :capture_rate => 1.0
        ),
        :edges => Dict{Symbol,Any}(
            :origin_edge => @edge_data(
                :commodity => "Biomass",
                :has_capacity => true,
                :can_expand => true,
                :can_retire => true,
                :constraints => Dict{Symbol,Bool}(
                    :CapacityConstraint => true,
                )
            ),

            :general_edge => @edge_data(
                :commodity => "Biomass",
            ),

            :coproduct_edge => @edge_data(
                :commodity => "Biomass",
                :variable_om_cost => 0.0,
            ),
            
            :co2_edge => @edge_data(
                :commodity => "CO2",
                :co2_sink => missing,
            ),
            :co2_emission_edge => @edge_data(
                :commodity => "CO2",
                :co2_sink => missing,
            ),
            :elec_consumption_edge => @edge_data(
                :commodity => "Electricity",
            ),
            :elec_production_edge => @edge_data(
                :commodity => "Electricity",
            ),
            :co2_captured_edge => @edge_data(
                :commodity => "CO2Captured",
            )
        )
    )
end

function simple_default_data(::Type{BiomassTransformation_coprod}, id=missing)
    return OrderedDict{Symbol,Any}(
        :id => id,
        :location => missing,
        :can_expand => true,
        :can_retire => true,
        :existing_capacity => 0.0,
        :general_commodity => "Biomass",
        :coproduct_commodity => "Biomass",
        :co2_sink => missing,
        :transformation_rate => 0.0,
        :coproduct_rate => 0.0,
        :electricity_consumption => 0.0,
        :electricity_production => 0.0,
        :co2_content => 0.0,
        :emission_rate => 1.0,
        :capture_rate => 1.0,
        :investment_cost => 0.0,
        :fixed_om_cost => 0.0,
        :variable_om_cost => 0.0,
    )
end

function make(asset_type::Type{BiomassTransformation_coprod}, data::AbstractDict{Symbol,Any}, system::System)
    id = AssetId(data[:id])
    location = as_symbol_or_missing(get(data, :location, missing))
    
    @setup_data(asset_type, data, id)

    beccs_transform_key = :transforms
    @process_data(
        transform_data,
        data[beccs_transform_key],
        [
            (data[beccs_transform_key], key),
            (data[beccs_transform_key], Symbol("transform_", key)),
            (data, Symbol("transform_", key)),
            (data, key),
        ]
    )
    beccs_transform = Transformation(;
        id = Symbol(id, "_", beccs_transform_key),
        timedata = system.time_data[Symbol(transform_data[:timedata])],
        location = location,
        constraints = transform_data[:constraints],
    )

    origin_edge_key = :origin_edge
    @process_data(
        origin_edge_data,
        data[:edges][origin_edge_key],
        [
            (data[:edges][origin_edge_key], key),
            (data[:edges][origin_edge_key], Symbol("origin_", key)),
            (data, Symbol("origin_", key)),
            (data, key),
        ]
    )
    commodity_symbol = Symbol(origin_edge_data[:commodity])
    commodity = commodity_types()[commodity_symbol]
    @start_vertex(
        origin_start_node,
        origin_edge_data,
        commodity,
        [(origin_edge_data, :start_vertex), (data, :location)],
    )
    origin_end_node = beccs_transform
    origin_edge = Edge(
        Symbol(id, "_", origin_edge_key),
        origin_edge_data,
        system.time_data[commodity_symbol],
        commodity,
        origin_start_node,
        origin_end_node,
    )

    general_edge_key = :general_edge
    @process_data(
        general_edge_data, 
        data[:edges][general_edge_key], 
        [
            (data[:edges][general_edge_key], key),
            (data[:edges][general_edge_key], Symbol("general_", key)),
            (data, Symbol("general_", key)),
        ]
    )
    commodity_symbol = Symbol(general_edge_data[:commodity])
    commodity = commodity_types()[commodity_symbol]
    general_start_node = beccs_transform
    @end_vertex(
        general_end_node,
        general_edge_data,
        commodity,
        [(general_edge_data, :end_vertex), (data, :location)],
    )
    general_edge = Edge(
        Symbol(id, "_", general_edge_key),
        general_edge_data,
        system.time_data[commodity_symbol],
        commodity,
        general_start_node,
        general_end_node,
    )

    # Co-Product Edge (second biomass output, e.g. sugarcane straw)
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
    coproduct_commodity_symbol = Symbol(coproduct_edge_data[:commodity])
    coproduct_commodity = commodity_types()[coproduct_commodity_symbol]
    coproduct_start_node = beccs_transform
    @end_vertex(
        coproduct_end_node,
        coproduct_edge_data,
        coproduct_commodity,
        [(coproduct_edge_data, :end_vertex), (data, :location)],
    )
    coproduct_edge = Edge(
        Symbol(id, "_", coproduct_edge_key),
        coproduct_edge_data,
        system.time_data[coproduct_commodity_symbol],
        coproduct_commodity,
        coproduct_start_node,
        coproduct_end_node,
    )

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
    elec_end_node = beccs_transform
    elec_consumption_edge = Edge(
        Symbol(id, "_", elec_consumption_edge_key),
        elec_consumption_edge_data,
        system.time_data[:Electricity],
        Electricity,
        elec_start_node,
        elec_end_node,
    )

    elec_production_edge_key = :elec_production_edge
    @process_data(
        elec_production_edge_data, 
        data[:edges][elec_production_edge_key],
        [
            (data[:edges][elec_production_edge_key], key),
            (data[:edges][elec_production_edge_key], Symbol("elec_production_", key)),
            (data, Symbol("elec_production_", key)),
        ]
    )
    elec_start_node = beccs_transform
    @end_vertex(
        elec_end_node,
        elec_production_edge_data,
        Electricity,
        [(elec_production_edge_data, :end_vertex), (data, :location)],
    )
    elec_production_edge = Edge(
        Symbol(id, "_", elec_production_edge_key),
        elec_production_edge_data,
        system.time_data[:Electricity],
        Electricity,
        elec_start_node,
        elec_end_node,
    )

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
    co2_end_node = beccs_transform
    co2_edge = Edge(
        Symbol(id, "_", co2_edge_key),
        co2_edge_data,
        system.time_data[:CO2],
        CO2,
        co2_start_node,
        co2_end_node,
    )

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
    co2_emission_start_node = beccs_transform
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
    co2_captured_start_node = beccs_transform
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

    beccs_transform.balance_data = Dict(
        :transformation_rate => Dict(
            general_edge.id => 1.0,
            origin_edge.id => get(transform_data, :transformation_rate, 0.0)
        ),
        :coproduct_rate => Dict(
            coproduct_edge.id => 1.0,
            origin_edge.id => get(transform_data, :coproduct_rate, 0.0)
        ),
        :elec_production => Dict(
            elec_production_edge.id => 1.0,
            origin_edge.id => get(transform_data, :electricity_production, 0.0)
        ),
        :elec_consumption => Dict(
            elec_consumption_edge.id => -1.0,
            origin_edge.id => get(transform_data, :electricity_consumption, 0.0)
        ),
        :negative_emissions => Dict(
            origin_edge.id => get(transform_data, :co2_content, 0.0),
            co2_edge.id => -1.0
        ),
        :emissions => Dict(
            origin_edge.id => get(transform_data, :emission_rate, 1.0),
            co2_emission_edge.id => 1.0
        ),
        :capture =>Dict(
            origin_edge.id => get(transform_data, :capture_rate, 1.0),
            co2_captured_edge.id => 1.0
        )
    )

    return BiomassTransformation_coprod(id, beccs_transform, origin_edge,  general_edge, coproduct_edge, elec_production_edge, elec_consumption_edge, co2_edge, co2_emission_edge, co2_captured_edge) 
end