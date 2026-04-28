function _align_to_length(values::AbstractVector, n::Int, strategy::Symbol)
    len = length(values)

    if len == n
        return collect(values), nothing
    elseif strategy == :strict
        error("Cannot commit vector of length $len to dataset with $n rows")
    elseif len == 1 || strategy == :cycle
        result = strategy == :cycle ? [values[mod1(i, len)] for i in 1:n] : fill(only(values), n)
    elseif strategy == :truncate
        target_len = min(len, n)
        result = collect(values[1:target_len])
        if target_len < n
            padded = Vector{Any}(missing, n)
            padded[1:target_len] .= result
            result = padded
        end
    elseif strategy == :padmissing
        result = Vector{Any}(missing, n)
        result[1:min(len, n)] .= values[1:min(len, n)]
    else
        error("Unknown commit alignment strategy: $strategy")
    end

    note = "committed vector length $len to dataset length $n using :$strategy"
    return result, note
end

function _target_column_name(var::Symbol, name)
    name !== nothing && return Symbol(name)

    parsed = _parse_qualified_name(var)
    parsed === nothing && return var

    _, column = parsed
    return column
end

function commit!(wb::Workbook,
                 var::Symbol;
                 to::Symbol,
                 name=nothing,
                 align::Symbol=:strict)
    haskey(wb.space.datasets, to) || error("Unknown dataset: :$to")

    df = wb.space.datasets[to]
    values = collect(getvar(wb, var))
    target_name = _target_column_name(var, name)
    committed_values, note = _align_to_length(values, nrow(df), align)

    df[!, target_name] = committed_values
    _rebuild_variables!(wb.space)

    note !== nothing && push!(wb.logs, string(to, ".", target_name, ": ", note))
    push!(wb.logs, string(to, ".", target_name, " <- commit!(", var, ")"))

    return df[!, target_name]
end
