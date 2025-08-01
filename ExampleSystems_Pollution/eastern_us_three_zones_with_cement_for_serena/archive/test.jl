using Pkg
Pkg.activate(dirname(dirname(@__DIR__)))
using Infiltrator
using MacroEnergy
using Gurobi
using DataFrames

case_path = @__DIR__
println("###### ###### ######")
println("Running case at $(case_path)")

## Run model

system = MacroEnergy.load_system(case_path)

model = MacroEnergy.generate_model(system)

MacroEnergy.set_optimizer(model, Gurobi.Optimizer);

MacroEnergy.set_optimizer_attributes(model, "BarConvTol"=>1e-3,"Crossover" => 0, "Method" => 2)

MacroEnergy.optimize!(model)

# Test cement_co2_node

nodes = Node[x for x in system.locations if x isa MacroEnergy.Node] # Get all nodes (and not locations) in system.locations
co2_nodes = MacroEnergy.get_nodes_sametype(nodes, CO2) # List of CO2 nodes
cement_co2_node = co2_nodes[1]
MacroEnergy.value(sum(cement_co2_node.operation_expr[:exogenous]))