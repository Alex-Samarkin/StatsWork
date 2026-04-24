mutable struct VariableSpace
    datasets::Dict{Symbol, Any}
    mapping::Dict{Symbol, Tuple{Symbol, Symbol}}
end

VariableSpace() = VariableSpace(Dict(), Dict())

function register_dataset!(space::VariableSpace, name::Symbol, df)
    space.datasets[name] = df
    for col in names(df)
        s = Symbol(col)
        space.mapping[s] = (name, s)
    end
end

function getvar(space::VariableSpace, var::Symbol)
    dataset, col = space.mapping[var]
    return space.datasets[dataset][!, col]
end

vars(space::VariableSpace) = collect(keys(space.mapping))
