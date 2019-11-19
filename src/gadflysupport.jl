using .Gadfly
using Colors
using Printf

const NeXLPalette = ( # This palette - https://flatuicolors.com/palette/nl
	RGB(234/255, 32/255, 39/255), RGB(27/255, 20/255, 100/255),
	RGB(0/255, 98/255, 102/255), RGB(87/255, 88/255, 187/255),
	RGB(11/2551, 30/255, 81/255), RGB(247/255, 159/255, 31/255),
	RGB(18/255, 137/255, 167/255), RGB(163/255, 203/255, 56/255),
	RGB(217/255, 128/255, 250/255), RGB(181/255, 52/255, 113/255),
	RGB(238/255, 90/255, 36/255), RGB(6/255, 82/255, 221/255),
	RGB(0/255, 148/255, 50/255), RGB(153/255, 128/255, 250/255),
	RGB(131/255, 52/255, 113/255), RGB(255/255, 195/255, 18/255),
	RGB(18/255, 203/255, 196/255), RGB(196/255, 229/255, 56/255),
	RGB(253/255, 167/255, 223/255), RGB(237/255, 76/255, 103/255) )

"""
    Gadfly.plot(spec::Spectrum; klms=[], xmin=0.0, xmax=nothing)::Plot

Plot a Spectrum using Gadfly.  klms is a Vector of CharXRays or Elements.
"""
Gadfly.plot( #
 	spec::Spectrum;
	klms=[],
	edges=[],
	escapes=[],
	coincidences=[],
	autoklms=false,
	xmin=0.0,
	xmax=missing,
	norm=:None,
	yscale=1.05,
	ytransform=identity
)::Plot =
	plot( #
		[spec],
		klms=klms,
		edges=edges,
		escapes=escapes,
		coincidences=coincidences,
		autoklms=autoklms,
		xmin=xmin,
		xmax=xmax,
		norm=norm,
		yscale=yscale,
		ytransform=identity)

"""
    plot(
	    specs::AbstractVector{Spectrum};
	    klms=[],
	    edges=[],
		escapes=[],
		coincidences=[],
	    autoklms = false,
	    xmin=0.0,
	    xmax=missing,
	    norm=:None,
	    yscale=1.05,
	    ytransform = identity
    )::Plot

Plot a multiple spectra on a single plot using Gadfly.

    norm = :None|:Sum|:Dose|:Peak|:DoseWidth
	klms = [ Element &| CharXRay ]
	edges = [ Element &| AtomicSubShell ]
	autoklms = false # Add KLMs based on elements in spectra
	xmin = 0.0 # Min energy (eV)
	xmax = missing # Max energy (eV) (defaults to max(:BeamEnergy))
	yscale = 1.05 # Fraction of max intensity for ymax
	ytransform = identity | log10 | sqrt | ???
"""
function Gadfly.plot(
	specs::AbstractVector{Spectrum};
	klms=[],
	edges=[],
	escapes=[],
	coincidences=[],
	autoklms = false,
	xmin=0.0,
	xmax=missing,
	norm=:None,
	yscale=1.05,
	ytransform = identity
)::Plot
	# The normalize functions return a Vector{Vector{Float64}}
	normalizeDoseWidth(specs::AbstractVector{Spectrum}, def=1.0) =
		normalizedosewidth.(specs)
	normalizeDose(specs::AbstractVector{Spectrum}, def=1.0) =
		collect( (def/dose(sp))*counts(sp, Float64, true) for sp in specs)
	normalizeSum(specs::AbstractVector{Spectrum}, total=1.0e6) =
		collect( (total/integrate(sp)) * counts(sp, Float64, true) for sp in specs)
	normalizePeak(specs::AbstractVector{Spectrum}, height=100.0) =
		collect( (height/findmax(sp)[1]) * counts(sp, Float64, true) for sp in specs)
	normalizeNone(specs::AbstractVector{Spectrum}) =
		collect( counts(sp, Float64, true) for sp in specs)
	function klmLayer(specdata, cxrs::AbstractArray{CharXRay})
	    d=Dict{Any,Array{CharXRay}}()
	    for cxr in cxrs
	        d[(element(cxr),shell(cxr))] = push!(get(d, (element(cxr), shell(cxr)), []), cxr)
	    end
	    x, y, label = [], [], []
	    for cs in values(d)
	        br=brightest(cs)
			ich = maximum(specdata[i][channel(energy(br), spec)] for (i,spec) in enumerate(specs))
	        if ich > 0
	            for c in cs
	                push!(x, energy(c))
	                push!(y, ytransform(ich*weight(c)))
					push!(label, weight(c) > 0.1 ? "$(element(c).symbol)" : "")
	            end
	        end
	    end
	    return layer(x=x, y=y, label=label, Geom.hair, Geom.point, Geom.label(position=:above), Theme(default_color="gray" ))
	end
	function edgeLayer(maxI, ashs::AbstractArray{AtomicSubShell})
		d=Dict{Any,Array{AtomicSubShell}}()
	    for ash in ashs
	        d[(element(ash),shell(ash))] = push!(get(d, (element(ash), shell(ash)), []), ash)
	    end
	    x, y, label = [], [], []
	    for ass in values(d)
	        br=ass[findmax(capacity.(ass))[2]]
            for ash in ass
                push!(x, energy(ash))
                push!(y, ytransform(maxI*capacity(ash)/capacity(br)))
                push!(label, "$(ash)")
            end
	    end
	    return layer(x=x, y=y, label=label, Geom.hair, Geom.label(position=:right), Theme(default_color="lightgray" ))
	end
	function siEscapeLayer(crxs)
		x, y, label = [], [], []
		for xrs in crxs
			eesc = energy(xrs)-energy(n"Si K-L3")
			if eesc>0.0
				ich = maximum(get(specdata[i], channel(eesc, spec), 0.0) for (i,spec) in enumerate(specs))
	 	        push!(x, eesc)
				push!(y, ytransform(ich))
				push!(label, "$(element(xrs).symbol)\nesc")
			end
		end
		return layer(x=x, y=y, label=label, Geom.hair, Geom.label(position=:above), Theme(default_color="black" ))
	end
	function sumPeaks(cxrs)
		x, y, label = [], [], []
		for (i, xrs1) in enumerate(cxrs)
			for xrs2 in cxrs[i:end] # place each pair once...
				eesc = energy(xrs1)+energy(xrs2)
				ich = maximum(get(specdata[i], channel(eesc, spec), 0.0) for (i,spec) in enumerate(specs))
				if ich>0.0
		 	        push!(x, eesc)
					push!(y, ytransform(ich))
					push!(label, "$(element(xrs1).symbol)\n+\n$(element(xrs2).symbol)")
				end
			end
		end
		return layer(x=x, y=y, label=label, Geom.hair, Geom.label(position=:above), Theme(default_color="gray" ))
	end

	if norm==:Dose
		specdata=normalizeDose(specs)
		ylbl = "Counts/(nA⋅s)"
	elseif norm==:Sum
		specdata=normalizeSum(specs)
		ylbl = "Normalized (Σ=10⁶)"
	elseif norm==:Peak
		specdata=normalizePeak(specs)
		ylbl = "Peak (%)"
	elseif norm==:DoseWidth
		specdata=normalizeDoseWidth(specs)
		ylbl = "Counts/(nA⋅s⋅eV)"
	else
		specdata=normalizeNone(specs)
		ylbl = "Counts"
	end
    maxI, maxE = 16, 1.0e3
    names, layers, colors=[], [],[]
    for (i, spec) in enumerate(specs)
		mE = ismissing(xmax) ? get(spec, :BeamEnergy, energy(length(spec), spec)) : xmax
        chs = max(1,channel(xmin,spec)):channel(mE,spec)
		mchs = max(chs.start, lld(spec)):chs.stop  # Ignore zero strobe...
        maxI = max(maxI, maximum(specdata[i][mchs]))
        maxE = max(maxE, mE)
		clr = NeXLSpectrum.NeXLPalette[(i-1) % length(NeXLSpectrum.NeXLPalette)+1]
		push!(names, spec[:Name])
		push!(colors, clr)
        push!(layers, layer(x=energyscale(spec)[chs], y=ytransform.(specdata[i][chs]), Geom.step, Theme(default_color=clr)))
    end
	maxE = ismissing(xmax) ? maxE : xmax
	append!(klms, autoklms ? mapreduce(s->NeXLSpectrum.elements(s, true, []), append!, specs) : [])
	if length(klms)>0
		tr(elm::Element) = characteristic(elm, alltransitions, 1.0e-3, maxE)
	    tr(cxr::CharXRay) = [ cxr ]
	    pklms = mapreduce(klm->tr(klm),append!,klms)
		if length(pklms)>0
			push!(layers, klmLayer(specdata,pklms))
		end
	end
	if length(edges)>0
		shs(elm::Element) = atomicsubshells(elm, maxE)
		shs(ash::AtomicSubShell) = [ ash ]
		pedges = mapreduce(ash->shs(ash), append!, edges)
		if length(pedges)>0
			push!(layers, edgeLayer(0.5*maxI,pedges))
		end
	end
	if length(escapes)>0
		push!(layers, siEscapeLayer(escapes))
	end
	if length(coincidences)>0
		push!(layers, sumPeaks(coincidences))
	end
    plot(layers...,
        Guide.XLabel("Energy (eV)"), Guide.YLabel(ylbl),
        Scale.x_continuous(format=:plain), Scale.y_continuous(format=:plain),
		Guide.manual_color_key(length(specs)>1 ? "Spectra" : "Spectrum", names, colors),
        Coord.Cartesian(ymin=0, ymax=ytransform(yscale*maxI), xmin=xmin, xmax=maxE))
end

"""
    plot(fd::FilteredData)

Plot the fitting filter and the spectrum from which it was derived.  Vertical red
lines represent the principle ROC.
"""
function Gadfly.plot(ffr::FilterFitResult, roi::Union{Missing, UnitRange{Int}}=missing)
	roilt(l1,l2) = isless(l1.roi.start,l2.roi.start)
	xx(i) = i % 4 + (i÷4)%2
	roi = ismissing(roi) ? ffr.roi : roi
	layers = [ layer(x=roi, y=ffr.raw[roi], Geom.step, Theme(default_color=NeXLPalette[1])),
	    	layer(x=roi, y=ffr.residual[roi], Geom.step, Theme(default_color=NeXLPalette[2])) ]
    mx, prev, i = 4.0*maximum(ffr.residual), -1000, -1
    for lbl in sort(labels(NeXLSpectrum.kratios(ffr)),lt=roilt)
		# This logic keeps the labels on different lines (mostly...)
        i, prev = (lbl.roi.start>prev+length(roi)÷10) || (i==4) ? ( 0, lbl.roi.stop ) : (i + 1, prev)
        labels = ["", name(lbl.xrays)]
		# Plot the ROI
		push!(layers, layer(x=[lbl.roi.start,lbl.roi.stop], y=mx*[0.5+0.1*i,0.5+0.1*i], label=labels,
                Geom.line, Geom.point, Geom.label(position=:right), Theme(default_color="gray")))
		# Plot the k-ratio as a label above ROI
		push!(layers, layer(x=[0.5*(lbl.roi.start+lbl.roi.stop)],y=mx*[0.5+0.1*i],
				label=[@sprintf("%1.4f",value(lbl,ffr))], Geom.label(position=:above), Theme(default_color="gray")))
    end
    plot(layers..., Coord.cartesian(xmin=roi.start, xmax=roi.stop, ymin=0.0, ymax=mx),
            Guide.XLabel("Channels"), Guide.YLabel("Counts"), Guide.title("$(ffr.label)"))
end
