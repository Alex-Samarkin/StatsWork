mutable struct Workbook
    name::String
    space::VariableSpace
    results::Vector{AbstractAnalysisResult}
    logs::Vector{String}
    closed::Bool
end

function open_workbook(name="Workbook")
    Workbook(name, VariableSpace(), [], String[], false)
end

function add_dataset!(wb::Workbook, name::Symbol, df)
    register_dataset!(wb.space, name, df)
end

vars(wb::Workbook) = vars(wb.space)

function close_workbook!(wb::Workbook)
    wb.closed = true
end
