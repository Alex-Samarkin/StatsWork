module GUInput

import Term: Panel, tprint, tprintln

export GUIInput, input_int, input_float, select_option, select_options

const MaybeReal = Union{Real,Nothing}

function _term_line(message::AbstractString; output::IO=stdout, style::AbstractString="bold cyan")
    if output === stdout
        tprintln("{$style}$message{/$style}")
    else
        println(output, message)
    end
    return nothing
end

function _term_prompt(prompt::AbstractString; output::IO=stdout)
    if output === stdout
        tprint("{bold}$prompt{/bold}")
    else
        print(output, prompt)
    end
    flush(output)
    return nothing
end

function _term_panel(title::AbstractString, message::AbstractString; output::IO=stdout)
    if output === stdout
        print(Panel(message; title=title, style="cyan", fit=true))
        println()
    else
        println(output, "$title: $message")
    end
    return nothing
end

function _readline(input::IO)
    try
        return readline(input)
    catch err
        err isa EOFError || rethrow()
        return ""
    end
end

function _in_bounds(value::Real, minimum::MaybeReal, maximum::MaybeReal)
    minimum !== nothing && value < minimum && return false
    maximum !== nothing && value > maximum && return false
    return true
end

function _range_hint(minimum::MaybeReal, maximum::MaybeReal)
    minimum === nothing && maximum === nothing && return ""
    minimum === nothing && return " <= $maximum"
    maximum === nothing && return " >= $minimum"
    return " between $minimum and $maximum"
end

function _integer_values(minimum::Integer, maximum::Integer, step::Integer)
    step > 0 || error("`step` must be positive")
    minimum <= maximum || error("`min` must be less than or equal to `max`")

    values = collect(Int(minimum):Int(step):Int(maximum))
    isempty(values) && error("Input range is empty")
    return values
end

function _nearest_integer(value, values::AbstractVector{Int})
    parsed = try
        Int(round(Float64(value)))
    catch
        first(values)
    end

    nearest_index = argmin(abs.(values .- parsed))
    return values[nearest_index]
end

function _parse_number(::Type{T}, raw::AbstractString) where {T<:Real}
    value = tryparse(T, strip(raw))
    value === nothing && error("Please enter a valid $(T).")
    return value
end

"""
    input_int(; default=0, min=-100, max=100, step=1, message="Input integer")

Ask for an integer in the terminal using Term-styled prompts. Press Enter to
accept `default`. Values are snapped to the nearest value in `min:step:max`.
"""
function input_int(; default::Integer=0,
                   min::Integer=-100,
                   max::Integer=100,
                   spep::Integer=1,
                   step::Integer=spep,
                   message::AbstractString="Input integer",
                   input::IO=stdin,
                   output::IO=stdout)
    values = _integer_values(min, max, step)
    default_value = Int(default)
    min <= default_value <= max || error("`default` must be between `min` and `max`")
    hint = "$message [$min:$step:$max, default $default_value]"
    _term_panel("Integer input", hint; output=output)

    while true
        try
            _term_prompt("> "; output=output)
            raw = strip(_readline(input))
            isempty(raw) && return default_value

            value = _parse_number(Int, raw)
            value in values && return value
            snapped = _nearest_integer(value, values)
            _term_line("Value is outside the step range. Nearest valid value: $snapped"; output=output, style="yellow")
        catch err
            err isa InterruptException && return default_value
            _term_line(sprint(showerror, err); output=output, style="red")
        end
    end
end

"""
    input_float(; default=0.0, min=nothing, max=nothing, message="Input float")

Ask for a floating point value in the terminal using Term-styled prompts. Press
Enter to accept `default`.
"""
function input_float(; default::Real=0.0,
                     min::MaybeReal=nothing,
                     max::MaybeReal=nothing,
                     message::AbstractString="Input float",
                     input::IO=stdin,
                     output::IO=stdout)
    default_value = Float64(default)
    _in_bounds(default_value, min, max) || error("`default` must be$(_range_hint(min, max))")

    hint = "$message$(_range_hint(min, max)), default $default_value"
    _term_panel("Float input", hint; output=output)

    while true
        try
            _term_prompt("> "; output=output)
            raw = strip(_readline(input))
            isempty(raw) && return default_value

            value = _parse_number(Float64, raw)
            if _in_bounds(value, min, max)
                return value
            end
            _term_line("Value must be$(_range_hint(min, max))."; output=output, style="yellow")
        catch err
            err isa InterruptException && return default_value
            _term_line(sprint(showerror, err); output=output, style="red")
        end
    end
end

function _option_index(options::AbstractVector, value)
    value isa Integer && 1 <= value <= length(options) && return Int(value)
    match = findfirst(==(value), options)
    match === nothing && error("Option `$value` is not present")
    return match
end

function _default_option_index(options::AbstractVector, default)
    isempty(options) && error("`options` must not be empty")
    default === nothing && return 1
    return _option_index(options, default)
end

function _default_option_indexes(options::AbstractVector, default)
    isempty(options) && error("`options` must not be empty")
    default === nothing && return Int[]
    defaults = default isa AbstractVector || default isa Tuple ? collect(default) : [default]
    indexes = [_option_index(options, item) for item in defaults]
    return unique(indexes)
end

function _parse_option_indexes(raw::AbstractString, noptions::Integer)
    text = lowercase(strip(raw))
    isempty(text) && return nothing
    text in ("all", "*") && return collect(1:noptions)
    text in ("none", "-") && return Int[]

    pieces = split(text, r"[\s,;]+")
    indexes = Int[]
    for piece in pieces
        isempty(piece) && continue
        index = tryparse(Int, piece)
        index === nothing && error("Use option numbers separated by commas or spaces.")
        1 <= index <= noptions || error("Choose numbers from 1 to $noptions.")
        push!(indexes, index)
    end
    return unique(indexes)
end

"""
    select_option(options; default=1, message="Select option")

Show numbered options in the terminal and return the selected option value.
Press Enter to accept `default`, which can be either an index or an option
value.
"""
function select_option(options::AbstractVector;
                       default=1,
                       message::AbstractString="Select option",
                       input::IO=stdin,
                       output::IO=stdout)
    default_index = _default_option_index(options, default)
    lines = String[message]
    for (index, option) in pairs(options)
        marker = index == default_index ? "*" : " "
        push!(lines, " $marker $index. $option")
    end
    push!(lines, "Default: $default_index")
    _term_panel("Option input", join(lines, "\n"); output=output)

    while true
        try
            _term_prompt("> "; output=output)
            raw = strip(_readline(input))
            isempty(raw) && return options[default_index]

            selected = _parse_number(Int, raw)
            if 1 <= selected <= length(options)
                return options[selected]
            end
            _term_line("Choose a number from 1 to $(length(options))."; output=output, style="yellow")
        catch err
            err isa InterruptException && return options[default_index]
            _term_line(sprint(showerror, err); output=output, style="red")
        end
    end
end

"""
    select_options(options; default=nothing, message="Select options")

Show numbered options in the terminal and return selected option values. Enter
several numbers separated by commas or spaces, `all` for every option, or
`none` for an empty selection. Press Enter to accept `default`.
"""
function select_options(options::AbstractVector;
                        default=nothing,
                        message::AbstractString="Select options",
                        input::IO=stdin,
                        output::IO=stdout)
    default_indexes = _default_option_indexes(options, default)
    default_set = Set(default_indexes)
    lines = String[message]
    for (index, option) in pairs(options)
        marker = index in default_set ? "*" : " "
        push!(lines, " $marker $index. $option")
    end
    default_label = isempty(default_indexes) ? "none" : join(default_indexes, ", ")
    push!(lines, "Default: $default_label")
    push!(lines, "Use: 1,3 or 1 3; all; none")
    _term_panel("Multi-option input", join(lines, "\n"); output=output)

    while true
        try
            _term_prompt("> "; output=output)
            raw = _readline(input)
            selected_indexes = _parse_option_indexes(raw, length(options))
            selected_indexes === nothing && return options[default_indexes]
            return options[selected_indexes]
        catch err
            err isa InterruptException && return options[default_indexes]
            _term_line(sprint(showerror, err); output=output, style="red")
        end
    end
end

"""
    GUIInput(; default=0, min=-100, max=100, step=1, message="Input integer")

Compatibility wrapper for the old Gtk-based integer picker. The input now uses
Term-styled terminal prompts and returns an integer.
"""
function GUIInput(; default::Integer=0,
                  min::Integer=-100,
                  max::Integer=100,
                  spep::Integer=1,
                  step::Integer=spep,
                  message::AbstractString="Input integer",
                  host::AbstractString="127.0.0.1",
                  port::Integer=8081,
                  input::IO=stdin,
                  output::IO=stdout,
)
    return input_int(; default=default,
                       min=min,
                       max=max,
                       step=step,
                       message=message,
                       input=input,
                       output=output)
end

end
