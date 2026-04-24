abstract type AbstractAnalysisResult end

struct AnalysisResult <: AbstractAnalysisResult
    id::Symbol
    group::Symbol
    analysis::Symbol
    title::String
    data::Dict{Symbol, Any}
    tables::Dict{Symbol, Any}
    metadata::Dict{Symbol, Any}
end
