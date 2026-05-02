"""
    HistogramAnalysis

Графический анализ для построения гистограммы одной числовой переменной.
Если задан `by`, данные разбиваются на несколько категорий, которые
отображаются на общей оси X разными цветами.
"""
struct HistogramAnalysis <: AbstractAnalysis
    info::AnalysisInfo
    variable::Symbol
    by::Union{Nothing, Symbol}
    kde::Bool
    palette_name::Symbol
    width::Int
    height::Int
end

"""
    HistogramAnalysis(variable; by=nothing, kde=true, ...)

Создаёт анализ категории `Graphics`. Без `by` строится одна гистограмма по
всем данным. С `by` строятся гистограммы нескольких категорий на общей оси X.
Опционально поверх добавляется KDE-кривая; по умолчанию `kde=true`.
"""
function HistogramAnalysis(variable::Symbol;
                           by::Union{Nothing, Symbol}=nothing,
                           kde::Bool=true,
                           palette_name::Symbol=:colorful,
                           width::Int=1900,
                           height::Int=600,
                           id::Symbol=:histogram,
                           category_path::AbstractVector{Symbol}=[:graphics, :histograms],
                           title::AbstractString="Histogram",
                           summary::AbstractString="Строит гистограмму одной числовой переменной и поддерживает разбиение по категориям через `by`.",
                           description::AbstractString="Анализ очищает числовые значения, при необходимости связывает их с категориями второй переменной и готовит гистограмму через Gadfly. KDE можно включать и выключать параметром `kde`.",
                           interpretation::AbstractString="Гистограмма помогает оценить форму распределения, диапазон значений, возможную мультимодальность и различия между категориями.")
    palette_name in available_plot_palettes() || error("Unsupported palette name: $palette_name")
    width > 0 || error("`width` must be positive")
    height > 0 || error("`height` must be positive")

    info = AnalysisInfo(
        id;
        category_path=category_path,
        title=title,
        summary=summary,
        description=description,
        interpretation=interpretation,
        formulas=[
            FormulaSpec("hist(x)", "Без `by` строится одна гистограмма по всем наблюдениям."),
            FormulaSpec("hist(x | group)", "С `by` данные делятся на категории и показываются на общей оси X."),
            FormulaSpec("kde(x)", "Если `kde=true`, поверх добавляется сглаженная оценка плотности.")
        ],
        notes=[
            "В график включаются только конечные числовые значения.",
            "Если `by` задан, строки с missing в группировке исключаются из графика."
        ]
    )

    return HistogramAnalysis(info, variable, by, kde, palette_name, width, height)
end

analysis_info(analysis::HistogramAnalysis) = analysis.info

function required_variables(analysis::HistogramAnalysis)
    analysis.by === nothing && return [analysis.variable]
    return [analysis.variable, analysis.by]
end

produced_variables(::HistogramAnalysis) = Symbol[]

function _histogram_rows(values, by_values::Nothing)
    rows = Dict{Symbol, Any}[]
    skipped = 0

    for value in values
        if value === missing
            skipped += 1
        elseif value isa Number
            numeric = Float64(value)
            if isfinite(numeric)
                push!(rows, Dict(:value => numeric))
            else
                skipped += 1
            end
        else
            skipped += 1
        end
    end

    return rows, skipped
end

function _histogram_rows(values, by_values)
    length(values) == length(by_values) || error("Variables `values` and `by` must have the same length")

    rows = Dict{Symbol, Any}[]
    skipped = 0

    for index in eachindex(values, by_values)
        value = values[index]
        group = by_values[index]

        if value === missing || group === missing
            skipped += 1
        elseif value isa Number
            numeric = Float64(value)
            if isfinite(numeric)
                push!(rows, Dict(:group => string(group), :value => numeric))
            else
                skipped += 1
            end
        else
            skipped += 1
        end
    end

    return rows, skipped
end

function analyze(wb, analysis::HistogramAnalysis; store::Bool=true)
    raw_values = getvar(wb, analysis.variable)
    raw_groups = analysis.by === nothing ? nothing : getvar(wb, analysis.by)
    rows, skipped = _histogram_rows(raw_values, raw_groups)
    isempty(rows) && error("Histogram analysis has no valid rows after cleaning")

    plot_df = DataFrame(rows)
    count_value = nrow(plot_df)
    mode = analysis.by === nothing ? :single : :group

    calculations = Dict{Symbol, Any}(
        :variable => analysis.variable,
        :by => analysis.by,
        :kde => analysis.kde,
        :count => count_value,
        :skipped => skipped,
        :minimum => minimum(plot_df.value),
        :maximum => maximum(plot_df.value),
        :mean => mean(plot_df.value)
    )

    result = BaseAnalysisResult(
        analysis.info;
        input_variables=required_variables(analysis),
        analysis_data=Dict(
            :analysis_type => :histogram,
            :mode => mode,
            :kde => analysis.kde
        ),
        calculations=calculations
    )

    add_table!(result, AnalysisTable(
        :summary,
        "Histogram summary",
        [:metric, :value];
        headers=Dict(:metric => "Metric", :value => "Value"),
        rows=[
            Dict(:metric => "variable", :value => String(analysis.variable)),
            Dict(:metric => "by", :value => analysis.by === nothing ? "none" : String(analysis.by)),
            Dict(:metric => "kde", :value => analysis.kde),
            Dict(:metric => "count", :value => count_value),
            Dict(:metric => "skipped", :value => skipped),
            Dict(:metric => "minimum", :value => calculations[:minimum]),
            Dict(:metric => "maximum", :value => calculations[:maximum]),
            Dict(:metric => "mean", :value => calculations[:mean])
        ]
    ))

    preview_columns = analysis.by === nothing ? [:value] : [:group, :value]
    preview_headers = Dict(:value => "Value")
    if analysis.by !== nothing
        preview_headers[:group] = "Group"
    end
    add_table!(result, AnalysisTable(
        :preview,
        "Histogram data preview",
        preview_columns;
        headers=preview_headers,
        rows=rows[1:min(length(rows), 25)]
    ))

    if analysis.by !== nothing
        grouped = combine(
            groupby(plot_df, :group),
            nrow => :count,
            :value => mean => :mean,
            :value => minimum => :minimum,
            :value => maximum => :maximum
        )

        add_table!(result, AnalysisTable(
            :groups,
            "Group summary",
            [:group, :count, :mean, :minimum, :maximum];
            headers=Dict(
                :group => "Group",
                :count => "Count",
                :mean => "Mean",
                :minimum => "Minimum",
                :maximum => "Maximum"
            ),
            rows=[Dict(
                :group => row.group,
                :count => row.count,
                :mean => row.mean,
                :minimum => row.minimum,
                :maximum => row.maximum
            ) for row in eachrow(grouped)]
        ))
    end

    add_plot!(result, PlotSpec(
        :histogram,
        analysis.by === nothing ? "Histogram" : "Histogram with grouped categories",
        :gadfly_histogram;
        payload=Dict(
            :data => plot_df,
            :mode => mode,
            :variable_label => string(analysis.variable),
            :group_label => analysis.by === nothing ? "" : string(analysis.by),
            :kde => analysis.kde,
            :palette_name => analysis.palette_name,
            :width => analysis.width,
            :height => analysis.height
        )
    ))

    if store
        add_result!(wb, result)
    end

    return result
end
