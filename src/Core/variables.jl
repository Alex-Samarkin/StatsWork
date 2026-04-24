mutable struct VariableSpace
    datasets::Dict{Symbol, Any}
    mapping::Dict{Symbol, Tuple{Symbol, Symbol}}
end

VariableSpace() = VariableSpace(Dict(), Dict())

_normalize_column_names(cols) = Symbol.(collect(cols))

function select_columns(df;
                        include::AbstractVector=Symbol[],
                        exclude::AbstractVector=Symbol[])
    include_names = _normalize_column_names(include)
    exclude_names = _normalize_column_names(exclude)

    if !isempty(include_names)
        return select(df, include_names)
    end

    if !isempty(exclude_names)
        return select(df, Not(exclude_names))
    end

    return select(df, :)
end

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
