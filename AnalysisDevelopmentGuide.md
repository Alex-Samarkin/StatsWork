# Создание и подключение нового анализа

Этот документ описывает, как устроен новый тип анализа в `StatsWorkbench`, как он
вписывается в архитектуру workbook/result/graphics/report и как практически
добавить новый analysis-модуль в пакет.

В репозитории есть подробный шаблон полного анализа:

```text
src/Analyses/TEMPLATE_full_analysis.jl
```

Его удобно копировать как стартовую точку: в нем уже есть вход, выходная
переменная, текстовое описание анализа, несколько таблиц, графики и dashboard.

## Часть 1. Общие идеи и архитектурная логика

### 1. Анализ как отдельная спецификация

В `StatsWorkbench` анализ начинается не с немедленного расчета, а с создания
объекта-спецификации:

```julia
analysis = SomeAnalysis(:x; option=123)
result = analyze(wb, analysis)
```

Тип анализа обычно наследуется от `AbstractAnalysis`:

```julia
struct SomeAnalysis <: AbstractAnalysis
    info::AnalysisInfo
    variable::Symbol
    option::Int
    palette_name::Symbol
end
```

Такой объект хранит не данные, а план работы: какие переменные нужны, какие
параметры выбраны, как анализ будет называться в отчете, какие формулы и
интерпретации следует показать пользователю.

Это разделение полезно: один и тот же analysis-объект можно выполнить над
разными workbook, а результат каждого запуска будет отдельным
`BaseAnalysisResult`.

### 2. Где живут анализы

Файлы анализов лежат в `src/Analyses`. Внутри уже есть тематические папки:

```text
src/Analyses/DataGenerators
src/Analyses/DataQuality
src/Analyses/Exploratory
```

Если новая группа анализов уже подходит под существующую категорию, файл лучше
положить туда. Например:

```text
src/Analyses/Exploratory/my_analysis.jl
```

Если появляется новая предметная область, можно создать новую папку:

```text
src/Analyses/HypothesisTests
src/Analyses/Regression
src/Analyses/TimeSeries
```

Название папки отражает архитектурную категорию. Внутри самого анализа эту
категорию также желательно указать в `AnalysisInfo(category_path=...)`, чтобы
отчет и будущий каталог анализов могли группировать результаты:

```julia
category_path=[:hypothesis_tests, :parametric]
```

### 3. Workbook и переменные

`Workbook` является рабочим контейнером. Он хранит датасеты, производные
переменные, результаты анализов и лог операций.

Анализ получает данные через:

```julia
values = getvar(wb, :x)
```

Переменная может быть:

- коротким именем колонки, например `:age`;
- квалифицированным именем, например `Symbol("data.age")`;
- производной переменной, сохраненной ранее через `store_vector!`.

У анализа должен быть метод:

```julia
required_variables(analysis::SomeAnalysis) = [analysis.variable]
```

Он сообщает внешнему коду, какие workbook-переменные нужны для запуска.

Если анализ создает новую переменную, нужно также определить:

```julia
produced_variables(analysis::SomeAnalysis) = [Symbol("derived.x_new")]
```

Само сохранение делается внутри `analyze` через `store_vector!`:

```julia
store_vector!(
    wb.space,
    :derived,
    :x_new,
    output_values;
    origin=:analysis,
    dirty=true,
    expression="some expression"
)
```

После сохранения полезно добавить запись в лог:

```julia
push!(wb.logs, "derived.x_new <- some expression")
```

Если анализ ничего не создает, `produced_variables` возвращает `Symbol[]`.

### 4. AnalysisInfo: текст, формулы и смысл анализа

`AnalysisInfo` - это паспорт анализа. Он хранит:

- `id`;
- `category_path`;
- `title`;
- `summary`;
- `description`;
- `interpretation`;
- `formulas`;
- `notes`;
- `metadata`.

Именно этот объект потом используется в markdown/html-отчетах. Поэтому хороший
анализ должен содержать не только код вычислений, но и объяснение того, что
было сделано.

Пример:

```julia
info = AnalysisInfo(
    :some_analysis;
    category_path=[:exploratory],
    title="Some analysis",
    summary="Short summary.",
    description="Longer description.",
    interpretation="How to read the result.",
    formulas=[
        FormulaSpec("mean = sum(x) / n", "Average value.")
    ],
    notes=[
        "Missing values are excluded."
    ]
)
```

### 5. BaseAnalysisResult: единая форма результата

Каждый analysis-модуль должен вернуть `BaseAnalysisResult`.

Обычно он создается так:

```julia
result = BaseAnalysisResult(
    analysis.info;
    input_variables=[analysis.variable],
    output_variables=produced_variables(analysis),
    analysis_data=Dict(:analysis_type => :some_analysis),
    calculations=calculations
)
```

`calculations` хранит машинно-читаемые результаты: числа, словари, параметры,
промежуточные оценки. Это не обязательно то же самое, что пользовательская
таблица. Таблицы и графики добавляются отдельно.

### 6. Таблицы результата

Таблица результата создается через `AnalysisTable` и добавляется через
`add_table!`.

```julia
add_table!(result, AnalysisTable(
    :summary,
    "Summary",
    [:metric, :value, :comment];
    headers=Dict(
        :metric => "Metric",
        :value => "Value",
        :comment => "Comment"
    ),
    rows=[
        Dict(:metric => "n", :value => n, :comment => "Sample size")
    ]
))
```

Если у результата есть таблица `:summary`, то `to_table(result)` по умолчанию
покажет именно ее. Остальные таблицы доступны так:

```julia
to_table(result; table=:parameters)
to_table(result; table=:preview)
```

Все таблицы автоматически участвуют в отчетах:

```julia
save_report("report.md", result)
save_report("report.html", result)
save_report("report.xlsx", result)
```

Отдельный код для markdown обычно писать не нужно: слой отчетов берет
`AnalysisInfo` и все `AnalysisTable` из результата.

### 7. Графика через PlotSpec

Анализ не должен сразу строить картинку через `Plots.plot`. Он должен добавить
декларативное описание графика:

```julia
add_plot!(result, PlotSpec(
    :histogram,
    "Histogram",
    :histogram;
    payload=Dict(:values => values),
    options=Dict(:xlabel => "Value", :ylabel => "Frequency")
))
```

Реальное построение происходит позже:

```julia
plot1(result)
plot2(result)
render_result_plot(result, 3)
plot_report(result)
```

Поддерживаемые типы графиков задаются в `src/Core/graphics.jl` в функции
`_render_plot`. Сейчас в проекте есть базовые виды вроде `:bar`, `:line`,
`:scatter`, `:histogram`, `:histogram_normal`, `:boxplot`, `:qq`, `:heatmap`,
`:confidence_interval`, `:dashboard`.

Если новому анализу нужен новый тип графика, добавляется новая ветка в
`_render_plot`. Но если можно выразить идею через существующий `PlotSpec`,
лучше сначала использовать существующий тип.

### 8. Dashboard как четвертый график

Dashboard - это обычный `PlotSpec` вида `:dashboard`, который содержит другие
`PlotSpec` внутри `payload`.

```julia
dashboard_spec = PlotSpec(
    :dashboard,
    "Dashboard",
    :dashboard;
    payload=Dict(:plots => [plot_a, plot_b, plot_c]),
    options=Dict(:layout => (1, 3))
)
```

Хороший полный анализ часто имеет такой порядок графиков:

1. основной график;
2. диагностический график;
3. дополнительный график;
4. dashboard из первых трех.

Тогда пользователь может быстро вызвать:

```julia
plot1(result)
plot2(result)
plot3(result)
plot4(result)
```

### 9. Как анализ подключается к пакету

Новый файл не заработает сам по себе. Его нужно подключить в
`src/StatsWorkbench.jl`:

```julia
include("Analyses/Exploratory/my_analysis.jl")
```

Если тип должен быть доступен пользователю после `using StatsWorkbench`, его
нужно добавить в `export`:

```julia
export MyAnalysis
```

После этого пользователь сможет писать:

```julia
analysis = MyAnalysis(:x)
result = analyze(wb, analysis)
```

Если тип не экспортировать, он все равно доступен как:

```julia
StatsWorkbench.MyAnalysis
```

## Часть 2. Пошаговая инструкция

### Шаг 1. Определите назначение анализа

Простая инструкция: коротко запишите, что анализ принимает, что считает и что
возвращает.

Комментарий: хороший analysis-модуль должен иметь ясную границу. Например:
`SingleVariableIntervalEstimatesAnalysis` берет одну переменную и считает
интервальные оценки. Он не должен одновременно заниматься очисткой всего
датасета, регрессией и генерацией отчета по всем переменным. Чем яснее
назначение, тем проще API, тесты и документация.

### Шаг 2. Выберите или создайте категорию

Простая инструкция: положите файл в существующую папку `src/Analyses/...` или
создайте новую папку под новую группу анализов.

Комментарий: если анализ относится к разведочному анализу, используйте
`src/Analyses/Exploratory`. Если это новая область, например критерии гипотез,
создайте:

```text
src/Analyses/HypothesisTests
```

Имя папки должно быть достаточно широким, чтобы рядом могли жить родственные
анализы, но не настолько общим, чтобы все снова оказалось в одной куче.

### Шаг 3. Скопируйте шаблон

Простая инструкция: скопируйте `src/Analyses/TEMPLATE_full_analysis.jl` в новую
папку и переименуйте файл.

Пример:

```text
src/Analyses/Exploratory/outlier_screening_analysis.jl
```

Комментарий: шаблон уже показывает полный жизненный цикл анализа: вход,
выходная переменная, таблицы, графики, dashboard и сохранение результата.
Копирование шаблона снижает риск забыть обязательные методы или собрать
результат в формате, несовместимом с отчетами.

### Шаг 4. Переименуйте тип анализа

Простая инструкция: замените `FullAnalysisTemplateAnalysis` на имя нового типа.

Пример:

```julia
struct OutlierScreeningAnalysis <: AbstractAnalysis
    info::AnalysisInfo
    variable::Symbol
    threshold::Float64
    palette_name::Symbol
end
```

Комментарий: имя типа должно отвечать на вопрос "что это за анализ?". В проекте
уже используется стиль `SomethingAnalysis`, например
`DescriptiveStatsAnalysis` или `SingleVariableIntervalEstimatesAnalysis`.
Лучше придерживаться этого стиля.

### Шаг 5. Настройте поля структуры

Простая инструкция: оставьте только те поля, которые реально нужны анализу.

Комментарий: тип анализа должен хранить параметры запуска, а не результаты.
Результаты появятся позже в `BaseAnalysisResult`. Если анализ принимает одну
переменную, достаточно `variable::Symbol`. Если несколько, используйте
`variables::Vector{Symbol}`. Если анализ создает производную переменную,
оставьте `output_namespace` и `output_name`. Если не создает, удалите их.

### Шаг 6. Заполните конструктор и AnalysisInfo

Простая инструкция: обновите `title`, `summary`, `description`,
`interpretation`, `formulas` и `notes`.

Комментарий: это не декоративный текст. Он попадет в markdown/html-отчеты и
поможет пользователю понять результат без чтения исходного кода. Формулы лучше
писать коротко, а пояснения - практично: что считается, какие есть ограничения,
как интерпретировать результат.

### Шаг 7. Реализуйте required_variables и produced_variables

Простая инструкция: укажите входные и выходные workbook-переменные анализа.

Пример для одной входной переменной:

```julia
required_variables(analysis::OutlierScreeningAnalysis) = [analysis.variable]
```

Пример без выходов:

```julia
produced_variables(::OutlierScreeningAnalysis) = Symbol[]
```

Комментарий: эти методы являются контрактом анализа с остальной системой.
Они нужны для проверки входов, документации, отчетов и будущей автоматизации.

### Шаг 8. Напишите helper-функции

Простая инструкция: вынесите очистку данных, подготовку строк таблиц и
повторяющиеся расчеты в небольшие внутренние функции.

Комментарий: helper-функции лучше именовать с уникальным префиксом, например
`_outlier_clean_values`, чтобы они не конфликтовали с helper-функциями других
анализов. В текущей архитектуре файлы анализа подключаются в один модуль
`StatsWorkbench`, поэтому слишком общие имена вроде `_clean_values` могут
столкнуться между разными файлами.

### Шаг 9. Напишите analyze

Простая инструкция: реализуйте метод:

```julia
function analyze(wb, analysis::OutlierScreeningAnalysis; store::Bool=true)
    ...
end
```

Комментарий: внутри `analyze` обычно идут такие блоки:

1. получить данные через `getvar`;
2. очистить и проверить данные;
3. посчитать основные величины;
4. сохранить выходную переменную, если она есть;
5. собрать `calculations`;
6. создать `BaseAnalysisResult`;
7. добавить таблицы;
8. добавить графики;
9. сохранить result в workbook через `add_result!`, если `store=true`;
10. вернуть `result`.

### Шаг 10. Если нужен выходной вектор, сохраните его через store_vector!

Простая инструкция: используйте `store_vector!` и добавьте запись в `wb.logs`.

Пример:

```julia
store_vector!(
    wb.space,
    :derived,
    :x_score,
    score_values;
    origin=:analysis,
    dirty=true,
    expression="score(x)"
)
push!(wb.logs, "derived.x_score <- score(x)")
```

Комментарий: выходная переменная становится частью workbook и может быть
использована следующими анализами. Это ключевая идея проекта: результаты
могут возвращаться не только как отчет, но и как новые рабочие переменные.

### Шаг 11. Соберите calculations

Простая инструкция: положите машинно-читаемые результаты в
`Dict{Symbol, Any}`.

Пример:

```julia
calculations = Dict{Symbol, Any}(
    :count => n,
    :mean => mean_value,
    :std => std_value
)
```

Комментарий: `calculations` нужен для программного доступа к результатам:

```julia
result_calculations(result)[:mean]
```

Не обязательно помещать туда все строки будущих таблиц, но важные численные
результаты и параметры запуска лучше сохранить.

### Шаг 12. Создайте BaseAnalysisResult

Простая инструкция: создайте result на основе `analysis.info`.

Пример:

```julia
result = BaseAnalysisResult(
    analysis.info;
    input_variables=[analysis.variable],
    output_variables=produced_variables(analysis),
    analysis_data=Dict(:analysis_type => :outlier_screening),
    calculations=calculations
)
```

Комментарий: `BaseAnalysisResult` является центральной структурой результата.
Все дальнейшее - таблицы, графики, markdown/html/xlsx - привязывается к нему.

### Шаг 13. Добавьте таблицу summary

Простая инструкция: создайте таблицу `:summary`.

Комментарий: `:summary` - таблица по умолчанию. Если пользователь вызовет:

```julia
to_table(result)
```

он увидит именно ее. Поэтому туда стоит положить самую полезную короткую
сводку, а подробности вынести в дополнительные таблицы.

### Шаг 14. Добавьте дополнительные таблицы

Простая инструкция: добавьте таблицы `:parameters`, `:diagnostics`,
`:preview`, `:coefficients` или другие, подходящие по смыслу.

Комментарий: таблиц может быть несколько. Все они автоматически попадут в
полный отчет. Это удобно: analysis-модуль отвечает за содержательную структуру,
а report layer отвечает за формат вывода.

### Шаг 15. Добавьте минимум три графика

Простая инструкция: создайте три `PlotSpec` и добавьте их через `add_plot!`.

Пример:

```julia
add_plot!(result, PlotSpec(
    :histogram,
    "Histogram",
    :histogram;
    payload=Dict(:values => values),
    options=Dict(:xlabel => "Value", :ylabel => "Frequency")
))
```

Комментарий: графики должны быть содержательно разными. Например:

- распределение;
- значения по индексу;
- диагностический scatter;
- boxplot;
- heatmap;
- QQ-график.

Порядок важен: `plot1`, `plot2`, `plot3` используют именно порядок добавления.

### Шаг 16. Добавьте четвертый график-dashboard

Простая инструкция: соберите первые три графика в `:dashboard`.

Пример:

```julia
dashboard_spec = PlotSpec(
    :dashboard,
    "Dashboard",
    :dashboard;
    payload=Dict(:plots => [plot1_spec, plot2_spec, plot3_spec]),
    options=Dict(:layout => (1, 3))
)
add_plot!(result, dashboard_spec)
```

Комментарий: dashboard не должен заново считать данные. Он переиспользует уже
созданные `PlotSpec`. Это делает код короче и гарантирует, что отдельные
графики и панель показывают одно и то же.

### Шаг 17. Подключите файл в StatsWorkbench.jl

Простая инструкция: добавьте `include` в `src/StatsWorkbench.jl`.

Пример:

```julia
include("Analyses/Exploratory/outlier_screening_analysis.jl")
```

Комментарий: порядок `include` имеет значение, если файл использует типы или
функции, определенные в других файлах. Обычно анализы подключаются после
`Core/...`, потому что им нужны `AnalysisInfo`, `BaseAnalysisResult`,
`AnalysisTable`, `PlotSpec`, `getvar`, `store_vector!` и графические helpers.

### Шаг 18. Добавьте export

Простая инструкция: если анализ должен быть публичным, добавьте тип в блок
`export`.

Пример:

```julia
export OutlierScreeningAnalysis
```

Комментарий: без `export` анализ все равно можно вызвать как
`StatsWorkbench.OutlierScreeningAnalysis`, но для учебных примеров и обычного
пользовательского API удобнее экспортировать.

### Шаг 19. Добавьте пример в demo_workbook

Простая инструкция: покажите создание анализа, запуск, просмотр таблиц и
сохранение графиков.

Пример:

```julia
analysis = SW.OutlierScreeningAnalysis(:height_cm; threshold=2.5)
result = SW.analyze(wb, analysis)

show(SW.to_table(result); allrows=true, allcols=true)
show(SW.to_table(result; table=:preview); allrows=true, allcols=true)

savefig(SW.plot1(result), "demo_outlier_plot1.png")
savefig(SW.plot4(result), "demo_outlier_dashboard.png")
```

Комментарий: demo-файл является живой документацией. Хороший пример должен
показывать не только "анализ запускается", но и как пользователь смотрит
результаты через стандартный API.

### Шаг 20. Проверьте загрузку пакета

Простая инструкция: запустите минимальную проверку.

```powershell
julia --project=. --startup-file=no -e 'using StatsWorkbench; println("loaded")'
```

Комментарий: эта проверка ловит синтаксические ошибки, конфликты имен,
ошибки `include` и забытые зависимости. Если пакет не загружается, сначала
исправьте это, а уже потом проверяйте сам анализ.

### Шаг 21. Проверьте smoke-тест анализа

Простая инструкция: создайте маленький workbook, запустите анализ и проверьте
таблицы и графики.

Пример:

```julia
using StatsWorkbench, DataFrames

wb = open_workbook("Smoke")
add_dataset!(wb, :d, DataFrame(x=collect(1.0:10.0)))

analysis = OutlierScreeningAnalysis(:x)
result = analyze(wb, analysis)

@assert !isempty(result_tables(result))
@assert length(result_plots(result)) >= 4
to_table(result)
render_result_plot(result, 4)
```

Комментарий: smoke-тест не обязан доказывать всю статистику. Его задача -
быстро проверить, что основной пользовательский путь работает: вход читается,
расчет выполняется, result создается, таблицы конвертируются, графики
рендерятся.

### Шаг 22. Проверьте отчеты

Простая инструкция: сохраните результат в markdown, html и xlsx.

```julia
save_report("demo_my_analysis.md", result)
save_report("demo_my_analysis.html", result)
save_report("demo_my_analysis.xlsx", result)
```

Комментарий: если таблицы собраны через `AnalysisTable`, отчеты обычно
заработают без отдельного кода. Проблемы чаще всего возникают из-за слишком
сложных значений в ячейках таблиц. Для отчетов лучше использовать числа,
строки, `missing`, короткие векторы или компактные кортежи.

### Шаг 23. Проверьте git diff

Простая инструкция: перед завершением посмотрите, какие файлы изменены.

```powershell
git status --short
git diff --stat
```

Комментарий: новый анализ обычно меняет:

- новый файл в `src/Analyses/...`;
- `src/StatsWorkbench.jl`;
- возможно `src/Core/graphics.jl`, если нужен новый тип графика;
- возможно `examples/demo_workbook.jl`;
- возможно документацию.

Если изменились лишние файлы или сгенерировались ненужные артефакты, лучше
разобраться до коммита.

### Шаг 24. Когда нужен новый тип графика

Простая инструкция: добавляйте новый `spec.kind` в `src/Core/graphics.jl`
только если существующих видов недостаточно.

Комментарий: новый тип графика должен быть универсальным, а не одноразовым.
Например, `:confidence_interval` полезен многим анализам. А график, жестко
завязанный на один конкретный анализ, лучше сначала попытаться выразить через
`:line`, `:scatter`, `:bar`, `:histogram`, `:boxplot`, `:heatmap` или
`:dashboard`.

### Шаг 25. Минимальный чеклист готовности

Простая инструкция: перед тем как считать анализ готовым, проверьте список.

Комментарий:

- тип наследуется от `AbstractAnalysis`;
- есть конструктор с `AnalysisInfo`;
- есть `analysis_info`, `required_variables`, `produced_variables`;
- `analyze` возвращает `BaseAnalysisResult`;
- входные данные читаются через `getvar`;
- выходы, если есть, сохраняются через `store_vector!`;
- есть `calculations`;
- есть таблица `:summary`;
- есть дополнительные таблицы для подробностей;
- есть минимум 3 отдельных графика;
- есть 4-й dashboard-график;
- пакет загружается через `using StatsWorkbench`;
- smoke-тест анализа проходит;
- пример добавлен в demo или отдельный example-файл.
