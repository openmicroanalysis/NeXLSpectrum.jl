using .Gadfly
using Colors
using Printf
"""
`NeXLSpectrumStyle` defines the default look-and-feel for Gadfly.plot(...) as
applied to EDS spectra using the Gadfly.plot(...) functions implemented in 
`NeXLSpectrum`.
"""
const NeXLSpectrumStyle = style(
    background_color=nothing,
    panel_fill=RGB(253 / 255, 253 / 255, 241 / 255),
    grid_color=RGB(255 / 255, 223 / 255, 223 / 255),
    grid_color_focused=RGB(255 / 255, 200 / 255, 200 / 255),
    grid_line_style=:solid,
    major_label_color=RGB(32 / 255, 32 / 255, 32 / 255),
    major_label_font_size=9pt,
    panel_stroke=RGB(32 / 255, 32 / 255, 32 / 255),
    plot_padding=[2pt],
    key_title_font_size=9pt,
    key_position=:right, # :bottom
    colorkey_swatch_shape=:square
)


"""
    plot(
	    specs::Union{Spectrum...,AbstractVector{Spectrum{<:Real}}};
	    klms=[],
	    edges=[],
		escapes=[],
		coincidences=[],
	    autoklms = false,
	    xmin=0.0,
	    xmax=missing,
	    norm=:None,
	    yscale=1.05,
	    ytransform = identity,
		style=NeXLSpectrumStyle,
		palette=NeXLPalette
    )::Plot

Required:

	specs::AbstractVector{Spectrum};

Named:

    klms = Union{Element, CharXRay}[ ]
	edges = Union{Element, AtomicSubShell}[ ]
	escapes = Union{Element, CharXRay}[ ],
	coincidences = CharXRay[ ],
	autoklms = false # Add KLMs based on elements in spectra
	xmin = 0.0 # Min energy (eV)
	xmax = missing # Max energy (eV) (defaults to max(:BeamEnergy))
	norm = NoScaling() | ScaleDoseWidth() | ScaleDose() | ScaleSum() | ScaleROISum() | ScalePeak() | (<: SpectrumScaling)()
	yscale = 1.05 # Fraction of max intensity for ymax over [max(lld,xmin):xmax]
	ytransform = identity | log10 | sqrt | ??? # How to transform the counts data before plotting
	style=NeXLSpectrumStyle (or another Gadfly.style)
	palette = NeXLPalette | Colorant[ ... ] # Colors for spectra...
    customlayers = Gadfly.Layer[] # Allows additional plot layers to be added

Plot a multiple spectra on a single plot using Gadfly.
"""
Gadfly.plot( #
    specs::AbstractVector{Spectrum{<:Real}};
    kwargs...
) = plot( #
    specs...;
    kwargs...
)
function Gadfly.plot(
    specs::Spectrum{<:Real}...;
    klms::Union{AbstractVector,AbstractSet,Tuple,NTuple,Material}=CharXRay[],
    edges::AbstractVector=AtomicSubShell[],
    escapes::AbstractVector=CharXRay[],
    coincidences::AbstractVector{CharXRay}=CharXRay[],
    autoklms=false,
    xmin=0.0,
    xmax=missing,
    legend=true,
    norm=NoScaling(),
    yscale=1.05,
    ytransform=identity,
    style=NeXLSpectrumStyle,
    palette=NeXLPalette,
    customlayers=Gadfly.Layer[],
    duanehunt=false,
    title=nothing,
    minklmweight=1.0e-3
)::Plot
    function klmLayer(specdata, cxrs::AbstractArray{CharXRay})  
        d = Dict{Any,Vector{CharXRay}}()
        for cxr in cxrs
            d[(element(cxr), shell(cxr))] =
                push!(get(d, (element(cxr), shell(cxr)), []), cxr)
        end
        x, y, label = [], [], []
        for cs in values(d)
            br = brightest(cs)
            ich = maximum(
                get(specdata[i], channel(energy(br), specs[i]), -1.0) for i in eachindex(specs)
            )
            if ich > 0
                for c in cs
                    push!(x, energy(c))
                    push!(y, ytransform(ich * weight(NormalizeToUnity, c)))
                    push!(label, weight(NormalizeToUnity, c) > 0.1 ? "$(element(c).symbol)" : "")
                end
            end
        end
        return length(x) > 0 ? layer(
            x=x,
            y=y,
            label=label,
            Geom.hair,
            Geom.point,
            Geom.label(position=:above),
            Theme(default_color=colorant"gray55"),
        ) : nothing
    end
    function edgeLayer(ashs::AbstractArray{AtomicSubShell})
        d = Dict{Any,Vector{AtomicSubShell}}()
        for ash in ashs
            d[(element(ash), shell(ash))] =
                push!(get(d, (element(ash), shell(ash)), []), ash)
        end
        x, y, label = [], [], []
        for ass in values(d)
            for ash in ass
                ee = energy(ash)
                ich = maximum(
                    get(specdata[i], channel(ee, specs[i]), 0.0) for i in eachindex(specs)
                )
                push!(x, ee)
                push!(y, ytransform(1.25 * ich))
                push!(label, "$(ash)\nedge")
            end
        end
        return length(x) > 0 ? layer(
            x=x,
            y=y,
            label=label,
            Geom.hair,
            Geom.label(position=:above),
            Theme(default_color=colorant"lightgray")
        ) : nothing
    end
    function siEscapeLayer(cxrs::AbstractVector{CharXRay}, maxE)
        x, y, label = [], [], []
        for xrs in cxrs
            eesc = energy(xrs) - energy(n"Si K-L3")
            ich = maximum(
                get(specdata[i], channel(eesc, specs[i]), 0.0) for i in eachindex(specs)
            )
            push!(x, eesc)
            push!(y, ytransform(ich))
            push!(label, "$(element(xrs).symbol)\nesc")
        end
        return length(x) > 0 ? layer(
            x=x,
            y=y,
            label=label,
            Geom.hair,
            Geom.label(position=:above),
            Theme(default_color=colorant"black"),
        ) : nothing
    end
    function siEscapeLayer(els::AbstractVector{Element}, maxE)
        cxrs = mapreduce(append!, els) do el
            mapreduce(append!, (ktransitions, ltransitions, mtransitions), init=CharXRay[]) do trs
                cx = characteristic(el, trs)
                (length(cx) > 0) && (50.0 < energy(brightest(cx)) - enx"Si K-L3" < maxE) ? [brightest(cx)] : CharXRay[]
            end
        end
        siEscapeLayer(cxrs, maxE)
    end
    function sumPeaks(cxrs)
        x, y, label = [], [], []
        for (i, xrs1) in enumerate(cxrs)
            for xrs2 in cxrs[i:end] # place each pair once...
                eesc = energy(xrs1) + energy(xrs2)
                ich = maximum(
                    get(specdata[i], channel(eesc, specs[1]), 0.0) for i in eachindex(specs)
                )
                if ich > 0.0
                    push!(x, eesc)
                    push!(y, ytransform(ich))
                    push!(label, "$(element(xrs1).symbol)\n+\n$(element(xrs2).symbol)")
                end
            end
        end
        return length(x) > 0 ? layer(
            x=x,
            y=y,
            label=label,
            Geom.hair,
            Geom.label(position=:above),
            Theme(default_color=colorant"gray"),
        ) : nothing
    end
    @assert length(specs) <= length(palette) "The palette must specify at least as many colors as spectra."
    specdata = [scaledcounts(norm, s) for s in specs]
    ylbl = repr(norm)
    maxI, maxE, maxE0 = 16, 1.0e3, 1.0e3
    names, layers = String[], Layer[]
    append!(layers, customlayers)
    if duanehunt
        if length(specs) == 1
            try
                p = _duane_hunt_impl(specs[1])
                es = (0.9*p[2]):10.0:(1.05*p[2])
                _duane_hunt_func(es, p)
                append!(layers, layer(x=es, y=_duane_hunt_func(es, p), Geom.line, Theme(default_color="black")))
            catch err
                @warn err.msg
            end
        else
            dhx, dhy = Float64[], Float64[]
            for i in eachindex(specs)
                append!(dhx, duane_hunt(specs[i]))
                append!(dhy, 0.9 * maxI * yscale)
            end
            append!(layers, layer(x=dhx, y=dhy, color=palette[eachindex(specs)], Geom.hair(orientation=:vertical), Geom.point))
        end
    end
    for (i, spec) in enumerate(specs)
        mE =
            ismissing(xmax) ? get(spec, :BeamEnergy, energy(length(spec), spec)) :
            convert(Float64, xmax)
        mE0 = get(spec, :BeamEnergy, missing)
        chs =
            max(
                1,
                channel(convert(Float64, xmin), spec),
            ):min(length(spec), channel(mE, spec))
        mchs =
            max(channel(200.0, spec), chs[1], lld(spec)):min(length(specdata[i]), chs[end])  # Ignore zero strobe...
        maxI = max(maxI, maximum(specdata[i][mchs]))
        maxE = max(maxE, mE)
        maxE0 = ismissing(mE0) ? maxE : max(maxE, mE0)
        push!(names, spec[:Name])
        ly = Gadfly.layer(
            x=energyscale(spec, chs),
            y=ytransform.(specdata[i][chs]), #
            Geom.step,
            Theme(default_color=palette[i]),
        )
        append!(layers, ly)
    end
    klm2v(klms::Material) = collect(keys(klms))
    klm2v(klms) = collect(klms)
    klms = klm2v(klms)
    autoklms && append!(klms, mapreduce(s -> elms(s, true), union!, specs))
    if length(klms) > 0
        tr(elm::Element) =
            filter(characteristic(elm, alltransitions, minklmweight, maxE0)) do cxr
                energy(cxr) > min(200.0, maxE0 / 25)
            end
        tr(mat::Material) = tr.(collect(keys(mat)))
        tr(cxr::CharXRay) = [cxr]
        pklms = mapreduce(klm -> tr(klm), append!, klms)
        if length(pklms) > 0
            l = klmLayer(specdata, pklms)
            (!isnothing(l)) && append!(layers, l)
        end
    end
    if length(edges) > 0
        shs(elm::Element) = atomicsubshells(elm, maxE0)
        shs(ash::AtomicSubShell) = [ash]
        pedges = mapreduce(ash -> shs(ash), append!, edges)
        if length(pedges) > 0
            l = edgeLayer(pedges)
            (!isnothing(l)) && append!(layers, l)
        end
    end
    if length(escapes) > 0
        l = siEscapeLayer(escapes, maxE)
        (!isnothing(l)) && append!(layers, l)
    end
    if length(coincidences) > 0
        l = sumPeaks(coincidences)
        (!isnothing(l)) && append!(layers, l)
    end
    Gadfly.with_theme(style) do
        leg =
            legend ?
            tuple(
                Guide.manual_color_key(
                    length(specs) > 1 ? "Spectra" : "Spectrum",
                    names,
                    palette[1:length(specs)],
                    pos=[0.8w, 0.0h]  # 80# over, centered
                ),
            ) : tuple()
        try
            plot(
                layers...,
                Guide.XLabel("Energy (eV)"),
                Guide.YLabel(ylbl),
                Scale.x_continuous(format=:plain),
                Scale.y_continuous(format=:plain),
                Coord.Cartesian(
                    ymin=0,
                    ymax=ytransform(yscale * maxI),
                    xmin=convert(Float64, xmin),
                    xmax=maxE,
                ),
                Guide.title(title),
                leg...,
            )
        catch
            plot(
                layers...,
                Guide.XLabel("Energy (eV)"),
                Guide.YLabel(ylbl),
                Scale.x_continuous(format=:plain),
                Scale.y_continuous(format=:plain),
                Coord.Cartesian(
                    ymin=0,
                    ymax=ytransform(yscale * maxI),
                    xmin=convert(Float64, xmin),
                    xmax=maxE,
                ),
                Guide.title(title),
                leg...,
            )
        end
    end
end


"""
    Gadfly.plot(
        ffr::FilterFitResult,
        roi::Union{Nothing,AbstractUnitRange{<:Integer}} = nothing;
        palette = NeXLPalette,
        style = NeXLSpectrumStyle,
        xmax::Union{AbstractFloat, Nothing} = nothing,
        comp::Union{Material, Nothing} = nothing,
        det::Union{EDSDetector, Nothing} = nothing,
        resp::Union{AbstractArray{<:AbstractFloat,2},Nothing} = nothing,
        yscale = 1.0
    )

Plot the sample spectrum, the residual and fit regions-of-interests and the associated k-ratios.
"""
function Gadfly.plot(
    ffr::FilterFitResult,
    roi::Union{Nothing,AbstractUnitRange{<:Integer}}=nothing;
    palette=NeXLPalette,
    style=NeXLSpectrumStyle,
    xmax::Union{AbstractFloat,Nothing}=nothing,
    comp::Union{Material,Nothing}=nothing,
    det::Union{EDSDetector,Nothing}=nothing,
    resp::Union{AbstractArray{<:AbstractFloat,2},Nothing}=nothing,
    yscale=1.0
)
    fspec = spectrum(ffr)
    function defroi(ffrr) # Compute a reasonable default display ROI
        tmp =
            minimum(
                lbl.roi[1] for lbl in keys(ffrr.kratios)
            ):maximum(lbl.roi[end] for lbl in keys(ffrr.kratios))
        return max(
            lld(fspec),
            tmp[1] - length(ffrr.roi) ÷ 40,
        ):min(tmp[end] + length(ffrr.roi) ÷ 10, ffrr.roi[end])
    end
    roilt(l1, l2) = isless(l1.roi[1], l2.roi[1])
    roi, resid = something(roi, defroi(ffr)), residual(ffr).counts
    layers = [
        layer(x=roi, y=resid[roi], Geom.step, Theme(default_color=palette[2])),
        layer(x=roi, y=ffr.raw[roi], Geom.step, Theme(default_color=palette[1])),
    ]
    # If the information is available,also model the continuum
    comp = isnothing(comp) ? get(fspec, :Composition, nothing) : comp
    det = isnothing(det) ? get(fspec, :Detector, nothing) : det
    if !any(isnothing.((comp, resp, det)))
        cc = fitcontinuum(fspec, det, resp)
        push!(layers, layer(x=roi, y=cc[roi], Geom.line, Theme(default_color=palette[2])))
    end
    scroi = min(channel(100.0, fspec), length(fspec)):roi.stop
    miny, maxy, prev, i =
        minimum(resid[scroi]), 3.0 * yscale * maximum(resid[scroi]), -1000, -1
    for lbl in sort(collect(keys(ffr.kratios)), lt=roilt)
        if NeXLUncertainties.value(ffr, lbl) > 0.0
            # This logic keeps the labels on different lines (mostly...)
            i, prev =
                (lbl.roi[1] > prev + length(roi) ÷ 10) || (i == 6) ? (0, lbl.roi[end]) :
                (i + 1, prev)
            labels = ["", name(lbl.xrays)]
            # Plot the ROI
            push!(
                layers,
                layer(
                    x=[lbl.roi[1], lbl.roi[end]],
                    y=maxy * [0.4 + 0.1 * i, 0.4 + 0.1 * i],
                    label=labels,
                    Geom.line,
                    Geom.point,
                    Geom.label(position=:right),
                    Theme(default_color="gray"),
                ),
            )
            # Plot the k-ratio as a label above ROI
            push!(
                layers,
                layer(
                    x=[0.5 * (lbl.roi[1] + lbl.roi[end])],
                    y=maxy * [0.4 + 0.1 * i],
                    label=[@sprintf("%1.4f", NeXLUncertainties.value(ffr, lbl))],
                    Geom.label(position=:above),
                    Theme(default_color="gray"),
                ),
            )
        end
    end
    Gadfly.with_theme(style) do
        plot(
            layers...,
            Coord.cartesian(
                xmin=roi[1],
                xmax=something(xmax, roi[end]),
                ymin=min(1.1 * miny, 0.0),
                ymax=maxy,
            ),
            Guide.XLabel("Channels"),
            Guide.YLabel("Counts"),
            Guide.title("$(ffr.label)"),
        )
    end
end

"""
    Gadfly.plot(fr::FilteredReference; palette = NeXLPalette))

Plot a filtered reference spectrum.
"""
function Gadfly.plot(fr::FilteredReference; palette=NeXLPalette)
    roicolors = Colorant[RGB(0.9, 1.0, 0.9), RGB(0.95, 0.95, 1.0)]
    layers = [
        layer(x=fr.ffroi, y=fr.data, Theme(default_color=palette[1]), Geom.step),
        layer(x=fr.ffroi, y=fr.filtered, Theme(default_color=palette[2]), Geom.step),
        layer(x=fr.roi, y=fr.charonly, Theme(default_color=palette[3]), Geom.step),
        layer(
            xmin=[fr.ffroi[1], fr.roi[1]],
            xmax=[fr.ffroi[end], fr.roi[end]],
            Geom.vband,
            color=roicolors,
        ),
    ]
    try
        plot(
            layers...,
            Coord.cartesian(
                xmin=fr.ffroi[1] - length(fr.ffroi) ÷ 10,
                xmax=fr.ffroi[end] + length(fr.ffroi) ÷ 10,
            ),
            Guide.xlabel("Channel"),
            Guide.ylabel("Counts"),
            Guide.title(repr(fr.label)),
            Guide.manual_color_key(
                "Legend",
                ["Spectrum", "Filtered", "Char. Only", "Filter ROC", "Base ROC"],
                [palette[1:3]..., roicolors...],
            ),
        )
    catch
        plot(
            layers...,
            Coord.cartesian(
                xmin=fr.ffroi[1] - length(fr.ffroi) ÷ 10,
                xmax=fr.ffroi[end] + length(fr.ffroi) ÷ 10,
            ),
            Guide.xlabel("Channel"),
            Guide.ylabel("Counts"),
            Guide.title(repr(fr.label)),
            #    Guide.manual_color_key("Legend",["Spectrum", "Filtered", "Char. Only", "Filter ROC", "Base ROC"], [ palette[1:3]..., roicolors...] )
        )
    end
end
"""
    plot(ff::TopHatFilter, fr::FilteredReference)

Plot a color map showing the filter data relevant to filtering the specified `FilteredReference`.
"""
Gadfly.plot(ff::TopHatFilter, fr::FilteredReference) = spy(
    filterdata(ff, fr.ffroi),
    Guide.title(repr(fr.label)),
    Guide.xlabel("Channels"),
    Guide.ylabel("Channels"),
)

"""
    Gadfly.plot(vq::VectorQuant, chs::UnitRange)

Plots the "vectors" used to quantify various elements/regions-of-interest over the range of channels specified.
"""
function Gadfly.plot(vq::VectorQuant, chs::UnitRange)
    colors = distinguishable_colors(
        size(vq.vectors, 1) + 2,
        [
            RGB(253 / 255, 253 / 255, 241 / 255),
            RGB(0, 0, 0),
            RGB(0 / 255, 168 / 255, 45 / 255),
        ],
        transform=deuteranopic,
    )[3:end]
    lyrs = mapreduce(
        i -> layer(
            x=chs,
            y=vq.vectors[i, chs],
            Theme(default_color=colors[i]),
            Geom.line,
        ),
        append!,
        eachindex(vq.references),
    )
    try
        plot(
            lyrs...,
            Guide.xlabel("Channel"),
            Guide.ylabel("Filtered"),
            Guide.manual_color_key(
                "Vector",
                [repr(r[1]) for r in vq.references],
                color=Colorant[colors...],
            ),
        )
    catch
        plot(
            lyrs...,
            Guide.xlabel("Channel"),
            Guide.ylabel("Filtered"),
            #    Guide.manual_color_key("Vector", [ repr(r[1]) for r in vq.references ], color=Colorant[colors...])
        )
    end
end

"""
    Gadfly.plot(deteffs::AbstractVector{DetectorEfficiency}; emax=20.0e3, emin=50.0, ymax = 1.0, edges::Union{Vector{AtomicSubShell}, Vector{Element}}=AtomicSubShell[])
    Gadfly.plot(deteff::DetectorEfficiency; emax=20.0e3, emin=50.0, ymax = 1.0, edges::Union{Vector{AtomicSubShell}, Vector{Element}}=AtomicSubShell[])

Plots the detector efficiency function assuming the detector is perpendicular to the incident X-rays.
"""
function Gadfly.plot(deteffs::AbstractVector{DetectorEfficiency}; emax=20.0e3, emin=50.0, ymax = 1.0, edges::Union{Vector{AtomicSubShell}, Vector{Element}}=AtomicSubShell[])
    eff(deteff, ee) = efficiency(deteff, ee, π / 2)
    layers = map(deteffs) do de 
        layer(e->eff(de, e), emin, emax, Theme(default_color=colorant"black"))
    end
    if length(edges) > 0
        shs(elm::Element) = filter(ass->energy(ass)>emin, atomicsubshells(elm, emax))
        shs(ash::AtomicSubShell) = [ash]
        x, y, label = [], [], []
        for ash in mapreduce(ash -> shs(ash), append!, edges)
            ee = energy(ash)
            push!(x, ee)
            maxdeteff = maximum(
                ( eff(deteff, ee) for deteff in deteffs )
            )
            push!(y, 1.1 * maxdeteff)
            push!(label, "$(ash)\nedge")
        end
        push!(layers, 
            layer(
                x=x,
                y=y,
                label=label,
                Geom.hair,
                Geom.label(position=:right),
                Theme(default_color=colorant"lightgray")
            )
        )
    end
    plot(layers..., 
        Coord.cartesian(xmin = emin<0.1*emax ? 0.0 : emin, xmax = emax, ymin=0.0, ymax=ymax),
        Guide.xlabel("Energy (eV)"), Guide.ylabel("Efficiency (fractional)")
    )
end
function Gadfly.plot(deteff::DetectorEfficiency; varargs...)
    plot([deteff]; varargs...)
end


function plotandimage(plot::Gadfly.Plot, image::Array)
    io = IOBuffer(maxsize=10 * 1024 * 1024)
    save(Stream(format"PNG", io), image)
    pix = max(size(image, 1), size(image, 2))
    scaleX, scaleY = size(image, 1) / pix, size(image, 2) / pix
    return compose(
        context(),
        (context(0.0, 0.0, 0.8, 1.0), Gadfly.render(plot)),
        (
            context(0.8, 0.0, 0.2, 1.0),
            bitmap(
                "image/png",
                take!(io),
                0.5 * (1.0 - scaleX),
                0.5 * (1.0 - scaleY),
                scaleX,
                scaleY,
            ),
        ),
    )
end

"""
    Gadfly.plot(ffp::FilterFitPacket; kwargs...)

Plots the reference spectra which were used to construct a `FilterFitPacket`.
"""
Gadfly.plot(ffp::FilterFitPacket; kwargs...) =
    plot(unique(spectra(ffp))...; klms=collect(elms(ffp)), kwargs...)

"""
    plot_compare(specs::AbstractArray{<:Spectrum}, mode=:Plot; xmin=100.0, xmax=1.0, palette = NeXLPalette)
   
Plots a comparison of the channel-by-channel data from each individual spectrum relative to the dose-corrected
mean of the other spectra.  Count statistics are taken into account so if the spectra agree to within count
statistics we expect a mean of 0.0 and a standard deviation of 1.0 over all channels. Note: xmax is relative
to the :BeamEnergy.
"""
function plot_compare(specs::AbstractArray{<:Spectrum}, mode=:Plot; xmin=100.0, xmax=1.0, palette=NeXLPalette)
    channels(spec) = channel(100.0, spec):channel(xmax * get(spec, :BeamEnergy, 20.0e3), spec)
    if mode == :Plot
        layers = [
            layer(x=energyscale(specs[i], channels(specs[i])), y=sigma(specs[i], specs, channels(specs[i])),
                Theme(default_color=palette[i], alphas=[0.4]))
            for i in eachindex(specs)
        ]
        plot(layers..., Guide.xlabel("Energy (eV)"), Guide.ylabel("σ"),
            Guide.manual_color_key("Spectra", [String(spec[:Name]) for spec in specs], palette[eachindex(specs)]),
            Coord.cartesian(xmin=100.0, xmax=xmax * maximum(get(spec, :BeamEnergy, 20.0e3) for spec in specs))
        )
    elseif mode == :Histogram
        layers = [
            layer(x=sigma(specs[i], specs, channels(specs[i])), Geom.histogram(),
                Theme(default_color=palette[i], alphas=[0.2]))
            for i in eachindex(specs)
        ]
        plot(layers..., Guide.xlabel("σ"), Guide.manual_color_key("Spectra", [String(spec[:Name]) for spec in specs], palette[eachindex(specs)]))
    else
        error("Unknown mode in plot_compare(...):  Not :Plot or :Histogram.")
    end
end

"""
    plot_multicompare(specs::AbstractArray{Spectrum{T}}; minE=200.0, maxE=0.5*specs[1][:BeamEnergy]) where { T<: Real}

Compare spectra collected simultaneously on multiple detectors in a single acquisition.
"""
function plot_multicompare(specs::AbstractArray{Spectrum{T}}; minE=200.0, maxE=0.5 * specs[1][:BeamEnergy]) where {T<:Real}
    s, mcs = specs[1], multicompare(specs)
    chs = max(1, channel(minE, s)):min(channel(maxE, s), length(s))
    xx = map(i -> energy(i, s), chs)
    plot(
        (layer(x=xx, y=view(mc, chs), Geom.line, Theme(default_color=c)) for (c, mc) in zip(NeXLPalette[1:length(mcs)], mcs))...,
        Guide.xlabel("Energy (eV)"), Guide.ylabel("Ratio")
    )
end


"""
    plot(wind::Union{AbstractWindow, AbstractArray{<:AbstractWindow}}; xmax=20.0e3, angle=π/2, style=NeXLSpectrumStyle)


Plot the window transmission function.
"""
function Gadfly.plot(winds::AbstractArray{<:AbstractWindow}; xmin=0.0, xmax=20.0e3, angle=π / 2, style=NeXLSpectrumStyle)
    Gadfly.with_theme(style) do
        es = max(xmin, 10.0):10.0:xmax
        lyr(w, c) = layer(x=es, y=map(e -> transmission(w, e, angle), es), Theme(default_color=c), Geom.line)
        plot(
            (lyr(w, c) for (w, c) in zip(winds, NeXLPalette[eachindex(winds)]))...,
            Coord.cartesian(
                xmin=xmin,
                xmax=xmax,
                ymin=0.0,
                ymax=1.0,
            ),
            Guide.xlabel("Energy (eV)"),
            Guide.ylabel("Transmission"),
            Guide.manual_color_key("Window", [name(w) for w in winds], NeXLPalette[eachindex(winds)])
        )
    end
end
Gadfly.plot(wind::AbstractWindow; xmin=0.0, xmax=20.0e3, angle=π / 2, style=NeXLSpectrumStyle) = #
    plot([wind], xmin=xmin, xmax=xmax, angle=angle, style=style)

"""
    Gadfly.plot(
        dfr::DirectFitResult,
        roi::Union{Nothing,AbstractUnitRange{<:Integer}} = nothing;
        palette = NeXLPalette,
        style = NeXLSpectrumStyle,
        xmax::Union{AbstractFloat, Nothing} = nothing,
        comp::Union{Material, Nothing} = nothing,
        det::Union{EDSDetector, Nothing} = nothing,
        resp::Union{AbstractArray{<:AbstractFloat,2},Nothing} = nothing,
        yscale = 1.0
    )

Plot the sample spectrum, the residual and fit regions-of-interests and the associated k-ratios.
"""
function Gadfly.plot(
    dfr::DirectFitResult,
    roi::Union{Nothing,AbstractUnitRange{<:Integer}}=nothing;
    palette=NeXLPalette,
    style=NeXLSpectrum.NeXLSpectrumStyle,
    xmax::Union{AbstractFloat,Nothing}=nothing,
    comp::Union{Material,Nothing}=nothing,
    det::Union{EDSDetector,Nothing}=nothing,
    resp::Union{AbstractArray{<:AbstractFloat,2},Nothing}=nothing,
    yscale=1.0
)
    dspec = dfr.label.spectrum
    function defroi(ddffrr) # Compute a reasonable default display ROI
        raw = ddffrr.label.spectrum.counts
        res = ddffrr.residual.counts
        mx = findlast(i -> raw[i] != res[i], eachindex(raw))
        mx = min(max(mx + mx ÷ 5, 100), length(raw))
        mn = channel(0.0, ddffrr.label.spectrum)
        return mn:mx
    end
    roilt(l1, l2) = isless(l1.roi[1], l2.roi[1])
    roi, resid = something(roi, defroi(dfr)), dfr.residual.counts
    layers = [
        layer(x=roi, y=counts(dfr.continuum, roi), Geom.step, Theme(default_color=palette[3])),
        layer(x=roi, y=resid[roi], Geom.step, Theme(default_color=palette[2])),
        layer(x=roi, y=counts(dspec, roi), Geom.step, Theme(default_color=palette[1])),
    ]
    # If the information is available,also model the continuum
    comp = isnothing(comp) ? get(dspec, :Composition, nothing) : comp
    det = isnothing(det) ? get(dspec, :Detector, nothing) : det
    if !any(isnothing.((comp, resp, det)))
        cc = fitcontinuum(dspec, det, resp)
        push!(layers, layer(x=roi, y=cc[roi], Geom.line, Theme(default_color=palette[2])))
    end
    scroi = min(channel(100.0, dspec), length(dspec)):roi.stop
    miny, maxy, prev, i =
        minimum(resid[scroi]), 3.0 * yscale * maximum(resid[scroi]), -1000, -1
    for lbl in sort(collect(keys(dfr.kratios)), lt=roilt)
        if NeXLUncertainties.value(dfr.kratios, lbl) > 0.0
            # This logic keeps the labels on different lines (mostly...)
            i, prev =
                (lbl.roi[1] > prev + length(roi) ÷ 10) || (i == 6) ? (0, lbl.roi[end]) :
                (i + 1, prev)
            labels = ["", name(lbl.xrays)]
            # Plot the ROI
            push!(
                layers,
                layer(
                    x=[lbl.roi[1], lbl.roi[end]],
                    y=maxy * [0.4 + 0.1 * i, 0.4 + 0.1 * i],
                    label=labels,
                    Geom.line,
                    Geom.point,
                    Geom.label(position=:right),
                    Theme(default_color="gray"),
                ),
            )
            # Plot the k-ratio as a label above ROI
            push!(
                layers,
                layer(
                    x=[0.5 * (lbl.roi[1] + lbl.roi[end])],
                    y=maxy * [0.4 + 0.1 * i],
                    label=[@sprintf("%1.4f", NeXLUncertainties.value(dfr, lbl))],
                    Geom.label(position=:above),
                    Theme(default_color="gray"),
                ),
            )
        end
    end
    Gadfly.with_theme(style) do
        plot(
            layers...,
            Coord.cartesian(
                xmin=roi[1],
                xmax=something(xmax, roi[end]),
                ymin=min(1.1 * miny, 0.0),
                ymax=maxy,
            ),
            Guide.XLabel("Channels"),
            Guide.YLabel("Counts"),
            Guide.title("$(dfr.label)"),
        )
    end
end

function Gadfly.plot(dr::DirectReference)
    sp = dr.label.spectrum
    bc = copy(sp.counts)
    bc[dr.roi] -= dr.data
    back = Spectrum(sp.energy, bc, copy(sp.properties))
    extroi = max(1, dr.roi.start - length(dr.roi) ÷ 3):min(length(sp), dr.roi.stop + length(dr.roi) ÷ 3)
    plot(
        layer(x=extroi, y=sp.counts[extroi], Geom.step, Theme(default_color=NeXLPalette[1])),
        layer(x=extroi, y=back.counts[extroi], Geom.step, Theme(default_color=NeXLPalette[2])),
        Guide.title("$(dr.label)"), Coord.cartesian(xmin=extroi.start, xmax=extroi.stop),
        Guide.xlabel("Channel"), Guide.ylabel("Counts")
    )
end

function Gadfly.plot(drs::DirectReferences; cols=3)
    plts = [plot(ref) for ref in drs.references]
    foreach(_ -> push!(plts, plot()), 1:((cols-length(drs.references)%cols)%cols))
    gridstack(reshape(plts, length(plts) ÷ cols, cols))
end

@info "Loading Gadfly support into NeXLSpectrum."
