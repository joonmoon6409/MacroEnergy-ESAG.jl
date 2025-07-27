using MacroEnergy
using Gurobi

(system, model) = run_case(@__DIR__; optimizer=Gurobi.Optimizer, lazy_load=false);

# system = MacroEnergy.load_system(@__DIR__);
# # unique(asset_types)
# vertex = MacroEnergy.find_node(system.locations, :elec_SE);