"""
    RandomIntegerGeneratorAnalysis

Спецификация генератора случайных целых значений из дискретных распределений.

Анализ хранит только описание задачи: какое распределение использовать,
с какими параметрами, сколько значений сгенерировать и какой seed задать.
"""
struct RandomIntegerGeneratorAnalysis <: AbstractAnalysis
    info::AnalysisInfo
    target::Symbol
    distribution::String
    parameters::Dict{Symbol, Any}
    count::Int
    seed::Int
    namespace::Symbol
    palette_name::Symbol
end

"""
    RandomIntegerGeneratorAnalysis(target; distribution, parameters, count, seed, ...)

Конструктор подготавливает воспроизводимый сценарий генерации.

Важно, что распределение задается английским названием. Это помогает
избежать неоднозначностей между локалями и делает сценарии переносимыми
между разными notebook/demo-кейсами.
"""
function RandomIntegerGeneratorAnalysis(target::Symbol;
                                        distribution::AbstractString,
                                        parameters::AbstractDict{Symbol},
                                        count::Integer,
                                        seed::Integer,
                                        namespace::Symbol=:generated,
                                        palette_name::Symbol=:colorful,
                                        id::Symbol=:random_integer_generator,
                                        category_path::AbstractVector{Symbol}=[:data_generator, :integer_distributions],
                                        title::AbstractString="Генератор случайных целых чисел",
                                        summary::AbstractString="Создает целочисленную случайную выборку из заданного дискретного распределения.",
                                        description::AbstractString="Для воспроизводимости используется начальное число генератора `seed`. Само распределение задается английским названием, а генерация выполняется средствами Distributions.jl.",
                                        interpretation::AbstractString="Результат сохраняет созданную переменную, характеристики выборки и базовые графики для быстрого контроля формы распределения.")
    count >= 0 || error("`count` must be non-negative")
    palette_name in available_plot_palettes() || error("Unsupported palette name: $palette_name")

    info = AnalysisInfo(
        id;
        category_path=category_path,
        title=title,
        summary=summary,
        description=description,
        interpretation=interpretation,
        formulas=[
            FormulaSpec("xᵢ ~ Distribution(parameters)", "Наблюдения генерируются из выбранного дискретного распределения."),
            FormulaSpec("seed -> reproducible sample", "Одинаковый seed дает одинаковую последовательность.")
        ],
        notes=[
            "Название распределения задается английским именем.",
            "Реализация использует готовые распределения из Distributions.jl."
        ]
    )

    return RandomIntegerGeneratorAnalysis(
        info,
        target,
        lowercase(String(distribution)),
        Dict{Symbol, Any}(parameters),
        Int(count),
        Int(seed),
        namespace,
        palette_name
    )
end

analysis_info(analysis::RandomIntegerGeneratorAnalysis) = analysis.info
required_variables(::RandomIntegerGeneratorAnalysis) = Symbol[]
produced_variables(analysis::RandomIntegerGeneratorAnalysis) = [
    Symbol(string(analysis.namespace), ".", string(analysis.target))
]

# Вспомогательная функция централизует проверку обязательных параметров
# распределения. Благодаря этому ошибки по отсутствующим параметрам получаются
# ранними и понятными.
function _required_param(parameters::Dict{Symbol, Any}, name::Symbol)
    haskey(parameters, name) || error("Missing required parameter `$(name)`")
    return parameters[name]
end

"""
    _distribution_from_name(name, parameters)

Преобразует строковое английское имя распределения в конкретный объект
из `Distributions.jl`.

Здесь намеренно не изобретается собственная математика генерации:
мы только маппим пользовательский ввод на готовые типы и конструкторы
из пакета `Distributions`.
"""
function _distribution_from_name(name::AbstractString, parameters::Dict{Symbol, Any})
    if name == "discreteuniform"
        lower = Int(_required_param(parameters, :lower))
        upper = Int(_required_param(parameters, :upper))
        return DiscreteUniform(lower, upper)
    elseif name == "binomial"
        n = Int(_required_param(parameters, :n))
        p = Float64(_required_param(parameters, :p))
        return Binomial(n, p)
    elseif name == "poisson"
        lambda = Float64(_required_param(parameters, :lambda))
        return Poisson(lambda)
    elseif name == "geometric"
        p = Float64(_required_param(parameters, :p))
        return Geometric(p)
    elseif name == "negativebinomial"
        r = Float64(_required_param(parameters, :r))
        p = Float64(_required_param(parameters, :p))
        return NegativeBinomial(r, p)
    elseif name == "hypergeometric"
        s = Int(_required_param(parameters, :successes))
        f = Int(_required_param(parameters, :failures))
        n = Int(_required_param(parameters, :draws))
        return Hypergeometric(s, f, n)
    elseif name == "betabinomial"
        n = Int(_required_param(parameters, :n))
        alpha = Float64(_required_param(parameters, :alpha))
        beta = Float64(_required_param(parameters, :beta))
        return BetaBinomial(n, alpha, beta)
    end

    supported = [
        "discreteuniform",
        "binomial",
        "poisson",
        "geometric",
        "negativebinomial",
        "hypergeometric",
        "betabinomial"
    ]
    error("Unsupported distribution `$name`. Supported: $(join(supported, ", "))")
end

# Комментарии к метрикам нужны для summary-таблицы: так один и тот же
# результат можно читать не только как набор чисел, но и как интерпретируемый отчет.
function _parameter_comment(name::String)
    if name == "mean"
        return "Параметрическая характеристика положения"
    elseif name == "std"
        return "Параметрическая характеристика разброса"
    elseif name == "median"
        return "Непараметрическая центральная тенденция"
    elseif name == "q1"
        return "Первый квартиль"
    elseif name == "q3"
        return "Третий квартиль"
    elseif name == "range"
        return "Минимум и максимум"
    elseif name == "count"
        return "Размер сгенерированной выборки"
    elseif name == "variable_name"
        return "Имя созданной workbook-переменной"
    end

    return ""
end

"""
    _random_integer_summary(values)

Строит компактный набор статистик по сгенерированной выборке.

Мы ограничиваемся 6-8 характеристиками, чтобы результат оставался
информативным, но не перегруженным деталями.
"""
function _random_integer_summary(values::Vector{Int})
    if isempty(values)
        return Dict{Symbol, Any}(
            :count => 0,
            :mean => missing,
            :std => missing,
            :median => missing,
            :q1 => missing,
            :q3 => missing,
            :range => "empty"
        )
    end

    q = quantile(values, [0.25, 0.75])
    return Dict{Symbol, Any}(
        :count => length(values),
        :mean => mean(values),
        :std => length(values) == 1 ? 0.0 : std(values),
        :median => median(values),
        :q1 => q[1],
        :q3 => q[2],
        :range => string(minimum(values), ":", maximum(values))
    )
end

"""
    analyze(wb, analysis::RandomIntegerGeneratorAnalysis; store=true)

Исполняет случайную генерацию, сохраняет вектор в workbook и собирает
полный результат анализа.

Основная идея функции:
- сначала воспроизводимо сгенерировать данные;
- затем зафиксировать их как workbook-переменную;
- после этого построить статистики, таблицы и набор графиков.
"""
function analyze(wb, analysis::RandomIntegerGeneratorAnalysis; store::Bool=true)
    distribution = _distribution_from_name(analysis.distribution, analysis.parameters)

    # Seed устанавливается прямо перед генерацией, чтобы одинаковый сценарий
    # анализа давал одинаковый результат независимо от предыдущих вызовов random.
    Random.seed!(analysis.seed)
    values = rand(distribution, analysis.count)

    expression = "rand($(analysis.distribution), count=$(analysis.count), seed=$(analysis.seed))"
    store_vector!(
        wb.space,
        analysis.namespace,
        analysis.target,
        values;
        origin=:generated,
        dirty=true,
        expression=expression
    )

    qualified_name = Symbol(string(analysis.namespace), ".", string(analysis.target))
    push!(wb.logs, string(qualified_name, " <- ", expression))

    summary = _random_integer_summary(values)
    summary[:variable_name] = qualified_name

    # `analysis_data` содержит машинно-ориентированные сведения о запуске,
    # а `calculations` — уже пользовательские расчетные показатели.
    result = BaseAnalysisResult(
        analysis.info;
        input_variables=Symbol[],
        output_variables=[qualified_name],
        analysis_data=Dict(
            :analysis_type => :random_integer_generator,
            :distribution => analysis.distribution,
            :parameters => analysis.parameters,
            :seed => analysis.seed,
            :count => analysis.count
        ),
        calculations=summary
    )

    # Таблица specification показывает, как именно была получена выборка:
    # имя переменной, распределение, параметры и seed.
    add_table!(result, AnalysisTable(
        :specification,
        "Параметры генерации",
        [:field, :value];
        headers=Dict(
            :field => "Field",
            :value => "Value"
        ),
        rows=[
            Dict(:field => "Variable", :value => String(qualified_name)),
            Dict(:field => "Distribution", :value => analysis.distribution),
            Dict(:field => "Parameters", :value => string(analysis.parameters)),
            Dict(:field => "Seed", :value => analysis.seed)
        ]
    ))

    # Таблица summary — главный короткий отчет по выборке. По умолчанию
    # именно ее будет возвращать `to_table(result)`.
    stat_keys = [:variable_name, :count, :mean, :std, :median, :q1, :q3, :range]
    add_table!(result, AnalysisTable(
        :summary,
        "Основные характеристики",
        [:metric, :value, :comment];
        headers=Dict(
            :metric => "Параметр",
            :value => "Значение",
            :comment => "Комментарий"
        ),
        rows=[
            Dict(
                :metric => String(key),
                :value => summary[key],
                :comment => _parameter_comment(String(key))
            ) for key in stat_keys
        ]
    ))

    # Общие настройки графиков берем из отдельного графического слоя.
    # Так визуальные стандарты задаются централизованно, а не размазываются
    # по всем анализам.
    plot_options = default_plot_config(; palette_name=analysis.palette_name)
    merge!(plot_options, Dict(:legend => false))

    # Scatterplot полезен для просмотра последовательности значений в порядке генерации:
    # он быстро показывает кластеры, редкие выбросы и характер разброса по индексам.
    scatter_spec = PlotSpec(
        :scatter,
        "Scatterplot of generated values",
        :scatter;
        payload=Dict(
            :x => collect(1:length(values)),
            :y => values
        ),
        options=merge(
            Dict(
                :xlabel => "Index",
                :ylabel => "Value"
            ),
            plot_options
        )
    )

    # Гистограмма показывает уже не порядок значений, а форму распределения:
    # где находятся моды, насколько выборка симметрична, есть ли длинные хвосты.
    histogram_spec = PlotSpec(
        :histogram,
        "Histogram of generated values",
        :histogram;
        payload=Dict(
            :values => values
        ),
        options=merge(
            Dict(
                :xlabel => "Value",
                :ylabel => "Frequency"
            ),
            plot_options
        )
    )

    # Dashboard собирает оба графика в одну композицию.
    # Это удобно для отчетов, когда нужно сразу видеть и форму распределения,
    # и поведение значений по индексам.
    dashboard_spec = PlotSpec(
        :dashboard,
        "Scatterplot and histogram dashboard",
        :dashboard;
        payload=Dict(
            :plots => [scatter_spec, histogram_spec]
        ),
        options=merge(
            Dict(
                :layout => (1, 2)
            ),
            plot_options
        )
    )

    add_plot!(result, scatter_spec)
    add_plot!(result, histogram_spec)
    add_plot!(result, dashboard_spec)

    if store
        add_result!(wb, result)
    end

    return result
end
