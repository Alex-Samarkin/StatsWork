abstract type AbstractAnalysis end
abstract type AbstractAnalysisResult end

"""
    FormulaSpec

Описывает одну формулу, связанную с анализом.

Здесь мы храним не вычисление, а его человекочитаемое представление:
- `expression` показывает запись формулы;
- `explanation` поясняет смысл формулы в отчете или справке.
"""
struct FormulaSpec
    expression::String
    explanation::String
end

FormulaSpec(expression::AbstractString, explanation::AbstractString="") =
    FormulaSpec(String(expression), String(explanation))

"""
    AnalysisInfo

Единый "паспорт" анализа.

Этот объект хранит все метаданные, которые сопровождают анализ:
идентификатор, место в дереве категорий, текстовое описание, интерпретацию,
формулы и заметки. Благодаря этому вычислительная часть и слой отчетности
остаются слабо связанными.
"""
struct AnalysisInfo
    id::Symbol
    category_path::Vector{Symbol}
    title::String
    summary::String
    description::String
    interpretation::String
    formulas::Vector{FormulaSpec}
    notes::Vector{String}
    metadata::Dict{Symbol, Any}
end

"""
    AnalysisInfo(id; ...)

Нормализующий конструктор метаописания анализа.

Он приводит входные значения к стабильным внутренним типам, чтобы объекты
результатов было проще сериализовать, отображать и переиспользовать.
"""
function AnalysisInfo(id::Symbol;
                      category_path::AbstractVector{Symbol}=Symbol[],
                      title::AbstractString=string(id),
                      summary::AbstractString="",
                      description::AbstractString="",
                      interpretation::AbstractString="",
                      formulas::AbstractVector{<:FormulaSpec}=FormulaSpec[],
                      notes::AbstractVector{<:AbstractString}=String[],
                      metadata::AbstractDict{Symbol}=Dict{Symbol, Any}())
    return AnalysisInfo(
        id,
        collect(category_path),
        String(title),
        String(summary),
        String(description),
        String(interpretation),
        collect(formulas),
        String.(collect(notes)),
        Dict{Symbol, Any}(metadata)
    )
end

"""
    AnalysisTable

Структурированное табличное представление результата анализа.

Таблица хранится в нейтральном формате, который затем можно преобразовать
в `DataFrame`, markdown, HTML или Excel без потери структуры.
"""
struct AnalysisTable
    id::Symbol
    title::String
    columns::Vector{Symbol}
    headers::Dict{Symbol, String}
    rows::Vector{Dict{Symbol, Any}}
    description::Union{Nothing, String}
end

"""
    AnalysisTable(id, title, columns; ...)

Конструктор приводит строки таблицы к единому словарному виду.

Это позволяет анализам формировать строки из разных источников, а слою
отчетности работать с ними одинаково.
"""
function AnalysisTable(id::Symbol,
                       title::AbstractString,
                       columns::AbstractVector{Symbol};
                       headers::AbstractDict{Symbol}=Dict{Symbol, String}(),
                       rows::AbstractVector{<:AbstractDict}=Vector{Dict{Symbol, Any}}(),
                       description::Union{Nothing, AbstractString}=nothing)
    prepared_rows = Dict{Symbol, Any}[]
    for row in rows
        push!(prepared_rows, Dict{Symbol, Any}(Symbol(k) => v for (k, v) in pairs(row)))
    end

    return AnalysisTable(
        id,
        String(title),
        collect(columns),
        Dict{Symbol, String}(Symbol(k) => String(v) for (k, v) in pairs(headers)),
        prepared_rows,
        isnothing(description) ? nothing : String(description)
    )
end

"""
    PlotSpec

Декларативное описание одного графика результата.

Анализ не обязан сразу вызывать `Plots.jl`. Вместо этого он может сохранить
спецификацию графика в результате, а графический слой позже решит, как именно
его отрисовать.
"""
struct PlotSpec
    id::Symbol
    title::String
    kind::Symbol
    payload::Dict{Symbol, Any}
    options::Dict{Symbol, Any}
end

"""
    PlotSpec(id, title, kind; payload, options)

Собирает универсальную спецификацию графика: данные в `payload` и параметры
оформления в `options`.
"""
function PlotSpec(id::Symbol,
                  title::AbstractString,
                  kind::Symbol;
                  payload::AbstractDict{Symbol}=Dict{Symbol, Any}(),
                  options::AbstractDict{Symbol}=Dict{Symbol, Any}())
    return PlotSpec(
        id,
        String(title),
        kind,
        Dict{Symbol, Any}(payload),
        Dict{Symbol, Any}(options)
    )
end

"""
    BaseAnalysisResult

Базовый контейнер результата анализа.

Он объединяет:
- входные и выходные workbook-переменные;
- служебные сведения о запуске анализа;
- расчеты;
- таблицы;
- графические спецификации;
- произвольные метаданные.
"""
mutable struct BaseAnalysisResult <: AbstractAnalysisResult
    id::Symbol
    info::AnalysisInfo
    input_variables::Vector{Symbol}
    output_variables::Vector{Symbol}
    analysis_data::Dict{Symbol, Any}
    calculations::Dict{Symbol, Any}
    tables::Dict{Symbol, AnalysisTable}
    plots::Vector{PlotSpec}
    metadata::Dict{Symbol, Any}
end

"""
    BaseAnalysisResult(info; ...)

Собирает результат анализа из отдельных логических слоев.

Конструктор копирует входные коллекции, чтобы итоговый результат не зависел
от внешних изменяемых объектов, переданных при создании.
"""
function BaseAnalysisResult(info::AnalysisInfo;
                            id::Symbol=info.id,
                            input_variables::AbstractVector{Symbol}=Symbol[],
                            output_variables::AbstractVector{Symbol}=Symbol[],
                            analysis_data::AbstractDict{Symbol}=Dict{Symbol, Any}(),
                            calculations::AbstractDict{Symbol}=Dict{Symbol, Any}(),
                            tables::AbstractDict{Symbol, AnalysisTable}=Dict{Symbol, AnalysisTable}(),
                            plots::AbstractVector{PlotSpec}=PlotSpec[],
                            metadata::AbstractDict{Symbol}=Dict{Symbol, Any}())
    return BaseAnalysisResult(
        id,
        info,
        collect(input_variables),
        collect(output_variables),
        Dict{Symbol, Any}(analysis_data),
        Dict{Symbol, Any}(calculations),
        Dict{Symbol, AnalysisTable}(tables),
        collect(plots),
        Dict{Symbol, Any}(metadata)
    )
end

analysis_info(analysis::AbstractAnalysis) =
    throw(MethodError(analysis_info, (analysis,)))

analysis_info(result::BaseAnalysisResult) = result.info

required_variables(::AbstractAnalysis) = Symbol[]
produced_variables(::AbstractAnalysis) = Symbol[]

# Небольшой слой доступа к частям результата.
# Благодаря этим функциям внешний код может работать через стабильный API,
# а не через прямое знание внутренней структуры `BaseAnalysisResult`.
function result_tables(result::BaseAnalysisResult)
    return result.tables
end

function result_plots(result::BaseAnalysisResult)
    return result.plots
end

function result_calculations(result::BaseAnalysisResult)
    return result.calculations
end

# Анализы обычно собирают результат по шагам, поэтому таблицы и графики
# добавляются отдельными мутационными функциями.
function add_table!(result::BaseAnalysisResult, table::AnalysisTable)
    result.tables[table.id] = table
    return result
end

function add_plot!(result::BaseAnalysisResult, plot_spec::PlotSpec)
    push!(result.plots, plot_spec)
    return result
end

function Base.show(io::IO, result::BaseAnalysisResult)
    info = analysis_info(result)
    categories = isempty(info.category_path) ? "-" : join(string.(info.category_path), " / ")
    println(io, "BaseAnalysisResult(", info.id, ")")
    println(io, "  title: ", info.title)
    println(io, "  categories: ", categories)
    println(io, "  inputs: ", isempty(result.input_variables) ? "-" : join(string.(result.input_variables), ", "))
    println(io, "  outputs: ", isempty(result.output_variables) ? "-" : join(string.(result.output_variables), ", "))
    println(io, "  tables: ", isempty(result.tables) ? 0 : length(result.tables))
    print(io, "  plots: ", length(result.plots))
end

"""
    table_dataframe(table)

Преобразует `AnalysisTable` во внешний табличный формат `DataFrame`.

Это основной мост между внутренним представлением результата и всеми местами,
где таблицу потом нужно показать, сохранить или дополнительно обработать.
"""
function table_dataframe(table::AnalysisTable)
    rows = Vector{NamedTuple}()

    for row in table.rows
        # Значения извлекаются строго в порядке `table.columns`, чтобы порядок
        # столбцов не зависел от внутреннего устройства словаря строки.
        values = map(table.columns) do column
            get(row, column, missing)
        end
        push!(rows, NamedTuple{Tuple(table.columns)}(Tuple(values)))
    end

    df = isempty(rows) ? DataFrame() : DataFrame(rows)

    if ncol(df) == 0
        for column in table.columns
            df[!, column] = Any[]
        end
    end

    for column in table.columns
        rename!(df, column => get(table.headers, column, string(column)))
    end

    return df
end

"""
    default_result_table(result)

Строит запасную summary-таблицу из словаря `calculations`.

Это полезно как fallback: даже если анализ не подготовил специальных таблиц,
результат все равно можно показать пользователю в осмысленном виде.
"""
function default_result_table(result::BaseAnalysisResult)
    rows = Dict{Symbol, Any}[]

    for key in sort(collect(keys(result.calculations)); by=string)
        push!(rows, Dict(
            :metric => String(key),
            :value => result.calculations[key],
            :comment => get(result.metadata, key, "")
        ))
    end

    return AnalysisTable(
        :summary,
        "Summary",
        [:metric, :value, :comment];
        headers=Dict(
            :metric => "Metric",
            :value => "Value",
            :comment => "Comment"
        ),
        rows=rows
    )
end

"""
    to_table(result; table=nothing)

Возвращает выбранную таблицу результата как `DataFrame`.

По умолчанию функция старается отдать таблицу `:summary`, если она есть.
Если пользователь указал конкретную таблицу, используется именно она.
"""
function to_table(result::BaseAnalysisResult; table::Union{Nothing, Symbol}=nothing)
    if table !== nothing
        haskey(result.tables, table) || error("Unknown result table: :$table")
        return table_dataframe(result.tables[table])
    end

    if haskey(result.tables, :summary)
        return table_dataframe(result.tables[:summary])
    end

    if !isempty(result.tables)
        first_key = sort(collect(keys(result.tables)); by=string)[1]
        return table_dataframe(result.tables[first_key])
    end

    return table_dataframe(default_result_table(result))
end

# Единое текстовое представление значений нужно для того, чтобы markdown- и
# HTML-отчеты использовали одинаковые правила форматирования.
function _stringify(value)
    if value === missing
        return "missing"
    elseif value isa AbstractFloat
        return string(round(value; digits=4))
    elseif value isa AbstractVector
        return "[" * join(_stringify.(collect(value)), ", ") * "]"
    elseif value isa Dict
        parts = String[]
        for key in sort(collect(keys(value)); by=x -> string(x))
            push!(parts, string(key, "=", _stringify(value[key])))
        end
        return "{" * join(parts, ", ") * "}"
    else
        return string(value)
    end
end

"""
    _markdown_table(df)

Преобразует `DataFrame` в markdown-таблицу.
"""
function _markdown_table(df::DataFrame)
    if ncol(df) == 0
        return "_No table data_\n"
    end

    headers = String.(names(df))
    lines = String[]
    push!(lines, "| " * join(headers, " | ") * " |")
    push!(lines, "| " * join(fill("---", length(headers)), " | ") * " |")

    for row in eachrow(df)
        cells = [_stringify(row[header]) for header in headers]
        push!(lines, "| " * join(cells, " | ") * " |")
    end

    return join(lines, "\n") * "\n"
end

# Экранирование HTML вынесено в отдельную функцию, чтобы безопасно помещать
# в отчет текст, пришедший из данных, заголовков и пользовательских комментариев.
function _html_escape(text::AbstractString)
    escaped = replace(String(text), "&" => "&amp;")
    escaped = replace(escaped, "<" => "&lt;")
    return replace(escaped, ">" => "&gt;")
end

"""
    _html_table(df)

Преобразует `DataFrame` в HTML-таблицу для вставки в отчет.
"""
function _html_table(df::DataFrame)
    if ncol(df) == 0
        return "<p><em>No table data</em></p>"
    end

    headers = String.(names(df))
    html = IOBuffer()
    println(html, "<table>")
    println(html, "<thead><tr>", join(["<th>$(_html_escape(header))</th>" for header in headers]), "</tr></thead>")
    println(html, "<tbody>")

    for row in eachrow(df)
        cells = [_html_escape(_stringify(row[header])) for header in headers]
        println(html, "<tr>", join(["<td>$cell</td>" for cell in cells]), "</tr>")
    end

    println(html, "</tbody></table>")
    return String(take!(html))
end

"""
    to_markdown(result)

Собирает полный markdown-отчет по одному результату анализа.

В отчет последовательно попадают метаданные анализа, входные и выходные
переменные workbook, формулы, интерпретация, таблицы и заметки.
"""
function to_markdown(result::BaseAnalysisResult)
    info = analysis_info(result)
    buffer = IOBuffer()

    println(buffer, "# ", info.title)
    println(buffer)

    if !isempty(info.category_path)
        println(buffer, "**Categories:** ", join(string.(info.category_path), " / "))
        println(buffer)
    end

    !isempty(info.summary) && println(buffer, info.summary, "\n")
    !isempty(info.description) && println(buffer, info.description, "\n")

    if !isempty(result.input_variables) || !isempty(result.output_variables)
        println(buffer, "## Workbook variables")
        println(buffer)
        println(buffer, "- Inputs: ", isempty(result.input_variables) ? "-" : join(string.(result.input_variables), ", "))
        println(buffer, "- Outputs: ", isempty(result.output_variables) ? "-" : join(string.(result.output_variables), ", "))
        println(buffer)
    end

    if !isempty(info.formulas)
        println(buffer, "## Formulas")
        println(buffer)
        for formula in info.formulas
            println(buffer, "- `", formula.expression, "`")
            !isempty(formula.explanation) && println(buffer, "  ", formula.explanation)
        end
        println(buffer)
    end

    if !isempty(info.interpretation)
        println(buffer, "## Interpretation")
        println(buffer)
        println(buffer, info.interpretation)
        println(buffer)
    end

    # Если анализ не добавил собственных таблиц, включаем запасную summary,
    # построенную прямо из словаря `calculations`.
    tables = isempty(result.tables) ? Dict(:summary => default_result_table(result)) : result.tables
    for key in sort(collect(keys(tables)); by=string)
        table = tables[key]
        println(buffer, "## ", table.title)
        println(buffer)
        table.description !== nothing && println(buffer, table.description, "\n")
        println(buffer, _markdown_table(table_dataframe(table)))
    end

    if !isempty(info.notes)
        println(buffer, "## Notes")
        println(buffer)
        for note in info.notes
            println(buffer, "- ", note)
        end
        println(buffer)
    end

    return String(take!(buffer))
end

"""
    to_html(result)

HTML-аналог markdown-отчета по одному результату анализа.
"""
function to_html(result::BaseAnalysisResult)
    info = analysis_info(result)
    buffer = IOBuffer()

    println(buffer, "<html><body>")
    println(buffer, "<h1>", _html_escape(info.title), "</h1>")

    if !isempty(info.category_path)
        println(buffer, "<p><strong>Categories:</strong> ", _html_escape(join(string.(info.category_path), " / ")), "</p>")
    end

    !isempty(info.summary) && println(buffer, "<p>", _html_escape(info.summary), "</p>")
    !isempty(info.description) && println(buffer, "<p>", _html_escape(info.description), "</p>")

    if !isempty(result.input_variables) || !isempty(result.output_variables)
        println(buffer, "<h2>Workbook variables</h2>")
        println(buffer, "<p><strong>Inputs:</strong> ", _html_escape(isempty(result.input_variables) ? "-" : join(string.(result.input_variables), ", ")), "</p>")
        println(buffer, "<p><strong>Outputs:</strong> ", _html_escape(isempty(result.output_variables) ? "-" : join(string.(result.output_variables), ", ")), "</p>")
    end

    if !isempty(info.formulas)
        println(buffer, "<h2>Formulas</h2><ul>")
        for formula in info.formulas
            print(buffer, "<li><code>", _html_escape(formula.expression), "</code>")
            !isempty(formula.explanation) && print(buffer, " - ", _html_escape(formula.explanation))
            println(buffer, "</li>")
        end
        println(buffer, "</ul>")
    end

    if !isempty(info.interpretation)
        println(buffer, "<h2>Interpretation</h2>")
        println(buffer, "<p>", _html_escape(info.interpretation), "</p>")
    end

    # Логика выбора таблиц такая же, как и в markdown-версии отчета, чтобы
    # разные форматы показывали одну и ту же содержательную структуру.
    tables = isempty(result.tables) ? Dict(:summary => default_result_table(result)) : result.tables
    for key in sort(collect(keys(tables)); by=string)
        table = tables[key]
        println(buffer, "<h2>", _html_escape(table.title), "</h2>")
        table.description !== nothing && println(buffer, "<p>", _html_escape(table.description), "</p>")
        println(buffer, _html_table(table_dataframe(table)))
    end

    if !isempty(info.notes)
        println(buffer, "<h2>Notes</h2><ul>")
        for note in info.notes
            println(buffer, "<li>", _html_escape(note), "</li>")
        end
        println(buffer, "</ul>")
    end

    println(buffer, "</body></html>")
    return String(take!(buffer))
end

# Приводим одиночный результат и список результатов к единой форме.
# Это упрощает внутренние функции сохранения и агрегации отчетов.
function _as_result_vector(results)
    return results isa AbstractVector ? collect(results) : [results]
end

"""
    text_report(result; format=:markdown)

Возвращает текстовый отчет по одному результату в выбранном формате.
"""
function text_report(result::BaseAnalysisResult; format::Symbol=:markdown)
    if format == :markdown || format == :md
        return to_markdown(result)
    elseif format == :html
        return to_html(result)
    end

    error("Unsupported report format: $format")
end

"""
    text_report(results; format=:markdown)

Собирает объединенный текстовый отчет по нескольким результатам.
"""
function text_report(results::AbstractVector{<:AbstractAnalysisResult}; format::Symbol=:markdown)
    rendered = String[]

    for result in results
        if result isa BaseAnalysisResult
            push!(rendered, text_report(result; format=format))
        else
            error("Unsupported result type: $(typeof(result))")
        end
    end

    separator = format == :html ? "<hr />\n" : "\n---\n\n"
    return join(rendered, separator)
end

# Excel ограничивает длину и набор символов в именах листов, поэтому имя
# очищается и укорачивается централизованно в одном месте.
function _sheet_name(parts...)
    raw = join(string.(parts), "_")
    clean = replace(raw, r"[\[\]\*:/\\\?]" => "_")
    return first(clean, min(lastindex(clean), 31))
end

"""
    _save_xlsx(file_path, results)

Сохраняет таблицы результатов в Excel-файл, раскладывая их по листам.
"""
function _save_xlsx(file_path::AbstractString, results::AbstractVector{<:AbstractAnalysisResult})
    sheets = Pair{String, DataFrame}[]

    for (result_index, result) in enumerate(results)
        result isa BaseAnalysisResult || error("Unsupported result type: $(typeof(result))")
        tables = isempty(result.tables) ? Dict(:summary => default_result_table(result)) : result.tables

        for (table_index, key) in enumerate(sort(collect(keys(tables)); by=string))
            df = table_dataframe(tables[key])
            name = _sheet_name(result_index, table_index, result.id, key)
            push!(sheets, name => df)
        end
    end

    XLSX.writetable(file_path, sheets; overwrite=true)
    return file_path
end

"""
    save_report(file_path, result; format=nothing)

Сохраняет один результат анализа в файл. Формат можно задать явно или вывести
из расширения имени файла.
"""
function save_report(file_path::AbstractString,
                     result::BaseAnalysisResult;
                     format::Union{Nothing, Symbol}=nothing)
    chosen_format = isnothing(format) ? Symbol(lowercase(replace(splitext(file_path)[2], "." => ""))) : format

    if chosen_format in (:md, :markdown)
        write(file_path, text_report(result; format=:markdown))
    elseif chosen_format == :html
        write(file_path, text_report(result; format=:html))
    elseif chosen_format == :xlsx
        _save_xlsx(file_path, [result])
    else
        error("Unsupported report format: $chosen_format")
    end

    return file_path
end

"""
    save_report(file_path, results; format=nothing)

Сохраняет несколько результатов анализа в общий файл отчета.
"""
function save_report(file_path::AbstractString,
                     results::AbstractVector{<:AbstractAnalysisResult};
                     format::Union{Nothing, Symbol}=nothing)
    chosen_format = isnothing(format) ? Symbol(lowercase(replace(splitext(file_path)[2], "." => ""))) : format

    if chosen_format in (:md, :markdown)
        write(file_path, text_report(results; format=:markdown))
    elseif chosen_format == :html
        write(file_path, text_report(results; format=:html))
    elseif chosen_format == :xlsx
        _save_xlsx(file_path, results)
    else
        error("Unsupported report format: $chosen_format")
    end

    return file_path
end
