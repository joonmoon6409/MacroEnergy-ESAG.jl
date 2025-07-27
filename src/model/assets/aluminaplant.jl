struct AluminaPlant{T} <: AbstractAsset
    id::AssetId
    aluminaplant_transform::Transformation
    elec_edge::Union{Edge{<:Electricity},EdgeWithUC{<:Electricity}}
    alumina_edge::Edge{<:Alumina} # alumina input
    bauxite_edge::Edge{<:Bauxite} # bauxite input
    fuel_edge::Edge{T}
    co2_edge::Edge{<:CO2} # co2 output
    sox_edge::Edge{<:Pollution} # SOx emissions
    nox_edge::Edge{<:Pollution} # NOx emissions
    pm_edge::Edge{<:Pollution} # PM emissions     
end

AluminaPlant(id::AssetId, aluminaplant_transform::Transformation, elec_edge::Union{Edge{<:Electricity},EdgeWithUC{<:Electricity}}, alumina_edge::Edge{<:Alumina}, bauxite_edge::Edge{<:Bauxite}, fuel_edge::Edge{T}, co2_edge::Edge{<:CO2}, sox_edge::Edge{<:Pollution}, nox_edge::Edge{<:Pollution}, pm_edge::Edge{<:Pollution}) where T<:Commodity =
    AluminaPlant{T}(id, aluminaplant_transform, elec_edge, alumina_edge, bauxite_edge, fuel_edge, co2_edge, sox_edge, nox_edge, pm_edge)

function default_data(t::Type{AluminaPlant}, id=missing, style="full")
    if style == "full"
        return full_default_data(t, id)
    else
        return simple_default_data(t, id)
    end
end

function full_default_data(::Type{AluminaPlant}, id=missing)
    return Dict{Symbol,Any}(
        :id => id,
        :transforms => @transform_data(
            :timedata => "Alumina",
            :elec_alumina_rate => 1.0,
            :bauxite_alumina_rate => 1.0,
            :fuel_alumina_rate => 1.0,
            :fuel_emissions_rate => 1.0,
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
            :alumina_edge => @edge_data(
                :commodity=>"Alumina",
                :has_capacity => true,
                :can_retire => true,
                :can_expand => true,
                :can_retire => true,
                :constraints => Dict{Symbol, Bool}(
                    :CapacityConstraint => true,
                )
            ),
            :bauxite_edge => @edge_data(
                :commodity => "Bauxite"
            ),
            :fuel_edge => @edge_data(
                :commodity => "NaturalGas"
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

function simple_default_data(::Type{AluminaPlant}, id=missing)
    return Dict{Symbol, Any}(
        :id => id,
        :location => missing,
        :can_expand => true,
        :can_retire => true,
        :existing_capacity => 0.0,
        :capacity_size => 1.0,
        :timedata => "Alumina",
        :elec_alumina_rate => 1.0,
        :bauxite_alumina_rate => 1.0,
        :fuel_alumina_rate => 1.0,
        :fuel_emissions_rate => 1.0,
        :co2_sink => missing,
        :uc => false,
        :investment_cost => 0.0,
        :fixed_om_cost => 0.0,
        :variable_om_cost => 0.0,
        :sox_rate => 0.0,
        :nox_rate => 0.0,
        :pm_rate => 0.0,
    )
end

function make(asset_type::Type{AluminaPlant}, data::AbstractDict{Symbol,Any}, system::System)
    id = AssetId(data[:id])

    @setup_data(asset_type, data, id)

    # AluminaPlant Transformation
    aluminaplant_key = :transforms
    @process_data(
        transform_data,
        data[aluminaplant_key],
        [
            (data[aluminaplant_key], key),
            (data[aluminaplant_key], Symbol("transform_", key)),
            (data, Symbol("transform_", key)),
            (data, key),
        ]
    )
    aluminaplant_transform = Transformation(;
        id = Symbol(id, "_", aluminaplant_key),
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
    elec_end_node = aluminaplant_transform

    elec_edge = Edge(
        Symbol(id, "_", elec_edge_key),
        elec_edge_data,
        system.time_data[:Electricity],
        Electricity,
        elec_start_node,
        elec_end_node,
    )

    #Bauxite Edge
    bauxite_edge_key = :bauxite_edge
    @process_data(
        bauxite_edge_data, 
        data[:edges][bauxite_edge_key],
        [
            (data[:edges][bauxite_edge_key], key),
            (data[:edges][bauxite_edge_key], Symbol("bauxite_", key)),
            (data, Symbol("bauxite_", key))
        ]
    )

    @start_vertex(
        bauxite_start_node,
        bauxite_edge_data,
        Bauxite,
        [(bauxite_edge_data, :start_vertex), (data, :location)],
    )
    bauxite_end_node = aluminaplant_transform

    bauxite_edge = Edge(
        Symbol(id, "_", bauxite_edge_key),
        bauxite_edge_data,
        system.time_data[:Bauxite],
        Bauxite,
        bauxite_start_node,
        bauxite_end_node,
    )

    fuel_edge_key = :fuel_edge
    @process_data(
        fuel_edge_data, 
        data[:edges][fuel_edge_key], 
        [
            (data[:edges][fuel_edge_key], key),
            (data[:edges][fuel_edge_key], Symbol("fuel_", key)),
            (data, Symbol("fuel_", key))
        ]
    )
    commodity_symbol = Symbol(fuel_edge_data[:commodity])
    commodity = commodity_types()[commodity_symbol]
    @start_vertex(
        fuel_start_node,
        fuel_edge_data,
        commodity,
        [(fuel_edge_data, :start_vertex), (data, :location)],
    )
    fuel_end_node = aluminaplant_transform
    fuel_edge = Edge(
        Symbol(id, "_", fuel_edge_key),
        fuel_edge_data,
        system.time_data[commodity_symbol],
        commodity,
        fuel_start_node,
        fuel_end_node,
    )

    # Alumina Edge
    alumina_edge_key = :alumina_edge
    @process_data(
        alumina_edge_data, 
        data[:edges][alumina_edge_key], 
        [
            (data[:edges][alumina_edge_key], key),
            (data[:edges][alumina_edge_key], Symbol("alumina_", key)),
            (data, Symbol("alumina_", key)),
            (data, key),
        ]
    )
    alumina_start_node = aluminaplant_transform
    @end_vertex(
        alumina_end_node,
        alumina_edge_data,
        Alumina,
        [(alumina_edge_data, :end_vertex), (data, :location)],
    )
    alumina_edge = Edge(
        Symbol(id, "_", alumina_edge_key),
        alumina_edge_data,
        system.time_data[:Alumina],
        Alumina,
        alumina_start_node,
        alumina_end_node,
    )

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
    co2_start_node = aluminaplant_transform
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
    sox_start_node = aluminaplant_transform
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
    nox_start_node = aluminaplant_transform
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
    pm_start_node = aluminaplant_transform
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
    aluminaplant_transform.balance_data = Dict(
        :elec_to_alumina => Dict(
            elec_edge.id => 1.0,
            fuel_edge.id => 0.0,
            bauxite_edge.id => 0.0,
            alumina_edge.id => get(transform_data, :elec_alumina_rate, 1.0)
        ),
        :bauxite_to_alumina => Dict(
            elec_edge.id => 0.0,
            fuel_edge.id => 0.0,
            bauxite_edge.id => 1.0,
            alumina_edge.id => get(transform_data, :bauxite_alumina_rate, 1.0)
        ),
        :fuel_to_alumina => Dict(
            elec_edge.id => 0.0,
            fuel_edge.id => 1.0,
            bauxite_edge.id => 0.0,
            alumina_edge.id => get(transform_data, :fuel_alumina_rate, 1.0)
        ),
        :emissions => Dict(
            fuel_edge.id => get(transform_data, :fuel_emissions_rate, 1.0),
            co2_edge.id => 1.0
        ),
        :sox_rate => Dict(
            sox_edge.id => -1.0,
            alumina_edge.id => get(transform_data, :sox_rate, 1.0),
        ),
        :nox_rate => Dict(
            nox_edge.id => -1.0,
            alumina_edge.id => get(transform_data, :nox_rate, 1.0),
        ),
        :pm_rate => Dict(
            pm_edge.id => -1.0,
            alumina_edge.id => get(transform_data, :pm_rate, 1.0),
        )
    )
    return AluminaPlant(id, aluminaplant_transform, elec_edge, alumina_edge, bauxite_edge, fuel_edge, co2_edge, sox_edge, nox_edge, pm_edge)
end