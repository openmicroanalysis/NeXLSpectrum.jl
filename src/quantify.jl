"""
    NeXLMatrixCorrection.quantify(
      ffr::FitResult;
      strip::AbstractVector{Element} = [],
      mc::Type{<:MatrixCorrection} = XPP,
      fl::Type{<:FluorescenceCorrection} = ReedFluorescence,
      kro::KRatioOptimizer = SimpleKRatioOptimizer(1.5),
    )::IterationResult

Facilitates converting `FilterFitResult` or `BasicFitResult` objects into estimates of composition by extracting
k-ratios from measured spectra and applying matrix correction algorithms.
"""
function NeXLMatrixCorrection.quantify(
    ffr::FitResult;
    strip::AbstractVector{Element} = Element[],
    mc::Type{<:MatrixCorrection} = XPP,
    fl::Type{<:FluorescenceCorrection} = ReedFluorescence,
    cc::Type{<:CoatingCorrection} = Coating,
    kro::KRatioOptimizer = SimpleKRatioOptimizer(1.5),
)::IterationResult
    iter = Iteration(mc, fl, cc, updater = WegsteinUpdateRule())
    krs = filter(kr -> !(element(kr) in strip), kratios(ffr))
    return quantify(iter, ffr.label, optimizeks(kro, krs))
end

"""
    NeXLMatrixCorrection.quantify(
        spec::Spectrum,
        ffp::FilterFitPacket;
        kwargs...
    )::IterationResult

Failitates quantifying spectra.  First filter fits and then matrix corrects.
"""
function NeXLMatrixCorrection.quantify(
    spec::Spectrum,
    ffp::FilterFitPacket;
    kwargs...
)::IterationResult
    return quantify(fit(spec, ffp), kwargs...)
end
