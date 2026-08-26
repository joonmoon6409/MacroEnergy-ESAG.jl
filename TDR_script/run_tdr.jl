"""
Script for Time Domain Reduction (TDR) preparation. Runs three steps in sequence:

  1. Auto-discover all 8760-row CSV files in <system_path>, build the TDR input
     matrix (timeseries_for_TDR.csv), and copy the folder to <system_path>_full/.
  2. Run TDR clustering and write Period_map.csv to <system_path>/.
  3. Apply the Period_map to reduce all timeseries CSV files in-place and
     update time_data.json.

Usage:
    julia run_tdr.jl <case_path>
"""

using Pkg
Pkg.activate(@__DIR__)
Pkg.instantiate()

using CSV
using DataFrames
using JSON3
using Logging
using MacroEnergyTimeReduction

const N_WEEKS = 52
const HOURS_PER_WEEK = 168
const N_HOURS = N_WEEKS * HOURS_PER_WEEK  # 8736; last 24 hours of year are dropped

const TDR_SETUP = Dict(
    "TimestepsPerRepPeriod" => HOURS_PER_WEEK,
    "ScalingMethod" => "N",
    "AutoEncoder" => Dict(
        "kernel_size" => 3,
        "stride" => 1,
        "epochs" => 50,
        "min_err_diff" => 1e-4,
        "patience" => 10,
        "warmup" => 5,
        "n_filters" => 8,
        "latent_dim" => 4,
        "lambda" => 0.1,
    ),
)
const N_CLUSTERS = 12
const N_ITERS = 20

function find_timeseries_files(folder::String)::Vector{String}
    files = String[]
    skipped = String[]
    for fname in readdir(folder)
        endswith(fname, ".csv") || continue
        n_lines = open(countlines, joinpath(folder, fname))
        if n_lines == 8761  # 1 header + 8760 data rows
            push!(files, fname)
        else
            push!(skipped, "$fname ($(n_lines - 1) rows)")
        end
    end
    sort!(files)
    @info "Discovered timeseries files in $folder" n_files=length(files) files
    isempty(skipped) || @warn "Skipped CSV files with unexpected row count" skipped
    isempty(files) && error("No valid timeseries files found in $folder")
    return files
end

function build_tdr_input(system_path::String)::Matrix{Float64}
    @info "=== Step 1: building TDR input matrix ===" system_path

    timeseries_files = find_timeseries_files(system_path)

    rows = Matrix{Float64}[]
    for fname in timeseries_files
        df = CSV.read(joinpath(system_path, fname), DataFrame)
        df = df[1:N_HOURS, :]
        for col in names(df)[2:end]  # skip index column
            values = Float64.(df[!, col])
            push!(rows, reshape(values, HOURS_PER_WEEK, N_WEEKS))
        end
    end

    tdr_matrix = vcat(rows...)
    @info "TDR matrix assembled" size=size(tdr_matrix)

    open(joinpath(dirname(system_path), "timeseries_for_TDR.csv"), "w") do io
        for row in eachrow(tdr_matrix)
            println(io, join(row, ","))
        end
    end
    @info "Written: timeseries_for_TDR.csv"

    full_path = system_path * "_full"
    cp(system_path, full_path; force=true)
    @info "Backup copy created" path=full_path

    return tdr_matrix
end

function run_tdr_clustering(system_path::String, clustering_input::DataFrame)
    @info "=== Step 2: running TDR clustering ===" N_CLUSTERS N_ITERS
    @info "Clustering input" size=size(clustering_input)

    _, A, W, M, _, _, clustering_time = cluster(
        nothing,
        TDR_SETUP,
        "kmeans",
        clustering_input,
        N_CLUSTERS,
        N_ITERS;
        v = false,
    )

    @info "Clustering complete" clustering_time_s=clustering_time representative_periods=M cluster_weights=W

    period_map = DataFrame(
        Period_Index     = collect(1:N_WEEKS),
        Rep_Period       = [M[a] for a in A],
        Rep_Period_Index = A,
    )
    out_path = joinpath(system_path, "Period_map.csv")
    CSV.write(out_path, period_map)
    @info "Written: $out_path"
    return nothing
end

function write_reduced_timeseries(system_path::String)
    @info "=== Step 3: applying TDR reduction ===" system_path

    full_path = system_path * "_full"
    timeseries_files = find_timeseries_files(full_path)

    period_map = CSV.read(joinpath(system_path, "Period_map.csv"), DataFrame)
    rep_weeks = unique(period_map[!, :Rep_Period])
    @info "Period map loaded" n_representative_weeks=length(rep_weeks) rep_weeks

    for fname in timeseries_files
        @info "Reducing $fname"
        df = CSV.read(joinpath(full_path, fname), DataFrame)
        blocks = [df[(w-1)*HOURS_PER_WEEK+1 : w*HOURS_PER_WEEK, :] for w in rep_weeks]
        reduced = vcat(blocks...)
        reduced[!, 1] = 1:nrow(reduced)
        CSV.write(joinpath(system_path, fname), reduced)
    end
    @info "All timeseries files reduced" n_files=length(timeseries_files)

    time_data_path = joinpath(system_path, "time_data.json")
    raw = JSON3.read(read(time_data_path, String))
    time_data = Dict{String, Any}(String(k) => v for (k, v) in pairs(raw))
    time_data["NumberOfSubperiods"] = length(rep_weeks)
    time_data["SubPeriodMap"] = Dict("path" => "system/Period_map.csv")
    open(time_data_path, "w") do io
        JSON3.pretty(io, time_data)
    end
    @info "Updated: $time_data_path"
    return nothing
end

function main()
    length(ARGS) >= 1 || error("Usage: julia run_tdr.jl <case_path>")
    case_path = ARGS[1]
    system_path = joinpath(case_path, "system")
    isdir(system_path) || error("system directory not found: $system_path")

    tdr_matrix = build_tdr_input(system_path)
    run_tdr_clustering(system_path, DataFrame(tdr_matrix, :auto))
    write_reduced_timeseries(system_path)
    return nothing
end

main()