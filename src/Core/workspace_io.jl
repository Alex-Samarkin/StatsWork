function save_workspace(wb::Workbook, file_path::AbstractString)
    save(file_path, "workbook", wb)
    return file_path
end

function load_workspace(file_path::AbstractString)
    data = load(file_path)
    haskey(data, "workbook") || error("Workspace file does not contain a workbook")
    return data["workbook"]
end
