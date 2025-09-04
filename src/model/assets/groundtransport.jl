struct GroundTransport{T} <: AbstractAsset
    id::AssetId
    groundtransport_transform::Transformation
    biomass_edge::Edge{T}
    co2_edge::Edge{<:CO2}
    co2_emission_edge::Edge{<:CO2}
end

GroundTransport(id::AssetId, groundtransport_transform::Transformation, biomass_edge::Edge{T}, co2_edge::Edge{<:CO2}, co2_emission_edge::Edge{<:CO2}) where T<:Commodity = GroundTransport{T}(id, groundtransport_transform, biomass_edge, co2_edge, co2_emission_edge)

function default_data(t::Type{GroundTransport}, id=missing, style="full")
    if style == "full"
        return full_default_data(t, id)
    else
        return simple_default_data(t, id)
    end
end

function full_default_data(::Type{GroundTransport}, id=missing)
    return OrderedDict{Symbol,Any}(
        :id => id,
        :transforms => @transform_data(
            :timedata => "Biomass",
            :constraints => Dict{Symbol,Bool}(
                :BalanceConstraint => true
            ),
            :co2_content => 0.0,
            :emission_rate => 1.0,
        ),
        :edges => Dict{Symbol,Any}(
            :biomass_edge => @edge_data(
                :commodity => missing,
                :unidirectional => true,
                :has_capacity => true,
                :can_expand => true,
                :can_retire => false,
                :loss_fraction => 0.0,
                :constraints => Dict(:CapacityConstraint => true),
            ),
            :co2_edge => @edge_data(
                :commodity => "CO2",
                :unidirectional => true,
                :has_capacity => false,
                :co2_sink => missing,
            ),
            :co2_emission_edge => @edge_data(
                :commodity => "CO2",
                :unidirectional => true,
                :has_capacity => false,
                :co2_sink => missing,
            ),
        ),
    )
end

function simple_default_data(::Type{GroundTransport}, id=missing)
    return OrderedDict{Symbol,Any}(
        :id => id,
        :location => missing,
        :commodity => missing,
        :can_expand => true,
        :can_retire => false,
        :existing_capacity => 0.0,
        :investment_cost => 0.0,
        :fixed_om_cost => 0.0,
        :variable_om_cost => 0.0,
        :co2_content => 0.0,
        :emission_rate => 1.0,
        :distance => 0.0,
        :unidirectional => true,
        :loss_fraction => 0.0,
        :co2_sink => missing,
    )
end

function set_commodity!(::Type{GroundTransport}, commodity::Type{<:Commodity}, data::AbstractDict{Symbol,Any})
    if haskey(data, :commodity)
        data[:commodity] = string(commodity)
    end
    if haskey(data, :edges) && haskey(data[:edges], :biomass_edge)
        edge = data[:edges][:biomass_edge]
        if haskey(edge, :commodity)
            edge[:commodity] = string(commodity)
        end
    end
end

function make(::Type{GroundTransport}, data::AbstractDict{Symbol,Any}, system::System)
    id = AssetId(data[:id])
    @setup_data(GroundTransport, data, id)

    groundtransport_transform_key = :transforms
    @process_data(
        transform_data,
        data[groundtransport_transform_key],
        [
            (data[groundtransport_transform_key], key),
            (data[groundtransport_transform_key], Symbol("transform_", key)),
            (data, Symbol("transform_", key)),
            (data, key),
        ]
    )
    groundtransport_transform = Transformation(;
        id=Symbol(id, "_", groundtransport_transform_key),
        timedata=system.time_data[Symbol(transform_data[:timedata])],
        constraints=transform_data[:constraints],
    )

    # Biomass edge setup
    bio_edge_key = :biomass_edge
    @process_data(
        bio_edge_data,
        data[:edges][bio_edge_key],
        [
            (data[:edges][bio_edge_key], key),
            (data[:edges][bio_edge_key], Symbol("transport_", key)),
            (data, Symbol("transport_", key)),
            (data, key), 
        ]
    )

    commodity_symbol = Symbol(bio_edge_data[:commodity])
    transport_commodity = commodity_types()[commodity_symbol]

    @start_vertex(
        bio_start_node,
        bio_edge_data,
        transport_commodity,
        [(bio_edge_data, :start_vertex), (data, :line_origin), (data, :location)],
    )
    @end_vertex(
        bio_end_node,
        bio_edge_data,
        transport_commodity,
        [(bio_edge_data, :end_vertex), (data, :line_dest), (data, :location)],
    )

    biomass_edge = Edge(
        Symbol(id, "_", bio_edge_key),
        bio_edge_data,
        system.time_data[commodity_symbol],
        transport_commodity,
        bio_start_node,
        bio_end_node,
    )

    # CO2 edge setup (negative emissions - from CO2 sink to transform)
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
    co2_end_node = groundtransport_transform
    co2_edge = Edge(
        Symbol(id, "_", co2_edge_key),
        co2_edge_data,
        system.time_data[:CO2],
        CO2,
        co2_start_node,
        co2_end_node,
    )

    # CO2 emission edge setup (emissions - from transform to CO2 sink)
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
    co2_emission_start_node = groundtransport_transform
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

    # Balance data setup 
    groundtransport_transform.balance_data = Dict(
        :negative_emissions => Dict(
            biomass_edge.id => get(transform_data, :co2_content, 0.0),
            co2_edge.id => -1.0
        ),
        :emissions => Dict(
            biomass_edge.id => get(transform_data, :emission_rate, 1.0),
            co2_emission_edge.id => 1.0
        )
    )

    return GroundTransport(id, groundtransport_transform, biomass_edge, co2_edge, co2_emission_edge)
end