struct AluminumSmelting <: AbstractAsset
    id::AssetId
    aluminumsmelting_transform::Transformation
    elec_edge::Edge{<:Electricity}
    alumina_edge::Edge{<:Alumina} # alumina input
    graphite_edge::Edge{<:Graphite} # graphite input
    aluminum_edge::Union{Edge{<:Aluminum},EdgeWithUC{<:Aluminum}} # aluminum output
    co2_edge::Edge{<:CO2} # co2 output
    sox_edge::Edge{<:Pollution} # SOx emissions
    nox_edge::Edge{<:Pollution} # NOx emissions
    pm_edge::Edge{<:Pollution} # PM emissions
end

function default_data(t::Type{AluminumSmelting}, id=missing, style="full")
    if style == "full"
        return full_default_data(t, id)
    else
        return simple_default_data(t, id)
    end
end

function full_default_data(::Type{AluminumSmelting}, id=missing)
    return Dict{Symbol,Any}(
        :id => id,
        :transforms => @transform_data(
            :timedata => "Aluminum",
            :elec_aluminum_rate => 1.0,
            :alumina_aluminum_rate => 1.0,
            :graphite_aluminum_rate => 1.0,
            :graphite_emissions_rate => 1.0,
            :sox_rate => 0.0,
            :nox_rate => 0.0,
            :pm_rate => 0.0,
            :constraints => Dict{Symbol, Bool}(
                :BalanceConstraint => true,
            ),
        ),
        :edges => Dict{Symbol,Any}(
            :elec_edge => @edge_data(
                :commodity => "Electricity"
            ),
            :aluminum_edge => @edge_data(
                :commodity=>"Aluminum",
                :has_capacity => true,
                :can_retire => true,
                :can_expand => true,
                :can_retire => true,
                :constraints => Dict{Symbol, Bool}(
                    :CapacityConstraint => true,
                )
            ),
            :alumina_edge => @edge_data(
                :commodity => "Alumina"
            ),
            :graphite_edge => @edge_data(
                :commodity => "Graphite"
            ),
            :co2_edge => @edge_data(
                :commodity => "CO2",
                :co2_sink => missing,
            ),
            :sox_edge => @edge_data(
                :commodity=>"Pollution"
            ),
            :nox_edge => @edge_data(
                :commodity=>"Pollution"
            ),
            :pm_edge => @edge_data(
                :commodity=>"Pollution"
            ),
        ),
    )
end

function simple_default_data(::Type{AluminumSmelting}, id=missing)
    return Dict{Symbol, Any}(
        :id => id,
        :location => missing,
        :can_expand => true,
        :can_retire => true,
        :existing_capacity => 0.0,
        :capacity_size => 1.0,
        :timedata => "Aluminum",
        :elec_aluminum_rate => 1.0,
        :alumina_aluminum_rate => 1.0,
        :graphite_aluminum_rate => 1.0,
        :graphite_emissions_rate => 1.0,
        :co2_sink => missing,
        :uc => false,
        :investment_cost => 0.0,
        :fixed_om_cost => 0.0,
        :variable_om_cost => 0.0,
        :startup_cost => 0.0,
        :min_up_time => 0,
        :min_down_time => 0,
        :ramp_up_fraction => 0.0,
        :ramp_down_fraction => 0.0,
        :sox_rate => 0.0,
        :nox_rate => 0.0,
        :pm_rate => 0.0,
    )
end

function make(asset_type::Type{AluminumSmelting}, data::AbstractDict{Symbol,Any}, system::System)
    id = AssetId(data[:id])

    @setup_data(asset_type, data, id)

    # AluminumSmelting Transformation
    aluminumsmelting_key = :transforms
    @process_data(
        transform_data,
        data[aluminumsmelting_key],
        [
            (data[aluminumsmelting_key], key),
            (data[aluminumsmelting_key], Symbol("transform_", key)),
            (data, Symbol("transform_", key)),
            (data, key),
        ]
    )
    aluminumsmelting_transform = Transformation(;
        id = Symbol(id, "_", aluminumsmelting_key),
        timedata = system.time_data[Symbol(transform_data[:timedata])],
        constraints = get(transform_data, :constraints, [BalanceConstraint()]),
    )

    # Electricity Edge
    elec_edge_key = :elec_edge
    @process_data(
        elec_edge_data, 
        data[:edges][elec_edge_key], 
        [
            (data[:edges][elec_edge_key], key),
            (data[:edges][elec_edge_key], Symbol("elec_", key)),
            (data, Symbol("elec_", key))
        ]
    )

    @start_vertex(
        elec_start_node,
        elec_edge_data,
        Electricity,
        [(elec_edge_data, :start_vertex), (data, :location)],
    )
    elec_end_node = aluminumsmelting_transform

    elec_edge = Edge(
        Symbol(id, "_", elec_edge_key),
        elec_edge_data,
        system.time_data[:Electricity],
        Electricity,
        elec_start_node,
        elec_end_node,
    )

    #Alumina Edge
    alumina_edge_key = :alumina_edge
    @process_data(
        alumina_edge_data, 
        data[:edges][alumina_edge_key], 
        [
            (data[:edges][alumina_edge_key], key),
            (data[:edges][alumina_edge_key], Symbol("alumina_", key)),
            (data, Symbol("alumina_", key))
        ]
    )

    @start_vertex(
        alumina_start_node,
        alumina_edge_data,
        Alumina,
        [(alumina_edge_data, :start_vertex), (data, :location)],
    )
    alumina_end_node = aluminumsmelting_transform

    alumina_edge = Edge(
        Symbol(id, "_", alumina_edge_key),
        alumina_edge_data,
        system.time_data[:Alumina],
        Alumina,
        alumina_start_node,
        alumina_end_node,
    )

    #Graphite Edge
    graphite_edge_key = :graphite_edge
    @process_data(
        graphite_edge_data, 
        data[:edges][graphite_edge_key],
        [
            (data[:edges][graphite_edge_key], key),
            (data[:edges][graphite_edge_key], Symbol("graphite_", key)),
            (data, Symbol("graphite_", key))
        ]
    )

    @start_vertex(
        graphite_start_node,
        graphite_edge_data,
        Graphite,
        [(graphite_edge_data, :start_vertex), (data, :location)],
    )
    graphite_end_node = aluminumsmelting_transform

    graphite_edge = Edge(
        Symbol(id, "_", graphite_edge_key),
        graphite_edge_data,
        system.time_data[:Graphite],
        Graphite,
        graphite_start_node,
        graphite_end_node,
    )

    # Aluminum Edge
    aluminum_edge_key = :aluminum_edge
    @process_data(
        aluminum_edge_data, 
        data[:edges][aluminum_edge_key], 
        [
            (data[:edges][aluminum_edge_key], key),
            (data[:edges][aluminum_edge_key], Symbol("aluminum_", key)),
            (data, Symbol("aluminum_", key)),
            (data, key),
        ]
    )
    aluminum_start_node = aluminumsmelting_transform
    @end_vertex(
        aluminum_end_node,
        aluminum_edge_data,
        Aluminum,
        [(aluminum_edge_data, :end_vertex), (data, :location)],
    )
    aluminum_edge = Edge(
        Symbol(id, "_", aluminum_edge_key),
        aluminum_edge_data,
        system.time_data[:Aluminum],
        Aluminum,
        aluminum_start_node,
        aluminum_end_node,
    )

    # Check if the edge has unit commitment constraints
    has_uc = get(aluminum_edge_data, :uc, false)
    EdgeType = has_uc ? EdgeWithUC : Edge
    # Create the aluminum edge with the appropriate type
    aluminum_edge = EdgeType(
        Symbol(id, "_", aluminum_edge_key),
        aluminum_edge_data,
        system.time_data[:Aluminum],
        Aluminum,
        aluminum_start_node,
        aluminum_end_node,
    )
    if has_uc
        uc_constraints = [MinUpTimeConstraint(), MinDownTimeConstraint()]
        for c in uc_constraints
            if !(c in aluminum_edge.constraints)
                push!(aluminum_edge.constraints, c)
            end
        end
        aluminum_edge.startup_fuel_balance_id = :energy
    end
    

    #CO2 Edge
    co2_edge_key = :co2_edge
    @process_data(
        co2_edge_data, 
        data[:edges][co2_edge_key],
        [
            (data[:edges][co2_edge_key], key),
            (data[:edges][co2_edge_key], Symbol("co2_", key)),
            (data, Symbol("co2_", key))
        ]
    )
    co2_start_node = aluminumsmelting_transform
    @end_vertex(
        co2_end_node,
        co2_edge_data,
        CO2,
        [(co2_edge_data, :end_vertex), (data, :co2_sink), (data, :location)],
    )
    co2_edge = Edge(
        Symbol(id, "_", co2_edge_key),
        co2_edge_data,
        system.time_data[:CO2],
        CO2,
        co2_start_node,
        co2_end_node,
    )

    # SOx emissions edge
    sox_edge_key = :sox_edge
    @process_data(
        sox_edge_data, 
        data[:edges][sox_edge_key], 
        [
            (data[:edges][sox_edge_key], key),
            (data[:edges][sox_edge_key], Symbol("sox_", key)),
            (data, Symbol("sox_", key)),
        ]
    )
    sox_start_node = aluminumsmelting_transform
    @end_vertex(
        sox_end_node,
        sox_edge_data,
        Pollution,
        [(sox_edge_data, :end_vertex), (data, :sox_sink), (data, :location)],
    )
    sox_edge = Edge(
        Symbol(id, "_", sox_edge_key),
        sox_edge_data,
        system.time_data[:Pollution],
        Pollution,
        sox_start_node,
        sox_end_node,
    )

    # NOx emissions edge
    nox_edge_key = :nox_edge
    @process_data(
        nox_edge_data, 
        data[:edges][nox_edge_key], 
        [
            (data[:edges][nox_edge_key], key),
            (data[:edges][nox_edge_key], Symbol("nox_", key)),
            (data, Symbol("nox_", key)),
        ]
    )
    nox_start_node = aluminumsmelting_transform
    @end_vertex(
        nox_end_node,
        nox_edge_data,
        Pollution,
        [(nox_edge_data, :end_vertex), (data, :nox_sink), (data, :location)],
    )
    nox_edge = Edge(
        Symbol(id, "_", nox_edge_key),
        nox_edge_data,
        system.time_data[:Pollution],
        Pollution,
        nox_start_node,
        nox_end_node,
    )

    # PM emissions edge
    pm_edge_key = :pm_edge
    @process_data(
        pm_edge_data, 
        data[:edges][pm_edge_key], 
        [
            (data[:edges][pm_edge_key], key),
            (data[:edges][pm_edge_key], Symbol("pm_", key)),
            (data, Symbol("pm_", key)),
        ]
    )
    pm_start_node = aluminumsmelting_transform
    @end_vertex(
        pm_end_node,
        pm_edge_data,
        Pollution,
        [(pm_edge_data, :end_vertex), (data, :pm_sink), (data, :location)],
    )
    pm_edge = Edge(
        Symbol(id, "_", pm_edge_key),
        pm_edge_data,
        system.time_data[:Pollution],
        Pollution,
        pm_start_node,
        pm_end_node,
    )

    # Balance Constraint Values
    aluminumsmelting_transform.balance_data = Dict(
        :elec_to_aluminum => Dict(
            elec_edge.id => 1.0,
            alumina_edge.id => 0.0,
            graphite_edge.id => 0.0,
            aluminum_edge.id => get(transform_data, :elec_aluminum_rate, 1.0)
        ),
        :alumina_to_aluminum => Dict(
            elec_edge.id => 0.0,
            alumina_edge.id => 1.0,
            graphite_edge.id => 0.0,
            aluminum_edge.id => get(transform_data, :alumina_aluminum_rate, 1.0)
        ),
        :graphite_to_aluminum => Dict(
            elec_edge.id => 0.0,
            alumina_edge.id => 0.0,
            graphite_edge.id => 1.0,
            aluminum_edge.id => get(transform_data, :graphite_aluminum_rate, 1.0)
        ),
        :emissions => Dict(
            graphite_edge.id => get(transform_data, :graphite_emissions_rate, 1.0),
            co2_edge.id => 1.0
        ),
        :sox_rate => Dict(
            sox_edge.id => -1.0,
            aluminum_edge.id => get(transform_data, :sox_rate, 1.0),
        ),
        :nox_rate => Dict(
            nox_edge.id => -1.0,
            aluminum_edge.id => get(transform_data, :nox_rate, 1.0),
        ),
        :pm_rate => Dict(
            pm_edge.id => -1.0,
            aluminum_edge.id => get(transform_data, :pm_rate, 1.0),
        )
    )

    return AluminumSmelting(id, aluminumsmelting_transform, elec_edge, alumina_edge, graphite_edge, aluminum_edge, co2_edge, sox_edge, nox_edge, pm_edge)
end