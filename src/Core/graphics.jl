const _GADFLY_PKGID = Base.PkgId(Base.UUID("c91e804a-d5a3-530f-b6f0-dfbca275c004"), "Gadfly")

function _gadfly_module()
    if !haskey(Base.loaded_modules, _GADFLY_PKGID)
        Base.require(_GADFLY_PKGID)
    end
    return Base.loaded_modules[_GADFLY_PKGID]
end

_gadfly_invoke(f, args...; kwargs...) = Base.invokelatest(f, args...; kwargs...)

function _gadfly_palette(name::Symbol)
    if name == :colorful
        return [
            "#1f77b4",
            "#ff7f0e",
            "#2ca02c",
            "#d62728",
            "#9467bd",
            "#8c564b",
            "#e377c2",
            "#7f7f7f"
        ]
    elseif name == :pastel
        return [
            "#87cefa",
            "#f08080",
            "#90ee90",
            "#dda0dd",
            "#f0e68c",
            "#ffa07a",
            "#20b2aa",
            "#b3b3b3"
        ]
    elseif name == :contrast
        return [
            "#000000",
            "#1874cd",
            "#cd2626",
            "#006400",
            "#cd6600",
            "#551a8b",
            "#cd1076",
            "#666666"
        ]
    end

    error("Unknown Gadfly palette: $name")
end

function _gadfly_tint(color::AbstractString, amount::Real)
    startswith(color, "#") && ncodeunits(color) == 7 || return color
    mix = clamp(float(amount), 0.0, 1.0)
    red = parse(Int, color[2:3], base=16)
    green = parse(Int, color[4:5], base=16)
    blue = parse(Int, color[6:7], base=16)
    tinted_red = round(Int, red + (255 - red) * mix)
    tinted_green = round(Int, green + (255 - green) * mix)
    tinted_blue = round(Int, blue + (255 - blue) * mix)
    return string(
        "#",
        uppercase(string(tinted_red, base=16, pad=2)),
        uppercase(string(tinted_green, base=16, pad=2)),
        uppercase(string(tinted_blue, base=16, pad=2))
    )
end

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
        return palette([
            :lightskyblue,
            :lightcoral,
            :palegreen3,
            :plum2,
            :khaki2,
            :lightsalmon,
            :lightseagreen,
            :gray70
        ])
    elseif name == :contrast
        return palette([
            :dodgerblue3,
            :black,
            :firebrick3,
            :darkgreen,
            :darkorange3,
            :purple4,
            :deeppink3,
            :gray40
        ])

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
    aspect_ratio::Tuple{Int,Int}=(16, 9),
    dpi::Int=300)
    height = round(Int, width * aspect_ratio[2] / aspect_ratio[1])
    return Dict{Symbol,Any}(
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
    merge!(options, Dict{Symbol,Any}(spec.options))
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
    elseif spec.kind == :histogram_normal
        values = Float64.(get(spec.payload, :values, Real[]))
        if isempty(values)
            return plot(; options...)
        end

        mu = get(spec.payload, :mean, mean(values))
        sigma = get(spec.payload, :std, length(values) == 1 ? 0.0 : std(values))
        get!(options, :normalize, :pdf)
        p = histogram(values; options...)

        if sigma > 0
            lower = minimum(values)
            upper = maximum(values)
            xs = collect(range(lower, upper; length=200))
            plot!(p, xs, pdf.(Normal(mu, sigma), xs); color=:black, linewidth=3, label="Normal")
        end
        return p
    elseif spec.kind == :boxplot
        values = Float64.(get(spec.payload, :values, Real[]))
        if isempty(values)
            return plot(; options...)
        end

        q1, med, q3 = quantile(values, [0.25, 0.5, 0.75])
        iqr_value = q3 - q1
        lower_fence = q1 - 1.5 * iqr_value
        upper_fence = q3 + 1.5 * iqr_value
        inside = values[(values.>=lower_fence).&(values.<=upper_fence)]
        whisker_low = isempty(inside) ? minimum(values) : minimum(inside)
        whisker_high = isempty(inside) ? maximum(values) : maximum(inside)
        outliers = values[(values.<whisker_low).|(values.>whisker_high)]

        delete!(options, :legend)
        get!(options, :xlim, (0.5, 1.5))
        get!(options, :xticks, false)
        get!(options, :legend, false)

        p = plot(; options...)
        plot!(p, [1.0, 1.0], [whisker_low, q1]; color=:black, linewidth=2, label="")
        plot!(p, [1.0, 1.0], [q3, whisker_high]; color=:black, linewidth=2, label="")
        plot!(p, [0.85, 1.15], [whisker_low, whisker_low]; color=:black, linewidth=2, label="")
        plot!(p, [0.85, 1.15], [whisker_high, whisker_high]; color=:black, linewidth=2, label="")
        plot!(p, Shape([0.75, 1.25, 1.25, 0.75], [q1, q1, q3, q3]); fillalpha=0.35, linecolor=:black, label="")
        plot!(p, [0.75, 1.25], [med, med]; color=:black, linewidth=3, label="")
        if get(spec.payload, :show_mean, true)
            scatter!(p, [1.0], [mean(values)]; marker=:diamond, markersize=7, color=:firebrick3, label="")
        end
        if !isempty(outliers)
            scatter!(p, fill(1.0, length(outliers)), outliers; markersize=4, markerstrokewidth=0, label="")
        end
        return p
    elseif spec.kind == :qq
        x = Float64.(get(spec.payload, :x, Real[]))
        y = Float64.(get(spec.payload, :y, Real[]))
        p = scatter(x, y; options...)
        if !isempty(x) && !isempty(y)
            line_x = Float64.(get(spec.payload, :line_x, [minimum(x), maximum(x)]))
            line_y = Float64.(get(spec.payload, :line_y, [minimum(y), maximum(y)]))
            plot!(p, line_x, line_y; color=:black, linewidth=2, label="")
        end
        return p
    elseif spec.kind == :confidence_interval
        lower = get(spec.payload, :lower, missing)
        upper = get(spec.payload, :upper, missing)
        estimate = get(spec.payload, :estimate, missing)
        label = String(get(spec.payload, :label, "Estimate"))

        if lower === missing || upper === missing || estimate === missing
            return plot(; options...)
        end

        delete!(options, :legend)
        get!(options, :legend, false)
        get!(options, :yticks, ([1], [label]))
        get!(options, :ylim, (0.5, 1.5))
        get!(options, :ylabel, "")

        p = plot(; options...)
        plot!(p, [Float64(lower), Float64(upper)], [1.0, 1.0]; linewidth=5, marker=:circle, label="")
        scatter!(p, [Float64(estimate)], [1.0]; marker=:diamond, markersize=8, color=:firebrick3, label="")
        return p
    elseif spec.kind == :heatmap
        x = get(spec.payload, :x, Any[])
        y = get(spec.payload, :y, Any[])
        z = get(spec.payload, :z, zeros(0, 0))
        return heatmap(x, y, z; options...)
    elseif spec.kind == :gadfly_scatter
        Gadfly = _gadfly_module()
        df = get(spec.payload, :data, DataFrame())
        mode = get(spec.payload, :mode, :index)
        variable_label = String(get(spec.payload, :variable_label, "Value"))
        group_label = String(get(spec.payload, :group_label, "Group"))
        palette_name = Symbol(get(spec.payload, :palette_name, :colorful))
        width = Int(get(spec.payload, :width, 1900))
        height = Int(get(spec.payload, :height, 600))
        palette_colors = _gadfly_palette(palette_name)

        _gadfly_invoke(Gadfly.set_default_plot_size, width * Gadfly.px, height * Gadfly.px)

        common_layers = Any[
            Gadfly.Geom.point,
            _gadfly_invoke(Gadfly.Guide.title, spec.title),
            _gadfly_invoke(Gadfly.Guide.ylabel, variable_label),
            _gadfly_invoke(
                Gadfly.Theme;
                default_color=palette_colors[1],
                discrete_color_scale=_gadfly_invoke(Gadfly.Scale.color_discrete_manual, palette_colors...),
                point_size=1.4 * Gadfly.mm,
                key_position=(mode == :group ? :right : :none)
            )
        ]

        if mode == :group
            push!(common_layers, _gadfly_invoke(Gadfly.Guide.xlabel, "Observation"))
            return _gadfly_invoke(
                Gadfly.plot,
                df,
                x=:observation,
                y=:value,
                color=:group,
                common_layers...
            )
        end

        push!(common_layers, _gadfly_invoke(Gadfly.Guide.xlabel, "Observation"))
        return _gadfly_invoke(
            Gadfly.plot,
            df,
            x=:observation,
            y=:value,
            common_layers...
        )
    elseif spec.kind == :gadfly_histogram
        Gadfly = _gadfly_module()
        df = get(spec.payload, :data, DataFrame())
        mode = get(spec.payload, :mode, :single)
        variable_label = String(get(spec.payload, :variable_label, "Value"))
        group_label = String(get(spec.payload, :group_label, "Group"))
        kde = Bool(get(spec.payload, :kde, true))
        palette_name = Symbol(get(spec.payload, :palette_name, :colorful))
        width = Int(get(spec.payload, :width, 1900))
        height = Int(get(spec.payload, :height, 600))
        palette_colors = _gadfly_palette(palette_name)

        _gadfly_invoke(Gadfly.set_default_plot_size, width * Gadfly.px, height * Gadfly.px)

        if mode == :group
            histogram_layer = _gadfly_invoke(
                Gadfly.layer,
                df,
                x=:value,
                color=:group,
                alpha=fill(0.45, nrow(df)),
                _gadfly_invoke(Gadfly.Geom.histogram; position=:identity, density=kde)
            )

            elements = Any[
                histogram_layer,
                _gadfly_invoke(Gadfly.Guide.title, spec.title),
                _gadfly_invoke(Gadfly.Guide.xlabel, variable_label),
                _gadfly_invoke(Gadfly.Guide.ylabel, kde ? "Density" : "Count"),
                _gadfly_invoke(
                    Gadfly.Theme;
                    default_color=palette_colors[1],
                    discrete_color_scale=_gadfly_invoke(Gadfly.Scale.color_discrete_manual, palette_colors...),
                    point_size=1.4 * Gadfly.mm,
                    key_position=:right
                )
            ]

            if kde
                density_layer = _gadfly_invoke(
                    Gadfly.layer,
                    df,
                    x=:value,
                    color=:group,
                    _gadfly_invoke(Gadfly.Geom.density)
                )
                push!(elements, density_layer)
            end

            return _gadfly_invoke(Gadfly.plot, elements...)
        end

        histogram_layer = _gadfly_invoke(
            Gadfly.layer,
            df,
            x=:value,
            _gadfly_invoke(Gadfly.Geom.histogram; density=kde)
        )

        elements = Any[
            histogram_layer,
            _gadfly_invoke(Gadfly.Guide.title, spec.title),
            _gadfly_invoke(Gadfly.Guide.xlabel, variable_label),
            _gadfly_invoke(Gadfly.Guide.ylabel, kde ? "Density" : "Count"),
            _gadfly_invoke(
                Gadfly.Theme;
                default_color=palette_colors[1],
                key_position=:none
            )
        ]

        if kde
            density_layer = _gadfly_invoke(
                Gadfly.layer,
                df,
                x=:value,
                _gadfly_invoke(Gadfly.Geom.density)
            )
            push!(elements, density_layer)
        end

        return _gadfly_invoke(Gadfly.plot, elements...)
    elseif spec.kind == :gadfly_boxplot
        Gadfly = _gadfly_module()
        df = get(spec.payload, :data, DataFrame())
        means_df = get(spec.payload, :means, DataFrame())
        variable_label = String(get(spec.payload, :variable_label, "Value"))
        palette_name = Symbol(get(spec.payload, :palette_name, :colorful))
        width = Int(get(spec.payload, :width, 1900))
        height = Int(get(spec.payload, :height, 600))
        variant = Symbol(get(spec.payload, :variant, :boxplot_mean))
        mode = get(spec.payload, :mode, :single)
        palette_colors = _gadfly_palette(palette_name)
        violin_palette = [_gadfly_tint(color, 0.58) for color in palette_colors]
        boxplot_palette = [_gadfly_tint(color, 0.30) for color in palette_colors]
        point_palette = [_gadfly_tint(color, 0.42) for color in palette_colors]
        outline_color = "#2b2b2b"

        _gadfly_invoke(Gadfly.set_default_plot_size, width * Gadfly.px, height * Gadfly.px)

        use_color = mode == :group
        key_position = use_color ? :right : :none

        elements = Any[
            _gadfly_invoke(Gadfly.Guide.title, spec.title),
            _gadfly_invoke(Gadfly.Guide.xlabel, "Group"),
            _gadfly_invoke(Gadfly.Guide.ylabel, variable_label),
            _gadfly_invoke(
                Gadfly.Theme;
                default_color=boxplot_palette[1],
                discrete_color_scale=_gadfly_invoke(Gadfly.Scale.color_discrete_manual, boxplot_palette...),
                point_size=1.0 * Gadfly.mm,
                highlight_width=0.35 * Gadfly.mm,
                discrete_highlight_color=_->outline_color,
                boxplot_spacing=0.2 * Gadfly.mm,
                key_position=key_position
            )
        ]

        if variant == :boxplot_violin
            violin_layer = use_color ?
                           _gadfly_invoke(
                               Gadfly.layer,
                               df,
                               x=:group,
                               y=:value,
                               color=:group,
                               _gadfly_invoke(
                                   Gadfly.Theme;
                                   default_color=violin_palette[1],
                                   discrete_color_scale=_gadfly_invoke(Gadfly.Scale.color_discrete_manual, violin_palette...),
                                   boxplot_spacing=0.2 * Gadfly.mm,
                                   key_position=:none
                               ),
                               Gadfly.Geom.violin
                           ) :
                           _gadfly_invoke(
                               Gadfly.layer,
                               df,
                               x=:group,
                               y=:value,
                               _gadfly_invoke(
                                   Gadfly.Theme;
                                   default_color=violin_palette[1],
                                   boxplot_spacing=0.2 * Gadfly.mm,
                                   key_position=:none
                               ),
                               Gadfly.Geom.violin
                           )
            push!(elements, violin_layer)
        end

        boxplot_layer = use_color ?
                        _gadfly_invoke(
                            Gadfly.layer,
                            df,
                            x=:group,
                            y=:value,
                            color=:group,
                            variant == :boxplot_points ?
                                _gadfly_invoke(Gadfly.Geom.boxplot; suppress_outliers=true) :
                                Gadfly.Geom.boxplot
                        ) :
                        _gadfly_invoke(
                            Gadfly.layer,
                            df,
                            x=:group,
                            y=:value,
                            variant == :boxplot_points ?
                                _gadfly_invoke(Gadfly.Geom.boxplot; suppress_outliers=true) :
                                Gadfly.Geom.boxplot
                        )
        push!(elements, boxplot_layer)

        if variant == :boxplot_points
            points_layer = use_color ?
                           _gadfly_invoke(
                               Gadfly.layer,
                               df,
                               x=:group,
                               y=:value,
                               color=:group,
                               _gadfly_invoke(
                                   Gadfly.Theme;
                                   default_color=point_palette[1],
                                   discrete_color_scale=_gadfly_invoke(Gadfly.Scale.color_discrete_manual, point_palette...),
                                   point_size=0.65 * Gadfly.mm,
                                   highlight_width=0.35 * Gadfly.mm,
                                   discrete_highlight_color=_->outline_color,
                                   key_position=:none
                               ),
                               _gadfly_invoke(Gadfly.Geom.beeswarm; padding=0.02 * Gadfly.mm)
                           ) :
                           _gadfly_invoke(
                               Gadfly.layer,
                               df,
                               x=:group,
                               y=:value,
                               _gadfly_invoke(
                                   Gadfly.Theme;
                                   default_color=point_palette[1],
                                   point_size=0.65 * Gadfly.mm,
                                   highlight_width=0.35 * Gadfly.mm,
                                   discrete_highlight_color=_->outline_color,
                                   key_position=:none
                               ),
                               _gadfly_invoke(Gadfly.Geom.beeswarm; padding=0.02 * Gadfly.mm)
                           )
            push!(elements, points_layer)
        end

        mean_layer = _gadfly_invoke(
            Gadfly.layer,
            means_df,
            x=:group,
            y=:mean,
            _gadfly_invoke(
                Gadfly.Theme;
                default_color="#b22222",
                point_size=1.4 * Gadfly.mm,
                key_position=:none
            ),
            Gadfly.Geom.point
        )
        push!(elements, mean_layer)

        return _gadfly_invoke(Gadfly.plot, elements...)
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
# пользователь может быстро запросить стандартные графики по порядку.
plot1(result::BaseAnalysisResult) = render_result_plot(result, 1)
plot2(result::BaseAnalysisResult) = render_result_plot(result, 2)
plot3(result::BaseAnalysisResult) = render_result_plot(result, 3)
plot4(result::BaseAnalysisResult) = render_result_plot(result, 4)

"""
    plot_report(result; which=nothing)

Единая точка входа для построения графики по одному результату.

Если `which` не задан, возвращаются все графики результата.
Если задан номер, возвращается только один выбранный график.
"""
function plot_report(result::BaseAnalysisResult; which::Union{Nothing,Int}=nothing)
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
