###############################################################################
# TEMPLATE_full_analysis.jl
#
# Шаблон полного analysis-модуля для StatsWorkbench.
#
# Как использовать:
# 1. Скопируйте этот файл в нужную папку, например:
#    src/Analyses/Exploratory/my_new_analysis.jl
# 2. Переименуйте тип `FullAnalysisTemplateAnalysis` во что-то предметное:
#    например `OutlierScreeningAnalysis` или `CorrelationProfileAnalysis`.
# 3. Переименуйте helper-функции с префиксом `_template_`, чтобы избежать
#    конфликтов имен, если несколько анализов будут подключены одновременно.
# 4. Добавьте `include("Analyses/.../my_new_analysis.jl")` в `src/StatsWorkbench.jl`.
# 5. Добавьте новый тип в `export`, если анализ должен быть публичным API.
#
# Файл намеренно НЕ подключен в StatsWorkbench.jl. Это заготовка, а не рабочий
# модуль пакета. После копирования и переименования он показывает полный путь:
# входные переменные -> расчеты -> выходная переменная -> таблицы -> markdown/html
# через стандартный report layer -> 3 графика -> 4-й график dashboard-панель.
###############################################################################

"""
    FullAnalysisTemplateAnalysis

Короткое назначение анализа.

В реальном модуле замените этот текст на предметное описание: какие данные
анализ принимает, какие статистики считает, какие результаты сохраняет в
workbook и как пользователь должен интерпретировать таблицы и графики.
"""
struct FullAnalysisTemplateAnalysis <: AbstractAnalysis
    # `info` хранит весь текстовый паспорт анализа: заголовок, описание,
    # формулы, интерпретацию и заметки. Результаты и отчеты читают именно его.
    info::AnalysisInfo

    # Обычно анализ принимает одну или несколько workbook-переменных по имени.
    # Если нужно несколько входов, замените поле на `variables::Vector{Symbol}`.
    variable::Symbol

    # Пример параметра анализа. В реальном анализе это может быть порог,
    # метод, число итераций, доверительная вероятность и т.п.
    threshold::Float64

    # Пример выходной переменной. Если анализ ничего не сохраняет в workbook,
    # можно убрать это поле и вернуть `Symbol[]` из `produced_variables`.
    output_namespace::Union{Nothing, Symbol}
    output_name::Union{Nothing, Symbol}

    # Единый выбор палитры делает графики анализа согласованными с остальными.
    palette_name::Symbol
end

"""
    FullAnalysisTemplateAnalysis(variable; ...)

Конструктор не выполняет вычисления. Он только проверяет параметры и собирает
спецификацию анализа, которую позже исполнит `analyze(wb, analysis)`.
"""
function FullAnalysisTemplateAnalysis(variable::Symbol;
                                      threshold::Real=0.0,
                                      output_namespace::Union{Nothing, Symbol}=:derived,
                                      output_name::Union{Nothing, Symbol}=nothing,
                                      palette_name::Symbol=:colorful,
                                      id::Symbol=:full_analysis_template,
                                      category_path::AbstractVector{Symbol}=[:template],
                                      title::AbstractString="Full analysis template",
                                      summary::AbstractString="Template for a complete StatsWorkbench analysis.",
                                      description::AbstractString="Shows input handling, output variables, calculations, several tables, report text and four plots including a dashboard.",
                                      interpretation::AbstractString="Replace this text with practical guidance for reading the analysis result.")
    palette_name in available_plot_palettes() || error("Unsupported palette name: $palette_name")

    info = AnalysisInfo(
        id;
        category_path=category_path,
        title=title,
        summary=summary,
        description=description,
        interpretation=interpretation,
        formulas=[
            FormulaSpec("z_i = (x_i - mean(x)) / std(x)", "Пример стандартизации входной переменной."),
            FormulaSpec("flag_i = abs(z_i) > threshold", "Пример производного признака для сохранения в workbook."),
            FormulaSpec("summary = f(clean_values)", "Замените на реальные формулы анализа.")
        ],
        notes=[
            "Этот файл является шаблоном и не должен подключаться без переименования.",
            "Таблицы автоматически попадают в markdown/html/xlsx через save_report.",
            "Графики описываются декларативно через PlotSpec и строятся позже через plot1/plot2/plot3/plot4."
        ],
        metadata=Dict(
            :template => true,
            :recommended_copy_path => "src/Analyses/Exploratory/<your_analysis>.jl"
        )
    )

    return FullAnalysisTemplateAnalysis(
        info,
        variable,
        Float64(threshold),
        output_namespace,
        output_name,
        palette_name
    )
end

# Эти три функции образуют минимальный контракт любого анализа.
analysis_info(analysis::FullAnalysisTemplateAnalysis) = analysis.info
required_variables(analysis::FullAnalysisTemplateAnalysis) = [analysis.variable]

function produced_variables(analysis::FullAnalysisTemplateAnalysis)
    analysis.output_namespace === nothing && return Symbol[]
    name = analysis.output_name === nothing ? Symbol(string(analysis.variable), "_template_output") : analysis.output_name
    return [Symbol(string(analysis.output_namespace), ".", string(name))]
end

function _template_clean_numeric_values(values)
    collected = collect(values)
    clean = Float64[]
    skipped = 0

    # В шаблоне входная обработка сделана явно: так в реальном анализе легко
    # решить, что делать с missing, Inf, строками, категориальными значениями.
    for value in collected
        if value === missing
            skipped += 1
        elseif value isa Number
            converted = Float64(value)
            if isfinite(converted)
                push!(clean, converted)
            else
                skipped += 1
            end
        else
            skipped += 1
        end
    end

    return clean, skipped, length(collected)
end

function _template_metric_row(metric::AbstractString, value, comment::AbstractString="")
    return Dict(:metric => String(metric), :value => value, :comment => String(comment))
end

function _template_preview_rows(values::Vector{Float64}, zscores::Vector{Float64}, flags::AbstractVector{Bool}; limit::Int=20)
    rows = Dict{Symbol, Any}[]
    for i in 1:min(limit, length(values))
        push!(rows, Dict(
            :index => i,
            :value => values[i],
            :zscore => zscores[i],
            :flag => flags[i]
        ))
    end
    return rows
end

function _template_quantile_rows(values::Vector{Float64})
    rows = Dict{Symbol, Any}[]
    for p in [0.0, 0.25, 0.5, 0.75, 1.0]
        push!(rows, Dict(
            :probability => p,
            :quantile => quantile(values, p)
        ))
    end
    return rows
end

"""
    analyze(wb, analysis::FullAnalysisTemplateAnalysis; store=true)

Стандартный сценарий исполнения:
1. Получить входные данные из workbook.
2. Очистить и проверить данные.
3. Выполнить расчеты.
4. При необходимости сохранить выходную переменную.
5. Собрать `BaseAnalysisResult`.
6. Добавить несколько таблиц.
7. Добавить три самостоятельных графика и четвертый dashboard.
8. Сохранить результат в workbook, если `store=true`.
"""
function analyze(wb, analysis::FullAnalysisTemplateAnalysis; store::Bool=true)
    raw_values = getvar(wb, analysis.variable)
    values, skipped, total_n = _template_clean_numeric_values(raw_values)
    isempty(values) && error("Variable `$(analysis.variable)` has no finite numeric values")

    n = length(values)
    mean_value = mean(values)
    std_value = n == 1 ? 0.0 : std(values)
    min_value = minimum(values)
    max_value = maximum(values)

    # В примере выходной вектор - z-score. Если разброс нулевой, все z-score
    # равны нулю: это лучше, чем деление на 0 и NaN в результатах.
    zscores = std_value == 0 ? zeros(Float64, n) : (values .- mean_value) ./ std_value
    flags = abs.(zscores) .> analysis.threshold
    output_values = zscores

    output_variables = produced_variables(analysis)
    if analysis.output_namespace !== nothing
        target_name = analysis.output_name === nothing ? Symbol(string(analysis.variable), "_template_output") : analysis.output_name
        expression = "zscore($(analysis.variable))"

        # `store_vector!` сохраняет производный вектор в workspace. Это
        # главный шаблон для анализов, которые не только считают отчет,
        # но и создают новые workbook-переменные для дальнейшей работы.
        store_vector!(
            wb.space,
            analysis.output_namespace,
            target_name,
            output_values;
            origin=:analysis,
            dirty=true,
            expression=expression
        )
        push!(wb.logs, string(first(output_variables), " <- ", expression))
    end

    calculations = Dict{Symbol, Any}(
        :variable => analysis.variable,
        :count => n,
        :total_count => total_n,
        :skipped => skipped,
        :threshold => analysis.threshold,
        :mean => mean_value,
        :std => std_value,
        :minimum => min_value,
        :maximum => max_value,
        :flag_count => count(flags),
        :flag_share => count(flags) / n
    )

    result = BaseAnalysisResult(
        analysis.info;
        input_variables=[analysis.variable],
        output_variables=output_variables,
        analysis_data=Dict(
            :analysis_type => :full_analysis_template,
            :variable => analysis.variable,
            :threshold => analysis.threshold
        ),
        calculations=calculations
    )

    # Таблица 1: короткая сводка. Если у результата есть таблица `:summary`,
    # именно она будет возвращаться по умолчанию через `to_table(result)`.
    add_table!(result, AnalysisTable(
        :summary,
        "Summary",
        [:metric, :value, :comment];
        headers=Dict(:metric => "Metric", :value => "Value", :comment => "Comment"),
        rows=[
            _template_metric_row("Count", n, "Finite numeric values"),
            _template_metric_row("Skipped", skipped, "Missing, nonnumeric or infinite values"),
            _template_metric_row("Mean", mean_value),
            _template_metric_row("Std", std_value),
            _template_metric_row("Flag count", calculations[:flag_count], "abs(zscore) > threshold"),
            _template_metric_row("Output variable", isempty(output_variables) ? "not stored" : String(first(output_variables)))
        ]
    ))

    # Таблица 2: параметры запуска. Она полезна для воспроизводимости отчета.
    add_table!(result, AnalysisTable(
        :parameters,
        "Analysis parameters",
        [:parameter, :value, :comment];
        headers=Dict(:parameter => "Parameter", :value => "Value", :comment => "Comment"),
        rows=[
            Dict(:parameter => "variable", :value => String(analysis.variable), :comment => "Input workbook variable"),
            Dict(:parameter => "threshold", :value => analysis.threshold, :comment => "Flagging threshold"),
            Dict(:parameter => "palette_name", :value => String(analysis.palette_name), :comment => "Plot palette"),
            Dict(:parameter => "output_namespace", :value => analysis.output_namespace, :comment => "Where output is stored")
        ]
    ))

    # Таблица 3: квантили. В реальном анализе это может быть любая
    # дополнительная таблица: модели, коэффициенты, диагностика, сравнения.
    add_table!(result, AnalysisTable(
        :quantiles,
        "Quantiles",
        [:probability, :quantile];
        headers=Dict(:probability => "Probability", :quantile => "Quantile"),
        rows=_template_quantile_rows(values)
    ))

    # Таблица 4: preview построчных расчетов. Полные построчные таблицы могут
    # быть очень большими, поэтому шаблон показывает первые 20 строк.
    add_table!(result, AnalysisTable(
        :preview,
        "Calculation preview",
        [:index, :value, :zscore, :flag];
        headers=Dict(:index => "Index", :value => "Value", :zscore => "Z-score", :flag => "Flag"),
        rows=_template_preview_rows(values, zscores, flags)
    ))

    plot_options = default_plot_config(; palette_name=analysis.palette_name)
    merge!(plot_options, Dict(:legend => false))

    # График 1: линия значений по индексу.
    line_spec = PlotSpec(
        :values_line,
        "Values by index",
        :line;
        payload=Dict(:x => collect(1:n), :y => values),
        options=merge(Dict(:xlabel => "Index", :ylabel => "Value"), plot_options)
    )

    # График 2: гистограмма распределения.
    histogram_spec = PlotSpec(
        :histogram,
        "Value distribution",
        :histogram;
        payload=Dict(:values => values),
        options=merge(Dict(:xlabel => "Value", :ylabel => "Frequency"), plot_options)
    )

    # График 3: scatter z-score по индексу. Для более сложной разметки можно
    # добавить отдельный kind в `Core/graphics.jl`, но базовый scatter уже
    # покрывает многие диагностические задачи.
    zscore_spec = PlotSpec(
        :zscore_scatter,
        "Z-scores by index",
        :scatter;
        payload=Dict(:x => collect(1:n), :y => zscores),
        options=merge(Dict(:xlabel => "Index", :ylabel => "Z-score"), plot_options)
    )

    # График 4: dashboard-панель из трех предыдущих графиков. Это стандартный
    # паттерн StatsWorkbench: дочерние PlotSpec переиспользуются без повторного
    # описания данных.
    dashboard_spec = PlotSpec(
        :dashboard,
        "Template dashboard",
        :dashboard;
        payload=Dict(:plots => [line_spec, histogram_spec, zscore_spec]),
        options=merge(Dict(:layout => (1, 3)), plot_options)
    )

    add_plot!(result, line_spec)
    add_plot!(result, histogram_spec)
    add_plot!(result, zscore_spec)
    add_plot!(result, dashboard_spec)

    if store
        add_result!(wb, result)
    end

    return result
end
