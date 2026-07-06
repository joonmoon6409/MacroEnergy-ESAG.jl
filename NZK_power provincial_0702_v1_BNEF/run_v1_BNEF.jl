using MacroEnergy
using Gurobi

# (system, model) = run_case(
#     @__DIR__;
#     optimizer=Gurobi.Optimizer,
#     optimizer_attributes=("Method" => 1, "Threads" => -1),
#     lazy_load=false,
# );

# run(`python3 $(joinpath(@__DIR__, "analyze_capacity.py"))`)

(system, model) = run_case(
    @__DIR__;
    optimizer=Gurobi.Optimizer,
    optimizer_attributes=("Method" => 2, "Crossover" => 0, "BarConvTol" => 1e-4),
    lazy_load=false,
);
 