struct BiomassHarvest{T} <: AbstractAsset
    id::AssetId
    storage::AbstractStorage{<:T}
    discharge_edge::Edge{<:T}
    inflow_edge::Edge{<:T}
    spill_edge::Edge{<:T}
    residue_edge::Edge{<:T}
end

BiomassHarvest(id::AssetId, storage::AbstractStorage{T}, discharge_edge::Edge{T}, inflow_edge::Edge{T}, spill_edge::Edge{T}, residue_edge::Edge{T}) where T<:Commodity =
    BiomassHarvest{T}(id, storage, discharge_edge, inflow_edge, spill_edge, residue_edge)

function default_data(t::Type{BiomassHarvest}, id=missing, style="full")
    if style == "full"
        return full_default_data(t, id)
    else
        return simple_default_data(t, id)
    end
end

function full_default_data(::Type{BiomassHarvest}, id=missing)
    return OrderedDict{Symbol,Any}(
        :id => id,
        :storage => @storage_data(
            :commodity => missing,
            :charge_discharge_ratio => 1.0,
            :constraints => Dict{Symbol, Bool}(
                :BalanceConstraint => true,
                :StorageChargeDischargeRatioConstraint => true,
            ),
        ),
        :edges => Dict{Symbol,Any}(
            :discharge_edge => @edge_data(
                :commodity => missing,
                :has_capacity => true,
                :can_expand => true,
                :can_retire => true,
                :constraints => Dict{Symbol, Bool}(
                    :CapacityConstraint => true
                ),
            ),
            :inflow_edge => @edge_data(
                :commodity => missing,
                :has_capacity => true,
                :can_expand => true,
                :can_retire => true,
                :constraints => Dict{Symbol, Bool}(
                    :MustRunConstraint => true,
                ),
            ),
            :spill_edge => @edge_data(
                :commodity => missing,
            ),
            :residue_edge => @edge_data(
                :commodity => missing,
                :has_capacity => true,
                :can_expand => true,
                :can_retire => true,
                :constraints => Dict{Symbol, Bool}(
                    :CapacityConstraint => true,
                    :StorageDischargeLimitConstraint => true,
                    :ResidueDischargeCapacitySyncConstraint => true,
                ),
            ),
        ),
    )
end

function simple_default_data(::Type{BiomassHarvest}, id=missing)
    return OrderedDict{Symbol,Any}(
        :id => id,
        :location => missing,
        :commodity => missing,
        :storage_can_expand => true,
        :storage_can_retire => true,
        :discharge_can_expand => true,
        :discharge_can_retire => true,
        :inflow_can_expand => true,
        :inflow_can_retire => true,
        :resource_source => missing,
        :storage_long_duration => false,
        :storage_existing_capacity => 0.0,
        :discharge_existing_capacity => 0.0,
        :inflow_existing_capacity => 0.0,
        :storage_charge_discharge_ratio => 1.0,
        :discharge_investment_cost => 0.0,
        :discharge_fixed_om_cost => 0.0,
        :discharge_variable_om_cost => 0.0,
        :inflow_investment_cost => 0.0,
        :inflow_fixed_om_cost => 0.0,
        :inflow_variable_om_cost => 0.0,
        :residue_variable_om_cost => 0.0,
        :discharge_efficiency => 1.0,
        :inflow_efficiency => 1.0,
        :residue_efficiency => 1.0,
    )
end

function set_commodity!(::Type{BiomassHarvest}, commodity::Type{<:Commodity}, data::AbstractDict{Symbol,Any})
    edge_keys = [:discharge_edge, :inflow_edge, :spill_edge, :residue_edge]
    if haskey(data, :commodity)
        data[:commodity] = string(commodity)
    end
    if haskey(data, :storage)
        if haskey(data[:storage], :commodity)
            data[:storage][:commodity] = string(commodity)
        end
    end
    if haskey(data, :edges)
        for edge_key in edge_keys
            if haskey(data[:edges], edge_key)
                if haskey(data[:edges][edge_key], :commodity)
                    data[:edges][edge_key][:commodity] = string(commodity)
                end
            end
        end
    end
end

function make(asset_type::Type{BiomassHarvest}, data::AbstractDict{Symbol,Any}, system::System)
    id = AssetId(data[:id])
    location = as_symbol_or_missing(get(data, :location, missing))
    
    @setup_data(asset_type, data, id)

    ## Storage component of the biomass harvest
    storage_key = :storage
    @process_data(
        storage_data,
        data[storage_key],
        [
            (data[storage_key], key),
            (data[storage_key], Symbol("storage_", key)),
            (data, Symbol("storage_", key)),
        ]
    )
    
    # Get commodity type from storage data
    commodity_symbol = Symbol(storage_data[:commodity])
    commodity = commodity_types()[commodity_symbol]
    
    # Check if the storage is a long duration storage
    long_duration = get(storage_data, :long_duration, false)
    StorageType = long_duration ? LongDurationStorage : Storage
    
    # Create the storage component
    storage = StorageType(
        Symbol(id, "_", storage_key),
        storage_data,
        system.time_data[commodity_symbol],
        commodity,
        location
    )
    
    if long_duration
        lds_constraints = [LongDurationStorageImplicitMinMaxConstraint()]
        for c in lds_constraints
            if !(c in storage.constraints)
                push!(storage.constraints, c)
            end
        end
    end

    # Discharge edge (outflow from storage)
    discharge_edge_key = :discharge_edge
    @process_data(
        discharge_edge_data,
        data[:edges][discharge_edge_key],
        [
            (data[:edges][discharge_edge_key], key),
            (data[:edges][discharge_edge_key], Symbol("discharge_", key)),
            (data, Symbol("discharge_", key)),
        ]
    )
    discharge_start_node = storage
    @end_vertex(
        discharge_end_node,
        discharge_edge_data,
        commodity,
        [(discharge_edge_data, :end_vertex), (data, :location)],
    )
    discharge_edge = Edge(
        Symbol(id, "_", discharge_edge_key),
        discharge_edge_data,
        system.time_data[commodity_symbol],
        commodity,
        discharge_start_node,
        discharge_end_node,
    )

    # Inflow edge (harvest/input to storage)
    inflow_edge_key = :inflow_edge
    @process_data(
        inflow_edge_data,
        data[:edges][inflow_edge_key],
        [
            (data[:edges][inflow_edge_key], key),
            (data[:edges][inflow_edge_key], Symbol("inflow_", key)),
            (data, Symbol("inflow_", key)),
        ]
    )
    @start_vertex(
        inflow_start_node,
        inflow_edge_data,
        commodity,
        [(inflow_edge_data, :start_vertex), (data, :resource_source), (data, :location),],
    )
    inflow_end_node = storage
    inflow_edge = Edge(
        Symbol(id, "_", inflow_edge_key),
        inflow_edge_data,
        system.time_data[commodity_symbol],
        commodity,
        inflow_start_node,
        inflow_end_node,
    )
    
    # Synchronize inflow and discharge edge properties
    inflow_edge.can_retire = discharge_edge.can_retire
    inflow_edge.can_expand = discharge_edge.can_expand
    inflow_edge.existing_capacity = discharge_edge.existing_capacity
    inflow_edge.capacity_size = discharge_edge.capacity_size

    # Spill edge (excess that cannot be stored)
    spill_edge_key = :spill_edge
    @process_data(
        spill_edge_data,
        data[:edges][spill_edge_key],
        [
            (data[:edges][spill_edge_key], key),
            (data[:edges][spill_edge_key], Symbol("spill_", key)),
            (data, Symbol("spill_", key)),
        ]
    )
    spill_start_node = storage
    @end_vertex(
        spill_end_node,
        spill_edge_data,
        commodity,
        [(spill_edge_data, :end_vertex), (data, :resource_source), (data, :location),],
    )
    spill_end_node = find_node(system.locations, Symbol(spill_edge_data[:end_vertex]))
    spill_edge = Edge(
        Symbol(id, "_", spill_edge_key),
        spill_edge_data,
        system.time_data[commodity_symbol],
        commodity,
        spill_start_node,
        spill_end_node,
    )

    # Residue edge (co-product of discharge)
    residue_edge_key = :residue_edge
    @process_data(
        residue_edge_data,
        data[:edges][residue_edge_key],
        [
            (data[:edges][residue_edge_key], key),
            (data[:edges][residue_edge_key], Symbol("residue_", key)),
            (data, Symbol("residue_", key)),
        ]
    )
    residue_start_node = storage
    @end_vertex(
        residue_end_node,
        residue_edge_data,
        commodity,
        [(residue_edge_data, :end_vertex), (data, :location)],
    )
    residue_edge = Edge(
        Symbol(id, "_", residue_edge_key),
        residue_edge_data,
        system.time_data[commodity_symbol],
        commodity,
        residue_start_node,
        residue_end_node,
    )
    
    residue_edge.existing_capacity = discharge_edge.existing_capacity
    residue_edge.capacity_size = discharge_edge.capacity_size
    residue_edge.can_expand = discharge_edge.can_expand
    residue_edge.can_retire = discharge_edge.can_retire
    
    for constraint in residue_edge.constraints
        if isa(constraint, ResidueDischargeCapacitySyncConstraint)
            constraint.linked_edge = discharge_edge
        end
    end

    # Configure storage edges and balance data
    storage.discharge_edge = discharge_edge
    storage.charge_edge = inflow_edge
    storage.spillage_edge = spill_edge

    storage.balance_data = Dict(
        :storage => Dict(
            discharge_edge.id => 1.0,
            inflow_edge.id => 1.0,
            spill_edge.id => 0.0,
            residue_edge.id => 0.0
        )
    )

    return BiomassHarvest(id, storage, discharge_edge, inflow_edge, spill_edge, residue_edge)
end