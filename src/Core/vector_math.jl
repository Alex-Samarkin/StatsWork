const DEFAULT_VECTOR_NAMESPACE = :calc

function _operand_values(wb::Workbook, operand)
    if operand isa Symbol
        return collect(getvar(wb, operand))
    elseif operand isa AbstractVector
        return collect(operand)
    else
        return [operand]
    end
end

function _resize_vector(values::AbstractVector, n::Int, strategy::Symbol)
    len = length(values)

    if len == n
        return collect(values)
    elseif len == 1
        return fill(only(values), n)
    elseif strategy == :truncate || strategy == :auto || strategy == :scalar_or_truncate
        return collect(values[1:min(len, n)])
    elseif strategy == :padmissing
        result = Vector{Any}(missing, n)
        result[1:min(len, n)] .= values[1:min(len, n)]
        return result
    elseif strategy == :cycle
        return [values[mod1(i, len)] for i in 1:n]
    elseif strategy == :strict
        error("Vector length mismatch: expected $n, got $len")
    end

    error("Unknown alignment strategy: $strategy")
end

function align_vectors(left::AbstractVector,
                       right::AbstractVector;
                       strategy::Symbol=:auto)
    left_len = length(left)
    right_len = length(right)

    if strategy == :strict
        if left_len == right_len
            return collect(left), collect(right), nothing
        elseif left_len == 1 || right_len == 1
            n = max(left_len, right_len)
            return _resize_vector(left, n, strategy),
                   _resize_vector(right, n, strategy),
                   nothing
        end

        error("Vector length mismatch: left has $left_len, right has $right_len")
    end

    n = if strategy == :padmissing || strategy == :cycle
        max(left_len, right_len)
    else
        left_len == 1 ? right_len :
        right_len == 1 ? left_len :
        min(left_len, right_len)
    end

    aligned_left = _resize_vector(left, n, strategy)
    aligned_right = _resize_vector(right, n, strategy)

    note = left_len == right_len ? nothing :
           "aligned vector lengths $left_len and $right_len to $n using :$strategy"

    return aligned_left, aligned_right, note
end

function _record_alignment!(wb::Workbook, namespace::Symbol, target::Symbol, note)
    note === nothing && return nothing
    push!(wb.logs, string(namespace, ".", target, ": ", note))
    return note
end

function _operation_expression(target::Symbol, left, op::Function, right)
    return string(target, " = ", left, " ", op, " ", right)
end

function calc!(wb::Workbook,
               target::Symbol,
               left,
               op::Function,
               right;
               namespace::Symbol=DEFAULT_VECTOR_NAMESPACE,
               align::Symbol=:auto)
    left_values = _operand_values(wb, left)
    right_values = _operand_values(wb, right)
    aligned_left, aligned_right, note = align_vectors(left_values, right_values;
                                                     strategy=align)

    result = op.(aligned_left, aligned_right)
    _record_alignment!(wb, namespace, target, note)
    expression = _operation_expression(target, left, op, right)
    push!(wb.logs, string(namespace, ".", target, " <- ", expression))

    return store_vector!(wb.space, namespace, target, result;
                         origin=:computed,
                         dirty=true,
                         expression=expression)
end

function calc!(wb::Workbook,
               target::Symbol,
               op::Function,
               source;
               namespace::Symbol=DEFAULT_VECTOR_NAMESPACE)
    source_values = _operand_values(wb, source)
    result = op.(source_values)
    expression = string(target, " = ", op, "(", source, ")")
    push!(wb.logs, string(namespace, ".", target, " <- ", expression))

    return store_vector!(wb.space, namespace, target, result;
                         origin=:computed,
                         dirty=true,
                         expression=expression)
end
