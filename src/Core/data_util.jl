# Utility functions for data handling

using CSV, XLSX, JLD2, Parquet, DataFrames

# Check if a file exists at the given path
function file_exists(file_path::AbstractString)
    isfile(file_path)
end

# Load data from a file based on its extension
function load_data_from_file(file_path::AbstractString)
    if !file_exists(file_path)
        error("File not found: $file_path")
    end

    ext = lowercase(splitext(file_path)[2])
    if ext == ".csv"
        return CSV.read(file_path, DataFrame)
    elseif ext == ".xlsx"
        return XLSX.readtable(file_path, "Sheet1") |> DataFrame
    elseif ext == ".jld2"
        return load(file_path)
    elseif ext == ".parquet"
        return Parquet.File(file_path) |> DataFrame
    else
        error("Unsupported file format: $ext")
    end
end

# Load data from a URL (assuming it's a CSV for simplicity)
function load_data_from_url(url::AbstractString)
    try
        return CSV.read(download(url), DataFrame)
    catch e
        error("Failed to load data from URL: $url. Error: $(sprint(showerror, e))")
    end
end

# Load data from file or URL
function load_data(source::AbstractString)
    
    if startswith(source, "http://") || startswith(source, "https://")
        return load_data_from_url(source)
    else
        return load_data_from_file(source)
    end
end

# Save data to a file based on its extension
function save_data(data::DataFrame, file_path::AbstractString)
    ext = lowercase(splitext(file_path)[2])
    if ext == ".csv"
        CSV.write(file_path, data)
    elseif ext == ".xlsx"
        XLSX.writetable(file_path, data, "Sheet1")
    elseif ext == ".jld2"
        save(file_path, "data", data)
    elseif ext == ".parquet"
        Parquet.write(file_path, data)
    else
        error("Unsupported file format: $ext, need .csv, .xlsx, .jld2, or .parquet")
    end
end

# Handle typical errors when loading data and provide user-friendly messages
function handle_data_loading_error(e::Exception)
    if isa(e, ArgumentError)
        println("Argument error: $(sprint(showerror, e)). Please check the file path and format.")
    elseif isa(e, CSV.Error)
        println("CSV parsing error: $(sprint(showerror, e)). Please ensure the CSV file is properly formatted.")
    elseif isa(e, XLSX.XLSXError)
        println("XLSX error: $(sprint(showerror, e)). Please check the Excel file and sheet name.")
    elseif isa(e, JLD2.JLD2Error)
        println("JLD2 error: $(sprint(showerror, e)). Please ensure the JLD2 file is valid.")
    elseif isa(e, Parquet.ParquetError)
        println("Parquet error: $(sprint(showerror, e)). Please check the Parquet file format.")
    else
        println("An unexpected error occurred: $(sprint(showerror, e))")
    end
end

# safe version of load_data that handles errors gracefully
function safe_load_data(source::AbstractString)
    try
        return load_data(source)
    catch e
        handle_data_loading_error(e)
        return nothing
    end
end

safe_load(source::AbstractString) = safe_load_data(source)


