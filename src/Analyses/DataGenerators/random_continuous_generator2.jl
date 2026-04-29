"""
    RandomContinuousGenerator2Analysis

Спецификация генератора специальных и комбинированных непрерывных
случайных распределений.

Этот генератор дополняет `RandomContinuousGeneratorAnalysis`: здесь собраны
более редкие семейства, усеченные распределения, смеси и трансформации.
"""
struct RandomContinuousGenerator2Analysis <: AbstractAnalysis
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
    RandomContinuousGenerator2Analysis(target; distribution, parameters, count, seed, ...)

Создает воспроизводимый сценарий генерации специальных непрерывных
распределений. Поддерживаются редкие распределения из Distributions.jl,
усеченные версии известных распределений, смеси и трансформации.
"""
function RandomContinuousGenerator2Analysis(target::Symbol;
                                            distribution::AbstractString,
                                            parameters::AbstractDict{Symbol}=Dict{Symbol, Any}(),
                                            count::Integer,
                                            seed::Integer,
                                            namespace::Symbol=:generated,
                                            palette_name::Symbol=:colorful,
                                            id::Symbol=:random_continuous_generator2,
                                            category_path::AbstractVector{Symbol}=[:data_generator, :special_continuous_distributions],
                                            title::AbstractString="Генератор специальных непрерывных распределений",
                                            summary::AbstractString="Создает числовую случайную выборку из редких, усеченных, смешанных или трансформированных непрерывных распределений.",
                                            description::AbstractString="Генератор использует Distributions.jl там, где распределение доступно напрямую, и явные композиции для смесей и трансформаций. Seed фиксирует воспроизводимость выборки.",
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
            FormulaSpec("xᵢ ~ SpecialDistribution(parameters)", "Наблюдения генерируются из выбранного специального распределения, смеси или трансформации."),
            FormulaSpec("seed -> reproducible sample", "Одинаковый seed дает одинаковую последовательность.")
        ],
        notes=[
            "Название распределения задается английским именем.",
            "Смеси используют веса компонент, а трансформации применяются к базовым случайным величинам."
        ]
    )

    return RandomContinuousGenerator2Analysis(
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

analysis_info(analysis::RandomContinuousGenerator2Analysis) = analysis.info
required_variables(::RandomContinuousGenerator2Analysis) = Symbol[]
produced_variables(analysis::RandomContinuousGenerator2Analysis) = [
    Symbol(string(analysis.namespace), ".", string(analysis.target))
]

function _probability_param(parameters::Dict{Symbol, Any}, name::Symbol, default)
    value = Float64(_optional_param(parameters, name, default))
    0.0 <= value <= 1.0 || error("`$(name)` must be between 0 and 1")
    return value
end

function _positive_param(parameters::Dict{Symbol, Any}, name::Symbol, default)
    value = Float64(_optional_param(parameters, name, default))
    value > 0.0 || error("`$(name)` must be positive")
    return value
end

function _rand_continuous_generator2(name::AbstractString,
                                     parameters::Dict{Symbol, Any},
                                     count::Int)
    if name in ("gev", "generalizedextremevalue")
        mu = Float64(_optional_param(parameters, :mu, _optional_param(parameters, :location, 0.0)))
        sigma = _positive_param(parameters, :sigma, _optional_param(parameters, :scale, 1.0))
        xi = Float64(_optional_param(parameters, :xi, _optional_param(parameters, :shape, 0.1)))
        return rand(GeneralizedExtremeValue(mu, sigma, xi), count)
    elseif name in ("gpd", "generalizedpareto")
        mu = Float64(_optional_param(parameters, :mu, _optional_param(parameters, :location, 0.0)))
        sigma = _positive_param(parameters, :sigma, _optional_param(parameters, :scale, 1.0))
        xi = Float64(_optional_param(parameters, :xi, _optional_param(parameters, :shape, 0.2)))
        return rand(GeneralizedPareto(mu, sigma, xi), count)
    elseif name == "vonmises"
        mu = Float64(_optional_param(parameters, :mu, 0.0))
        kappa = _positive_param(parameters, :kappa, 1.0)
        return rand(VonMises(mu, kappa), count)
    elseif name == "erlang"
        shape = Int(_optional_param(parameters, :shape, _optional_param(parameters, :k, 3)))
        scale = _positive_param(parameters, :scale, _optional_param(parameters, :theta, 1.0))
        return rand(Erlang(shape, scale), count)
    elseif name == "epanechnikov"
        mu = Float64(_optional_param(parameters, :mu, 0.0))
        sigma = _positive_param(parameters, :sigma, _optional_param(parameters, :scale, 1.0))
        return rand(Epanechnikov(mu, sigma), count)
    elseif name == "biweight"
        mu = Float64(_optional_param(parameters, :mu, 0.0))
        sigma = _positive_param(parameters, :sigma, _optional_param(parameters, :scale, 1.0))
        return rand(Biweight(mu, sigma), count)
    elseif name == "triweight"
        mu = Float64(_optional_param(parameters, :mu, 0.0))
        sigma = _positive_param(parameters, :sigma, _optional_param(parameters, :scale, 1.0))
        return rand(Triweight(mu, sigma), count)
    elseif name == "cosine"
        mu = Float64(_optional_param(parameters, :mu, 0.0))
        sigma = _positive_param(parameters, :sigma, _optional_param(parameters, :scale, 1.0))
        return rand(Cosine(mu, sigma), count)
    elseif name == "semicircle"
        mu = Float64(_optional_param(parameters, :mu, 0.0))
        radius = _positive_param(parameters, :radius, _optional_param(parameters, :scale, 1.0))
        return rand(LocationScale(mu, radius, Semicircle(1.0)), count)
    elseif name == "noncentralbeta"
        alpha = _positive_param(parameters, :alpha, 2.0)
        beta = _positive_param(parameters, :beta, 3.0)
        lambda = Float64(_optional_param(parameters, :lambda, 1.0))
        return rand(NoncentralBeta(alpha, beta, lambda), count)
    elseif name in ("betaprime", "betaprime2")
        alpha = _positive_param(parameters, :alpha, 2.0)
        beta = _positive_param(parameters, :beta, 3.0)
        return rand(BetaPrime(alpha, beta), count)
    elseif name in ("pgen-gaussian", "pgeneralizedgaussian", "powergeneralizedgaussian")
        mu = Float64(_optional_param(parameters, :mu, 0.0))
        alpha = _positive_param(parameters, :alpha, _optional_param(parameters, :scale, 1.0))
        p = _positive_param(parameters, :p, 1.5)
        return rand(PGeneralizedGaussian(mu, alpha, p), count)
    elseif name in ("symtriangular", "symmetrictriangular")
        mu = Float64(_optional_param(parameters, :mu, 0.0))
        sigma = _positive_param(parameters, :sigma, _optional_param(parameters, :scale, 1.0))
        return rand(SymTriangularDist(mu, sigma), count)
    elseif name in ("scaledt", "shiftedscaledt", "locationscalet")
        mu = Float64(_optional_param(parameters, :mu, _optional_param(parameters, :location, 0.0)))
        sigma = _positive_param(parameters, :sigma, _optional_param(parameters, :scale, 1.0))
        nu = _positive_param(parameters, :nu, _optional_param(parameters, :df, 5.0))
        return rand(LocationScale(mu, sigma, TDist(nu)), count)
    elseif name == "truncatednormal"
        mu = Float64(_optional_param(parameters, :mu, 0.0))
        sigma = _positive_param(parameters, :sigma, 1.0)
        lower = Float64(_optional_param(parameters, :lower, mu - 2sigma))
        upper = Float64(_optional_param(parameters, :upper, mu + 2sigma))
        return rand(truncated(Normal(mu, sigma), lower, upper), count)
    elseif name == "truncatedlognormal"
        mu = Float64(_optional_param(parameters, :mu, 0.0))
        sigma = _positive_param(parameters, :sigma, 1.0)
        lower = Float64(_optional_param(parameters, :lower, 0.0))
        upper = Float64(_optional_param(parameters, :upper, exp(mu + 2sigma)))
        return rand(truncated(LogNormal(mu, sigma), lower, upper), count)
    elseif name == "truncatedgamma"
        alpha = _positive_param(parameters, :alpha, _optional_param(parameters, :shape, 2.0))
        theta = _positive_param(parameters, :theta, _optional_param(parameters, :scale, 1.0))
        lower = Float64(_optional_param(parameters, :lower, 0.0))
        upper = Float64(_optional_param(parameters, :upper, alpha * theta * 3))
        return rand(truncated(Gamma(alpha, theta), lower, upper), count)
    elseif name == "truncatedcauchy"
        mu = Float64(_optional_param(parameters, :mu, _optional_param(parameters, :location, 0.0)))
        sigma = _positive_param(parameters, :sigma, _optional_param(parameters, :scale, 1.0))
        lower = Float64(_optional_param(parameters, :lower, mu - 10sigma))
        upper = Float64(_optional_param(parameters, :upper, mu + 10sigma))
        return rand(truncated(Cauchy(mu, sigma), lower, upper), count)
    elseif name in ("normalmixture2", "bimodalnormal")
        mu1 = Float64(_optional_param(parameters, :mu1, -2.0))
        sigma1 = _positive_param(parameters, :sigma1, 1.0)
        mu2 = Float64(_optional_param(parameters, :mu2, 2.0))
        sigma2 = _positive_param(parameters, :sigma2, 1.0)
        weight1 = _probability_param(parameters, :weight1, 0.5)
        return rand(MixtureModel(Normal[Normal(mu1, sigma1), Normal(mu2, sigma2)], [weight1, 1 - weight1]), count)
    elseif name == "normalmixture3"
        mu1 = Float64(_optional_param(parameters, :mu1, -3.0))
        mu2 = Float64(_optional_param(parameters, :mu2, 0.0))
        mu3 = Float64(_optional_param(parameters, :mu3, 3.0))
        sigma1 = _positive_param(parameters, :sigma1, 0.7)
        sigma2 = _positive_param(parameters, :sigma2, 1.0)
        sigma3 = _positive_param(parameters, :sigma3, 0.7)
        w1 = _probability_param(parameters, :weight1, 0.3)
        w2 = _probability_param(parameters, :weight2, 0.4)
        w1 + w2 <= 1.0 || error("`weight1 + weight2` must be <= 1")
        return rand(MixtureModel(Normal[Normal(mu1, sigma1), Normal(mu2, sigma2), Normal(mu3, sigma3)], [w1, w2, 1 - w1 - w2]), count)
    elseif name == "contaminatednormal"
        mu = Float64(_optional_param(parameters, :mu, 0.0))
        sigma = _positive_param(parameters, :sigma, 1.0)
        contamination = _probability_param(parameters, :contamination, 0.08)
        multiplier = _positive_param(parameters, :multiplier, 8.0)
        return rand(MixtureModel(Normal[Normal(mu, sigma), Normal(mu, sigma * multiplier)], [1 - contamination, contamination]), count)
    elseif name == "gammamixture2"
        alpha1 = _positive_param(parameters, :alpha1, 2.0)
        theta1 = _positive_param(parameters, :theta1, 1.0)
        alpha2 = _positive_param(parameters, :alpha2, 8.0)
        theta2 = _positive_param(parameters, :theta2, 0.6)
        weight1 = _probability_param(parameters, :weight1, 0.5)
        return rand(MixtureModel(Gamma[Gamma(alpha1, theta1), Gamma(alpha2, theta2)], [weight1, 1 - weight1]), count)
    elseif name == "betamixture2"
        alpha1 = _positive_param(parameters, :alpha1, 2.0)
        beta1 = _positive_param(parameters, :beta1, 8.0)
        alpha2 = _positive_param(parameters, :alpha2, 8.0)
        beta2 = _positive_param(parameters, :beta2, 2.0)
        weight1 = _probability_param(parameters, :weight1, 0.5)
        return rand(MixtureModel(Beta[Beta(alpha1, beta1), Beta(alpha2, beta2)], [weight1, 1 - weight1]), count)
    elseif name == "lognormalmixture2"
        mu1 = Float64(_optional_param(parameters, :mu1, 0.0))
        sigma1 = _positive_param(parameters, :sigma1, 0.4)
        mu2 = Float64(_optional_param(parameters, :mu2, 1.5))
        sigma2 = _positive_param(parameters, :sigma2, 0.8)
        weight1 = _probability_param(parameters, :weight1, 0.7)
        return rand(MixtureModel(LogNormal[LogNormal(mu1, sigma1), LogNormal(mu2, sigma2)], [weight1, 1 - weight1]), count)
    elseif name == "uniformmixture2"
        a1 = Float64(_optional_param(parameters, :a1, -3.0))
        b1 = Float64(_optional_param(parameters, :b1, -1.0))
        a2 = Float64(_optional_param(parameters, :a2, 1.0))
        b2 = Float64(_optional_param(parameters, :b2, 3.0))
        weight1 = _probability_param(parameters, :weight1, 0.5)
        return rand(MixtureModel(Uniform[Uniform(a1, b1), Uniform(a2, b2)], [weight1, 1 - weight1]), count)
    elseif name == "exponentialmixture2"
        theta1 = _positive_param(parameters, :theta1, 0.5)
        theta2 = _positive_param(parameters, :theta2, 3.0)
        weight1 = _probability_param(parameters, :weight1, 0.7)
        return rand(MixtureModel(Exponential[Exponential(theta1), Exponential(theta2)], [weight1, 1 - weight1]), count)
    elseif name == "tmixture2"
        nu1 = _positive_param(parameters, :nu1, 3.0)
        nu2 = _positive_param(parameters, :nu2, 15.0)
        weight1 = _probability_param(parameters, :weight1, 0.5)
        return rand(MixtureModel(TDist[TDist(nu1), TDist(nu2)], [weight1, 1 - weight1]), count)
    elseif name == "foldednormal"
        mu = Float64(_optional_param(parameters, :mu, 0.0))
        sigma = _positive_param(parameters, :sigma, 1.0)
        return abs.(rand(Normal(mu, sigma), count))
    elseif name == "halfnormal"
        sigma = _positive_param(parameters, :sigma, 1.0)
        return abs.(rand(Normal(0.0, sigma), count))
    elseif name == "ratioofnormals"
        mu1 = Float64(_optional_param(parameters, :mu1, 0.0))
        sigma1 = _positive_param(parameters, :sigma1, 1.0)
        mu2 = Float64(_optional_param(parameters, :mu2, 0.0))
        sigma2 = _positive_param(parameters, :sigma2, 1.0)
        denominator_floor = _positive_param(parameters, :denominator_floor, eps(Float64))
        numerator = rand(Normal(mu1, sigma1), count)
        denominator = rand(Normal(mu2, sigma2), count)
        denominator = [abs(v) < denominator_floor ? copysign(denominator_floor, v == 0 ? 1.0 : v) : v for v in denominator]
        return numerator ./ denominator
    elseif name == "productnormals"
        mu1 = Float64(_optional_param(parameters, :mu1, 0.0))
        sigma1 = _positive_param(parameters, :sigma1, 1.0)
        mu2 = Float64(_optional_param(parameters, :mu2, 0.0))
        sigma2 = _positive_param(parameters, :sigma2, 1.0)
        return rand(Normal(mu1, sigma1), count) .* rand(Normal(mu2, sigma2), count)
    elseif name == "sumgamma"
        alpha1 = _positive_param(parameters, :alpha1, 2.0)
        theta1 = _positive_param(parameters, :theta1, 1.0)
        alpha2 = _positive_param(parameters, :alpha2, 5.0)
        theta2 = _positive_param(parameters, :theta2, 0.5)
        return rand(Gamma(alpha1, theta1), count) .+ rand(Gamma(alpha2, theta2), count)
    end

    supported = [
        "gev", "generalizedpareto", "vonmises", "erlang", "epanechnikov",
        "biweight", "triweight", "cosine", "semicircle", "noncentralbeta",
        "betaprime", "pgeneralizedgaussian", "symmetrictriangular",
        "shiftedscaledt", "truncatednormal", "truncatedlognormal",
        "truncatedgamma", "truncatedcauchy", "normalmixture2",
        "normalmixture3", "contaminatednormal", "gammamixture2",
        "betamixture2", "lognormalmixture2", "uniformmixture2",
        "exponentialmixture2", "tmixture2", "foldednormal", "halfnormal",
        "ratioofnormals", "productnormals", "sumgamma"
    ]
    error("Unsupported distribution `$name`. Supported: $(join(supported, ", "))")
end

"""
    analyze(wb, analysis::RandomContinuousGenerator2Analysis; store=true)

Исполняет генерацию специальной непрерывной выборки, сохраняет ее в workbook,
считает основные статистики и добавляет scatterplot, histogram, boxplot и
dashboard из трех графиков.
"""
function analyze(wb, analysis::RandomContinuousGenerator2Analysis; store::Bool=true)
    Random.seed!(analysis.seed)
    values = Float64.(_rand_continuous_generator2(analysis.distribution, analysis.parameters, analysis.count))

    expression = "rand_special($(analysis.distribution), count=$(analysis.count), seed=$(analysis.seed))"
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
            :analysis_type => :random_continuous_generator2,
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
