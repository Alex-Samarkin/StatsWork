"""
    NormalityAnalysis

Проверка нормальности одной числовой выборки несколькими критериями.
"""
struct NormalityAnalysis <: AbstractAnalysis
    info::AnalysisInfo
    variable::Symbol
    confidence_probability::Float64
    ks_corrected_simulations::Int
    random_seed::Int
    palette_name::Symbol
end

"""
    NormalityAnalysis(variable; P=0.95, ...)

Создает exploratory-анализ нормальности выборки. Анализ очищает входной вектор,
оценивает параметры нормального распределения по выборке и выполняет несколько
критериев согласия: Шапиро-Уилка, Колмогорова-Смирнова, KS с поправкой
Лиллиефорса (Monte Carlo), Андерсона-Дарлинга, Пирсона и Jarque-Bera.
"""
function NormalityAnalysis(variable::Symbol;
                           P::Real=0.95,
                           ks_corrected_simulations::Int=1000,
                           random_seed::Int=12345,
                           palette_name::Symbol=:colorful,
                           id::Symbol=:normality_analysis,
                           category_path::AbstractVector{Symbol}=[:exploratory, :normality],
                           title::AbstractString="Проверка нормальности выборки",
                           summary::AbstractString="Проверяет близость одной числовой выборки к нормальному распределению несколькими критериями и строит диагностические графики.",
                           description::AbstractString="Анализ оценивает параметры нормального распределения по очищенной выборке, выполняет несколько критериев согласия и строит графики: гистограмму с нормальной плотностью, сравнение CDF, кумулятивную гистограмму с нормальной CDF и QQ-график.",
                           interpretation::AbstractString="При p-value < α гипотеза нормальности отвергается. Критерии чувствительны к разным отклонениям: Шапиро-Уилка и Андерсона-Дарлинга хорошо замечают ненормальность формы, KS с поправкой учитывает оценивание параметров по самой выборке, а критерий Пирсона зависит от группировки по интервалам.")
    palette_name in available_plot_palettes() || error("Unsupported palette name: $palette_name")
    confidence_probability = _normality_normalize_probability(P)
    ks_corrected_simulations >= 100 || error("ks_corrected_simulations must be >= 100")

    info = AnalysisInfo(
        id;
        category_path=category_path,
        title=title,
        summary=summary,
        description=description,
        interpretation=interpretation,
        formulas=[
            FormulaSpec("alpha = 1 - P", "Уровень значимости, соответствующий доверительной вероятности P."),
            FormulaSpec("F_n(x) = (1/n) * sum(I(x_i <= x))", "Эмпирическая функция распределения."),
            FormulaSpec("D = sup_x |F_n(x) - F(x)|", "Статистика критерия Колмогорова-Смирнова."),
            FormulaSpec("A^2 = -n - (1/n) * sum((2i-1)(ln F(x_(i)) + ln(1-F(x_(n+1-i)))))", "Статистика Андерсона-Дарлинга."),
            FormulaSpec("X^2 = sum((O_i - E_i)^2 / E_i)", "Статистика критерия Пирсона по сгруппированным интервалам."),
            FormulaSpec("JB = n*(S^2/6 + (K-3)^2/24)", "Статистика Jarque-Bera по асимметрии и эксцессу.")
        ],
        notes=[
            "P=0.95 и P=95 интерпретируются как доверительная вероятность 95%.",
            "Перед расчетами исключаются missing, нечисловые и бесконечные значения.",
            "KS с поправкой реализован как Monte Carlo-приближение Лиллиефорса с повторным оцениванием mean и std на каждой симуляции.",
            "Критерий Пирсона использует равновероятные интервалы ожидаемого нормального распределения, чтобы ожидаемые частоты были достаточно устойчивыми.",
            "При почти постоянной выборке критерии нормальности неинформативны, поэтому анализ требует ненулевого разброса."
        ]
    )

    return NormalityAnalysis(
        info,
        variable,
        confidence_probability,
        ks_corrected_simulations,
        random_seed,
        palette_name
    )
end

analysis_info(analysis::NormalityAnalysis) = analysis.info
required_variables(analysis::NormalityAnalysis) = [analysis.variable]
produced_variables(::NormalityAnalysis) = Symbol[]

function _normality_normalize_probability(P::Real)
    probability = Float64(P)
    if 1 < probability < 100
        probability /= 100
    end
    0 < probability < 1 || error("Confidence probability P must be between 0 and 1, or between 1 and 100 as percent")
    return probability
end

function _normality_clean_numeric_values(values)
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

function _normality_row(test::AbstractString,
                        statistic,
                        p_value,
                        alpha,
                        decision::AbstractString,
                        method::AbstractString,
                        comment::AbstractString="")
    return Dict(
        :test => String(test),
        :statistic => statistic,
        :p_value => p_value,
        :alpha => alpha,
        :decision => String(decision),
        :method => String(method),
        :comment => String(comment)
    )
end

function _normality_decision(p_value, alpha)
    p_value === missing && return "не рассчитан"
    return p_value < alpha ? "отклонить H0" : "нет оснований отклонить H0"
end

function _ks_statistic(sorted_values::Vector{Float64}, dist::Normal)
    n = length(sorted_values)
    cdf_values = cdf.(Ref(dist), sorted_values)
    d_plus = maximum((i / n) - cdf_values[i] for i in 1:n)
    d_minus = maximum(cdf_values[i] - ((i - 1) / n) for i in 1:n)
    d = max(d_plus, d_minus)
    return d, d_plus, d_minus
end

function _ks_asymptotic_pvalue(n::Int, d::Float64)
    n <= 0 && return missing
    lambda = sqrt(n) * d
    lambda <= 0 && return 1.0
    return ccdf(Kolmogorov(), lambda)
end

function _anderson_darling_statistic(sorted_values::Vector{Float64}, dist::Normal)
    n = length(sorted_values)
    total = 0.0
    epsilon = eps(Float64)
    for i in 1:n
        fi = clamp(cdf(dist, sorted_values[i]), epsilon, 1 - epsilon)
        fj = clamp(cdf(dist, sorted_values[n - i + 1]), epsilon, 1 - epsilon)
        total += (2i - 1) * (log(fi) + log1p(-fj))
    end
    return -n - total / n
end

function _anderson_darling_pvalue(n::Int, a2::Float64)
    a2 <= 0 && return 1.0
    y = if a2 < 2.0
        exp(-1.2337141 / a2) *
        (2.00012 + (0.247105 - (0.0649821 - (0.0347962 - (0.0116720 - 0.00168691 * a2) * a2) * a2) * a2) * a2) / sqrt(a2)
    else
        exp(-exp(1.0776 - (2.30695 - (0.43424 - (0.082433 - (0.008056 - 0.0003146 * a2) * a2) * a2) * a2) * a2))
    end

    g1(x) = sqrt(x) * (1.0 - x) * (49.0 * x - 102.0)
    g2(x) = -0.00022633 + (6.54034 - (14.6538 - (14.458 - (8.259 - 1.91864 * x) * x) * x) * x) * x
    g3(x) = -130.2137 + (745.2337 - (1705.091 - (1950.646 - (1116.360 - 255.7844 * x) * x) * x) * x) * x

    pv = y
    if y > 0.8
        pv += g3(y) / n
    else
        c = 0.01265 + 0.1757 / n
        if y < c
            pv += (0.0037 / n^3 + 0.00078 / n^2 + 0.00006 / n) * g1(y / c)
        else
            pv += (0.04213 / n + 0.01365 / n^2) * g2((y - c) / (0.8 - c))
        end
    end
    return clamp(1.0 - pv, 0.0, 1.0)
end

function _jarque_bera_test(values::Vector{Float64})
    n = length(values)
    m1 = mean(values)
    centered = values .- m1
    m2 = mean(centered .^ 2)
    m3 = mean(centered .^ 3)
    m4 = mean(centered .^ 4)
    skew = m3 / m2^(3 / 2)
    kurt = m4 / m2^2
    statistic = n * (skew^2 / 6 + (kurt - 3)^2 / 24)
    p_value = ccdf(Chisq(2), statistic)
    return statistic, p_value, skew, kurt
end

for (name, coefficients) in [
    (:sw_c1, [0.0, 0.221157, -0.147981, -2.07119, 4.434685, -2.706056]),
    (:sw_c2, [0.0, 0.042981, -0.293762, -1.752461, 5.682633, -3.582633]),
    (:sw_c3, [0.5440, -0.39978, 0.025054, -0.0006714]),
    (:sw_c4, [1.3822, -0.77857, 0.062767, -0.0020322]),
    (:sw_c5, [-1.5861, -0.31082, -0.083751, 0.0038915]),
    (:sw_c6, [-0.4803, -0.082676, 0.0030302]),
    (:sw_g, [-2.273, 0.459])
]
    @eval function $(name)(x)
        coeffs = $coefficients
        result = 0.0
        for coefficient in reverse(coeffs)
            result = result * x + coefficient
        end
        return result
    end
end

function _shapiro_wilk_coefs(n::Int)
    n >= 3 || error("Shapiro-Wilk requires n >= 3")
    if n == 3
        w = sqrt(2.0) / 2.0
        return [w, 0.0, -w]
    end

    half_n = fld(n, 2)
    coefficients = Vector{Float64}(undef, n)
    half = view(coefficients, 1:half_n)
    for i in eachindex(half)
        half[i] = -quantile(Normal(), (i - 3 / 8) / (n + 1 / 4))
    end

    sumsq = 2 * sum(abs2, half)
    x = 1 / sqrt(n)
    a1 = half[1] / sqrt(sumsq) + sw_c1(x)

    if n <= 5
        phi = (sumsq - 2 * half[1]^2) / (1 - 2 * a1^2)
        half .= half ./ sqrt(phi)
        half[1] = a1
    else
        a2 = half[2] / sqrt(sumsq) + sw_c2(x)
        phi = (sumsq - 2 * half[1]^2 - 2 * half[2]^2) / (1 - 2 * a1^2 - 2 * a2^2)
        half .= half ./ sqrt(phi)
        half[1] = a1
        half[2] = a2
    end

    for i in 1:half_n
        coefficients[n - i + 1] = -coefficients[i]
    end
    if isodd(n)
        coefficients[half_n + 1] = 0.0
    end
    return coefficients
end

function _shapiro_wilk_test(sorted_values::Vector{Float64})
    n = length(sorted_values)
    n >= 3 || return (missing, missing, "нужен n >= 3")
    if sorted_values[end] - sorted_values[1] < n * eps(Float64)
        return (missing, missing, "выборка почти постоянна")
    end

    coefs = _shapiro_wilk_coefs(n)
    ax = sum(coefs .* sorted_values)
    m = mean(sorted_values)
    s2 = sum((x - m)^2 for x in sorted_values)
    w = clamp(ax^2 / s2, 0.0, 1.0)

    p_value = if n == 3
        1 - 6 * acos(sqrt(w)) / pi
    elseif n <= 11
        gamma = sw_g(n)
        transformed = -log(gamma - log1p(-w))
        mu = sw_c3(n)
        sigma = exp(sw_c4(n))
        ccdf(Normal(mu, sigma), transformed)
    else
        transformed = log1p(-w)
        mu = sw_c5(log(n))
        sigma = exp(sw_c6(log(n)))
        ccdf(Normal(mu, sigma), transformed)
    end

    note = n > 5000 ? "p-value outside the most reliable range of Royston approximation" : ""
    return w, clamp(p_value, 0.0, 1.0), note
end

function _ks_lilliefors_bootstrap(sorted_values::Vector{Float64},
                                  dist::Normal;
                                  simulations::Int,
                                  seed::Int)
    n = length(sorted_values)
    observed_d, _, _ = _ks_statistic(sorted_values, dist)
    rng = MersenneTwister(seed)
    exceed = 0

    for _ in 1:simulations
        sample = sort(rand(rng, dist, n))
        sample_mu = mean(sample)
        sample_sigma = std(sample)
        if sample_sigma <= eps(Float64)
            continue
        end
        simulated_dist = Normal(sample_mu, sample_sigma)
        simulated_d, _, _ = _ks_statistic(sample, simulated_dist)
        simulated_d >= observed_d && (exceed += 1)
    end

    p_value = (exceed + 1) / (simulations + 1)
    return observed_d, p_value
end

function _pearson_bin_count(n::Int)
    n < 20 && return 0
    return max(4, min(10, fld(n, 5)))
end

function _pearson_chi_square_test(sorted_values::Vector{Float64}, dist::Normal)
    n = length(sorted_values)
    bin_count = _pearson_bin_count(n)
    bin_count == 0 && return (missing, missing, missing, missing, "нужен n >= 20")

    expected = n / bin_count
    edges = [-Inf]
    for i in 1:(bin_count - 1)
        push!(edges, quantile(dist, i / bin_count))
    end
    push!(edges, Inf)

    observed = zeros(Int, bin_count)
    bin_index = 1
    for value in sorted_values
        while !(edges[bin_index] <= value < edges[bin_index + 1]) && bin_index < bin_count
            bin_index += 1
        end
        observed[bin_index] += 1
    end

    statistic = sum((count - expected)^2 / expected for count in observed)
    degrees_freedom = bin_count - 3
    degrees_freedom > 0 || return (missing, missing, observed, expected, "недостаточно степеней свободы")
    p_value = ccdf(Chisq(degrees_freedom), statistic)
    comment = "k=$(bin_count), df=$(degrees_freedom), E=$(round(expected; digits=2)) в каждом интервале"
    return statistic, p_value, observed, expected, comment
end

function _cdf_payload(sorted_values::Vector{Float64}, dist::Normal)
    n = length(sorted_values)
    empirical = collect(1:n) ./ n
    x_min = minimum(sorted_values)
    x_max = maximum(sorted_values)
    dist_mean = mean(dist)
    dist_std = std(dist)
    grid_left = min(x_min, dist_mean - 4 * dist_std)
    grid_right = max(x_max, dist_mean + 4 * dist_std)
    grid = collect(range(grid_left, grid_right; length=300))

    return Dict{Symbol, Any}(
        :x_empirical => sorted_values,
        :y_empirical => empirical,
        :x_theoretical => grid,
        :y_theoretical => cdf.(Ref(dist), grid)
    )
end

function _cumulative_hist_payload(sorted_values::Vector{Float64}, dist::Normal)
    x_min = minimum(sorted_values)
    x_max = maximum(sorted_values)
    dist_mean = mean(dist)
    dist_std = std(dist)
    grid_left = min(x_min, dist_mean - 4 * dist_std)
    grid_right = max(x_max, dist_mean + 4 * dist_std)
    grid = collect(range(grid_left, grid_right; length=300))

    return Dict{Symbol, Any}(
        :values => sorted_values,
        :x_theoretical => grid,
        :y_theoretical => cdf.(Ref(dist), grid)
    )
end

"""
    analyze(wb, analysis::NormalityAnalysis; store=true)

Выполняет анализ проверки нормальности для одной workbook-переменной.
"""
function analyze(wb, analysis::NormalityAnalysis; store::Bool=true)
    raw_values = getvar(wb, analysis.variable)
    values, skipped, total_n = _normality_clean_numeric_values(raw_values)
    isempty(values) && error("Variable `$(analysis.variable)` has no finite numeric values")

    sorted_values = sort(values)
    n = length(sorted_values)
    n >= 3 || error("Normality analysis requires at least 3 finite numeric values")

    mu = mean(sorted_values)
    sigma = std(sorted_values)
    sigma > eps(Float64) || error("Variable `$(analysis.variable)` has almost zero variance; normality tests are not informative")

    alpha = 1 - analysis.confidence_probability
    fitted_normal = Normal(mu, sigma)

    shapiro_stat, shapiro_p, shapiro_note = _shapiro_wilk_test(sorted_values)

    ks_stat, ks_dplus, ks_dminus = _ks_statistic(sorted_values, fitted_normal)
    ks_p = _ks_asymptotic_pvalue(n, ks_stat)

    lilliefors_stat, lilliefors_p = _ks_lilliefors_bootstrap(
        sorted_values,
        fitted_normal;
        simulations=analysis.ks_corrected_simulations,
        seed=analysis.random_seed
    )

    ad_stat = _anderson_darling_statistic(sorted_values, fitted_normal)
    ad_p = _anderson_darling_pvalue(n, ad_stat)

    pearson_stat, pearson_p, pearson_observed, pearson_expected, pearson_note =
        _pearson_chi_square_test(sorted_values, fitted_normal)

    jb_stat, jb_p, jb_skew, jb_kurt = _jarque_bera_test(sorted_values)

    calculations = Dict{Symbol, Any}(
        :variable => analysis.variable,
        :count => n,
        :total_count => total_n,
        :skipped => skipped,
        :confidence_probability => analysis.confidence_probability,
        :alpha => alpha,
        :mean => mu,
        :std => sigma,
        :shapiro_w => shapiro_stat,
        :shapiro_p => shapiro_p,
        :ks_d => ks_stat,
        :ks_d_plus => ks_dplus,
        :ks_d_minus => ks_dminus,
        :ks_p => ks_p,
        :lilliefors_d => lilliefors_stat,
        :lilliefors_p => lilliefors_p,
        :anderson_darling_a2 => ad_stat,
        :anderson_darling_p => ad_p,
        :pearson_chi_square => pearson_stat,
        :pearson_p => pearson_p,
        :pearson_observed => pearson_observed,
        :pearson_expected => pearson_expected,
        :jarque_bera => jb_stat,
        :jarque_bera_p => jb_p,
        :jarque_bera_skewness => jb_skew,
        :jarque_bera_kurtosis => jb_kurt
    )

    result = BaseAnalysisResult(
        analysis.info;
        input_variables=[analysis.variable],
        output_variables=Symbol[],
        analysis_data=Dict(
            :analysis_type => :normality,
            :variable => analysis.variable,
            :confidence_probability => analysis.confidence_probability,
            :ks_corrected_simulations => analysis.ks_corrected_simulations
        ),
        calculations=calculations
    )

    add_table!(result, AnalysisTable(
        :sample,
        "Сводка по выборке",
        [:metric, :value, :comment];
        headers=Dict(:metric => "Параметр", :value => "Значение", :comment => "Комментарий"),
        rows=[
            Dict(:metric => "Количество", :value => n, :comment => "Число конечных числовых наблюдений"),
            Dict(:metric => "Всего значений", :value => total_n, :comment => "Длина исходной переменной"),
            Dict(:metric => "Исключено", :value => skipped, :comment => "Missing, нечисловые или бесконечные"),
            Dict(:metric => "Среднее", :value => mu, :comment => "Оценка μ нормального распределения"),
            Dict(:metric => "Стандартное отклонение", :value => sigma, :comment => "Оценка σ нормального распределения"),
            Dict(:metric => "Доверительная вероятность P", :value => analysis.confidence_probability, :comment => "По умолчанию 0.95"),
            Dict(:metric => "Уровень значимости α", :value => alpha, :comment => "α = 1 - P")
        ]
    ))

    normality_rows = [
        _normality_row(
            "Шапиро-Уилк",
            shapiro_stat,
            shapiro_p,
            alpha,
            _normality_decision(shapiro_p, alpha),
            "Shapiro-Wilk W",
            isempty(shapiro_note) ? "чувствителен к общим отклонениям от нормальности" : shapiro_note
        ),
        _normality_row(
            "Колмогоров-Смирнов",
            ks_stat,
            ks_p,
            alpha,
            _normality_decision(ks_p, alpha),
            "Asymptotic one-sample KS",
            "сравнение с N(μ̂, σ̂); D+=$(round(ks_dplus; digits=4)), D-=$(round(ks_dminus; digits=4))"
        ),
        _normality_row(
            "KS с поправкой Лиллиефорса",
            lilliefors_stat,
            lilliefors_p,
            alpha,
            _normality_decision(lilliefors_p, alpha),
            "Monte Carlo corrected KS",
            "simulations=$(analysis.ks_corrected_simulations), seed=$(analysis.random_seed)"
        ),
        _normality_row(
            "Андерсон-Дарлинг",
            ad_stat,
            ad_p,
            alpha,
            _normality_decision(ad_p, alpha),
            "Anderson-Darling A^2",
            "повышенная чувствительность к хвостам"
        ),
        _normality_row(
            "Пирсон Chi-Square",
            pearson_stat,
            pearson_p,
            alpha,
            _normality_decision(pearson_p, alpha),
            "Grouped Pearson chi-square",
            pearson_note
        ),
        _normality_row(
            "Jarque-Bera",
            jb_stat,
            jb_p,
            alpha,
            _normality_decision(jb_p, alpha),
            "Omnibus skewness-kurtosis test",
            "skew=$(round(jb_skew; digits=4)), kurtosis=$(round(jb_kurt; digits=4))"
        )
    ]

    add_table!(result, AnalysisTable(
        :normality_tests,
        "Результаты проверки нормальности",
        [:test, :statistic, :p_value, :alpha, :decision, :method, :comment];
        headers=Dict(
            :test => "Критерий",
            :statistic => "Статистика",
            :p_value => "p-value",
            :alpha => "α",
            :decision => "Решение",
            :method => "Метод",
            :comment => "Комментарий"
        ),
        rows=normality_rows
    ))

    add_table!(result, AnalysisTable(
        :summary,
        "Краткая сводка",
        [:test, :statistic, :p_value, :decision];
        headers=Dict(
            :test => "Критерий",
            :statistic => "Статистика",
            :p_value => "p-value",
            :decision => "Решение"
        ),
        rows=[Dict(
            :test => row[:test],
            :statistic => row[:statistic],
            :p_value => row[:p_value],
            :decision => row[:decision]
        ) for row in normality_rows]
    ))

    plot_options = default_plot_config(; palette_name=analysis.palette_name)
    merge!(plot_options, Dict(:legend => true))

    add_plot!(result, PlotSpec(
        :histogram_normal_density,
        "Гистограмма и ожидаемое нормальное распределение",
        :histogram_normal;
        payload=Dict(:values => sorted_values, :mean => mu, :std => sigma),
        options=merge(
            Dict(
                :xlabel => "Value",
                :ylabel => "Density",
                :legend => true
            ),
            plot_options
        )
    ))

    add_plot!(result, PlotSpec(
        :cdf_compare,
        "CDF: эмпирическая и нормальная",
        :cdf_compare;
        payload=_cdf_payload(sorted_values, fitted_normal),
        options=merge(
            Dict(
                :xlabel => "Value",
                :ylabel => "CDF",
                :legend => true
            ),
            plot_options
        )
    ))

    add_plot!(result, PlotSpec(
        :cumulative_histogram,
        "Кумулятивная гистограмма и нормальная CDF",
        :cumhist_normal_cdf;
        payload=_cumulative_hist_payload(sorted_values, fitted_normal),
        options=merge(
            Dict(
                :xlabel => "Value",
                :ylabel => "Cumulative probability",
                :legend => true
            ),
            plot_options
        )
    ))

    add_plot!(result, PlotSpec(
        :qq,
        "Нормальный QQ-график",
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
    ))

    if store
        add_result!(wb, result)
    end

    return result
end
