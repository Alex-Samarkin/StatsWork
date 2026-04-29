using Pkg
# Подключаем менеджер пакетов Julia.
# В демонстрационных скриптах это часто делается прямо в начале,
# чтобы код запускался в правильном проектном окружении независимо
# от того, из какой папки пользователь его открыл.
Pkg.activate(joinpath(@__DIR__, ".."))
# `@__DIR__` указывает на директорию текущего файла `demo_workbook.jl`.
# Комбинация `joinpath(@__DIR__, "..")` поднимается на один уровень выше,
# то есть к корню проекта. Именно там ожидается `Project.toml`,
# описывающий зависимости проекта.

using Revise
using DataFrames
using Statistics
using Plots
# `Revise` удобен в интерактивной разработке: он подхватывает изменения
# в исходниках без необходимости полностью перезапускать сессию Julia.
# `DataFrames` даёт табличные структуры данных, а `Statistics` подключает
# базовые статистические функции стандартной библиотеки.

if isdefined(Main, :StatsWorkbench)
    # VS Code keeps `Main` alive between runs, so we reuse the loaded module.
    # Если модуль уже был загружен в пространство `Main`, подключаем именно
    # его локальную версию. Это особенно полезно при повторных запусках
    # скрипта из IDE: состояние процесса сохраняется, и повторная загрузка
    # может вести себя иначе, чем в "чистой" сессии.
    Core.eval(Main, :(using .StatsWorkbench))
else
    # В обычной ситуации модуль ещё не загружен, поэтому импортируем его
    # стандартным способом из активированного окружения проекта.
    Core.eval(Main, :(using StatsWorkbench))
end

using .StatsWorkbench
# После этого делаем модуль доступным в текущей области видимости,
# чтобы можно было вызывать его функции без длинных квалифицированных имён.

const SW = StatsWorkbench
# Заводим короткий псевдоним `SW`. Это не обязательный шаг, но он делает
# примеры компактнее и удобнее для чтения, особенно там, где нужно явно
# показать принадлежность функции модулю.

# ============================================================
# Demo: data loading + data quality diagnosis + workbook usage
# ============================================================
# Ниже расположен линейный "учебный сценарий": мы по шагам загружаем
# данные, проверяем их качество, изучаем результаты диагностики и затем
# используем эти данные в рабочем пространстве (`workbook`).

# 1. Load external data into a DataFrame.
# `safe_load` читает CSV-файл и возвращает `DataFrame`.
# Название функции подсказывает, что внутри, вероятно, есть дополнительные
# проверки или защитная логика по сравнению с прямым вызовом CSV-парсера.
df = safe_load("./examples/patients_3500.csv")
# `size(df)` возвращает кортеж `(число_строк, число_столбцов)`.
# Сразу печатаем размер набора данных, чтобы убедиться, что файл считался
# корректно и объём данных соответствует ожиданиям.
println("Loaded dataset size: ", size(df))

# 2. Run diagnostics.
# Функция `diagnose(df)` строит объект диагностики качества данных.
# Обычно такой объект содержит агрегированные сводки, список найденных
# проблем, рекомендации по исправлению и вспомогательные представления
# для последующего анализа.
dq = diagnose(df)
println()
# Печать пустой строки здесь служит только для визуального отделения
# блоков вывода в консоли.
println(dq)
# Выводим сам объект `dq`. Если для него реализован красивый `show`,
# в консоли появится компактная сводка по найденным проблемам.

# 3. Frame-level summary.
# "Frame-level" означает сводку по таблице в целом: общие метрики,
# количество строк, число проблемных записей, доля пропусков и т.п.
println("\n=== Frame report ===")
show(dq.frame; allrows=true, allcols=true)
# Используем `show`, а не `println`, потому что для `DataFrame` так
# вывод получается более табличным. Флаги `allrows=true, allcols=true`
# отключают усечение и просят показать весь отчёт целиком.
println()

# 4. Column-level summary.
# На этом шаге изучаем качество данных уже по отдельным столбцам.
# Мы объединяем базовый отчёт `dq.columns` со скоринговой оценкой,
# чтобы можно было отсортировать столбцы по проблемности.
println("\n=== Column report: most problematic columns first ===")
col_report = leftjoin(dq.columns, column_score(dq), on=:column)
# `leftjoin` сохраняет все строки левого датафрейма (`dq.columns`) и
# подтягивает к ним вычисленные оценки по имени столбца.
col_report.score = coalesce.(col_report.score, 0)
col_report.n_issues = coalesce.(col_report.n_issues, 0)
# После соединения часть значений может оказаться `missing`, если для
# какого-то столбца оценка не была рассчитана. `coalesce.` поэлементно
# заменяет `missing` на 0, чтобы потом можно было безопасно сортировать.
sort!(col_report, [:score, :n_issues], rev=true)
# Сортировка "на месте" (`sort!`) экономит память.
# `rev=true` означает порядок по убыванию: наверху окажутся столбцы
# с наибольшим суммарным скором и числом замечаний.
show(first(col_report, min(15, nrow(col_report))); allcols=true)
# Показываем только первые 15 строк либо меньше, если самих столбцов
# меньше 15. Так вывод остаётся информативным и не слишком громоздким.
println()

# 5. Error map aggregated by issue type and column.
# Здесь строится сводка "тип проблемы x столбец".
# Такой срез помогает понять не просто где есть ошибки, а какого именно
# рода они преобладают: пропуски, выбросы, некорректные форматы и т.д.
println("\n=== Error summary by issue type ===")
summary_by_issue = inspect(dq)
show(summary_by_issue; allcols=true)
println()

# 6. Same map, but aggregated by status: warning / error.
# Ещё один уровень агрегации: теперь группируем проблемы по степени
# серьёзности (`status`), например предупреждения против ошибок.
println("\n=== Error summary by severity status ===")
summary_by_status = error_summary(dq; by=:status)
show(summary_by_status; allcols=true)
println()

# 7. Overall issue ranking.
# Этот отчёт ранжирует типы проблем глобально по всему набору данных.
# Он полезен, когда нужно быстро определить, какие классы ошибок сильнее
# всего влияют на качество данных и требуют первоочередного внимания.
println("\n=== Issue type ranking ===")
show(issue_summary(dq); allrows=true, allcols=true)
println()

# 8. Drill-down into the most problematic column.
# Переходим от агрегированной аналитики к детализации.
# Если отчёт по типам проблем не пустой, берём первую строку. Поскольку
# ранее мы строили проблемно-ориентированные сводки, здесь разумно
# интерпретировать первый столбец как один из самых проблемных.
if nrow(summary_by_issue) > 0
    selected_col = summary_by_issue.column[1]
    # Извлекаем имя столбца, чтобы затем адресно посмотреть только его.

    println("\n=== Drill-down column: ", selected_col, " ===")
    show(issues_summary(dq, selected_col); allrows=true, allcols=true)
    # `issues_summary` даёт детальную разбивку проблем внутри выбранного
    # столбца: сколько каких нарушений найдено именно в нём.
    println()

    example_rows = rows_with_issues(dq, selected_col)
    # Получаем номера строк, в которых по выбранному столбцу были найдены
    # замечания. Это мост между агрегированной диагностикой и исходными
    # данными, позволяющий перейти к конкретным наблюдениям.
    println("\nProblem rows in ", selected_col, ":")
    println(example_rows[1:min(20, length(example_rows))])
    # Печатаем только первые 20 индексов, чтобы не перегружать консоль.

    println("\n=== Source rows with issues in ", selected_col, " ===")
    show(view_rows(df, dq, selected_col; n=10); allcols=true)
    # `view_rows` возвращает небольшой фрагмент исходного датафрейма
    # по проблемным строкам. Параметр `n=10` ограничивает пример десятью
    # строками, чего обычно достаточно для первичного визуального анализа.
    println()

    # 9. Drill-down into one row.
    # Если проблемные строки действительно есть, проваливаемся ещё глубже:
    # выбираем первую из них и смотрим все связанные с ней замечания.
    if !isempty(example_rows)
        selected_row = first(example_rows)

        println("\n=== Issues in row ", selected_row, " ===")
        show(inspect(dq; row=selected_row); allrows=true, allcols=true)
        # Здесь `inspect` используется уже с фильтром по строке, а значит
        # возвращает перечень проблем только для одного наблюдения.
        println()

        println("\n=== Highlighted row ", selected_row, " ===")
        show(highlight_row(df, dq, selected_row); allrows=true, allcols=true)
        # `highlight_row` полезен для объясняющего режима: он показывает
        # исходную строку и, вероятно, визуально помечает проблемные поля.
        println()
    end
end

# 10. Proposed repair plan. This will be used later by repair(df, dq).
# После диагностики можно не только смотреть на ошибки, но и строить
# план исправлений. `dq.actions` хранит набор рекомендуемых действий,
# который затем потенциально может быть подан в функцию ремонта данных.
println("\n=== Proposed repair actions ===")
show(dq.actions; allrows=true, allcols=true)
println()

# 11. Optional static plots.
# Ниже оставлены закомментированные вызовы построения графиков.
# Это хороший приём для учебного примера: читатель видит, что такие
# возможности есть, но запуск не требует обязательной графической среды.
# plot_error_summary(dq)
# plot_error_bars(dq)

# 12. Put the dataset into the workbook / variable space.
# Теперь переходим от проверки качества к сценарию "рабочей книги".
# `Workbook` здесь играет роль контейнера, где можно хранить датасеты,
# обращаться к переменным по имени, вычислять новые признаки и сохранять
# результат работы как единое рабочее пространство.
wb = open_workbook("Demo")
add_dataset!(wb, :data, df)
# Функция с `!` в Julia по соглашению изменяет объект "на месте".
# `add_dataset!` регистрирует датафрейм `df` внутри рабочей книги под
# символическим именем `:data`.

# Add a second dataset to demonstrate disambiguated variable names.
# Добавляем второй набор данных намеренно: это позволяет показать, как
# система различает переменные из разных источников по квалифицированным
# именам вроде `data.id` и, возможно, `visits.id`, если бы такой столбец
# существовал во втором датафрейме.
visits = DataFrame(id=1:5, visit_score=rand(5))
add_dataset!(wb, :visits, visits)

println("\n=== Workbook variables ===")
println(vars(wb))
# `vars(wb)` возвращает список доступных переменных в рабочей книге.
# Это удобная стартовая точка для понимания того, какие имена сейчас
# можно использовать в последующих вычислениях.

println("\n=== Variable access examples ===")
println(SW.getvar(wb, :age))
println(SW.getvar(wb, Symbol("data.id")))
# Первый пример показывает доступ по короткому имени переменной.
# Второй пример иллюстрирует явное обращение к переменной конкретного
# датасета через квалифицированное имя `data.id`.

SW.calc!(wb, :height_m, :height_cm, /, 100)
SW.calc!(wb, :pulse_pressure, :sbp_mmhg, -, :dbp_mmhg)
SW.calc!(wb, :age_plus_visit_score, :age, +, :visit_score; align=:truncate)
# `calc!` создаёт новые переменные в рабочей книге на основе операций
# над уже существующими.
# 1. `height_m = height_cm / 100` переводит рост из сантиметров в метры.
# 2. `pulse_pressure = sbp_mmhg - dbp_mmhg` вычисляет пульсовое давление.
# 3. `age_plus_visit_score` демонстрирует вычисление между переменными
#    из наборов разной длины. Опция `align=:truncate` подсказывает, что
#    при несовпадении размеров следует обрезать результат до общей длины.

println("\n=== Variables after calculations ===")
println(vars(wb))
println(SW.getvar(wb, :height_m))
println(SW.getvar(wb, :pulse_pressure))
println(SW.getvar(wb, :age_plus_visit_score))
# Сначала снова печатаем список переменных, чтобы увидеть, что новые
# вычисляемые признаки действительно появились в рабочей книге, а затем
# смотрим их конкретные значения.

println("\n=== Workbook log ===")
println(wb.logs)
# Лог рабочей книги полезен для воспроизводимости: по нему можно понять,
# какие операции были выполнены, в каком порядке и с какими аргументами.

# 13. Descriptive analysis over selected workbook variables.
# Этот блок показывает базовый сценарий работы с системой анализов:
# 1. сначала мы создаем объект-спецификацию анализа;
# 2. затем исполняем его в контексте workbook через `analyze`;
# 3. после этого используем единый API результата для просмотра таблиц
#    и сохранения отчетов в разные форматы.
# Такой двухшаговый подход удобен архитектурно: спецификация анализа
# отделена от конкретного запуска над данными.
desc = SW.DescriptiveStatsAnalysis([:age, :height_cm, :weight_kg, :sbp_mmhg, :dbp_mmhg])
desc_result = SW.analyze(wb, desc)
println("\n=== Analysis result object ===")
println(desc_result)
println("\n=== Analysis summary table ===")
show(SW.to_table(desc_result); allrows=true, allcols=true)
println()
# Один и тот же результат можно сохранить в несколько текстовых и табличных
# представлений. Здесь демонстрируется, что слой отчетности уже не зависит
# от конкретного анализа: он работает с общим типом результата.
SW.save_report("demo_descriptive_report.md", desc_result)
SW.save_report("demo_descriptive_report.html", desc_result)
SW.save_report("demo_descriptive_report.xlsx", desc_result)

# 14. Deterministic integer sequence generator.
# Этот анализ относится к генераторам данных и создает новую workbook-
# переменную, а не только описывает уже существующие данные. Поэтому после
# выполнения мы смотрим и сам созданный вектор, и несколько представлений
# результата: краткую summary-таблицу и preview первых значений.
sequence_analysis = SW.IntegerSequenceGeneratorAnalysis(
    :sequence_10;
    start=5,
    step=3,
    count=12,
    namespace=:generated,
    maximum=20
)
sequence_result = SW.analyze(wb, sequence_analysis)

println("\n=== Generated sequence variable ===")
println(SW.getvar(wb, Symbol("generated.sequence_10")))
println("\n=== Sequence generator summary ===")
show(SW.to_table(sequence_result); allrows=true, allcols=true)
println()
println("\n=== Sequence generator preview ===")
show(SW.to_table(sequence_result; table=:preview); allrows=true, allcols=true)
println()

# 15. Random integer generator from a discrete distribution.
# Здесь уже используется воспроизводимая случайная генерация из
# `Distributions.jl`: имя распределения задается английским названием,
# параметры передаются словарем, а `seed` фиксирует конкретную выборку.
# Результат снова унифицирован: он хранит и созданную переменную, и summary,
# и таблицу параметров генерации, и набор графических спецификаций.
random_int_analysis = SW.RandomIntegerGeneratorAnalysis(
    :rand_pois;
    distribution="poisson",
    parameters=Dict{Symbol, Any}(:lambda => 4.5),
    count=200,
    seed=20260429,
    namespace=:generated,
    palette_name=:colorful
)
random_int_result = SW.analyze(wb, random_int_analysis)

println("\n=== Random integer variable ===")
println(first(SW.getvar(wb, Symbol("generated.rand_pois")), 20))
println("\n=== Random integer summary ===")
show(SW.to_table(random_int_result); allrows=true, allcols=true)
println()
println("\n=== Random integer specification ===")
show(SW.to_table(random_int_result; table=:specification); allrows=true, allcols=true)
println()

# 16. Rendering concrete plots from the result.
# Анализ не строит графики "на месте", а сохраняет их как `PlotSpec`.
# Функции `plot1/plot2/plot3` показывают, как отдельный графический слой
# может позднее материализовать эти спецификации в реальные объекты `Plots`.
# Для генератора случайных целых:
# - `plot1` -> scatterplot значений по индексу;
# - `plot2` -> histogram формы распределения;
# - `plot3` -> dashboard, объединяющий оба графика.
scatter_plot = SW.plot1(random_int_result)
histogram_plot = SW.plot2(random_int_result)
dashboard_plot = SW.plot3(random_int_result)

# Сохраняем графики в PNG-файлы, чтобы демо показывало не только консольный
# вывод и табличные отчеты, но и полный цикл построения визуализаций.
savefig(scatter_plot, "demo_random_integer_scatter.png")
savefig(histogram_plot, "demo_random_integer_histogram.png")
savefig(dashboard_plot, "demo_random_integer_dashboard.png")

SW.commit!(wb, :age_plus_visit_score; to=:data, align=:padmissing)
SW.save_workspace(wb, "demo_workspace.jld2")
# `commit!` переносит вычисленную переменную обратно в указанный датасет
# внутри рабочей книги. Здесь результат сохраняется в набор `:data`.
# Параметр `align=:padmissing` подсказывает, что если длина вычисленного
# вектора меньше длины целевого набора, недостающие значения нужно
# дополнить `missing`, а не отбрасывать строки.
#
# `save_workspace` сериализует состояние рабочей книги в файл `JLD2`,
# чтобы к нему можно было вернуться в будущем без повторения всех шагов.

restored = SW.load_workspace("demo_workspace.jld2")
# После загрузки получаем новый объект рабочей книги `restored`.
# Это демонстрирует, что рабочее пространство действительно переносимо
# между сессиями Julia.
println("\n=== Restored committed variable ===")
println(SW.getvar(restored, Symbol("data.age_plus_visit_score")))
# Проверяем, что сохранённая и затем восстановленная переменная доступна
# в загруженном workspace по своему полному имени.

close_workbook!(wb)
# В конце явно закрываем рабочую книгу. Даже если объект со временем
# будет собран сборщиком мусора, явное завершение работы делает сценарий
# аккуратным и подчёркивает жизненный цикл ресурса.
