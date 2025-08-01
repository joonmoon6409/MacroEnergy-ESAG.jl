module MacroEnergy

using CSV, JSON3, GZip, Parquet2
using Dates
using DuckDB
using DataFrames
using OrderedCollections
using JuMP
using HiGHS
using Revise
using InteractiveUtils
using Printf: @printf
using MacroEnergyScaling
using MacroEnergySolvers
using Pkg
using DistributedArrays
using Distributed
using ClusterManagers
using Gurobi
using GitHub
using Markdown

import MacroEnergyScaling: scale_constraints!
import JuMP: set_optimizer, set_optimizer_attributes

import Base: /, push!, merge!

# Type parameter for Macro data structures

## Commodity types
abstract type Commodity end
abstract type Electricity <: Commodity end ## MWh
abstract type Hydrogen <: Commodity end ## MWh
abstract type NaturalGas <: Commodity end ## MWh
abstract type CO2 <: Commodity end ## tonnes
abstract type CO2Captured <: CO2 end ## tonnes
abstract type Coal <: Commodity end ## MWh
abstract type Biomass <: Commodity end ## tonnes
abstract type Ammonia <: Commodity end ## MWh
abstract type Biomethane <: Commodity end ## MWh        
abstract type Uranium <: Commodity end ## MWh
abstract type LiquidFuels <: Commodity end ## MWh
abstract type Pollution <: Commodity end ## tonnes
abstract type Cement <: Commodity end ## tonnes
abstract type AluminumScrap <: Commodity end ## tonnes
abstract type Aluminum <: Commodity end ## tonnes
abstract type Alumina <: Commodity end ## tonnes
abstract type Graphite <: Commodity end ## tonnes
abstract type Bauxite <: Commodity end ## tonnes

## Time data types
abstract type AbstractTimeData{T<:Commodity} end

##
abstract type AbstractSystem end

## Structure types
abstract type MacroObject end
abstract type AbstractVertex <: MacroObject end
abstract type AbstractStorage{T<:Commodity} <: AbstractVertex end

## Network types
abstract type AbstractEdge{T<:Commodity} <: MacroObject end

## Assets types
abstract type AbstractAsset <: MacroObject end

## Constraints types
abstract type AbstractTypeConstraint end
abstract type OperationConstraint <: AbstractTypeConstraint end
abstract type PolicyConstraint <: OperationConstraint end
abstract type PlanningConstraint <: AbstractTypeConstraint end

## Solution algorithms

abstract type AbstractSolutionAlgorithm end
struct Benders <: AbstractSolutionAlgorithm end
struct Monolithic <: AbstractSolutionAlgorithm end
struct Myopic <: AbstractSolutionAlgorithm end
solution_algorithm(::AbstractSolutionAlgorithm) = Monolithic() # default to monolithic
solution_algorithm(::Benders) = Benders()
solution_algorithm(::Monolithic) = Monolithic()
solution_algorithm(::Myopic) = Myopic()

# global constants
const ME_DEPOT_PATH = joinpath(homedir(), ".macroenergy")
const H2_MWh = 33.33 # MWh per tonne of H2
const NG_MWh = 0.29307107 # MWh per MMBTU of NG 
const AssetId = Symbol
const JuMPConstraint =
    Union{Array,Containers.DenseAxisArray,Containers.SparseAxisArray,ConstraintRef}
const JuMPVariable =
    Union{Array,Containers.DenseAxisArray,Containers.SparseAxisArray,VariableRef}

# Load subcommodities from file when MacroEnergy is loaded
# Also load the Gurobi environment
const GRB_ENV = Ref{Gurobi.Env}()
function __init__()
    isdir(ME_DEPOT_PATH) && load_subcommodities_from_file(ME_DEPOT_PATH)
    try
        GRB_ENV[] = Gurobi.Env()
    catch e
        if isa(e, ErrorException) && occursin("Gurobi Error", string(e))
            @debug "Gurobi is not available."
        else
            rethrow(e)
        end
    end
end

function include_all_in_folder(folder::AbstractString, root_path::AbstractString=@__DIR__)
    base_path = joinpath(root_path, folder)
    for (root, dirs, files) in Base.Filesystem.walkdir(base_path)
        for file in files
            if endswith(file, ".jl")
                include(joinpath(root, file))
            end
        end
    end
    return nothing
end

# include files
include_all_in_folder("utilities")

include("model/units.jl")
include("model/time_management.jl")
include("model/networks/vertex.jl")
include("model/networks/node.jl")
include("model/networks/storage.jl")
include("model/networks/transformation.jl")
include("model/networks/location.jl")
include("model/networks/edge.jl")
include("model/networks/asset.jl")
include("model/system.jl")
include("model/case.jl")
include("model/networks/macroobject.jl")
include("model/generate_model.jl")
include("model/optimizer.jl")
include("model/scaling.jl")
include("model/solver.jl")
include("model/myopic.jl")
include_all_in_folder("model/constraints")
include_all_in_folder("model/benders")

include("model/assets/battery.jl")
include("model/assets/electrolyzer.jl")
include("model/assets/fuelcell.jl")
include("model/assets/gasstorage.jl")
include("model/assets/thermalhydrogen.jl")
include("model/assets/thermalpower.jl")
include("model/assets/transmissionlink.jl")
include("model/assets/vre.jl")
include("model/assets/thermalhydrogenccs.jl")
include("model/assets/thermalpowerccs.jl")
include("model/assets/natgasdac.jl")
include("model/assets/electricdac.jl")
include("model/assets/beccselectricity.jl")
include("model/assets/beccshydrogen.jl")
include("model/assets/beccsgasoline.jl")
include("model/assets/beccsliquidfuels.jl")
include("model/assets/beccsnaturalgas.jl")
include("model/assets/hydrores.jl")
include("model/assets/mustrun.jl")
include("model/assets/fossilfuelsupstream.jl")
include("model/assets/fuelsenduse.jl")
include("model/assets/syntheticnaturalgas.jl")
include("model/assets/syntheticliquidfuels.jl")
include("model/assets/co2injection.jl")
include("model/assets/cementplant.jl")
include("model/assets/aluminumrefining.jl")
include("model/assets/aluminumsmelting.jl")
include("model/assets/aluminaplant.jl")
include("model/assets/beccsammonia.jl")
include("model/assets/beccsbiomethane.jl")
include("model/assets/cropethanol.jl")
include("model/assets/biomasstransformation.jl")
include("model/assets/fischertropsch.jl")

include("config/configure_settings.jl")
include("config/case_settings.jl")
include_all_in_folder("load_inputs")

include_all_in_folder("write_outputs/")

export AbstractAsset,
    AbstractTypeConstraint,
    AgeBasedRetirementConstraint,
    Alumina,
    Aluminum,
    AluminumScrap,
    AluminumRefining,
    AluminumSmelting,
    AluminaPlant,
    Bauxite,
    BalanceConstraint,
    Battery,
    Biomass,
    BiomassTransformation,
    CropEthanol,
    Coal,
    Cement,
    BECCSAmmonia, 
    BECCSBiomethane,
    BECCSElectricity,
    BECCSHydrogen,
    BECCSGasoline,
    BECCSLiquidFuels,
    BECCSNaturalGas,
    CO2,
    CO2CapConstraint,
    CO2Captured,
    CO2Injection,
    CO2StorageConstraint,
    CapacityConstraint,
    collect_results,
    Commodity,
    Edge,
    EdgeWithUC,
    Electricity,
    Electrolyzer,
    ElectricDAC,
    FossilFuelsUpstream,
    FischerTropsch,
    FuelCell,
    FuelsEndUse,
    GasStorage,
    Graphite,
    get_optimal_capacity, 
    get_optimal_discounted_costs,
    get_optimal_flow,
    get_optimal_new_capacity,
    get_optimal_retired_capacity,
    HydroRes,
    Hydrogen,
    LongDurationStorage,
    LongDurationStorageImplicitMinMaxConstraint,
    LongDurationStorageChangeConstraint,
    LiquidFuels,
    load_subcommodities_from_file,
    MaxCapacityConstraint,
    MaxNewCapacityConstraint,
    MaxNonServedDemandConstraint,
    MaxNonServedDemandPerSegmentConstraint,
    MaxStorageLevelConstraint,
    MinCapacityConstraint,
    MinDownTimeConstraint,
    MinFlowConstraint,
    MinStorageOutflowConstraint,
    MinStorageLevelConstraint,
    MinUpTimeConstraint,
    MustRun,
    MustRunConstraint,
    NaturalGas,
    NaturalGasDAC,
    NaturalGasFossilUpstream,
    Node,
    OperationConstraint,
    PlanningConstraint,
    PolicyConstraint,
    Pollution,
    RampingLimitConstraint,
    run_case,
    Storage,
    StorageCapacityConstraint,
    StorageChargeDischargeRatioConstraint,
    StorageMaxDurationConstraint,
    StorageMinDurationConstraint,
    StorageSymmetricCapacityConstraint,
    StorageDischargeLimitConstraint,
    SyntheticNaturalGas,
    SyntheticLiquidFuels,
    ThermalHydrogen,
    ThermalPower,
    ThermalHydrogenCCS,
    ThermalPowerCCS,
    TransmissionLink,
    Transformation,
    Uranium,
    VRE,
    write_capacity,
    write_costs,
    write_dataframe,
    write_flow,
    write_results,
    template_system,
    template_node,
    template_location,
    template_asset,
    template_subcommodity,
    asset_ids,
    asset_ids_from_dir,
    list_examples,
    download_example,
    download_examples,
    example_readme,
    example_contents,
    authenticate_github
    
end # module MacroEnergy
