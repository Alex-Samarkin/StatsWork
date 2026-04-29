mutable struct Workbook
    name::String
    space::VariableSpace
    results::Vector{AbstractAnalysisResult}
    logs::Vector{String}
    closed::Bool
end

function open_workbook(name="Workbook")
    Workbook(name, VariableSpace(), AbstractAnalysisResult[], String[], false)
end

function add_dataset!(wb::Workbook, name::Symbol, df)
    register_dataset!(wb.space, name, df)
    return df
end

function add_dataset!(wb::Workbook, name::Symbol, source::AbstractString)
    df = safe_load(source)
    isnothing(df) && return nothing

    register_dataset!(wb.space, name, df)
    return df
end

vars(wb::Workbook) = vars(wb.space)

getvar(wb::Workbook, var::Symbol) = getvar(wb.space, var)

function add_result!(wb::Workbook, result::AbstractAnalysisResult)
    push!(wb.results, result)
    push!(wb.logs, "result <- " * string(typeof(result)))
    return result
end

function close_workbook!(wb::Workbook)
    wb.closed = true
end
