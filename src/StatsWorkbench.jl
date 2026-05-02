module StatsWorkbench

using DataFrames
using Statistics
using StatsBase
using Distributions
using Plots
using Markdown
using Random
using XLSX

# Base extension points are declared before includes so downstream files can
# safely add methods to them during module loading.
function analyze end
function plot_report end
function text_report end
function save_report end

include("Core/results.jl")
include("Core/vector_store.jl")
include("Core/variables.jl")
include("Core/data_util.jl")
include("Core/workbook.jl")
include("Core/vector_math.jl")
include("Core/dataset_commit.jl")
include("Core/workspace_io.jl")
include("Core/graphics.jl")
include("Core/gui_input.jl")

include("Analyses/DataQuality/data_repair.jl")
include("Analyses/DataTransform/auto_recode_analysis.jl")
include("Analyses/Exploratory/descriptive_stats_analysis.jl")
include("Analyses/Exploratory/single_variable_descriptive_analysis.jl")
include("Analyses/Exploratory/single_variable_interval_estimates_analysis.jl")
include("Analyses/Exploratory/normality_analysis.jl")
include("Analyses/Graphics/scatterplot_analysis.jl")
include("Analyses/Graphics/histogram_analysis.jl")
include("Analyses/Graphics/boxplot_analysis.jl")
include("Analyses/DataGenerators/integer_sequence_generator.jl")
include("Analyses/DataGenerators/random_integer_generator.jl")
include("Analyses/DataGenerators/random_continuous_generator.jl")
include("Analyses/DataGenerators/random_continuous_generator2.jl")

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

using .GUInput: GUIInput, input_int, input_float, select_option, select_options

export Workbook,
       GUInput,
       GUIInput,
       input_int,
       input_float,
       select_option,
       select_options,
       open_workbook,
       close_workbook!,
       add_dataset!,
       add_result!,
       safe_load,
       save_data,
       vars,
       getvar,
       calc!,
       align_vectors,
       store_vector!,
       commit!,
       save_workspace,
       load_workspace,
       select_columns,
       AbstractAnalysis,
       AbstractAnalysisResult,
       FormulaSpec,
       AnalysisInfo,
       AnalysisTable,
       PlotSpec,
       BaseAnalysisResult,
       AutoRecodeAnalysis,
       DescriptiveStatsAnalysis,
       SingleVariableDescriptiveAnalysis,
       SingleVariableIntervalEstimatesAnalysis,
       NormalityAnalysis,
       ScatterplotAnalysis,
       HistogramAnalysis,
       BoxplotAnalysis,
       IntegerSequenceGeneratorAnalysis,
       RandomIntegerGeneratorAnalysis,
       RandomContinuousGeneratorAnalysis,
       RandomContinuousGenerator2Analysis,
       analysis_info,
       required_variables,
       produced_variables,
       add_table!,
       add_plot!,
       result_tables,
       result_plots,
       result_calculations,
       table_dataframe,
       to_table,
       to_markdown,
       to_html,
       available_plot_palettes,
       default_plot_config,
       render_result_plot,
       render_result_plots,
       plot1,
       plot2,
       plot3,
       plot4,
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
