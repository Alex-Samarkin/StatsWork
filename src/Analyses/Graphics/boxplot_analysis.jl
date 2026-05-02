"""
    BoxplotAnalysis

Графический анализ для boxplot одной числовой переменной. Если задан `by`,
строится набор boxplot по категориям; иначе строится один boxplot.
"""
struct BoxplotAnalysis <: AbstractAnalysis
    info::AnalysisInfo
    variable::Symbol
    by::Union{Nothing, Symbol}
    palette_name::Symbol
    width::Int
    height::Int
end

"""
    BoxplotAnalysis(variable; by=nothing, ...)

Создаёт анализ категории `Graphics`. Первый вывод - boxplot со средним.
Второй вывод - boxplot и violinplot. Третий вывод - boxplot и точки данных.
"""
function BoxplotAnalysis(variable::Symbol;
                         by::Union{Nothing, Symbol}=nothing,
                         palette_name::Symbol=:colorful,
                         width::Int=1900,
                         height::Int=600,
                         id::Symbol=:boxplot,
                         category_path::AbstractVector{Symbol}=[:graphics, :boxplots],
                         title::AbstractString="Boxplot",
                         summary::AbstractString="Строит boxplot одной числовой переменной и поддерживает разбиение по категориям через `by`.",
                         description::AbstractString="Анализ очищает числовые значения, при необходимости связывает их с категориями второй переменной и готовит три графических представления через Gadfly: boxplot со средним, boxplot с violinplot и boxplot с точками данных.",
                         interpretation::AbstractString="Boxplot помогает оценить медиану, межквартильный размах, усы, выбросы и различия между категориями.")
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
            FormulaSpec("boxplot(x)", "Базовый вывод показывает медиану, усы и выбросы."),
            FormulaSpec("mean(x)", "Среднее дополнительно показывается отдельной точкой."),
            FormulaSpec("boxplot(x) + violin(x)", "Второй вывод совмещает boxplot и violinplot."),
            FormulaSpec("boxplot(x) + points(x)", "Третий вывод совмещает boxplot и отдельные наблюдения.")
        ],
        notes=[
            "В график включаются только конечные числовые значения.",
            "Если `by` задан, строки с missing в группировке исключаются из графика."
        ]
    )

    return BoxplotAnalysis(info, variable, by, palette_name, width, height)
end

analysis_info(analysis::BoxplotAnalysis) = analysis.info

function required_variables(analysis::BoxplotAnalysis)
    analysis.by === nothing && return [analysis.variable]
    return [analysis.variable, analysis.by]
end

produced_variables(::BoxplotAnalysis) = Symbol[]

function _boxplot_rows(values, by_values::Nothing)
    rows = Dict{Symbol, Any}[]
    skipped = 0

    for value in values
        if value === missing
            skipped += 1
        elseif value isa Number
            numeric = Float64(value)
            if isfinite(numeric)
                push!(rows, Dict(:group => "All", :value => numeric))
            else
                skipped += 1
            end
        else
            skipped += 1
        end
    end

    return rows, skipped
end

function _boxplot_rows(values, by_values)
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

function analyze(wb, analysis::BoxplotAnalysis; store::Bool=true)
    raw_values = getvar(wb, analysis.variable)
    raw_groups = analysis.by === nothing ? nothing : getvar(wb, analysis.by)
    rows, skipped = _boxplot_rows(raw_values, raw_groups)
    isempty(rows) && error("Boxplot analysis has no valid rows after cleaning")

    plot_df = DataFrame(rows)
    mode = analysis.by === nothing ? :single : :group
    count_value = nrow(plot_df)
    grouped = combine(
        groupby(plot_df, :group),
        nrow => :count,
        :value => mean => :mean,
        :value => median => :median,
        :value => minimum => :minimum,
        :value => maximum => :maximum
    )

    calculations = Dict{Symbol, Any}(
        :variable => analysis.variable,
        :by => analysis.by,
        :count => count_value,
        :skipped => skipped,
        :minimum => minimum(plot_df.value),
        :maximum => maximum(plot_df.value),
        :mean => mean(plot_df.value),
        :median => median(plot_df.value)
    )

    result = BaseAnalysisResult(
        analysis.info;
        input_variables=required_variables(analysis),
        analysis_data=Dict(
            :analysis_type => :boxplot,
            :mode => mode
        ),
        calculations=calculations
    )

    add_table!(result, AnalysisTable(
        :summary,
        "Boxplot summary",
        [:metric, :value];
        headers=Dict(:metric => "Metric", :value => "Value"),
        rows=[
            Dict(:metric => "variable", :value => String(analysis.variable)),
            Dict(:metric => "by", :value => analysis.by === nothing ? "none" : String(analysis.by)),
            Dict(:metric => "count", :value => count_value),
            Dict(:metric => "skipped", :value => skipped),
            Dict(:metric => "minimum", :value => calculations[:minimum]),
            Dict(:metric => "maximum", :value => calculations[:maximum]),
            Dict(:metric => "mean", :value => calculations[:mean]),
            Dict(:metric => "median", :value => calculations[:median])
        ]
    ))

    add_table!(result, AnalysisTable(
        :groups,
        "Group summary",
        [:group, :count, :mean, :median, :minimum, :maximum];
        headers=Dict(
            :group => "Group",
            :count => "Count",
            :mean => "Mean",
            :median => "Median",
            :minimum => "Minimum",
            :maximum => "Maximum"
        ),
        rows=[Dict(
            :group => row.group,
            :count => row.count,
            :mean => row.mean,
            :median => row.median,
            :minimum => row.minimum,
            :maximum => row.maximum
        ) for row in eachrow(grouped)]
    ))

    add_table!(result, AnalysisTable(
        :preview,
        "Boxplot data preview",
        [:group, :value];
        headers=Dict(:group => "Group", :value => "Value"),
        rows=rows[1:min(length(rows), 25)]
    ))

    common_payload = Dict(
        :data => plot_df,
        :means => grouped,
        :mode => mode,
        :variable_label => string(analysis.variable),
        :group_label => analysis.by === nothing ? "" : string(analysis.by),
        :palette_name => analysis.palette_name,
        :width => analysis.width,
        :height => analysis.height
    )

    add_plot!(result, PlotSpec(
        :boxplot,
        "Boxplot with mean",
        :gadfly_boxplot;
        payload=merge(copy(common_payload), Dict(:variant => :boxplot_mean))
    ))

    add_plot!(result, PlotSpec(
        :boxplot_violin,
        "Boxplot and violinplot",
        :gadfly_boxplot;
        payload=merge(copy(common_payload), Dict(:variant => :boxplot_violin))
    ))

    add_plot!(result, PlotSpec(
        :boxplot_points,
        "Boxplot and data points",
        :gadfly_boxplot;
        payload=merge(copy(common_payload), Dict(:variant => :boxplot_points))
    ))

    if store
        add_result!(wb, result)
    end

    return result
end
