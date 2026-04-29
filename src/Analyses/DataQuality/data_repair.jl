module DataRepair

using DataFrames
using Statistics
using Plots

export diagnose,
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

const DQ_OK = 0
const DQ_WARNING = 1
const DQ_ERROR = 2

const MISSING_LIKE_STRINGS = Set([
    "", "na", "n/a", "nan", "null", "none", "missing", "-", "--", "—"
])

struct DataQualityDiagnosis
    map::DataFrame
    plot_data::Matrix{Int}
    columns::DataFrame
    frame::DataFrame
    actions::DataFrame
end

function Base.show(io::IO, dq::DataQualityDiagnosis)
    nrows = dq.frame[dq.frame.metric .== "nrows", :value][1]
    ncols = dq.frame[dq.frame.metric .== "ncols", :value][1]
    problem_cells = dq.frame[dq.frame.metric .== "problem_cells", :value][1]
    warning_cells = dq.frame[dq.frame.metric .== "warning_cells", :value][1]
    error_cells = dq.frame[dq.frame.metric .== "error_cells", :value][1]

    println(io, "DataQualityDiagnosis")
    println(io, "  size: $(nrows) × $(ncols)")
    println(io, "  problem cells: $(problem_cells)")
    println(io, "  warnings: $(warning_cells)")
    println(io, "  errors: $(error_cells)")
    println(io, "")
    println(io, "Use:")
    println(io, "  inspect(dq)              # summary by issue and column")
    println(io, "  inspect(dq; col=:name)   # issues in one column")
    println(io, "  inspect(dq; row=10)      # issues in one row")
end

function is_missing_like(x)
    if x === missing
        return true
    end

    if x isa AbstractFloat && isnan(x)
        return true
    end

    if x isa AbstractString
        s = strip(lowercase(x))
        return s in MISSING_LIKE_STRINGS
    end

    return false
end

function _remove_spaces(s::AbstractString)
    s = replace(s, " " => "")
    return replace(s, "\u00a0" => "")
end

"""
    parse_numeric_text(x)

Tries to parse strings such as `"12,5"`, `"1 234,56"`, `"1,234.56"`,
`"1.234,56"` into `Float64`. Returns `nothing` if parsing is not safe.
"""
function parse_numeric_text(x)
    if !(x isa AbstractString)
        return nothing
    end

    s = strip(x)
    isempty(s) && return nothing

    s = _remove_spaces(s)

    # Plain number with dot decimal separator.
    try
        return parse(Float64, s)
    catch
        # continue with locale-aware attempts
    end

    # European decimal comma: 1234,56 -> 1234.56
    if occursin(",", s) && !occursin(".", s)
        s2 = replace(s, "," => ".")
        try
            return parse(Float64, s2)
        catch
            return nothing
        end
    end

    # Both separators exist. The last separator is treated as decimal separator.
    if occursin(",", s) && occursin(".", s)
        last_comma = findlast(isequal(','), s)
        last_dot = findlast(isequal('.'), s)

        if last_comma === nothing || last_dot === nothing
            return nothing
        end

        if last_comma > last_dot
            # 1.234,56 -> 1234.56
            s2 = replace(s, "." => "")
            s2 = replace(s2, "," => ".")
        else
            # 1,234.56 -> 1234.56
            s2 = replace(s, "," => "")
        end

        try
            return parse(Float64, s2)
        catch
            return nothing
        end
    end

    return nothing
end

function _numeric_value(x)
    if x === missing
        return missing
    elseif x isa AbstractFloat && isnan(x)
        return missing
    elseif x isa Number
        return Float64(x)
    elseif x isa AbstractString
        is_missing_like(x) && return missing
        parsed = parse_numeric_text(x)
        return parsed === nothing ? missing : parsed
    else
        return missing
    end
end

function infer_role(col; numeric_threshold::Float64=0.80, categorical_threshold::Float64=0.30)
    vals = [x for x in col if !is_missing_like(x)]

    isempty(vals) && return :unknown

    if all(x -> x isa Bool, vals)
        return :boolean
    end

    if all(x -> x isa Number && !(x isa Bool), vals)
        return :numeric
    end

    numeric_like = count(x -> _numeric_value(x) !== missing, vals)
    numeric_ratio = numeric_like / length(vals)

    if numeric_ratio >= numeric_threshold
        return :numeric
    end

    if all(x -> x isa AbstractString, vals)
        unique_ratio = length(unique(vals)) / length(vals)
        return unique_ratio <= categorical_threshold ? :categorical : :text
    end

    return :unknown
end

function detect_outlier_flags(col; k::Float64=2.5)
    numeric_values = [_numeric_value(x) for x in col]
    vals = collect(skipmissing(numeric_values))

    flags = falses(length(col))

    length(vals) < 4 && return flags

    q1 = quantile(vals, 0.25)
    q3 = quantile(vals, 0.75)
    iqr = q3 - q1

    iqr == 0 && return flags

    lower = q1 - k * iqr
    upper = q3 + k * iqr

    for i in eachindex(numeric_values)
        v = numeric_values[i]
        if v !== missing
            flags[i] = v < lower || v > upper
        end
    end

    return flags
end

function _add_issue!(issue_map, plot_data, row, colindex, colname, value, status, issue, severity, recommendation)
    plot_data[row, colindex] = max(plot_data[row, colindex], severity)

    push!(issue_map, (
        row,
        Symbol(colname),
        value,
        status,
        issue,
        severity,
        recommendation
    ))

    return nothing
end

function _column_recommendation(role, pct_missing, n_missing, n_numeric_text, n_non_numeric_text, n_outliers)
    if pct_missing > 0.50
        return "consider_drop_column"
    elseif n_non_numeric_text > 0 && role == :numeric
        return "set_non_numeric_text_to_missing_or_review"
    elseif n_numeric_text > 0
        return "convert_numeric_text"
    elseif n_missing > 0 && role == :numeric
        return "impute_median"
    elseif n_missing > 0 && role in (:categorical, :text, :boolean, :unknown)
        return "impute_mode_or_constant"
    elseif n_outliers > 0
        return "review_or_winsorize"
    else
        return "ok"
    end
end

function _add_action!(actions, colname, action, method, reason; severity=:warning)
    push!(actions, (
        Symbol(colname),
        action,
        method,
        severity,
        reason
    ))
    return nothing
end

"""
    diagnose(df::DataFrame; outlier_k=2.5)

Builds a diagnostic object with:

- `dq.map`: long-form cell-level issue map;
- `dq.plot_data`: integer severity matrix, useful for static heatmaps;
- `dq.columns`: column-level summary;
- `dq.frame`: frame-level summary;
- `dq.actions`: proposed repair plan for a future `repair(df, dq)` function.
"""
function diagnose(df::DataFrame; outlier_k::Float64=2.5)
    n, p = size(df)

    issue_map = DataFrame(
        row = Int[],
        column = Symbol[],
        value = Any[],
        status = Symbol[],
        issue = String[],
        severity = Int[],
        recommendation = String[]
    )

    plot_data = zeros(Int, n, p)

    column_reports = DataFrame(
        column = Symbol[],
        eltype = String[],
        n = Int[],
        n_missing = Int[],
        pct_missing = Float64[],
        n_numeric_text = Int[],
        n_non_numeric_text = Int[],
        n_outliers = Int[],
        n_unique = Int[],
        inferred_role = Symbol[],
        recommendation = String[]
    )

    actions = DataFrame(
        column = Symbol[],
        action = Symbol[],
        method = Symbol[],
        severity = Symbol[],
        reason = String[]
    )

    for (j, colname) in enumerate(names(df))
        col = df[!, colname]
        role = infer_role(col)

        n_missing = 0
        n_numeric_text = 0
        n_non_numeric_text = 0
        n_outliers = 0

        outlier_flags = role == :numeric ? detect_outlier_flags(col; k=outlier_k) : falses(n)

        for i in 1:n
            v = col[i]

            if is_missing_like(v)
                n_missing += 1
                _add_issue!(
                    issue_map,
                    plot_data,
                    i,
                    j,
                    colname,
                    v,
                    :error,
                    "missing",
                    DQ_ERROR,
                    "impute_or_drop"
                )
            elseif v isa AbstractString
                parsed = parse_numeric_text(v)

                if parsed !== nothing && role == :numeric
                    n_numeric_text += 1
                    _add_issue!(
                        issue_map,
                        plot_data,
                        i,
                        j,
                        colname,
                        v,
                        :warning,
                        "numeric_text",
                        DQ_WARNING,
                        "convert_to_number"
                    )
                elseif parsed === nothing && role == :numeric
                    n_non_numeric_text += 1
                    _add_issue!(
                        issue_map,
                        plot_data,
                        i,
                        j,
                        colname,
                        v,
                        :error,
                        "non_numeric_text",
                        DQ_ERROR,
                        "set_missing_or_review"
                    )
                end
            end

            if outlier_flags[i]
                n_outliers += 1
                _add_issue!(
                    issue_map,
                    plot_data,
                    i,
                    j,
                    colname,
                    v,
                    :warning,
                    "outlier",
                    DQ_WARNING,
                    "winsorize_or_review"
                )
            end
        end

        pct_missing = n == 0 ? 0.0 : n_missing / n
        recommendation = _column_recommendation(
            role,
            pct_missing,
            n_missing,
            n_numeric_text,
            n_non_numeric_text,
            n_outliers
        )

        nonmissing_values = [x for x in col if !is_missing_like(x)]
        n_unique = isempty(nonmissing_values) ? 0 : length(unique(nonmissing_values))

        push!(column_reports, (
            Symbol(colname),
            string(eltype(col)),
            n,
            n_missing,
            pct_missing,
            n_numeric_text,
            n_non_numeric_text,
            n_outliers,
            n_unique,
            role,
            recommendation
        ))

        if n_numeric_text > 0
            _add_action!(
                actions,
                colname,
                :convert,
                :numeric_text,
                "column contains numeric values stored as text"
            )
        end

        if n_non_numeric_text > 0 && role == :numeric
            _add_action!(
                actions,
                colname,
                :replace,
                :missing,
                "numeric column contains non-numeric text values";
                severity=:error
            )
        end

        if n_missing > 0
            method = role == :numeric ? :median : :mode
            _add_action!(
                actions,
                colname,
                :impute,
                method,
                "column contains missing-like values";
                severity=:error
            )
        end

        if n_outliers > 0
            _add_action!(
                actions,
                colname,
                :repair_outliers,
                :winsorize,
                "column contains potential outliers"
            )
        end
    end

    problem_cells = count(!=(DQ_OK), plot_data)
    warning_cells = count(==(DQ_WARNING), plot_data)
    error_cells = count(==(DQ_ERROR), plot_data)

    frame_report = DataFrame(
        metric = [
            "nrows",
            "ncols",
            "total_cells",
            "problem_cells",
            "warning_cells",
            "error_cells",
            "pct_problem_cells",
            "columns_with_missing",
            "columns_with_numeric_text",
            "columns_with_non_numeric_text",
            "columns_with_outliers",
            "duplicate_rows"
        ],
        value = Any[
            n,
            p,
            n * p,
            problem_cells,
            warning_cells,
            error_cells,
            n * p == 0 ? 0.0 : problem_cells / (n * p),
            count(column_reports.n_missing .> 0),
            count(column_reports.n_numeric_text .> 0),
            count(column_reports.n_non_numeric_text .> 0),
            count(column_reports.n_outliers .> 0),
            n - nrow(unique(df))
        ]
    )

    return DataQualityDiagnosis(
        issue_map,
        plot_data,
        column_reports,
        frame_report,
        actions
    )
end

"""
    error_summary(dq; by=:issue, sort_by_total=true)

Returns a wide table: one row per column, one count column per issue type or status.
Examples:

    error_summary(dq)
    error_summary(dq; by=:status)
"""
function error_summary(dq::DataQualityDiagnosis; by::Symbol=:issue, sort_by_total::Bool=true)
    df = dq.map

    if isempty(df)
        return DataFrame(column = Symbol[], total = Int[])
    end

    allowed = Set(names(df))
    by_name = string(by)
    by_name in allowed || throw(ArgumentError("`by` must be one of $(collect(allowed))"))

    g = combine(groupby(df, [:column, by]), nrow => :count)
    wide = unstack(g, by, :count)

    for c in names(wide)
        c == "column" && continue
        wide[!, c] = coalesce.(wide[!, c], 0)
    end

    value_cols = setdiff(names(wide), ["column"])
    wide.total = isempty(value_cols) ? zeros(Int, nrow(wide)) : vec(sum(Matrix(wide[:, value_cols]); dims=2))

    if sort_by_total
        sort!(wide, :total, rev=true)
    end

    return wide
end

function issue_summary(dq::DataQualityDiagnosis)
    isempty(dq.map) && return DataFrame(issue=String[], count=Int[])
    return sort(combine(groupby(dq.map, :issue), nrow => :count), :count, rev=true)
end

function column_score(dq::DataQualityDiagnosis)
    isempty(dq.map) && return DataFrame(column=Symbol[], score=Int[], n_issues=Int[])

    scores = combine(
        groupby(dq.map, :column),
        :severity => sum => :score,
        nrow => :n_issues
    )

    return sort(scores, :score, rev=true)
end

function issues(dq::DataQualityDiagnosis, col::Symbol)
    return filter(:column => ==(col), dq.map)
end

function issues_summary(dq::DataQualityDiagnosis, col::Symbol)
    df = issues(dq, col)
    isempty(df) && return DataFrame(issue=String[], count=Int[])
    return sort(combine(groupby(df, :issue), nrow => :count), :count, rev=true)
end

function rows_with_issues(dq::DataQualityDiagnosis, col::Symbol)
    df = issues(dq, col)
    isempty(df) && return Int[]
    return sort(unique(df.row))
end

function view_rows(df::DataFrame, dq::DataQualityDiagnosis, col::Symbol; n::Int=20)
    rows = rows_with_issues(dq, col)
    isempty(rows) && return first(df, 0)
    selected = rows[1:min(length(rows), n)]
    return df[selected, :]
end

function inspect_row(dq::DataQualityDiagnosis, row::Int)
    return filter(:row => ==(row), dq.map)
end

function highlight_row(df::DataFrame, dq::DataQualityDiagnosis, row::Int)
    1 <= row <= nrow(df) || throw(BoundsError(df, row))

    row_issues = inspect_row(dq, row)
    issue_dict = Dict{Symbol, Vector{String}}()

    for r in eachrow(row_issues)
        if !haskey(issue_dict, r.column)
            issue_dict[r.column] = String[]
        end
        push!(issue_dict[r.column], r.issue)
    end

    out = DataFrame(
        column = Symbol[],
        value = Any[],
        issue = String[],
        status = String[]
    )

    for c in names(df)
        csym = Symbol(c)
        issues_for_col = get(issue_dict, csym, String[])
        status = isempty(issues_for_col) ? "ok" : join(unique(issues_for_col), ", ")
        push!(out, (
            csym,
            df[row, c],
            status == "ok" ? "" : status,
            status == "ok" ? "ok" : "problem"
        ))
    end

    return out
end

"""
    inspect(dq; col=nothing, row=nothing)

Small REPL-friendly navigator:

- `inspect(dq)` returns a summary by issue and column;
- `inspect(dq; col=:income)` returns all issues in the column;
- `inspect(dq; row=12)` returns all issues in the row.
"""
function inspect(dq::DataQualityDiagnosis; col=nothing, row=nothing)
    if col !== nothing && row !== nothing
        throw(ArgumentError("use either `col` or `row`, not both"))
    elseif col !== nothing
        return issues(dq, Symbol(col))
    elseif row !== nothing
        return inspect_row(dq, Int(row))
    else
        return error_summary(dq)
    end
end

function plot_error_summary(dq::DataQualityDiagnosis)
    summary = error_summary(dq)

    if nrow(summary) == 0
        return plot(title="Нет найденных проблем качества данных")
    end

    cols = setdiff(names(summary), ["column", "total"])
    mat = Matrix(summary[:, cols])

    return heatmap(
        cols,
        string.(summary.column),
        mat,
        xlabel = "Тип ошибки",
        ylabel = "Колонка",
        title = "Карта ошибок по колонкам",
        colorbar = true
    )
end

function plot_error_bars(dq::DataQualityDiagnosis)
    summary = error_summary(dq)

    if nrow(summary) == 0
        return plot(title="Нет найденных проблем качества данных")
    end

    cols = setdiff(names(summary), ["column", "total"])

    return bar(
        string.(summary.column),
        eachcol(Matrix(summary[:, cols])),
        label = reshape(cols, 1, :),
        title = "Ошибки по колонкам",
        xlabel = "Колонка",
        ylabel = "Количество",
        legend = :topright,
        xrotation = 45
    )
end

end
