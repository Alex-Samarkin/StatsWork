"""
    SingleVariableIntervalEstimatesAnalysis

Интервальные оценки для одной числовой переменной.

Этот анализ намеренно отделен от подробной описательной статистики:
он сам рассчитывает нужные точечные оценки, а затем строит доверительные
интервалы для среднего, дисперсии, стандартного отклонения и медианы.
"""
struct SingleVariableIntervalEstimatesAnalysis <: AbstractAnalysis
    info::AnalysisInfo
    variable::Symbol
    confidence_probability::Float64
    palette_name::Symbol
end

"""
    SingleVariableIntervalEstimatesAnalysis(variable; P=0.95, ...)

Создает спецификацию интервального анализа одной workbook-переменной.

`P` можно задавать как долю (`0.95`) или как процент (`95`).
Расчеты используют только конечные числовые значения; `missing`,
нечисловые и бесконечные значения исключаются.
"""
function SingleVariableIntervalEstimatesAnalysis(variable::Symbol;
                                                 P::Real=0.95,
                                                 palette_name::Symbol=:colorful,
                                                 id::Symbol=:single_variable_interval_estimates,
                                                 category_path::AbstractVector{Symbol}=[:exploratory, :single_variable],
                                                 title::AbstractString="Интервальные оценки одной переменной",
                                                 summary::AbstractString="Рассчитывает доверительные интервалы для среднего, дисперсии, стандартного отклонения и медианы.",
                                                 description::AbstractString="Анализ отдельно считает точечные оценки одной числовой переменной и строит для них интервальные оценки с заданной доверительной вероятностью P.",
                                                 interpretation::AbstractString="Интервалы показывают неопределенность оценок центра и разброса. Интервалы среднего, дисперсии и стандартного отклонения предполагают нормальность генеральной совокупности; интервал медианы является непараметрическим.")
    palette_name in available_plot_palettes() || error("Unsupported palette name: $palette_name")
    confidence_probability = _interval_normalize_probability(P)

    info = AnalysisInfo(
        id;
        category_path=category_path,
        title=title,
        summary=summary,
        description=description,
        interpretation=interpretation,
        formulas=[
            FormulaSpec("mean = sum(x) / n", "Среднее арифметическое по очищенной выборке."),
            FormulaSpec("s² = sum((x - mean)^2) / (n - 1)", "Выборочная дисперсия."),
            FormulaSpec("s = sqrt(s²)", "Выборочное стандартное отклонение."),
            FormulaSpec("mean CI = mean +/- t(1 - alpha/2, n - 1) * s / sqrt(n)", "Интервал среднего при неизвестной дисперсии строится по распределению Стьюдента."),
            FormulaSpec("variance CI = ((n - 1)s² / χ²(1 - alpha/2), (n - 1)s² / χ²(alpha/2))", "Интервал дисперсии нормальной генеральной совокупности строится по распределению хи-квадрат."),
            FormulaSpec("std CI = sqrt(variance CI)", "Интервал стандартного отклонения получается монотонным преобразованием границ интервала дисперсии."),
            FormulaSpec("median CI = [x(k), x(n-k+1)]", "Непараметрический интервал медианы строится по порядковым статистикам и биномиальному распределению Binomial(n, 0.5).")
        ],
        notes=[
            "P=0.95 и P=95 интерпретируются как доверительная вероятность 95%.",
            "Для среднего, дисперсии и стандартного отклонения нужен объем n >= 2.",
            "Интервал медианы дискретен по рангам, поэтому фактическая вероятность покрытия может отличаться от заданной P.",
            "Алгоритм медианы использует порядковые статистики: если истинная медиана делит распределение пополам, количество наблюдений ниже нее имеет биномиальное распределение."
        ]
    )

    return SingleVariableIntervalEstimatesAnalysis(
        info,
        variable,
        confidence_probability,
        palette_name
    )
end

analysis_info(analysis::SingleVariableIntervalEstimatesAnalysis) = analysis.info
required_variables(analysis::SingleVariableIntervalEstimatesAnalysis) = [analysis.variable]
produced_variables(::SingleVariableIntervalEstimatesAnalysis) = Symbol[]

function _interval_normalize_probability(P::Real)
    probability = Float64(P)
    if 1 < probability < 100
        probability /= 100
    end
    0 < probability < 1 || error("Confidence probability P must be between 0 and 1, or between 1 and 100 as percent")
    return probability
end

function _interval_clean_numeric_values(values)
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

function _interval_row(parameter::AbstractString,
                       estimate,
                       lower,
                       upper,
                       requested_probability,
                       actual_probability,
                       method::AbstractString,
                       comment::AbstractString="")
    return Dict(
        :parameter => String(parameter),
        :estimate => estimate,
        :lower => lower,
        :upper => upper,
        :requested_probability => requested_probability,
        :actual_probability => actual_probability,
        :method => String(method),
        :comment => String(comment)
    )
end

function _single_variable_point_estimates(sorted_values::Vector{Float64})
    n = length(sorted_values)

    # Все точечные оценки сосредоточены в одном helper-е, чтобы было видно:
    # интервальный модуль не зависит от описательного анализа, а полностью
    # рассчитывает свою минимально необходимую статистическую базу сам.
    mean_value = mean(sorted_values)
    variance_value = n == 1 ? 0.0 : var(sorted_values)
    std_value = n == 1 ? 0.0 : std(sorted_values)
    median_value = median(sorted_values)

    return Dict{Symbol, Any}(
        :n => n,
        :mean => mean_value,
        :variance => variance_value,
        :std => std_value,
        :median => median_value,
        :minimum => minimum(sorted_values),
        :maximum => maximum(sorted_values)
    )
end

function _mean_interval(estimate::AbstractDict, confidence_probability::Real)
    n = estimate[:n]
    n < 2 && return (missing, missing, missing)

    alpha = 1 - confidence_probability
    degrees_freedom = n - 1
    critical_value = quantile(TDist(degrees_freedom), 1 - alpha / 2)
    margin = critical_value * estimate[:std] / sqrt(n)

    return (estimate[:mean] - margin, estimate[:mean] + margin, critical_value)
end

function _variance_interval(estimate::AbstractDict, confidence_probability::Real)
    n = estimate[:n]
    n < 2 && return (missing, missing, missing, missing)

    alpha = 1 - confidence_probability
    degrees_freedom = n - 1
    lower_quantile = quantile(Chisq(degrees_freedom), alpha / 2)
    upper_quantile = quantile(Chisq(degrees_freedom), 1 - alpha / 2)
    lower = degrees_freedom * estimate[:variance] / upper_quantile
    upper = degrees_freedom * estimate[:variance] / lower_quantile

    return (lower, upper, lower_quantile, upper_quantile)
end

function _std_interval(variance_lower, variance_upper)
    variance_lower === missing && return (missing, missing)
    return (sqrt(variance_lower), sqrt(variance_upper))
end

function _median_rank_coverage(n::Int, k::Int)
    k < 1 && return 1.0
    k > n - k + 1 && return 0.0
    return cdf(Binomial(n, 0.5), n - k) - cdf(Binomial(n, 0.5), k - 1)
end

function _median_interval(sorted_values::Vector{Float64}, confidence_probability::Real)
    n = length(sorted_values)
    n == 0 && return (missing, missing, missing, missing, missing)

    # Ранговый интервал медианы строится из отсортированной выборки.
    # Для ранга k интервал [x(k), x(n-k+1)] покрывает истинную медиану,
    # когда не слишком много наблюдений оказалось строго ниже или выше нее.
    # При непрерывном распределении это событие выражается через
    # Binomial(n, 0.5). Мы выбираем самый узкий симметричный интервал,
    # чье фактическое покрытие еще не ниже заданной вероятности P.
    max_k = cld(n, 2)
    selected_k = 1
    selected_coverage = _median_rank_coverage(n, selected_k)

    for k in 1:max_k
        coverage = _median_rank_coverage(n, k)
        if coverage >= confidence_probability
            selected_k = k
            selected_coverage = coverage
        else
            break
        end
    end

    lower_rank = selected_k
    upper_rank = n - selected_k + 1

    return (
        sorted_values[lower_rank],
        sorted_values[upper_rank],
        lower_rank,
        upper_rank,
        selected_coverage
    )
end

function _interval_plot(id::Symbol,
                        title::AbstractString,
                        label::AbstractString,
                        estimate,
                        lower,
                        upper,
                        xlabel::AbstractString,
                        plot_options::AbstractDict)
    return PlotSpec(
        id,
        title,
        :confidence_interval;
        payload=Dict(
            :estimate => estimate,
            :lower => lower,
            :upper => upper,
            :label => String(label)
        ),
        options=merge(
            Dict(
                :xlabel => String(xlabel),
                :legend => false
            ),
            plot_options
        )
    )
end

"""
    analyze(wb, analysis::SingleVariableIntervalEstimatesAnalysis; store=true)

Исполняет отдельный модуль интервальных оценок.
"""
function analyze(wb, analysis::SingleVariableIntervalEstimatesAnalysis; store::Bool=true)
    raw_values = getvar(wb, analysis.variable)
    values, skipped, total_n = _interval_clean_numeric_values(raw_values)
    isempty(values) && error("Variable `$(analysis.variable)` has no finite numeric values")

    sorted_values = sort(values)
    point_estimates = _single_variable_point_estimates(sorted_values)
    n = point_estimates[:n]
    confidence_probability = analysis.confidence_probability

    mean_lower, mean_upper, mean_t_critical = _mean_interval(point_estimates, confidence_probability)
    variance_lower, variance_upper, chi_lower, chi_upper = _variance_interval(point_estimates, confidence_probability)
    std_lower, std_upper = _std_interval(variance_lower, variance_upper)
    median_lower, median_upper, median_lower_rank, median_upper_rank, median_actual_probability =
        _median_interval(sorted_values, confidence_probability)

    calculations = Dict{Symbol, Any}(
        :variable => analysis.variable,
        :count => n,
        :total_count => total_n,
        :skipped => skipped,
        :confidence_probability => confidence_probability,
        :alpha => 1 - confidence_probability,
        :mean => point_estimates[:mean],
        :mean_ci_lower => mean_lower,
        :mean_ci_upper => mean_upper,
        :mean_t_critical => mean_t_critical,
        :variance => point_estimates[:variance],
        :variance_ci_lower => variance_lower,
        :variance_ci_upper => variance_upper,
        :variance_chi_lower => chi_lower,
        :variance_chi_upper => chi_upper,
        :std => point_estimates[:std],
        :std_ci_lower => std_lower,
        :std_ci_upper => std_upper,
        :median => point_estimates[:median],
        :median_ci_lower => median_lower,
        :median_ci_upper => median_upper,
        :median_ci_lower_rank => median_lower_rank,
        :median_ci_upper_rank => median_upper_rank,
        :median_actual_confidence_probability => median_actual_probability
    )

    result = BaseAnalysisResult(
        analysis.info;
        input_variables=[analysis.variable],
        output_variables=Symbol[],
        analysis_data=Dict(
            :analysis_type => :single_variable_interval_estimates,
            :variable => analysis.variable,
            :confidence_probability => confidence_probability
        ),
        calculations=calculations
    )

    add_table!(result, AnalysisTable(
        :point_estimates,
        "Точечные оценки",
        [:metric, :value, :comment];
        headers=Dict(:metric => "Параметр", :value => "Значение", :comment => "Комментарий"),
        rows=[
            Dict(:metric => "Количество", :value => n, :comment => "Число конечных числовых наблюдений"),
            Dict(:metric => "Всего значений", :value => total_n, :comment => "Длина исходной переменной"),
            Dict(:metric => "Исключено", :value => skipped, :comment => "Missing, нечисловые или бесконечные значения"),
            Dict(:metric => "Среднее", :value => point_estimates[:mean], :comment => "Точечная оценка математического ожидания"),
            Dict(:metric => "Дисперсия", :value => point_estimates[:variance], :comment => "Выборочная дисперсия"),
            Dict(:metric => "Стандартное отклонение", :value => point_estimates[:std], :comment => "Корень из выборочной дисперсии"),
            Dict(:metric => "Медиана", :value => point_estimates[:median], :comment => "50-й процентиль очищенной выборки")
        ]
    ))

    add_table!(result, AnalysisTable(
        :confidence_intervals,
        "Интервальные оценки",
        [:parameter, :estimate, :lower, :upper, :requested_probability, :actual_probability, :method, :comment];
        headers=Dict(
            :parameter => "Параметр",
            :estimate => "Точечная оценка",
            :lower => "Нижняя граница",
            :upper => "Верхняя граница",
            :requested_probability => "Заданная P",
            :actual_probability => "Фактическая P",
            :method => "Метод",
            :comment => "Комментарий"
        ),
        rows=[
            _interval_row(
                "Среднее",
                point_estimates[:mean],
                mean_lower,
                mean_upper,
                confidence_probability,
                confidence_probability,
                "t-распределение Стьюдента",
                n < 2 ? "Недостаточно наблюдений: нужен n >= 2" : "df=$(n - 1), t=$(mean_t_critical)"
            ),
            _interval_row(
                "Дисперсия",
                point_estimates[:variance],
                variance_lower,
                variance_upper,
                confidence_probability,
                confidence_probability,
                "χ²-распределение",
                n < 2 ? "Недостаточно наблюдений: нужен n >= 2" : "df=$(n - 1), χ² α/2=$(chi_lower), χ² 1-α/2=$(chi_upper)"
            ),
            _interval_row(
                "Стандартное отклонение",
                point_estimates[:std],
                std_lower,
                std_upper,
                confidence_probability,
                confidence_probability,
                "sqrt границ интервала дисперсии",
                n < 2 ? "Недостаточно наблюдений: нужен n >= 2" : "Предполагается нормальность генеральной совокупности"
            ),
            _interval_row(
                "Медиана",
                point_estimates[:median],
                median_lower,
                median_upper,
                confidence_probability,
                median_actual_probability,
                "Порядковые статистики + Binomial(n, 0.5)",
                "Ранги [$median_lower_rank, $median_upper_rank]"
            )
        ]
    ))

    add_table!(result, AnalysisTable(
        :summary,
        "Краткая сводка",
        [:section, :metric, :value];
        headers=Dict(:section => "Раздел", :metric => "Параметр", :value => "Значение"),
        rows=[
            Dict(:section => "point", :metric => "mean", :value => point_estimates[:mean]),
            Dict(:section => "interval", :metric => "mean_ci", :value => (mean_lower, mean_upper)),
            Dict(:section => "point", :metric => "variance", :value => point_estimates[:variance]),
            Dict(:section => "interval", :metric => "variance_ci", :value => (variance_lower, variance_upper)),
            Dict(:section => "point", :metric => "std", :value => point_estimates[:std]),
            Dict(:section => "interval", :metric => "std_ci", :value => (std_lower, std_upper)),
            Dict(:section => "point", :metric => "median", :value => point_estimates[:median]),
            Dict(:section => "interval", :metric => "median_ci", :value => (median_lower, median_upper))
        ]
    ))

    plot_options = default_plot_config(; palette_name=analysis.palette_name)
    merge!(plot_options, Dict(:legend => false))

    add_plot!(result, _interval_plot(
        :mean_confidence_interval,
        "Confidence interval for mean",
        "Mean",
        point_estimates[:mean],
        mean_lower,
        mean_upper,
        "Value",
        plot_options
    ))
    add_plot!(result, _interval_plot(
        :std_confidence_interval,
        "Confidence interval for standard deviation",
        "Std",
        point_estimates[:std],
        std_lower,
        std_upper,
        "Standard deviation",
        plot_options
    ))
    add_plot!(result, _interval_plot(
        :median_confidence_interval,
        "Confidence interval for median",
        "Median",
        point_estimates[:median],
        median_lower,
        median_upper,
        "Value",
        plot_options
    ))

    if store
        add_result!(wb, result)
    end

    return result
end
