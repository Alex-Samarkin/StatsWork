"""
    ScatterplotAnalysis

Графический анализ, который строит scatterplot для одной числовой переменной.
Если указан `by`, значения делятся на группы по второй переменной и
отрисовываются как точки по категориям.
"""
struct ScatterplotAnalysis <: AbstractAnalysis
    info::AnalysisInfo
    variable::Symbol
    by::Union{Nothing, Symbol}
    palette_name::Symbol
    width::Int
    height::Int
end

"""
    ScatterplotAnalysis(variable; by=nothing, ...)

Создаёт анализ категории `Graphics`. Без `by` строится scatterplot значений по
индексу наблюдения. С `by` строится grouped scatterplot: по оси X идут
категории из `by`, по оси Y - значения `variable`.
"""
function ScatterplotAnalysis(variable::Symbol;
                             by::Union{Nothing, Symbol}=nothing,
                             palette_name::Symbol=:colorful,
                             width::Int=1900,
                             height::Int=600,
                             id::Symbol=:scatterplot,
                             category_path::AbstractVector{Symbol}=[:graphics, :scatterplots],
                             title::AbstractString="Scatterplot",
                             summary::AbstractString="Строит scatterplot для одной числовой переменной и поддерживает группировку через параметр `by`.",
                             description::AbstractString="Анализ очищает числовые значения, при необходимости связывает их с категориями второй переменной и готовит график через Gadfly.",
                             interpretation::AbstractString="Scatterplot помогает быстро увидеть разброс значений, выбросы и различия между группами.")
    info = AnalysisInfo(
        id;
        category_path=category_path,
        title=title,
        summary=summary,
        description=description,
        interpretation=interpretation,
        formulas=[
            FormulaSpec("x = 1:n, y = values", "Без `by` по оси X используется индекс наблюдения."),
            FormulaSpec("x = group, y = values", "С `by` по оси X используются категории группировки.")
        ],
        notes=[
            "В график включаются только конечные числовые значения.",
            "Если `by` задан, строки с missing в группировке исключаются из графика."
        ]
    )

    palette_name in available_plot_palettes() || error("Unsupported palette name: $palette_name")
    width > 0 || error("`width` must be positive")
    height > 0 || error("`height` must be positive")

    return ScatterplotAnalysis(info, variable, by, palette_name, width, height)
end

analysis_info(analysis::ScatterplotAnalysis) = analysis.info

function required_variables(analysis::ScatterplotAnalysis)
    analysis.by === nothing && return [analysis.variable]
    return [analysis.variable, analysis.by]
end

produced_variables(::ScatterplotAnalysis) = Symbol[]

function _scatterplot_rows(values, by_values::Nothing)
    rows = Dict{Symbol, Any}[]
    skipped = 0

    for (index, value) in enumerate(values)
        if value === missing
            skipped += 1
        elseif value isa Number
            numeric = Float64(value)
            if isfinite(numeric)
                push!(rows, Dict(:observation => index, :value => numeric))
            else
                skipped += 1
            end
        else
            skipped += 1
        end
    end

    return rows, skipped
end

function _scatterplot_rows(values, by_values)
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
                push!(rows, Dict(
                    :observation => index,
                    :group => string(group),
                    :value => numeric
                ))
            else
                skipped += 1
            end
        else
            skipped += 1
        end
    end

    return rows, skipped
end

function analyze(wb, analysis::ScatterplotAnalysis; store::Bool=true)
    raw_values = getvar(wb, analysis.variable)
    raw_groups = analysis.by === nothing ? nothing : getvar(wb, analysis.by)
    rows, skipped = _scatterplot_rows(raw_values, raw_groups)
    isempty(rows) && error("Scatterplot analysis has no valid rows after cleaning")

    plot_df = DataFrame(rows)
    count_value = nrow(plot_df)
    mode = analysis.by === nothing ? :index : :group

    calculations = Dict{Symbol, Any}(
        :variable => analysis.variable,
        :by => analysis.by,
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
            :analysis_type => :scatterplot,
            :mode => mode
        ),
        calculations=calculations
    )

    add_table!(result, AnalysisTable(
        :summary,
        "Scatterplot summary",
        [:metric, :value];
        headers=Dict(:metric => "Metric", :value => "Value"),
        rows=[
            Dict(:metric => "variable", :value => String(analysis.variable)),
            Dict(:metric => "by", :value => analysis.by === nothing ? "none" : String(analysis.by)),
            Dict(:metric => "count", :value => count_value),
            Dict(:metric => "skipped", :value => skipped),
            Dict(:metric => "minimum", :value => calculations[:minimum]),
            Dict(:metric => "maximum", :value => calculations[:maximum]),
            Dict(:metric => "mean", :value => calculations[:mean])
        ]
    ))

    preview_columns = analysis.by === nothing ? [:observation, :value] : [:observation, :group, :value]
    preview_headers = Dict(:observation => "Observation", :value => "Value")
    if analysis.by !== nothing
        preview_headers[:group] = "Group"
    end
    add_table!(result, AnalysisTable(
        :preview,
        "Scatterplot data preview",
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
        :scatterplot,
        analysis.by === nothing ? "Scatterplot by observation index" : "Scatterplot by observation index with colored groups",
        :gadfly_scatter;
        payload=Dict(
            :data => plot_df,
            :mode => mode,
            :variable_label => string(analysis.variable),
            :group_label => analysis.by === nothing ? "" : string(analysis.by),
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
