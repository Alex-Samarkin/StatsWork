module StatsWorkbench

using DataFrames
using Statistics
using StatsBase
using Distributions
using Plots
using Markdown

include("Core/results.jl")
include("Core/variables.jl")
include("Core/workbook.jl")

include("Data/data_space.jl")

include("Analysis/Analysis.jl")

include("Viz/Viz.jl")
include("Reports/Reports.jl")

export Workbook,
       open_workbook,
       close_workbook!,
       add_dataset!,
       vars,
       analyze,
       plot_report,
       text_report,
       save_report

end
