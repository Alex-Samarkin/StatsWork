module StatsWorkbench

using DataFrames
using Statistics
using StatsBase
using Distributions
using Plots
using Markdown

include("Core/results.jl")
include("Core/variables.jl")
include("Core/data_util.jl")
include("Core/workbook.jl")

# Future extension points. These methods are declared now so the package can
# precompile before the corresponding modules are implemented.
function analyze end
function plot_report end
function text_report end
function save_report end

export Workbook,
       open_workbook,
       close_workbook!,
       add_dataset!,
       safe_load,
       save_data,
       vars,
       select_columns,
       analyze,
       plot_report,
       text_report,
       save_report

end
