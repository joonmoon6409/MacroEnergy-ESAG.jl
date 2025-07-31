struct CropEthanol <: AbstractAsset
    id::AssetId
    beccs_transform::Transformation # might change name 
    crop_edge::Edge{<:Biomass}
    bagasse_edge::Edge{<:Biomass}
    ethanol_edge::Edge{<:LiquidFuels}
    elec_production_edge::Edge{<:Electricity}
    elec_consumption_edge::Edge{<:Electricity}
    co2_edge::Edge{<:CO2}
    co2_emission_edge::Edge{<:CO2}
    co2_captured_edge::Edge{<:CO2Captured}
end

function default_data(t::Type{CropEthanol}, id=missing, style="full")
    if style == "full"
        return full_default_data(t, id)
    else
        return simple_default_data(t, id)
    end
end

function full_default_data(::Type{CropEthanol}, id=missing)
    return OrderedDict{Symbol,Any}(
        :id => id,
        :transforms => @transform_data(
            :timedata => "Biomass", #should this be :timedata => "crop"
            :constraints => Dict{Symbol,Bool}(
                :BalanceConstraint => true
            ),
            :ethanol_production => 0.0,
            :bagasse_production => 0.0,
            :electricity_consumption => 0.0,
            :electricity_production => 0.0,
            :co2_content => 0.0,
            :emission_rate => 1.0,
            :capture_rate => 1.0
        ),
        :edges => Dict{Symbol,Any}(
            :crop_edge => @edge_data(
                :commodity => "Biomass",
                :has_capacity => true,
                :can_expand => true,
                :can_retire => true,
                :constraints => Dict{Symbol,Bool}(
                    :CapacityConstraint => true,
                )
            ),

            :bagasse_edge => @edge_data(
                :commodity => "Biomass"
            ),

            :ethanol_edge => @edge_data(
                :commodity => "LiquidFuels",
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

function simple_default_data(::Type{CropEthanol}, id=missing)
    return OrderedDict{Symbol,Any}(
        :id => id,
        :location => missing,
        :can_expand => true,
        :can_retire => true,
        :existing_capacity => 0.0,
        :ethanol_commodity => "LiquidFuels",
        :bagasse_commodity => "BioMass",
        :co2_sink => missing,
        :ethanol_production => 0.0,
        :bagasse_production => 0.0,
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

function make(asset_type::Type{CropEthanol}, data::AbstractDict{Symbol,Any}, system::System)
    id = AssetId(data[:id])

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
        constraints = transform_data[:constraints],
    )

    crop_edge_key = :crop_edge
    @process_data(
        crop_edge_data,
        data[:edges][crop_edge_key],
        [
            (data[:edges][crop_edge_key], key),
            (data[:edges][crop_edge_key], Symbol("crop_", key)),
            (data, Symbol("crop_", key)),
            (data, key),
        ]
    )
    commodity_symbol = Symbol(crop_edge_data[:commodity])
    commodity = commodity_types()[commodity_symbol]
    @start_vertex(
        crop_start_node,
        crop_edge_data,
        commodity,
        [(crop_edge_data, :start_vertex), (data, :location)],
    )
    crop_end_node = beccs_transform
    crop_edge = Edge(
        Symbol(id, "_", crop_edge_key),
        crop_edge_data,
        system.time_data[commodity_symbol],
        commodity,
        crop_start_node,
        crop_end_node,
    )

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
    commodity_symbol = Symbol(ethanol_edge_data[:commodity])
    commodity = commodity_types()[commodity_symbol]
    ethanol_start_node = beccs_transform
    @end_vertex(
        ethanol_end_node,
        ethanol_edge_data,
        commodity,
        [(ethanol_edge_data, :end_vertex), (data, :location)],
    )
    ethanol_edge = Edge(
        Symbol(id, "_", ethanol_edge_key),
        ethanol_edge_data,
        system.time_data[commodity_symbol],
        commodity,
        ethanol_start_node,
        ethanol_end_node,
    )

    bagasse_edge_key = :bagasse_edge
    @process_data(
        bagasse_edge_data,
        data[:edges][bagasse_edge_key],
        [
            (data[:edges][bagasse_edge_key], key),
            (data[:edges][bagasse_edge_key], Symbol("bagasse_", key)),
            (data, Symbol("bagasse_", key)),
        ]
    )
    commodity_symbol = Symbol(bagasse_edge_data[:commodity])
    commodity = commodity_types()[commodity_symbol]
    
    bagasse_start_node = beccs_transform
    @end_vertex(
        bagasse_end_node,
        bagasse_edge_data,
        commodity,
        [(bagasse_edge_data, :end_vertex), (data, :location)],
    )
    bagasse_edge = Edge(
        Symbol(id, "_", bagasse_edge_key),
        bagasse_edge_data,
        system.time_data[commodity_symbol],
        commodity,
        bagasse_start_node,
        bagasse_end_node,
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
        :ethanol_production => Dict(
            ethanol_edge.id => 1.0,
            crop_edge.id => get(transform_data, :ethanol_production, 0.0)
        ),
        :bagasse_production => Dict(
            bagasse_edge.id => 1.0,
            crop_edge.id => get(transform_data, :bagasse_production, 0.0)
        ),
        :elec_production => Dict(
            elec_production_edge.id => 1.0,
            crop_edge.id => get(transform_data, :electricity_production, 0.0)
        ),
        :elec_consumption => Dict(
            elec_consumption_edge.id => -1.0,
            crop_edge.id => get(transform_data, :electricity_consumption, 0.0)
        ),
        :negative_emissions => Dict(
            crop_edge.id => get(transform_data, :co2_content, 0.0),
            co2_edge.id => -1.0
        ),
        :emissions => Dict(
            crop_edge.id => get(transform_data, :emission_rate, 1.0),
            co2_emission_edge.id => 1.0
        ),
        :capture =>Dict(
            crop_edge.id => get(transform_data, :capture_rate, 1.0),
            co2_captured_edge.id => 1.0
        )
    )

    return CropEthanol(id, beccs_transform, crop_edge, bagasse_edge,  ethanol_edge, elec_production_edge, elec_consumption_edge, co2_edge, co2_emission_edge, co2_captured_edge) 
end