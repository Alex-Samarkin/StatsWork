mutable struct StoredVector
    name::Symbol
    values::AbstractVector
    namespace::Symbol
    source::Union{Nothing, Symbol}
    column::Union{Nothing, Symbol}
    origin::Symbol
    dirty::Bool
    expression::Union{Nothing, String}
end

function StoredVector(namespace::Symbol,
                      name::Symbol,
                      values::AbstractVector;
                      source=nothing,
                      column=nothing,
                      origin::Symbol=:computed,
                      dirty::Bool=true,
                      expression=nothing)
    StoredVector(name, values, namespace, source, column, origin, dirty, expression)
end

_vector_key(namespace::Symbol, name::Symbol) = (namespace, name)

function store_vector!(space,
                       namespace::Symbol,
                       name::Symbol,
                       values::AbstractVector;
                       origin::Symbol=:computed,
                       dirty::Bool=true,
                       expression=nothing)
    if haskey(space.datasets, namespace) &&
       name in Symbol.(names(space.datasets[namespace]))
        error("Cannot store vector as $namespace.$name: a dataset column already uses that name")
    end

    space.vectors[_vector_key(namespace, name)] =
        StoredVector(namespace, name, collect(values);
                     origin=origin,
                     dirty=dirty,
                     expression=expression)

    _rebuild_variables!(space)
    return space.vectors[_vector_key(namespace, name)].values
end
