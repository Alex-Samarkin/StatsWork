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
include("Core/data_repair.jl")
include("Core/workbook.jl")

using .DataRepair: diagnose,
                   DataQualityDiagnosis,
                   error_summary,
                   issue_summary,
                   column_score,
                   issues,
                   issues_summary,
                   rows_with_issues,
                   view_rows,
                   inspect_row,
                   highlight_row,
                   inspect,
                   plot_error_summary,
                   plot_error_bars

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
       save_report,
       diagnose,
       DataQualityDiagnosis,
       error_summary,
       issue_summary,
       column_score,
       issues,
       issues_summary,
       rows_with_issues,
       view_rows,
       inspect_row,
       highlight_row,
       inspect,
       plot_error_summary,
       plot_error_bars

end
