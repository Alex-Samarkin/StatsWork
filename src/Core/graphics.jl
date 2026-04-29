"""
    available_plot_palettes()

Возвращает имена доступных преднастроенных палитр оформления.

Эта функция нужна как публичная точка входа: анализы и пользовательский код
могут опираться на нее вместо знания внутренних деталей `Plots.jl`.
"""
function available_plot_palettes()
    return [:colorful, :pastel, :contrast]
end

"""
    _resolve_plot_palette(name)

Внутренний маппинг от символического имени палитры к конкретной палитре `Plots`.

Такой слой абстракции позволяет менять визуальный стиль приложения,
не меняя код отдельных анализов.
"""
function _resolve_plot_palette(name::Symbol)
    if name == :colorful
        return palette(:default)
    elseif name == :pastel
        return palette(:pastel1)
    elseif name == :contrast
        return palette(:dark2)
    end

    error("Unknown plot palette: $name")
end

"""
    default_plot_config(; ...)

Создает базовый словарь настроек графики.

Идея в том, что любой анализ может взять этот набор как стартовую точку,
а потом переопределить только нужные параметры: подписи осей, layout, legend и т.д.
"""
function default_plot_config(; palette_name::Symbol=:colorful,
                             width::Int=1900,
                             aspect_ratio::Tuple{Int, Int}=(16, 9),
                             dpi::Int=300)
    height = round(Int, width * aspect_ratio[2] / aspect_ratio[1])
    return Dict{Symbol, Any}(
        :size => (width, height),
        :dpi => dpi,
        :palette => _resolve_plot_palette(palette_name)
    )
end

"""
    _render_plot(spec)

Нижний уровень рендеринга `PlotSpec` в конкретный объект `Plots.Plot`.

Именно здесь структурное описание графика превращается в вызов конкретной
функции `Plots`: `bar`, `scatter`, `histogram`, `plot`, `heatmap`.
"""
function _render_plot(spec::PlotSpec)
    options = default_plot_config()
    merge!(options, Dict{Symbol, Any}(spec.options))
    get!(options, :title, spec.title)

    if spec.kind == :bar
        x = get(spec.payload, :x, String[])
        y = get(spec.payload, :y, Float64[])
        return bar(x, y; options...)
    elseif spec.kind == :line
        x = get(spec.payload, :x, 1:length(get(spec.payload, :y, Any[])))
        y = get(spec.payload, :y, Any[])
        return plot(x, y; options...)
    elseif spec.kind == :scatter
        x = get(spec.payload, :x, Any[])
        y = get(spec.payload, :y, Any[])
        return scatter(x, y; options...)
    elseif spec.kind == :histogram
        values = get(spec.payload, :values, Any[])
        return histogram(values; options...)
    elseif spec.kind == :heatmap
        x = get(spec.payload, :x, Any[])
        y = get(spec.payload, :y, Any[])
        z = get(spec.payload, :z, zeros(0, 0))
        return heatmap(x, y, z; options...)
    elseif spec.kind == :dashboard
        # Dashboard — это композиция уже подготовленных дочерних PlotSpec.
        # Тем самым сложные визуализации можно собирать из простых кирпичиков.
        child_specs = get(spec.payload, :plots, PlotSpec[])
        child_plots = [_render_plot(child) for child in child_specs]
        layout = get(options, :layout, (1, max(1, length(child_plots))))
        delete!(options, :layout)
        return plot(child_plots...; layout=layout, options...)
    end

    error("Unsupported plot kind: $(spec.kind)")
end

"""
    render_result_plot(result, which)

Строит один график по его порядковому номеру внутри результата.

Это базовый механизм для пользовательских сокращений `plot1`, `plot2`, `plot3`.
"""
function render_result_plot(result::BaseAnalysisResult, which::Int)
    1 <= which <= length(result.plots) || error("Plot index $which is out of bounds")
    return _render_plot(result.plots[which])
end

"""
    render_result_plots(result)

Строит сразу все графики, которые описаны в результате анализа.
"""
function render_result_plots(result::BaseAnalysisResult)
    return [render_result_plot(result, i) for i in eachindex(result.plots)]
end

# Короткие функции-ярлыки удобны в интерактивной работе и в demo-скриптах:
# пользователь может быстро запросить первый, второй или третий стандартный график.
plot1(result::BaseAnalysisResult) = render_result_plot(result, 1)
plot2(result::BaseAnalysisResult) = render_result_plot(result, 2)
plot3(result::BaseAnalysisResult) = render_result_plot(result, 3)

"""
    plot_report(result; which=nothing)

Единая точка входа для построения графики по одному результату.

Если `which` не задан, возвращаются все графики результата.
Если задан номер, возвращается только один выбранный график.
"""
function plot_report(result::BaseAnalysisResult; which::Union{Nothing, Int}=nothing)
    return which === nothing ? render_result_plots(result) : render_result_plot(result, which)
end

"""
    plot_report(results)

Агрегированный вариант для списка результатов.

Полезен в ситуациях, когда генератор отчета или dashboard верхнего уровня
хочет собрать графики сразу по нескольким анализам.
"""
function plot_report(results::AbstractVector{<:AbstractAnalysisResult})
    figures = Any[]

    for result in results
        if result isa BaseAnalysisResult
            append!(figures, render_result_plots(result))
        else
            error("Unsupported result type: $(typeof(result))")
        end
    end

    return figures
end
