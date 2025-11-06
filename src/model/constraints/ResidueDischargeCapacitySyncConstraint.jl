Base.@kwdef mutable struct ResidueDischargeCapacitySyncConstraint <: PlanningConstraint
    value::Union{Missing,Vector{Float64}} = missing
    lagrangian_multiplier::Union{Missing,Vector{Float64}} = missing
    constraint_ref::Union{Missing,JuMPConstraint} = missing
    linked_edge::Union{Missing,AbstractEdge} = missing
end

@doc raw"""
    add_model_constraint!(
        ct::ResidueDischargeCapacitySyncConstraint,
        e::Edge,
        model::Model,
    )

Add a constraint to synchronize residue edge capacity with its linked discharge edge capacity. 
The functional form of the constraint is:
```math
\begin{aligned}
    \text{capacity(residue\_edge)} = \text{capacity(linked\_discharge\_edge)}
\end{aligned}
```

This constraint is only applied if the edge has a linked_edge reference stored.
"""
function add_model_constraint!(
    ct::ResidueDischargeCapacitySyncConstraint,
    e::Edge,
    model::Model,
)
    # linked_edge가 설정되어 있으면 constraint 추가
    if !ismissing(ct.linked_edge)
        ct.constraint_ref = @constraint(
            model,
            capacity(e) == capacity(ct.linked_edge)
        )
    end

    return nothing
end