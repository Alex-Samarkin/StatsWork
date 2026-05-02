using Pkg
Pkg.activate(joinpath(@__DIR__, ".."))

using Revise
using DataFrames

if isdefined(Main, :StatsWorkbench)
    Core.eval(Main, :(using .StatsWorkbench))
else
    Core.eval(Main, :(using StatsWorkbench))
end

using .StatsWorkbench
const SW = StatsWorkbench

# Минимальный пример: создаём workbook и загружаем в него patients_3500.
wb = open_workbook("Demo Workbook 2")
df = add_dataset!(wb, :patients_3500, "./examples/patients_3500.csv")

println("=== Workbook ===")
println(wb.name)

println("\n=== Loaded dataset size ===")
println(size(df))

println("\n=== Workbook variables ===")
println(vars(wb))

println("\n=== Preview ===")
show(first(df, 10); allcols=true)
println()

println("\n=== Access example: height_cm ===")
println(first(SW.getvar(wb, :height_cm), 10))

height_analysis = SW.SingleVariableDescriptiveAnalysis(
    :height_cm;
    variation_name=:height_cm_variation_series,
    normal_overlay=true,
    palette_name=:colorful
)
height_result = SW.analyze(wb, height_analysis)

weight_analysis = SW.SingleVariableDescriptiveAnalysis(
    :weight_kg;
    variation_name=:weight_kg_variation_series,
    normal_overlay=true,
    palette_name=:contrast
)
weight_result = SW.analyze(wb, weight_analysis)

height_normality_analysis = SW.NormalityAnalysis(
    :height_cm;
    P=0.95,
    ks_corrected_simulations=500,
    palette_name=:colorful
)
height_normality_result = SW.analyze(wb, height_normality_analysis)

height_scatter_analysis = SW.ScatterplotAnalysis(:height_cm)
height_scatter_result = SW.analyze(wb, height_scatter_analysis)

weight_by_sex_scatter_analysis = SW.ScatterplotAnalysis(:weight_kg; by=:sex)
weight_by_sex_scatter_result = SW.analyze(wb, weight_by_sex_scatter_analysis)

height_hist_analysis = SW.HistogramAnalysis(:height_cm)
height_hist_result = SW.analyze(wb, height_hist_analysis)

weight_by_sex_hist_analysis = SW.HistogramAnalysis(:weight_kg; by=:sex, kde=true)
weight_by_sex_hist_result = SW.analyze(wb, weight_by_sex_hist_analysis)

height_box_analysis = SW.BoxplotAnalysis(:height_cm)
height_box_result = SW.analyze(wb, height_box_analysis)

weight_by_sex_box_analysis = SW.BoxplotAnalysis(:weight_kg; by=:sex)
weight_by_sex_box_result = SW.analyze(wb, weight_by_sex_box_analysis)

println("\n=== Height descriptive summary ===")
show(SW.to_table(height_result); allrows=true, allcols=true)
println("\n=== Weight descriptive summary ===")
show(SW.to_table(weight_result); allrows=true, allcols=true)
println("\n=== Height normality tests ===")
show(SW.to_table(height_normality_result; table=:normality_tests); allrows=true, allcols=true)
println("\n=== Height scatter summary ===")
show(SW.to_table(height_scatter_result); allrows=true, allcols=true)
println("\n=== Weight-by-sex scatter summary ===")
show(SW.to_table(weight_by_sex_scatter_result); allrows=true, allcols=true)
println("\n=== Height histogram summary ===")
show(SW.to_table(height_hist_result); allrows=true, allcols=true)
println("\n=== Weight-by-sex histogram summary ===")
show(SW.to_table(weight_by_sex_hist_result); allrows=true, allcols=true)
println("\n=== Height boxplot summary ===")
show(SW.to_table(height_box_result); allrows=true, allcols=true)
println("\n=== Weight-by-sex boxplot summary ===")
show(SW.to_table(weight_by_sex_box_result); allrows=true, allcols=true)

height_histogram_plot = SW.plot1(height_result)
height_histogram_boxplot = SW.plot2(height_result)
height_qq_plot = SW.plot3(height_result)

weight_histogram_plot = SW.plot1(weight_result)
weight_histogram_boxplot = SW.plot2(weight_result)
weight_qq_plot = SW.plot3(weight_result)

height_normality_histogram_plot = SW.plot1(height_normality_result)
height_normality_cdf_plot = SW.plot2(height_normality_result)
height_normality_cumulative_plot = SW.plot3(height_normality_result)
height_normality_qq_plot = SW.plot4(height_normality_result)

height_scatter_plot = SW.plot1(height_scatter_result)
weight_by_sex_scatter_plot = SW.plot1(weight_by_sex_scatter_result)
height_hist_plot2 = SW.plot1(height_hist_result)
weight_by_sex_hist_plot2 = SW.plot1(weight_by_sex_hist_result)
height_box_plot = SW.plot1(height_box_result)
height_box_violin_plot = SW.plot2(height_box_result)
height_box_points_plot = SW.plot3(height_box_result)
weight_by_sex_box_plot = SW.plot1(weight_by_sex_box_result)
weight_by_sex_box_violin_plot = SW.plot2(weight_by_sex_box_result)
weight_by_sex_box_points_plot = SW.plot3(weight_by_sex_box_result)

# После установки Gadfly эти объекты можно показать прямо в IDE.
# Для сохранения в PNG/SVG можно использовать `Gadfly.draw(...)`.

close_workbook!(wb)
