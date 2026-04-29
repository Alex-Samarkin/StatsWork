"""
    SingleVariableDescriptiveAnalysis

Подробная описательная статистика одной числовой переменной.

Анализ строит отсортированный вариационный ряд, рассчитывает параметрические
и непараметрические характеристики и добавляет диагностические графики.
"""
struct SingleVariableDescriptiveAnalysis <: AbstractAnalysis
    info::AnalysisInfo
    variable::Symbol
    variation_namespace::Union{Nothing, Symbol}
    variation_name::Union{Nothing, Symbol}
    normal_overlay::Bool
    palette_name::Symbol
end

"""
    SingleVariableDescriptiveAnalysis(variable; ...)

Создает анализ одной workbook-переменной. Входная переменная должна быть
числовым вектором, возможно с `missing`. Нечисловые и бесконечные значения
не участвуют в расчетах.
"""
function SingleVariableDescriptiveAnalysis(variable::Symbol;
                                           variation_namespace::Union{Nothing, Symbol}=:derived,
                                           variation_name::Union{Nothing, Symbol}=nothing,
                                           normal_overlay::Bool=true,
                                           palette_name::Symbol=:colorful,
                                           id::Symbol=:single_variable_descriptive,
                                           category_path::AbstractVector{Symbol}=[:exploratory, :single_variable],
                                           title::AbstractString="Описательная статистика одной переменной",
                                           summary::AbstractString="Строит вариационный ряд и подробные описательные характеристики одной числовой переменной.",
                                           description::AbstractString="Анализ рассчитывает общие, параметрические и непараметрические характеристики, а также готовит гистограмму, boxplot и QQ-график.",
                                           interpretation::AbstractString="Сводка помогает оценить центр, разброс, форму распределения, выбросы и близость эмпирического распределения к нормальному.")
    palette_name in available_plot_palettes() || error("Unsupported palette name: $palette_name")

    info = AnalysisInfo(
        id;
        category_path=category_path,
        title=title,
        summary=summary,
        description=description,
        interpretation=interpretation,
        formulas=[
            FormulaSpec("x(1) <= x(2) <= ... <= x(n)", "Вариационный ряд - отсортированные наблюдения."),
            FormulaSpec("mean = sum(x) / n", "Среднее арифметическое."),
            FormulaSpec("std = sqrt(sum((x - mean)^2) / (n - 1))", "Выборочное стандартное отклонение."),
            FormulaSpec("SE(mean) = std / sqrt(n)", "Стандартная ошибка среднего."),
            FormulaSpec("IQR = Q3 - Q1", "Межквартильное расстояние.")
        ],
        notes=[
            "Missing и нечисловые значения исключаются из расчетов.",
            "Гармоническое и геометрическое средние рассчитываются только для положительных значений.",
            "Мода возвращается только если есть повторяющиеся значения."
        ]
    )

    return SingleVariableDescriptiveAnalysis(
        info,
        variable,
        variation_namespace,
        variation_name,
        normal_overlay,
        palette_name
    )
end

analysis_info(analysis::SingleVariableDescriptiveAnalysis) = analysis.info
required_variables(analysis::SingleVariableDescriptiveAnalysis) = [analysis.variable]

function produced_variables(analysis::SingleVariableDescriptiveAnalysis)
    analysis.variation_namespace === nothing && return Symbol[]
    name = analysis.variation_name === nothing ? Symbol(string(analysis.variable), "_variation_series") : analysis.variation_name
    return [Symbol(string(analysis.variation_namespace), ".", string(name))]
end

function _clean_numeric_values(values)
    collected = collect(values)
    numeric = Float64[]
    skipped = 0

    for value in collected
        if value === missing
            skipped += 1
        elseif value isa Number
            converted = Float64(value)
            if isfinite(converted)
                push!(numeric, converted)
            else
                skipped += 1
            end
        else
            skipped += 1
        end
    end

    return numeric, skipped, length(collected)
end

function _safe_harmonic_mean(values::Vector{Float64})
    isempty(values) && return missing
    all(>(0), values) || return missing
    return length(values) / sum(1 ./ values)
end

function _safe_geometric_mean(values::Vector{Float64})
    isempty(values) && return missing
    all(>(0), values) || return missing
    return exp(mean(log.(values)))
end

function _safe_mode(values::Vector{Float64})
    isempty(values) && return missing
    counts = countmap(values)
    max_count = maximum(Base.values(counts))
    max_count <= 1 && return missing
    modes = sort([key for (key, count) in counts if count == max_count])
    return length(modes) == 1 ? modes[1] : modes
end

function _summary_metric_row(metric::AbstractString, value, comment::AbstractString="")
    return Dict(:metric => String(metric), :value => value, :comment => String(comment))
end

function _quantile_rows(values::Vector{Float64})
    rows = Dict{Symbol, Any}[]

    percentile_probs = [0.01, 0.05, 0.10, 0.25, 0.50, 0.75, 0.90, 0.95, 0.99]
    for p in percentile_probs
        push!(rows, Dict(
            :group => "percentile",
            :level => string(round(Int, p * 100), "%"),
            :probability => p,
            :value => quantile(values, p)
        ))
    end

    for k in 1:9
        p = k / 10
        push!(rows, Dict(
            :group => "decile",
            :level => "D$k",
            :probability => p,
            :value => quantile(values, p)
        ))
    end

    for k in 1:5
        p = k / 6
        push!(rows, Dict(
            :group => "sixth",
            :level => "S$k",
            :probability => p,
            :value => quantile(values, p)
        ))
    end

    for (label, p) in [("LQ", 0.25), ("Median", 0.50), ("UQ", 0.75)]
        push!(rows, Dict(
            :group => "quartile",
            :level => label,
            :probability => p,
            :value => quantile(values, p)
        ))
    end

    return rows
end

function _qq_payload(values::Vector{Float64})
    n = length(values)
    n == 0 && return Dict{Symbol, Any}(:x => Float64[], :y => Float64[])

    sorted_values = sort(values)
    probs = [(i - 0.5) / n for i in 1:n]
    theoretical = quantile.(Normal(), probs)
    mu = mean(sorted_values)
    sigma = n == 1 ? 0.0 : std(sorted_values)
    line_x = [minimum(theoretical), maximum(theoretical)]
    line_y = sigma == 0 ? [mu, mu] : mu .+ sigma .* line_x

    return Dict{Symbol, Any}(
        :x => theoretical,
        :y => sorted_values,
        :line_x => line_x,
        :line_y => line_y
    )
end

"""
    analyze(wb, analysis::SingleVariableDescriptiveAnalysis; store=true)

Исполняет подробную описательную статистику одной переменной.
"""
function analyze(wb, analysis::SingleVariableDescriptiveAnalysis; store::Bool=true)
    raw_values = getvar(wb, analysis.variable)
    values, skipped, total_n = _clean_numeric_values(raw_values)
    isempty(values) && error("Variable `$(analysis.variable)` has no finite numeric values")

    sorted_values = sort(values)
    n = length(sorted_values)
    sum_values = sum(sorted_values)
    sum_squares = sum(abs2, sorted_values)
    mean_value = mean(sorted_values)
    sample_std = n == 1 ? 0.0 : std(sorted_values)
    sample_var = n == 1 ? 0.0 : var(sorted_values)
    q1, med, q3 = quantile(sorted_values, [0.25, 0.50, 0.75])
    iqr_value = q3 - q1

    variation_output = produced_variables(analysis)
    if analysis.variation_namespace !== nothing
        target_name = analysis.variation_name === nothing ? Symbol(string(analysis.variable), "_variation_series") : analysis.variation_name
        expression = "sort($(analysis.variable))"
        store_vector!(
            wb.space,
            analysis.variation_namespace,
            target_name,
            sorted_values;
            origin=:analysis,
            dirty=true,
            expression=expression
        )
        push!(wb.logs, string(first(variation_output), " <- ", expression))
    end

    central3 = mean((sorted_values .- mean_value) .^ 3)
    central4 = mean((sorted_values .- mean_value) .^ 4)
    skewness_value = n < 3 ? missing : skewness(sorted_values)
    excess_value = n < 4 ? missing : kurtosis(sorted_values)
    kurtosis_coefficient = excess_value === missing ? missing : excess_value + 3
    coefficient_variation = mean_value == 0 ? missing : sample_std / abs(mean_value)

    calculations = Dict{Symbol, Any}(
        :variable => analysis.variable,
        :count => n,
        :total_count => total_n,
        :skipped => skipped,
        :sum => sum_values,
        :sum_squares => sum_squares,
        :mean => mean_value,
        :harmonic_mean => _safe_harmonic_mean(sorted_values),
        :geometric_mean => _safe_geometric_mean(sorted_values),
        :quadratic_mean => sqrt(sum_squares / n),
        :std => sample_std,
        :variance => sample_var,
        :central_moment_3 => central3,
        :central_moment_4 => central4,
        :skewness => skewness_value,
        :excess => excess_value,
        :kurtosis_coefficient => kurtosis_coefficient,
        :standard_error_mean => sample_std / sqrt(n),
        :coefficient_variation => coefficient_variation,
        :minimum => minimum(sorted_values),
        :maximum => maximum(sorted_values),
        :range => maximum(sorted_values) - minimum(sorted_values),
        :median => med,
        :mode => _safe_mode(sorted_values),
        :lq => q1,
        :uq => q3,
        :iqr => iqr_value
    )

    result = BaseAnalysisResult(
        analysis.info;
        input_variables=[analysis.variable],
        output_variables=variation_output,
        analysis_data=Dict(
            :analysis_type => :single_variable_descriptive,
            :variable => analysis.variable,
            :normal_overlay => analysis.normal_overlay
        ),
        calculations=calculations
    )

    add_table!(result, AnalysisTable(
        :general,
        "Общие характеристики",
        [:metric, :value, :comment];
        headers=Dict(:metric => "Параметр", :value => "Значение", :comment => "Комментарий"),
        rows=[
            _summary_metric_row("Количество", n, "Число конечных числовых наблюдений"),
            _summary_metric_row("Всего значений", total_n, "Длина исходной переменной"),
            _summary_metric_row("Исключено", skipped, "Missing, нечисловые или бесконечные значения"),
            _summary_metric_row("Сумма", sum_values, "Σx"),
            _summary_metric_row("Сумма квадратов", sum_squares, "Σx²"),
            _summary_metric_row("Вариационный ряд", isempty(variation_output) ? "table only" : String(first(variation_output)), "Отсортированный выходной вектор")
        ]
    ))

    add_table!(result, AnalysisTable(
        :parametric,
        "Параметрические характеристики",
        [:metric, :value, :comment];
        headers=Dict(:metric => "Параметр", :value => "Значение", :comment => "Комментарий"),
        rows=[
            _summary_metric_row("Среднее арифметическое", mean_value),
            _summary_metric_row("Среднее гармоническое", calculations[:harmonic_mean], "Только для положительных значений"),
            _summary_metric_row("Среднее геометрическое", calculations[:geometric_mean], "Только для положительных значений"),
            _summary_metric_row("Среднее квадратическое", calculations[:quadratic_mean]),
            _summary_metric_row("Стандартное отклонение", sample_std),
            _summary_metric_row("Дисперсия", sample_var),
            _summary_metric_row("Момент асимметрии", central3, "Третий центральный момент"),
            _summary_metric_row("Момент эксцесса", central4, "Четвертый центральный момент"),
            _summary_metric_row("Коэффициент асимметрии", skewness_value),
            _summary_metric_row("Эксцесс", excess_value, "Коэффициент эксцесса относительно нормального распределения"),
            _summary_metric_row("Коэффициент куртозиса", kurtosis_coefficient, "Эксцесс + 3"),
            _summary_metric_row("Стандартная ошибка среднего", calculations[:standard_error_mean]),
            _summary_metric_row("Коэффициент вариации", coefficient_variation, "std / abs(mean)")
        ]
    ))

    add_table!(result, AnalysisTable(
        :nonparametric,
        "Непараметрические характеристики",
        [:metric, :value, :comment];
        headers=Dict(:metric => "Параметр", :value => "Значение", :comment => "Комментарий"),
        rows=[
            _summary_metric_row("Минимум", calculations[:minimum]),
            _summary_metric_row("Максимум", calculations[:maximum]),
            _summary_metric_row("Диапазон", calculations[:range], "max - min"),
            _summary_metric_row("Медиана", med),
            _summary_metric_row("Мода", calculations[:mode], "Если есть повторяющиеся значения"),
            _summary_metric_row("LQ", q1, "Нижний квартиль"),
            _summary_metric_row("UQ", q3, "Верхний квартиль"),
            _summary_metric_row("IQR", iqr_value, "UQ - LQ")
        ]
    ))

    add_table!(result, AnalysisTable(
        :quantiles,
        "Процентили, децили, шестые части и квартили",
        [:group, :level, :probability, :value];
        headers=Dict(
            :group => "Группа",
            :level => "Уровень",
            :probability => "Вероятность",
            :value => "Значение"
        ),
        rows=_quantile_rows(sorted_values)
    ))

    add_table!(result, AnalysisTable(
        :variation_series,
        "Вариационный ряд",
        [:rank, :value];
        headers=Dict(:rank => "Ранг", :value => "Значение"),
        rows=[Dict(:rank => i, :value => value) for (i, value) in enumerate(sorted_values)]
    ))

    # По умолчанию `to_table(result)` показывает полный короткий отчет:
    # общие, параметрические и непараметрические показатели вместе.
    add_table!(result, AnalysisTable(
        :summary,
        "Краткая сводка",
        [:section, :metric, :value];
        headers=Dict(:section => "Раздел", :metric => "Параметр", :value => "Значение"),
        rows=[
            Dict(:section => "general", :metric => "count", :value => n),
            Dict(:section => "general", :metric => "sum", :value => sum_values),
            Dict(:section => "general", :metric => "sum_squares", :value => sum_squares),
            Dict(:section => "parametric", :metric => "mean", :value => mean_value),
            Dict(:section => "parametric", :metric => "std", :value => sample_std),
            Dict(:section => "parametric", :metric => "variance", :value => sample_var),
            Dict(:section => "parametric", :metric => "skewness", :value => skewness_value),
            Dict(:section => "parametric", :metric => "excess", :value => excess_value),
            Dict(:section => "nonparametric", :metric => "minimum", :value => calculations[:minimum]),
            Dict(:section => "nonparametric", :metric => "median", :value => med),
            Dict(:section => "nonparametric", :metric => "maximum", :value => calculations[:maximum]),
            Dict(:section => "nonparametric", :metric => "iqr", :value => iqr_value)
        ]
    ))

    plot_options = default_plot_config(; palette_name=analysis.palette_name)
    merge!(plot_options, Dict(:legend => false))

    histogram_kind = analysis.normal_overlay ? :histogram_normal : :histogram
    histogram_options = merge(
        plot_options,
        Dict(
            :xlabel => "Value",
            :ylabel => analysis.normal_overlay ? "Density" : "Frequency",
            :legend => analysis.normal_overlay
        )
    )
    histogram_spec = PlotSpec(
        :histogram,
        analysis.normal_overlay ? "Histogram with normal density" : "Histogram",
        histogram_kind;
        payload=Dict(:values => sorted_values, :mean => mean_value, :std => sample_std),
        options=histogram_options
    )

    boxplot_spec = PlotSpec(
        :boxplot,
        "Boxplot with median, mean and outliers",
        :boxplot;
        payload=Dict(:values => sorted_values, :show_mean => true),
        options=merge(Dict(:ylabel => "Value"), plot_options)
    )

    histogram_boxplot_spec = PlotSpec(
        :histogram_boxplot,
        "Histogram and boxplot",
        :dashboard;
        payload=Dict(:plots => [histogram_spec, boxplot_spec]),
        options=merge(Dict(:layout => (1, 2)), plot_options)
    )

    qq_spec = PlotSpec(
        :qq,
        "Normal QQ plot",
        :qq;
        payload=_qq_payload(sorted_values),
        options=merge(
            Dict(
                :xlabel => "Theoretical normal quantiles",
                :ylabel => "Observed quantiles",
                :legend => false
            ),
            plot_options
        )
    )

    add_plot!(result, histogram_spec)
    add_plot!(result, histogram_boxplot_spec)
    add_plot!(result, qq_spec)

    if store
        add_result!(wb, result)
    end

    return result
end
