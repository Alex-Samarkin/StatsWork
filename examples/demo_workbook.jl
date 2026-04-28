using Pkg
Pkg.activate(joinpath(@__DIR__, ".."))

using Revise
using DataFrames
using Statistics

if isdefined(Main, :StatsWorkbench)
    # VS Code's REPL keeps `Main` alive between runs. Reuse the already loaded module.
    Core.eval(Main, :(using .StatsWorkbench))
else
    Core.eval(Main, :(using StatsWorkbench))
end

using .StatsWorkbench

# ============================================================
# Demo: data loading + data quality diagnosis + workbook usage
# ============================================================

# 1. Load external data into a DataFrame.
df = safe_load("./examples/patients_3500.csv")
println("Loaded dataset size: ", size(df))

# 2. Run diagnostics.
dq = diagnose(df)
println()
println(dq)

# 3. Frame-level summary.
println("\n=== Frame report ===")
show(dq.frame; allrows=true, allcols=true)
println()

# 4. Column-level summary.
println("\n=== Column report: most problematic columns first ===")
col_report = leftjoin(dq.columns, column_score(dq), on=:column)
col_report.score = coalesce.(col_report.score, 0)
col_report.n_issues = coalesce.(col_report.n_issues, 0)
sort!(col_report, [:score, :n_issues], rev=true)
show(first(col_report, min(15, nrow(col_report))); allcols=true)
println()

# 5. Error map aggregated by issue type and column.
println("\n=== Error summary by issue type ===")
summary_by_issue = inspect(dq)
show(summary_by_issue; allcols=true)
println()

# 6. Same map, but aggregated by status: warning / error.
println("\n=== Error summary by severity status ===")
summary_by_status = error_summary(dq; by=:status)
show(summary_by_status; allcols=true)
println()

# 7. Overall issue ranking.
println("\n=== Issue type ranking ===")
show(issue_summary(dq); allrows=true, allcols=true)
println()

# 8. Drill-down into the most problematic column.
if nrow(summary_by_issue) > 0
    selected_col = summary_by_issue.column[1]

    println("\n=== Drill-down column: ", selected_col, " ===")
    show(issues_summary(dq, selected_col); allrows=true, allcols=true)
    println()

    println("\nProblem rows in ", selected_col, ":")
    println(rows_with_issues(dq, selected_col)[1:min(20, length(rows_with_issues(dq, selected_col)))])

    println("\n=== Source rows with issues in ", selected_col, " ===")
    show(view_rows(df, dq, selected_col; n=10); allcols=true)
    println()

    # 9. Drill-down into one row.
    example_rows = rows_with_issues(dq, selected_col)
    if !isempty(example_rows)
        selected_row = first(example_rows)

        println("\n=== Issues in row ", selected_row, " ===")
        show(inspect(dq; row=selected_row); allrows=true, allcols=true)
        println()

        println("\n=== Highlighted row ", selected_row, " ===")
        show(highlight_row(df, dq, selected_row); allrows=true, allcols=true)
        println()
    end
end

# 10. Proposed repair plan. This will be used later by repair(df, dq).
println("\n=== Proposed repair actions ===")
show(dq.actions; allrows=true, allcols=true)
println()

# 11. Optional static plots. Uncomment if you want visual output.
plot_error_summary(dq)
plot_error_bars(dq)

# 12. Put the dataset into the workbook / variable space.
wb = open_workbook("Demo")
add_dataset!(wb, :data, df)

println("\n=== Workbook variables ===")
println(vars(wb))

close_workbook!(wb)
