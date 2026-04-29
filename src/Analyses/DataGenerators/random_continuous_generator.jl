"""
    RandomContinuousGeneratorAnalysis

Спецификация генератора непрерывно распределенных случайных чисел.

Анализ хранит описание сценария: распределение, параметры, размер выборки,
seed, имя создаваемой workbook-переменной и оформление графиков.
"""
struct RandomContinuousGeneratorAnalysis <: AbstractAnalysis
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
    RandomContinuousGeneratorAnalysis(target; distribution, parameters, count, seed, ...)

Создает воспроизводимый сценарий генерации случайных чисел из непрерывного
распределения `Distributions.jl`.

Название распределения задается английским именем: `normal`, `uniform`,
`gamma`, `beta` и т.д. Параметры передаются словарем с Symbol-ключами.
"""
function RandomContinuousGeneratorAnalysis(target::Symbol;
                                           distribution::AbstractString,
                                           parameters::AbstractDict{Symbol}=Dict{Symbol, Any}(),
                                           count::Integer,
                                           seed::Integer,
                                           namespace::Symbol=:generated,
                                           palette_name::Symbol=:colorful,
                                           id::Symbol=:random_continuous_generator,
                                           category_path::AbstractVector{Symbol}=[:data_generator, :continuous_distributions],
                                           title::AbstractString="Генератор непрерывно распределенных случайных чисел",
                                           summary::AbstractString="Создает числовую случайную выборку из заданного непрерывного распределения.",
                                           description::AbstractString="Для воспроизводимости используется начальное число генератора `seed`. Распределение задается английским названием, а генерация выполняется средствами Distributions.jl.",
                                           interpretation::AbstractString="Результат сохраняет созданную переменную, основные характеристики выборки и графики: scatterplot, histogram, boxplot и общую панель.")
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
            FormulaSpec("xᵢ ~ Distribution(parameters)", "Наблюдения генерируются из выбранного непрерывного распределения."),
            FormulaSpec("seed -> reproducible sample", "Одинаковый seed дает одинаковую последовательность.")
        ],
        notes=[
            "Название распределения задается английским именем.",
            "Реализация использует готовые непрерывные распределения из Distributions.jl."
        ]
    )

    return RandomContinuousGeneratorAnalysis(
        info,
        target,
        lowercase(replace(String(distribution), "_" => "")),
        Dict{Symbol, Any}(parameters),
        Int(count),
        Int(seed),
        namespace,
        palette_name
    )
end

analysis_info(analysis::RandomContinuousGeneratorAnalysis) = analysis.info
required_variables(::RandomContinuousGeneratorAnalysis) = Symbol[]
produced_variables(analysis::RandomContinuousGeneratorAnalysis) = [
    Symbol(string(analysis.namespace), ".", string(analysis.target))
]

function _optional_param(parameters::Dict{Symbol, Any}, name::Symbol, default)
    return haskey(parameters, name) ? parameters[name] : default
end

"""
    _continuous_distribution_from_name(name, parameters)

Преобразует английское имя распределения в объект `Distributions.jl`.
Поддерживается набор типовых непрерывных распределений для учебных,
демонстрационных и симуляционных сценариев.
"""
function _continuous_distribution_from_name(name::AbstractString, parameters::Dict{Symbol, Any})
    if name == "uniform"
        a = Float64(_optional_param(parameters, :a, _optional_param(parameters, :lower, 0.0)))
        b = Float64(_optional_param(parameters, :b, _optional_param(parameters, :upper, 1.0)))
        return Uniform(a, b)
    elseif name == "normal"
        mu = Float64(_optional_param(parameters, :mu, _optional_param(parameters, :mean, 0.0)))
        sigma = Float64(_optional_param(parameters, :sigma, _optional_param(parameters, :std, 1.0)))
        return Normal(mu, sigma)
    elseif name == "lognormal"
        mu = Float64(_optional_param(parameters, :mu, 0.0))
        sigma = Float64(_optional_param(parameters, :sigma, 1.0))
        return LogNormal(mu, sigma)
    elseif name == "exponential"
        theta = Float64(_optional_param(parameters, :theta, _optional_param(parameters, :scale, 1.0)))
        return Exponential(theta)
    elseif name == "gamma"
        alpha = Float64(_optional_param(parameters, :alpha, _optional_param(parameters, :shape, 2.0)))
        theta = Float64(_optional_param(parameters, :theta, _optional_param(parameters, :scale, 1.0)))
        return Gamma(alpha, theta)
    elseif name == "beta"
        alpha = Float64(_optional_param(parameters, :alpha, 2.0))
        beta = Float64(_optional_param(parameters, :beta, 2.0))
        return Beta(alpha, beta)
    elseif name in ("chisq", "chisquare", "chisquared")
        nu = Float64(_optional_param(parameters, :nu, _optional_param(parameters, :df, 5.0)))
        return Chisq(nu)
    elseif name in ("f", "fdist", "fdistribution")
        nu1 = Float64(_optional_param(parameters, :nu1, _optional_param(parameters, :df1, 5.0)))
        nu2 = Float64(_optional_param(parameters, :nu2, _optional_param(parameters, :df2, 10.0)))
        return FDist(nu1, nu2)
    elseif name in ("t", "tdist", "studentt")
        nu = Float64(_optional_param(parameters, :nu, _optional_param(parameters, :df, 10.0)))
        return TDist(nu)
    elseif name == "weibull"
        alpha = Float64(_optional_param(parameters, :alpha, _optional_param(parameters, :shape, 2.0)))
        theta = Float64(_optional_param(parameters, :theta, _optional_param(parameters, :scale, 1.0)))
        return Weibull(alpha, theta)
    elseif name == "cauchy"
        mu = Float64(_optional_param(parameters, :mu, _optional_param(parameters, :location, 0.0)))
        sigma = Float64(_optional_param(parameters, :sigma, _optional_param(parameters, :scale, 1.0)))
        return Cauchy(mu, sigma)
    elseif name == "laplace"
        mu = Float64(_optional_param(parameters, :mu, _optional_param(parameters, :location, 0.0)))
        theta = Float64(_optional_param(parameters, :theta, _optional_param(parameters, :scale, 1.0)))
        return Laplace(mu, theta)
    elseif name == "logistic"
        mu = Float64(_optional_param(parameters, :mu, _optional_param(parameters, :location, 0.0)))
        theta = Float64(_optional_param(parameters, :theta, _optional_param(parameters, :scale, 1.0)))
        return Logistic(mu, theta)
    elseif name == "rayleigh"
        sigma = Float64(_optional_param(parameters, :sigma, _optional_param(parameters, :scale, 1.0)))
        return Rayleigh(sigma)
    elseif name == "pareto"
        alpha = Float64(_optional_param(parameters, :alpha, _optional_param(parameters, :shape, 2.0)))
        theta = Float64(_optional_param(parameters, :theta, _optional_param(parameters, :scale, 1.0)))
        return Pareto(alpha, theta)
    elseif name in ("triangular", "triangulardist")
        a = Float64(_optional_param(parameters, :a, _optional_param(parameters, :lower, 0.0)))
        b = Float64(_optional_param(parameters, :b, _optional_param(parameters, :upper, 1.0)))
        c = Float64(_optional_param(parameters, :c, _optional_param(parameters, :mode, (a + b) / 2)))
        return TriangularDist(a, b, c)
    elseif name == "gumbel"
        mu = Float64(_optional_param(parameters, :mu, _optional_param(parameters, :location, 0.0)))
        theta = Float64(_optional_param(parameters, :theta, _optional_param(parameters, :scale, 1.0)))
        return Gumbel(mu, theta)
    elseif name == "frechet"
        alpha = Float64(_optional_param(parameters, :alpha, _optional_param(parameters, :shape, 2.0)))
        theta = Float64(_optional_param(parameters, :theta, _optional_param(parameters, :scale, 1.0)))
        return Frechet(alpha, theta)
    elseif name == "inversegamma"
        alpha = Float64(_optional_param(parameters, :alpha, _optional_param(parameters, :shape, 3.0)))
        theta = Float64(_optional_param(parameters, :theta, _optional_param(parameters, :scale, 1.0)))
        return InverseGamma(alpha, theta)
    elseif name == "inversegaussian"
        mu = Float64(_optional_param(parameters, :mu, _optional_param(parameters, :mean, 1.0)))
        lambda = Float64(_optional_param(parameters, :lambda, _optional_param(parameters, :shape, 1.0)))
        return InverseGaussian(mu, lambda)
    elseif name == "levy"
        mu = Float64(_optional_param(parameters, :mu, _optional_param(parameters, :location, 0.0)))
        c = Float64(_optional_param(parameters, :c, _optional_param(parameters, :scale, 1.0)))
        return Levy(mu, c)
    elseif name == "kolmogorov"
        return Kolmogorov()
    elseif name == "arcsine"
        a = Float64(_optional_param(parameters, :a, _optional_param(parameters, :lower, 0.0)))
        b = Float64(_optional_param(parameters, :b, _optional_param(parameters, :upper, 1.0)))
        return Arcsine(a, b)
    elseif name in ("noncentralchisq", "noncentralchisquare")
        nu = Float64(_optional_param(parameters, :nu, _optional_param(parameters, :df, 5.0)))
        lambda = Float64(_optional_param(parameters, :lambda, 1.0))
        return NoncentralChisq(nu, lambda)
    elseif name in ("noncentralf", "noncentralfdist")
        nu1 = Float64(_optional_param(parameters, :nu1, _optional_param(parameters, :df1, 5.0)))
        nu2 = Float64(_optional_param(parameters, :nu2, _optional_param(parameters, :df2, 10.0)))
        lambda = Float64(_optional_param(parameters, :lambda, 1.0))
        return NoncentralF(nu1, nu2, lambda)
    elseif name in ("noncentralt", "noncentraltdist")
        nu = Float64(_optional_param(parameters, :nu, _optional_param(parameters, :df, 10.0)))
        lambda = Float64(_optional_param(parameters, :lambda, 1.0))
        return NoncentralT(nu, lambda)
    end

    supported = [
        "uniform", "normal", "lognormal", "exponential", "gamma", "beta",
        "chisq", "f", "t", "weibull", "cauchy", "laplace", "logistic",
        "rayleigh", "pareto", "triangular", "gumbel", "frechet",
        "inversegamma", "inversegaussian", "levy", "kolmogorov", "arcsine",
        "noncentralchisq", "noncentralf", "noncentralt"
    ]
    error("Unsupported distribution `$name`. Supported: $(join(supported, ", "))")
end

function _continuous_parameter_comment(name::String)
    if name == "mean"
        return "Среднее значение выборки"
    elseif name == "std"
        return "Выборочное стандартное отклонение"
    elseif name == "variance"
        return "Выборочная дисперсия"
    elseif name == "median"
        return "Медиана"
    elseif name == "q1"
        return "Первый квартиль"
    elseif name == "q3"
        return "Третий квартиль"
    elseif name == "iqr"
        return "Межквартильный размах"
    elseif name == "minimum"
        return "Минимальное значение"
    elseif name == "maximum"
        return "Максимальное значение"
    elseif name == "range"
        return "Минимум и максимум"
    elseif name == "skewness"
        return "Асимметрия выборки"
    elseif name == "kurtosis"
        return "Эксцесс выборки"
    elseif name == "count"
        return "Размер сгенерированной выборки"
    elseif name == "variable_name"
        return "Имя созданной workbook-переменной"
    end

    return ""
end

"""
    _random_continuous_summary(values)

Строит набор основных статистик по сгенерированной непрерывной выборке.
"""
function _random_continuous_summary(values::Vector{Float64})
    if isempty(values)
        return Dict{Symbol, Any}(
            :count => 0,
            :mean => missing,
            :std => missing,
            :variance => missing,
            :median => missing,
            :q1 => missing,
            :q3 => missing,
            :iqr => missing,
            :minimum => missing,
            :maximum => missing,
            :range => "empty",
            :skewness => missing,
            :kurtosis => missing
        )
    end

    q = quantile(values, [0.25, 0.75])
    return Dict{Symbol, Any}(
        :count => length(values),
        :mean => mean(values),
        :std => length(values) == 1 ? 0.0 : std(values),
        :variance => length(values) == 1 ? 0.0 : var(values),
        :median => median(values),
        :q1 => q[1],
        :q3 => q[2],
        :iqr => q[2] - q[1],
        :minimum => minimum(values),
        :maximum => maximum(values),
        :range => string(minimum(values), ":", maximum(values)),
        :skewness => length(values) < 3 ? missing : skewness(values),
        :kurtosis => length(values) < 4 ? missing : kurtosis(values)
    )
end

"""
    analyze(wb, analysis::RandomContinuousGeneratorAnalysis; store=true)

Исполняет генерацию непрерывной случайной выборки, сохраняет ее в workbook,
считает основные статистики и добавляет графики контроля формы распределения.
"""
function analyze(wb, analysis::RandomContinuousGeneratorAnalysis; store::Bool=true)
    distribution = _continuous_distribution_from_name(analysis.distribution, analysis.parameters)

    Random.seed!(analysis.seed)
    values = Float64.(rand(distribution, analysis.count))

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

    summary = _random_continuous_summary(values)
    summary[:variable_name] = qualified_name

    result = BaseAnalysisResult(
        analysis.info;
        input_variables=Symbol[],
        output_variables=[qualified_name],
        analysis_data=Dict(
            :analysis_type => :random_continuous_generator,
            :distribution => analysis.distribution,
            :parameters => analysis.parameters,
            :seed => analysis.seed,
            :count => analysis.count
        ),
        calculations=summary
    )

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

    stat_keys = [
        :variable_name, :count, :mean, :std, :variance, :median, :q1, :q3,
        :iqr, :minimum, :maximum, :range, :skewness, :kurtosis
    ]
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
                :comment => _continuous_parameter_comment(String(key))
            ) for key in stat_keys
        ]
    ))

    add_table!(result, AnalysisTable(
        :preview,
        "Первые значения",
        [:index, :value];
        headers=Dict(
            :index => "Index",
            :value => "Value"
        ),
        rows=[Dict(:index => i, :value => v) for (i, v) in enumerate(first(values, min(length(values), 20)))]
    ))

    plot_options = default_plot_config(; palette_name=analysis.palette_name)
    merge!(plot_options, Dict(:legend => false))

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

    boxplot_spec = PlotSpec(
        :boxplot,
        "Boxplot of generated values",
        :boxplot;
        payload=Dict(
            :values => values
        ),
        options=merge(
            Dict(
                :ylabel => "Value"
            ),
            plot_options
        )
    )

    dashboard_spec = PlotSpec(
        :dashboard,
        "Scatterplot, histogram and boxplot dashboard",
        :dashboard;
        payload=Dict(
            :plots => [scatter_spec, histogram_spec, boxplot_spec]
        ),
        options=merge(
            Dict(
                :layout => (1, 3)
            ),
            plot_options
        )
    )

    add_plot!(result, scatter_spec)
    add_plot!(result, histogram_spec)
    add_plot!(result, boxplot_spec)
    add_plot!(result, dashboard_spec)

    if store
        add_result!(wb, result)
    end

    return result
end
