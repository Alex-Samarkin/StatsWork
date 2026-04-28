mutable struct VariableSpace
    datasets::Dict{Symbol, Any}
    vectors::Dict{Tuple{Symbol, Symbol}, StoredVector}
    variables::Dict{Symbol, Vector{Tuple{Symbol, Symbol, Symbol}}}
end

VariableSpace() = VariableSpace(Dict{Symbol, Any}(),
                                Dict{Tuple{Symbol, Symbol}, StoredVector}(),
                                Dict{Symbol, Vector{Tuple{Symbol, Symbol, Symbol}}}())

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
    _rebuild_variables!(space)
end

function _qualified_name(dataset::Symbol, col::Symbol)
    Symbol(string(dataset), ".", string(col))
end

function _parse_qualified_name(var::Symbol)
    parts = split(String(var), "."; limit=2)
    length(parts) == 2 || return nothing
    return (Symbol(parts[1]), Symbol(parts[2]))
end

function _rebuild_variables!(space::VariableSpace)
    empty!(space.variables)

    for (dataset, df) in space.datasets
        for col in names(df)
            s = Symbol(col)
            push!(get!(space.variables, s, Tuple{Symbol, Symbol, Symbol}[]),
                  (:dataset, dataset, s))
        end
    end

    for ((namespace, name), _) in space.vectors
        push!(get!(space.variables, name, Tuple{Symbol, Symbol, Symbol}[]),
              (:vector, namespace, name))
    end

    return space
end

function _qualified_name(location::Tuple{Symbol, Symbol, Symbol})
    _, namespace, name = location
    return _qualified_name(namespace, name)
end

function _resolve_variable(space::VariableSpace, var::Symbol)
    if haskey(space.variables, var)
        matches = space.variables[var]
        if length(matches) == 1
            return only(matches)
        end

        choices = join(sort(string.(_qualified_name.(matches))), ", ")
        error("Variable :$var is ambiguous. Use a qualified name: $choices")
    end

    parsed = _parse_qualified_name(var)
    if parsed !== nothing
        namespace, name = parsed
        matches = Tuple{Symbol, Symbol, Symbol}[]

        if haskey(space.datasets, namespace)
            df_cols = Symbol.(names(space.datasets[namespace]))
            if name in df_cols
                push!(matches, (:dataset, namespace, name))
            end
        end

        if haskey(space.vectors, _vector_key(namespace, name))
            push!(matches, (:vector, namespace, name))
        end

        if length(matches) == 1
            return only(matches)
        elseif length(matches) > 1
            error("Variable :$var is ambiguous between dataset and vector storage")
        end
    end

    error("Unknown variable: :$var")
end

function getvar(space::VariableSpace, var::Symbol)
    kind, namespace, name = _resolve_variable(space, var)

    if kind == :dataset
        return space.datasets[namespace][!, name]
    elseif kind == :vector
        return space.vectors[_vector_key(namespace, name)].values
    end

    error("Unknown variable storage: $kind")
end

function vars(space::VariableSpace)
    result = Symbol[]

    for (name, matches) in space.variables
        if length(matches) == 1
            push!(result, name)
        else
            for location in sort(matches; by=x -> string(x[2]))
                push!(result, _qualified_name(location))
            end
        end
    end

    return sort!(unique(result); by=string)
end
