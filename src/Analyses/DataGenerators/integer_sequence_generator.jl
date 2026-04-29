"""
    IntegerSequenceGeneratorAnalysis

Спецификация генератора целочисленной последовательности.

Этот анализ относится к группе генерации данных и создает служебный
или тестовый вектор по простому детерминированному правилу.
"""
struct IntegerSequenceGeneratorAnalysis <: AbstractAnalysis
    info::AnalysisInfo
    target::Symbol
    start::Int
    step::Int
    count::Int
    namespace::Symbol
    maximum::Union{Nothing, Int}
end

"""
    IntegerSequenceGeneratorAnalysis(target; ...)

Создает объект-описание анализа, который позже можно выполнить через
`analyze(wb, analysis)`.

Ключевые параметры:
- `target`: имя будущей workbook-переменной;
- `start`: стартовое значение;
- `step`: шаг;
- `count`: сколько элементов создать;
- `maximum`: необязательная верхняя граница для циклического сброса.
"""
function IntegerSequenceGeneratorAnalysis(target::Symbol;
                                          start::Integer=1,
                                          step::Integer=1,
                                          count::Integer,
                                          namespace::Symbol=:generated,
                                          maximum::Union{Nothing, Integer}=nothing,
                                          id::Symbol=:sequence_generator,
                                          category_path::AbstractVector{Symbol}=[:data_generator, :integer_distributions],
                                          title::AbstractString="Генератор последовательностей",
                                          summary::AbstractString="Создает целочисленную последовательность и сохраняет ее как переменную workbook.",
                                          description::AbstractString="Последовательность строится от стартового значения с фиксированным шагом и заданным числом элементов. Если задан максимум, значения после его превышения сбрасываются к стартовому значению.",
                                          interpretation::AbstractString="Результат полезен как источник тестовых или служебных данных. В сводке возвращаются размер последовательности, фактический диапазон и имя созданной переменной.")
    count >= 0 || error("`count` must be non-negative")
    step != 0 || error("`step` must not be zero")

    max_value = isnothing(maximum) ? nothing : Int(maximum)
    if max_value !== nothing
        Int(start) <= max_value || error("`start` must be less than or equal to `maximum`")
    end

    info = AnalysisInfo(
        id;
        category_path=category_path,
        title=title,
        summary=summary,
        description=description,
        interpretation=interpretation,
        formulas=[
            FormulaSpec("x1 = start", "Первый элемент последовательности."),
            FormulaSpec("x[i+1] = x[i] + step", "Базовый шаг генерации."),
            FormulaSpec("if x[i] > maximum => x[i] = start", "При заданном максимуме последовательность циклически сбрасывается.")
        ],
        notes=[
            "Созданная последовательность сохраняется как workbook-вектор.",
            "Если максимум не задан, последовательность строится без сброса."
        ]
    )

    return IntegerSequenceGeneratorAnalysis(
        info,
        target,
        Int(start),
        Int(step),
        Int(count),
        namespace,
        max_value
    )
end

analysis_info(analysis::IntegerSequenceGeneratorAnalysis) = analysis.info
required_variables(::IntegerSequenceGeneratorAnalysis) = Symbol[]
produced_variables(analysis::IntegerSequenceGeneratorAnalysis) = [Symbol(string(analysis.namespace), ".", string(analysis.target))]

# Эта функция нужна для единообразного формирования полного имени переменной
# в стиле `namespace.name`. Такое имя потом удобно показывать в отчетах и логах.
function _qualified_output_name(namespace::Symbol, name::Symbol)
    return Symbol(string(namespace), ".", string(name))
end

"""
    _generate_integer_sequence(start, step, count; maximum=nothing)

Низкоуровневый генератор самих значений последовательности.

Логика отделена от `analyze`, чтобы:
- сам алгоритм генерации можно было тестировать отдельно;
- верхнеуровневый код результата не смешивался с вычислительным ядром;
- при необходимости позже можно было добавить альтернативные стратегии.
"""
function _generate_integer_sequence(start::Int,
                                    step::Int,
                                    count::Int;
                                    maximum::Union{Nothing, Int}=nothing)
    count == 0 && return Int[]

    values = Vector{Int}(undef, count)
    current = start

    for i in 1:count
        values[i] = current
        current += step

        # Если максимум задан, последовательность становится циклической:
        # как только следующий шаг выходит за верхнюю границу, мы начинаем
        # снова со стартового значения.
        if maximum !== nothing && current > maximum
            current = start
        end
    end

    return values
end

"""
    analyze(wb, analysis::IntegerSequenceGeneratorAnalysis; store=true)

Исполняет генератор последовательности и сохраняет новый вектор в workbook.

Функция делает три вещи:
1. создает саму последовательность;
2. регистрирует ее как workbook-вектор;
3. формирует структурированный результат с таблицами и графиком.
"""
function analyze(wb, analysis::IntegerSequenceGeneratorAnalysis; store::Bool=true)
    values = _generate_integer_sequence(
        analysis.start,
        analysis.step,
        analysis.count;
        maximum=analysis.maximum
    )

    expression = isnothing(analysis.maximum) ?
        "sequence(start=$(analysis.start), step=$(analysis.step), count=$(analysis.count))" :
        "sequence(start=$(analysis.start), step=$(analysis.step), count=$(analysis.count), maximum=$(analysis.maximum))"

    store_vector!(
        wb.space,
        analysis.namespace,
        analysis.target,
        values;
        origin=:generated,
        dirty=true,
        expression=expression
    )

    qualified_name = _qualified_output_name(analysis.namespace, analysis.target)
    push!(wb.logs, string(qualified_name, " <- ", expression))

    actual_min = isempty(values) ? missing : minimum(values)
    actual_max = isempty(values) ? missing : maximum(values)

    # В `analysis_data` кладем "технический паспорт" анализа:
    # параметры запуска, namespace, target. Это полезно и для отчетов,
    # и для будущей сериализации или воспроизводимости.
    result = BaseAnalysisResult(
        analysis.info;
        input_variables=Symbol[],
        output_variables=[qualified_name],
        analysis_data=Dict(
            :analysis_type => :integer_sequence_generator,
            :namespace => analysis.namespace,
            :target => analysis.target,
            :start => analysis.start,
            :step => analysis.step,
            :count => analysis.count,
            :maximum => analysis.maximum
        ),
        calculations=Dict(
            :count => length(values),
            :range => (actual_min, actual_max),
            :variable_name => qualified_name
        )
    )

    # `summary` — таблица для быстрого человеческого чтения.
    # Она короткая и отвечает на главный вопрос: что было создано.
    add_table!(result, AnalysisTable(
        :summary,
        "Результат генерации",
        [:metric, :value, :comment];
        headers=Dict(
            :metric => "Параметр",
            :value => "Значение",
            :comment => "Комментарий"
        ),
        rows=[
            Dict(:metric => "Количество", :value => length(values), :comment => "Число сгенерированных элементов"),
            Dict(:metric => "Диапазон", :value => isempty(values) ? "empty" : "$(actual_min):$(actual_max)", :comment => "Минимум и максимум в последовательности"),
            Dict(:metric => "Имя переменной", :value => String(qualified_name), :comment => "Новая переменная workbook")
        ]
    ))

    # `preview` — это уже не сводка, а просмотр части сырых данных.
    # Обычно он удобен, когда нужно глазами убедиться, что генерация
    # действительно пошла по задуманному правилу.
    add_table!(result, AnalysisTable(
        :preview,
        "Первые значения",
        [:index, :value];
        headers=Dict(
            :index => "Index",
            :value => "Value"
        ),
        rows=[Dict(:index => i, :value => v) for (i, v) in enumerate(first(values, min(length(values), 15)))]
    ))

    # Для детерминированной последовательности достаточно одного line plot:
    # по нему хорошо видно шаг, цикличность и точки сброса.
    add_plot!(result, PlotSpec(
        :sequence,
        "Generated integer sequence",
        :line;
        payload=Dict(
            :x => collect(1:length(values)),
            :y => values
        ),
        options=Dict(
            :xlabel => "Index",
            :ylabel => "Value",
            :legend => false
        )
    ))

    if store
        add_result!(wb, result)
    end

    return result
end
