struct BioGasifSNG <: AbstractAsset
    id::AssetId
    beccs_transform::Transformation
    biomass_edge::Edge{<:Biomass}
    sng_edge::Edge{<:NaturalGas}
    elec_consumption_edge::Edge{<:Electricity}
    elec_production_edge::Edge{<:Electricity}
    co2_edge::Edge{<:CO2}
    co2_emission_edge::Edge{<:CO2}
    co2_captured_edge::Edge{<:CO2Captured}
end

function default_data(t::Type{BioGasifSNG}, id=missing, style="full")
    if style == "full"
        return full_default_data(t, id)
    else
        return simple_default_data(t, id)
    end
end

function full_default_data(::Type{BioGasifSNG}, id=missing)
    return OrderedDict{Symbol,Any}(
        :id => id,
        :transforms => @transform_data(
            :timedata => "Biomass",
            :constraints => Dict{Symbol,Bool}(
                :BalanceConstraint => true
            ),
            :sng_production => 0.0,
            # A given instance normally uses only ONE of the two electricity terms.
            # Indirect (steam-blown) gasification with a steam turbine tends to be a net
            # exporter; oxygen-blown (ASU) and/or CCS compression tends to be a net importer.
            :electricity_consumption => 0.0,
            :electricity_production => 0.0,
            :co2_content => 0.0,
            :emission_rate => 1.0,
            :capture_rate => 1.0
        ),
        :edges => Dict{Symbol,Any}(
            :biomass_edge => @edge_data(
                :commodity => "Biomass",
                :has_capacity => true,
                :can_expand => true,
                :can_retire => true,
                :constraints => Dict{Symbol,Bool}(
                    :CapacityConstraint => true,
                )
            ),
            :sng_edge => @edge_data(
                :commodity => "NaturalGas",
            ),
            :elec_consumption_edge => @edge_data(
                :commodity => "Electricity",
            ),
            :elec_production_edge => @edge_data(
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
            )
        )
    )
end

function simple_default_data(::Type{BioGasifSNG}, id=missing)
    return OrderedDict{Symbol,Any}(
        :id => id,
        :location => missing,
        :can_expand => true,
        :can_retire => true,
        :existing_capacity => 0.0,
        :biomass_commodity => "Biomass",
        :sng_commodity => "NaturalGas",
        :co2_sink => missing,
        :sng_production => 0.0,
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

function make(asset_type::Type{BioGasifSNG}, data::AbstractDict{Symbol,Any}, system::System)
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

    # Biomass Edge (feedstock; carries the capacity constraint)
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
    biomass_commodity_symbol = Symbol(biomass_edge_data[:commodity])
    biomass_commodity = commodity_types()[biomass_commodity_symbol]
    @start_vertex(
        biomass_start_node,
        biomass_edge_data,
        biomass_commodity,
        [(biomass_edge_data, :start_vertex), (data, :location)],
    )
    biomass_end_node = beccs_transform
    biomass_edge = Edge(
        Symbol(id, "_", biomass_edge_key),
        biomass_edge_data,
        system.time_data[biomass_commodity_symbol],
        biomass_commodity,
        biomass_start_node,
        biomass_end_node,
    )

    # SNG Edge (synthetic natural gas product)
    sng_edge_key = :sng_edge
    @process_data(
        sng_edge_data,
        data[:edges][sng_edge_key],
        [
            (data[:edges][sng_edge_key], key),
            (data[:edges][sng_edge_key], Symbol("sng_", key)),
            (data, Symbol("sng_", key)),
        ]
    )
    sng_commodity_symbol = Symbol(sng_edge_data[:commodity])
    sng_commodity = commodity_types()[sng_commodity_symbol]
    sng_start_node = beccs_transform
    @end_vertex(
        sng_end_node,
        sng_edge_data,
        sng_commodity,
        [(sng_edge_data, :end_vertex), (data, :location)],
    )
    sng_edge = Edge(
        Symbol(id, "_", sng_edge_key),
        sng_edge_data,
        system.time_data[sng_commodity_symbol],
        sng_commodity,
        sng_start_node,
        sng_end_node,
    )

    # Electricity Consumption Edge
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
        elec_consumption_start_node,
        elec_consumption_edge_data,
        Electricity,
        [(elec_consumption_edge_data, :start_vertex), (data, :location)],
    )
    elec_consumption_end_node = beccs_transform
    elec_consumption_edge = Edge(
        Symbol(id, "_", elec_consumption_edge_key),
        elec_consumption_edge_data,
        system.time_data[:Electricity],
        Electricity,
        elec_consumption_start_node,
        elec_consumption_end_node,
    )

    # Electricity Production Edge
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
    elec_production_start_node = beccs_transform
    @end_vertex(
        elec_production_end_node,
        elec_production_edge_data,
        Electricity,
        [(elec_production_edge_data, :end_vertex), (data, :location)],
    )
    elec_production_edge = Edge(
        Symbol(id, "_", elec_production_edge_key),
        elec_production_edge_data,
        system.time_data[:Electricity],
        Electricity,
        elec_production_start_node,
        elec_production_end_node,
    )

    # CO2 Edge (biogenic uptake / negative emissions)
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

    # CO2 Emission Edge (vented)
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

    # CO2 Captured Edge
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
        :sng_production => Dict(
            sng_edge.id => 1.0,
            biomass_edge.id => get(transform_data, :sng_production, 0.0)
        ),
        :elec_consumption => Dict(
            elec_consumption_edge.id => -1.0,
            biomass_edge.id => get(transform_data, :electricity_consumption, 0.0)
        ),
        :elec_production => Dict(
            elec_production_edge.id => 1.0,
            biomass_edge.id => get(transform_data, :electricity_production, 0.0)
        ),
        :negative_emissions => Dict(
            biomass_edge.id => get(transform_data, :co2_content, 0.0),
            co2_edge.id => -1.0
        ),
        :emissions => Dict(
            biomass_edge.id => get(transform_data, :emission_rate, 1.0),
            co2_emission_edge.id => 1.0
        ),
        :capture => Dict(
            biomass_edge.id => get(transform_data, :capture_rate, 1.0),
            co2_captured_edge.id => 1.0
        )
    )

    return BioGasifSNG(
        id,
        beccs_transform,
        biomass_edge,
        sng_edge,
        elec_consumption_edge,
        elec_production_edge,
        co2_edge,
        co2_emission_edge,
        co2_captured_edge,
    )
end