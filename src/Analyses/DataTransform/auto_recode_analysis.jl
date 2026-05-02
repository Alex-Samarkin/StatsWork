"""
    AutoRecodeAnalysis

Автоматическое кодирование текстовой переменной целыми числами.

Анализ читает строковую workbook-переменную, при необходимости приводит
значения к одному регистру, строит отсортированный список категорий и создаёт
новую workbook-переменную той же длины, где каждое текстовое значение заменено
на числовой код. Все таблицы сопоставлений сохраняются в результате анализа.
"""
struct AutoRecodeAnalysis <: AbstractAnalysis
    info::AnalysisInfo
    variable::Symbol
    output_namespace::Symbol
    output_name::Symbol
    normalize_case::Bool
    case_mode::Symbol
    sort_labels::Bool
    start_index::Int
    max_levels::Union{Nothing, Int}
end

"""
    AutoRecodeAnalysis(variable; ...)

Создаёт спецификацию анализа для автоматического кодирования текстовой
переменной. Исходная переменная должна содержать строки и, возможно, `missing`.
"""
function AutoRecodeAnalysis(variable::Symbol;
                            output_namespace::Symbol=:derived,
                            output_name::Union{Nothing, Symbol}=nothing,
                            normalize_case::Bool=true,
                            case_mode::Symbol=:lower,
                            sort_labels::Bool=true,
                            start_index::Integer=1,
                            max_levels::Union{Nothing, Integer}=20,
                            id::Symbol=:auto_recode,
                            category_path::AbstractVector{Symbol}=[:data_transform, :encoding],
                            title::AbstractString="Автоматическое кодирование текстовой переменной",
                            summary::AbstractString="Создаёт числовые коды для строковых категорий и сохраняет новую переменную той же длины, что и исходная.",
                            description::AbstractString="Анализ извлекает уникальные текстовые метки, при необходимости нормализует их по регистру, сортирует, присваивает последовательные числовые коды и сохраняет полную таблицу соответствий в результате.",
                            interpretation::AbstractString="Таблица сопоставлений показывает, какие исходные и нормализованные метки соответствуют каждому коду, а выходная переменная может использоваться в последующих анализах.")
    case_mode in (:lower, :upper) || error("`case_mode` must be :lower or :upper")
    Int(start_index) >= 0 || error("`start_index` must be non-negative")

    target_name = isnothing(output_name) ? Symbol(string(variable), "_codes") : output_name

    info = AnalysisInfo(
        id;
        category_path=category_path,
        title=title,
        summary=summary,
        description=description,
        interpretation=interpretation,
        formulas=[
            FormulaSpec("normalized_label = normalize_case ? lower(label) : label", "Нормализация строки по регистру."),
            FormulaSpec("codes = start_index:(start_index + k - 1)", "Последовательные коды для отсортированных категорий."),
            FormulaSpec("encoded[i] = code(normalized_label[i])", "Каждая исходная метка заменяется её кодом.")
        ],
        notes=[
            "Новая переменная имеет ту же длину, что и исходная.",
            "Значения `missing` не кодируются и остаются `missing`.",
            "В результате сохраняются исходные метки, нормализованные метки и частоты наблюдений."
        ]
    )

    return AutoRecodeAnalysis(
        info,
        variable,
        output_namespace,
        target_name,
        normalize_case,
        case_mode,
        sort_labels,
        Int(start_index),
        isnothing(max_levels) ? nothing : Int(max_levels)
    )
end

analysis_info(analysis::AutoRecodeAnalysis) = analysis.info
required_variables(analysis::AutoRecodeAnalysis) = [analysis.variable]
produced_variables(analysis::AutoRecodeAnalysis) = [Symbol(string(analysis.output_namespace), ".", string(analysis.output_name))]

function _normalize_recode_label(label::AbstractString, normalize_case::Bool, case_mode::Symbol)
    text = String(label)
    normalize_case || return text
    return case_mode == :upper ? uppercase(text) : lowercase(text)
end

function _prepare_recode(source_values,
                         normalize_case::Bool,
                         case_mode::Symbol,
                         sort_labels::Bool,
                         start_index::Int,
                         max_levels::Union{Nothing, Int})
    collected = collect(source_values)
    original_counts = Dict{String, Int}()
    normalized_counts = Dict{String, Int}()
    original_to_normalized = Dict{String, String}()
    normalized_to_originals = Dict{String, Vector{String}}()
    normalized_order = String[]
    missing_count = 0

    for value in collected
        if value === missing
            missing_count += 1
            continue
        end

        value isa AbstractString || error("Variable contains non-string value `$(repr(value))`; auto recode expects strings and optional missing")
        original = String(value)
        normalized = _normalize_recode_label(original, normalize_case, case_mode)

        original_counts[original] = get(original_counts, original, 0) + 1
        normalized_counts[normalized] = get(normalized_counts, normalized, 0) + 1
        original_to_normalized[original] = normalized

        originals = get!(normalized_to_originals, normalized, String[])
        if length(originals) == 0
            push!(normalized_order, normalized)
        end
        if !(original in originals)
            push!(originals, original)
        end
    end

    normalized_labels = copy(normalized_order)
    if sort_labels
        sort!(normalized_labels)
    end

    if max_levels !== nothing && length(normalized_labels) > max_levels
        error("Variable `$(length(normalized_labels))` unique normalized labels, which exceeds `max_levels=$(max_levels)`")
    end

    normalized_label_to_code = Dict{String, Int}()
    code_to_normalized_label = Dict{Int, String}()
    for (offset, label) in enumerate(normalized_labels)
        code = start_index + offset - 1
        normalized_label_to_code[label] = code
        code_to_normalized_label[code] = label
    end

    encoded = Vector{Union{Missing, Int}}(undef, length(collected))
    for (i, value) in enumerate(collected)
        if value === missing
            encoded[i] = missing
        else
            normalized = original_to_normalized[String(value)]
            encoded[i] = normalized_label_to_code[normalized]
        end
    end

    for originals in Base.values(normalized_to_originals)
        sort!(originals)
    end

    return (
        encoded=encoded,
        total_count=length(collected),
        coded_count=length(collected) - missing_count,
        missing_count=missing_count,
        original_counts=original_counts,
        normalized_counts=normalized_counts,
        original_to_normalized=original_to_normalized,
        normalized_to_originals=normalized_to_originals,
        normalized_label_to_code=normalized_label_to_code,
        code_to_normalized_label=code_to_normalized_label
    )
end

function _recode_summary_row(metric::AbstractString, value, comment::AbstractString="")
    return Dict(:metric => String(metric), :value => value, :comment => String(comment))
end

"""
    analyze(wb, analysis::AutoRecodeAnalysis; store=true)

Исполняет автоматическое кодирование строковой переменной, сохраняет новый
вектор кодов в workbook и возвращает структурированный результат с таблицами
сопоставлений.
"""
function analyze(wb, analysis::AutoRecodeAnalysis; store::Bool=true)
    raw_values = getvar(wb, analysis.variable)
    prepared = _prepare_recode(
        raw_values,
        analysis.normalize_case,
        analysis.case_mode,
        analysis.sort_labels,
        analysis.start_index,
        analysis.max_levels
    )

    expression = "auto_recode($(analysis.variable))"
    store_vector!(
        wb.space,
        analysis.output_namespace,
        analysis.output_name,
        prepared.encoded;
        origin=:analysis,
        dirty=true,
        expression=expression
    )

    output_variable = first(produced_variables(analysis))
    push!(wb.logs, string(output_variable, " <- ", expression))

    calculations = Dict{Symbol, Any}(
        :source_variable => analysis.variable,
        :output_variable => output_variable,
        :total_count => prepared.total_count,
        :coded_count => prepared.coded_count,
        :missing_count => prepared.missing_count,
        :unique_original_count => length(prepared.original_counts),
        :unique_normalized_count => length(prepared.normalized_counts),
        :normalize_case => analysis.normalize_case,
        :case_mode => analysis.case_mode,
        :sort_labels => analysis.sort_labels,
        :start_index => analysis.start_index,
        :max_levels => analysis.max_levels,
        :original_label_counts => prepared.original_counts,
        :normalized_label_counts => prepared.normalized_counts,
        :original_to_normalized_label => prepared.original_to_normalized,
        :normalized_to_original_labels => prepared.normalized_to_originals,
        :normalized_label_to_code => prepared.normalized_label_to_code,
        :code_to_normalized_label => prepared.code_to_normalized_label
    )

    result = BaseAnalysisResult(
        analysis.info;
        input_variables=[analysis.variable],
        output_variables=[output_variable],
        analysis_data=Dict(
            :analysis_type => :auto_recode,
            :source_variable => analysis.variable,
            :output_namespace => analysis.output_namespace,
            :output_name => analysis.output_name
        ),
        calculations=calculations
    )

    add_table!(result, AnalysisTable(
        :summary,
        "Сводка кодирования",
        [:metric, :value, :comment];
        headers=Dict(:metric => "Параметр", :value => "Значение", :comment => "Комментарий"),
        rows=[
            _recode_summary_row("Исходная переменная", String(analysis.variable)),
            _recode_summary_row("Выходная переменная", String(output_variable)),
            _recode_summary_row("Всего значений", prepared.total_count),
            _recode_summary_row("Кодировано", prepared.coded_count, "Нестроковые значения не допускаются, missing не кодируются"),
            _recode_summary_row("Пропущено", prepared.missing_count, "Количество missing"),
            _recode_summary_row("Уникальных исходных меток", length(prepared.original_counts)),
            _recode_summary_row("Уникальных нормализованных меток", length(prepared.normalized_counts)),
            _recode_summary_row("Начальный код", analysis.start_index),
            _recode_summary_row("Нормализация регистра", analysis.normalize_case),
            _recode_summary_row("Режим регистра", String(analysis.case_mode)),
            _recode_summary_row("Сортировка меток", analysis.sort_labels),
            _recode_summary_row("Максимум уровней", isnothing(analysis.max_levels) ? "not limited" : analysis.max_levels)
        ]
    ))

    mapping_rows = Dict{Symbol, Any}[]
    normalized_labels = collect(keys(prepared.normalized_label_to_code))
    sort!(normalized_labels)
    for normalized_label in normalized_labels
        code = prepared.normalized_label_to_code[normalized_label]
        originals = prepared.normalized_to_originals[normalized_label]
        push!(mapping_rows, Dict(
            :code => code,
            :normalized_label => normalized_label,
            :count => prepared.normalized_counts[normalized_label],
            :n_original_labels => length(originals),
            :original_labels => join(originals, ", ")
        ))
    end

    add_table!(result, AnalysisTable(
        :mapping,
        "Таблица сопоставлений",
        [:code, :normalized_label, :count, :n_original_labels, :original_labels];
        headers=Dict(
            :code => "Код",
            :normalized_label => "Нормализованная метка",
            :count => "Частота",
            :n_original_labels => "Число исходных вариантов",
            :original_labels => "Исходные метки"
        ),
        rows=mapping_rows
    ))

    observed_rows = Dict{Symbol, Any}[]
    original_labels = collect(keys(prepared.original_counts))
    sort!(original_labels)
    for original_label in original_labels
        normalized_label = prepared.original_to_normalized[original_label]
        code = prepared.normalized_label_to_code[normalized_label]
        push!(observed_rows, Dict(
            :original_label => original_label,
            :normalized_label => normalized_label,
            :code => code,
            :count => prepared.original_counts[original_label]
        ))
    end

    add_table!(result, AnalysisTable(
        :observed_labels,
        "Наблюдённые исходные метки",
        [:original_label, :normalized_label, :code, :count];
        headers=Dict(
            :original_label => "Исходная метка",
            :normalized_label => "Нормализованная метка",
            :code => "Код",
            :count => "Частота"
        ),
        rows=observed_rows
    ))

    preview_rows = Dict{Symbol, Any}[]
    values = collect(raw_values)
    for i in 1:min(length(values), 20)
        original_label = values[i] === missing ? missing : String(values[i])
        normalized_label = values[i] === missing ? missing : prepared.original_to_normalized[String(values[i])]
        push!(preview_rows, Dict(
            :index => i,
            :original_label => original_label,
            :normalized_label => normalized_label,
            :code => prepared.encoded[i]
        ))
    end

    add_table!(result, AnalysisTable(
        :preview,
        "Превью перекодирования",
        [:index, :original_label, :normalized_label, :code];
        headers=Dict(
            :index => "Index",
            :original_label => "Исходная метка",
            :normalized_label => "Нормализованная метка",
            :code => "Код"
        ),
        rows=preview_rows
    ))

    if store
        add_result!(wb, result)
    end

    return result
end
