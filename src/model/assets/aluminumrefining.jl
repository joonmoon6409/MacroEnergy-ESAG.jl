# AluminumRefining represents a facility that transforms electricity and aluminum scrap into refined aluminum
# It inherits from AbstractAsset and contains edges for electricity input, aluminum scrap input, and aluminum output
struct AluminumRefining <: AbstractAsset
    id::AssetId                                    # Unique identifier for the asset
    aluminum_transform::Transformation             # Transformation process that converts inputs to outputs
    elec_edge::Edge{<:Electricity}                  # Edge representing electricity input
    aluminumscrap_edge::Edge{<:AluminumScrap}       # Edge representing aluminum scrap input
    aluminum_edge::Edge{<:Aluminum}                  # Edge representing aluminum output
    sox_edge::Edge{<:Pollution} # SOx emissions
    nox_edge::Edge{<:Pollution} # NOx emissions
    pm_edge::Edge{<:Pollution} # PM emissions             
end

# Factory function to create default data for AluminumRefining
# style can be either "full" (detailed configuration) or "simple" (basic configuration)
function default_data(t::Type{AluminumRefining}, id=missing, style="full")
    if style == "full"
        return full_default_data(t, id)
    else
        return simple_default_data(t, id)
    end
end

# Creates detailed default configuration for AluminumRefining
# Includes transformation rates, constraints, and edge configurations
function full_default_data(::Type{AluminumRefining}, id=missing)
    return Dict{Symbol,Any}(
        :id => id,
        :transforms => @transform_data(
            :timedata => "Aluminum",              # Time series data identifier
            :elec_aluminum_rate => 1.0,           # Rate of electricity needed per unit of aluminum
            :aluminumscrap_aluminum_rate => 1.05, # Rate of aluminum scrap needed per unit of aluminum (includes 5% loss)
            :aluminum_emissions_rate => 0.0,  
                # Emissions rate for aluminum production
            :sox_rate => 0.0,
            :nox_rate => 0.0,
            :pm_rate => 0.0,
                :constraints => Dict{Symbol, Bool}(
                :BalanceConstraint => true,       # Enforces material balance constraints
            ),
        ),
        :edges => Dict{Symbol,Any}(
            # Electricity input edge configuration
            :elec_edge => @edge_data(
                :commodity => "Electricity"
            ),
            # Aluminum output edge configuration
            :aluminum_edge => @edge_data(
                :commodity=>"Aluminum",
                :has_capacity => true,            # Edge has capacity constraints
                :can_retire => true,              # Capacity can be retired
                :can_expand => true,              # Capacity can be expanded
                :constraints => Dict{Symbol, Bool}(
                    :CapacityConstraint => true,  # Enforces capacity constraints
                )
            ),
            # Aluminum scrap input edge configuration
            :aluminumscrap_edge => @edge_data(
                :commodity => "AluminumScrap"
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

# Creates simplified default configuration for AluminumRefining
# Contains basic parameters without detailed edge configurations
function simple_default_data(::Type{AluminumRefining}, id=missing)
    return Dict{Symbol, Any}(
        :id => id,
        :location => missing,
        :can_expand => true,                      # Asset can be expanded
        :can_retire => true,                      # Asset can be retired
        :existing_capacity => 0.0,                # Initial capacity
        :capacity_size => 1.0,                    # Size of capacity units
        :timedata => "Aluminum",                  # Time series data identifier
        :elec_aluminum_rate => 1.0,               # Rate of electricity needed per unit of aluminum
        :aluminumscrap_aluminum_rate => 1.05,     # Rate of aluminum scrap needed per unit of aluminum
        :aluminum_emissions_rate => 0.0,          # Emissions rate for aluminum production
        :investment_cost => 0.0,                  # Cost to build new capacity
        :fixed_om_cost => 0.0,                    # Fixed operating and maintenance cost
        :variable_om_cost => 0.0, 
        :sox_rate => 0.0,
        :nox_rate => 0.0,
        :pm_rate => 0.0,                # Variable operating and maintenance cost
    )
end

# Main constructor function that creates an AluminumRefining asset from configuration data
function make(asset_type::Type{AluminumRefining}, data::AbstractDict{Symbol,Any}, system::System)
    id = AssetId(data[:id])

    @setup_data(asset_type, data, id)

    # Create the transformation process that converts inputs to outputs
    aluminumrefining_key = :transforms
    @process_data(
        transform_data,
        data[aluminumrefining_key],
        [
            (data[aluminumrefining_key], key),
            (data[aluminumrefining_key], Symbol("transform_", key)),
            (data, Symbol("transform_", key)),
            (data, key),
        ]
    )
    aluminumrefining_transform = Transformation(;
        id = Symbol(id, "_", aluminumrefining_key),
        timedata = system.time_data[Symbol(transform_data[:timedata])],
        constraints = get(transform_data, :constraints, [BalanceConstraint()]),
    )

    # Create the electricity input edge
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

    # Set up electricity edge vertices (start and end nodes)
    @start_vertex(
        elec_start_node,
        elec_edge_data,
        Electricity,
        [(elec_edge_data, :start_vertex), (data, :location)],
    )
    elec_end_node = aluminumrefining_transform

    # Create the electricity edge
    elec_edge = Edge(
        Symbol(id, "_", elec_edge_key),
        elec_edge_data,
        system.time_data[:Electricity],
        Electricity,
        elec_start_node,
        elec_end_node,
    )

    # Create the aluminum scrap input edge
    aluminumscrap_edge_key = :aluminumscrap_edge
    @process_data(
        aluminumscrap_edge_data, 
        data[:edges][aluminumscrap_edge_key], 
        [
            (data[:edges][aluminumscrap_edge_key], key),
            (data[:edges][aluminumscrap_edge_key], Symbol("aluminumscrap_", key)),
            (data, Symbol("aluminumscrap_", key))
        ]
    )

    # Set up aluminum scrap edge vertices
    @start_vertex(
        aluminumscrap_start_node,
        aluminumscrap_edge_data,
        AluminumScrap,
        [(aluminumscrap_edge_data, :start_vertex), (data, :location)],
    )
    aluminumscrap_end_node = aluminumrefining_transform

    # Create the aluminum scrap edge
    aluminumscrap_edge = Edge(
        Symbol(id, "_", aluminumscrap_edge_key),
        aluminumscrap_edge_data,
        system.time_data[:AluminumScrap],
        AluminumScrap,
        aluminumscrap_start_node,
        aluminumscrap_end_node,
    )

    # Create the aluminum output edge
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
    aluminum_start_node = aluminumrefining_transform
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
    sox_start_node = aluminumrefining_transform
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
    nox_start_node = aluminumrefining_transform
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
    pm_start_node = aluminumrefining_transform
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

    # Set up balance constraints for the transformation process
    # These define how inputs (electricity and aluminum scrap) are converted to outputs (aluminum)
    aluminumrefining_transform.balance_data = Dict(
        :elec_to_aluminum => Dict(
            elec_edge.id => 1.0,                  # Electricity input coefficient
            aluminumscrap_edge.id => 0.0,         # No direct conversion from electricity to aluminum scrap
            aluminum_edge.id => get(transform_data, :elec_aluminum_rate, 1.0)  # Electricity needed per unit of aluminum
        ),
        :aluminumscrap_to_aluminum => Dict(
            elec_edge.id => 0.0,                  # No direct conversion from aluminum scrap to electricity
            aluminumscrap_edge.id => 1.0,         # Aluminum scrap input coefficient
            aluminum_edge.id => get(transform_data, :aluminumscrap_aluminum_rate, 1.0)  # Aluminum scrap needed per unit of aluminum
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
    return AluminumRefining(id, aluminumrefining_transform, elec_edge, aluminumscrap_edge, aluminum_edge, sox_edge, nox_edge, pm_edge)
end