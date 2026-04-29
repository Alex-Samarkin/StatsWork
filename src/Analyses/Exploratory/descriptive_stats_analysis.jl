"""
    DescriptiveStatsAnalysis

Спецификация анализа описательной статистики.

Объект этого типа не хранит сами данные, а только описание того,
какие workbook-переменные нужно взять и как затем оформить результат.
Это разделение полезно архитектурно: один объект задает "план" анализа,
а `analyze(wb, analysis)` уже исполняет его в контексте конкретного workbook.
"""
struct DescriptiveStatsAnalysis <: AbstractAnalysis
    info::AnalysisInfo
    variables::Vector{Symbol}
    output_namespace::Union{Nothing, Symbol}
end

"""
    DescriptiveStatsAnalysis(variables; ...)

Конструктор подготавливает метаописание анализа:
- куда он относится в дереве анализов (`category_path`);
- как называется;
- какую справку, интерпретацию и формулы будет получать результат.

На этом этапе никаких вычислений еще не происходит: мы только собираем
"паспорт" анализа, который потом будет вложен в `BaseAnalysisResult`.
"""
function DescriptiveStatsAnalysis(variables::AbstractVector{Symbol};
                                  id::Symbol=:descriptive_stats,
                                  category_path::AbstractVector{Symbol}=[:exploratory, :summary],
                                  title::AbstractString="Descriptive statistics",
                                  summary::AbstractString="Computes basic descriptive statistics for workbook variables.",
                                  description::AbstractString="The analysis inspects numeric workbook variables and summarizes central tendency, spread and missingness.",
                                  interpretation::AbstractString="Compare means, medians and variability across variables. Large missingness or strong gaps between mean and median may indicate skewness or data quality issues.",
                                  output_namespace::Union{Nothing, Symbol}=nothing)
    info = AnalysisInfo(
        id;
        category_path=category_path,
        title=title,
        summary=summary,
        description=description,
        interpretation=interpretation,
        formulas=[
            FormulaSpec("mean = sum(x) / n", "Average over non-missing values."),
            FormulaSpec("std = sqrt(sum((x - mean)^2) / (n - 1))", "Sample standard deviation.")
        ],
        notes=[
            "Only numeric values participate in the calculations.",
            "Missing values are counted separately and excluded from summary statistics."
        ]
    )

    return DescriptiveStatsAnalysis(info, collect(variables), output_namespace)
end

analysis_info(analysis::DescriptiveStatsAnalysis) = analysis.info
required_variables(analysis::DescriptiveStatsAnalysis) = analysis.variables
produced_variables(::DescriptiveStatsAnalysis) = Symbol[]

"""
    _numeric_summary(values)

Внутренняя вспомогательная функция, которая считает базовый набор
описательных статистик для одного вектора.

Почему она вынесена отдельно:
- основная функция `analyze` тогда остается короче и читается как сценарий;
- этот кусок проще переиспользовать в других числовых анализах;
- логику обработки `missing` можно менять в одном месте.
"""
function _numeric_summary(values)
    collected = collect(values)
    total_n = length(collected)
    nonmissing = collect(skipmissing(collected))
    n = length(nonmissing)

    if n == 0
        return Dict{Symbol, Any}(
            :n => 0,
            :missing => total_n,
            :mean => missing,
            :median => missing,
            :std => missing,
            :minimum => missing,
            :maximum => missing
        )
    end

    return Dict{Symbol, Any}(
        :n => n,
        :missing => total_n - n,
        :mean => mean(nonmissing),
        :median => median(nonmissing),
        :std => n == 1 ? 0.0 : std(nonmissing),
        :minimum => minimum(nonmissing),
        :maximum => maximum(nonmissing)
    )
end

"""
    analyze(wb, analysis::DescriptiveStatsAnalysis; store=true)

Исполняет анализ описательной статистики в контексте workbook.

Шаги функции:
1. Берет каждую переменную из workbook по имени.
2. Пропускает нечисловые переменные.
3. Считает сводные статистики по каждой числовой переменной.
4. Формирует табличное представление результата.
5. Добавляет простой график средних значений.
6. При `store=true` сохраняет результат в `wb.results`.

На выходе возвращается структурированный `BaseAnalysisResult`, который
уже "знает", как быть превращенным в таблицу, markdown/html-отчет и графики.
"""
function analyze(wb, analysis::DescriptiveStatsAnalysis; store::Bool=true)
    rows = Dict{Symbol, Any}[]
    calculations = Dict{Symbol, Any}()
    mean_labels = String[]
    mean_values = Float64[]

    # Здесь мы идем по списку переменных, который был задан в спецификации
    # анализа, и по каждой переменной строим одну строку будущей summary-таблицы.
    for variable in analysis.variables
        values = getvar(wb, variable)

        # Анализ описательной статистики сейчас рассчитан только на числовые
        # векторы. Если пользователь передал текстовую или категориальную
        # переменную, мы ее просто пропускаем, не прерывая весь анализ.
        if !(eltype(values) <: Union{Missing, Number} || eltype(values) <: Number)
            continue
        end

        summary = _numeric_summary(values)
        calculations[variable] = summary

        # Каждая строка rows потом станет одной строкой DataFrame/таблицы.
        # Здесь специально используется словарь, чтобы структура результата
        # была гибкой и легко сериализовалась в разные представления.
        push!(rows, Dict(
            :variable => String(variable),
            :n => summary[:n],
            :missing => summary[:missing],
            :mean => summary[:mean],
            :median => summary[:median],
            :std => summary[:std],
            :minimum => summary[:minimum],
            :maximum => summary[:maximum],
            :comment => summary[:missing] > 0 ? "contains missing values" : ""
        ))

        # Для графика средних собираем отдельные массивы подписей и значений.
        # Это делает последующее построение PlotSpec максимально простым.
        if summary[:mean] !== missing
            push!(mean_labels, String(variable))
            push!(mean_values, summary[:mean])
        end
    end

    table = AnalysisTable(
        :summary,
        "Summary statistics",
        [:variable, :n, :missing, :mean, :median, :std, :minimum, :maximum, :comment];
        headers=Dict(
            :variable => "Variable",
            :n => "N",
            :missing => "Missing",
            :mean => "Mean",
            :median => "Median",
            :std => "Std",
            :minimum => "Min",
            :maximum => "Max",
            :comment => "Comment"
        ),
        rows=rows,
        description="Each row corresponds to one numeric workbook variable."
    )

    result = BaseAnalysisResult(
        analysis.info;
        input_variables=analysis.variables,
        output_variables=Symbol[],
        analysis_data=Dict(
            :analysis_type => :descriptive_stats,
            :variable_count => length(rows)
        ),
        calculations=calculations
    )

    # Таблица добавляется в результат отдельно от raw-расчетов. Это важно:
    # вычислительная часть и пользовательское представление не обязаны совпадать
    # один в один и могут эволюционировать независимо.
    add_table!(result, table)

    if !isempty(mean_values)
        add_plot!(result, PlotSpec(
            :means,
            "Means by variable",
            :bar;
            payload=Dict(:x => mean_labels, :y => mean_values),
            options=Dict(
                :xlabel => "Variable",
                :ylabel => "Mean",
                :legend => false,
                :xrotation => 45
            )
        ))
    end

    if store
        add_result!(wb, result)
    end

    return result
end
