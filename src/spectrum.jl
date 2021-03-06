
# Keeps track of the number of spectra in this session.

let spectrumIndex = 1
    global spectrumCounter() = (spectrumIndex += 1)
end

"""
    Spectrum{T<:Real} <: AbstractVector{T}

    Spectrum(energy::EnergyScale, data::Vector{<:Real}, props::Dict{Symbol,Any})

Construct a structure to hold spectrum data (energy scale, counts and metadata).

See [`NeXLSpectrum.EnergyScale`](@ref) or [`NeXLSpectrum.LinearEnergyScale`](@ref)

Example:

    julia> spec = Spectrum(LinearEnergyScale(0.0,10.0),
                     collect(1:1024),
                     Dict{Symbol,Any}(:BeamEnergy=>10.0e3, :LiveTime=>30.0))
                                                                                  ** 1024.0
                                                                           *********
                                                                   *****************
                                                            ************************
                                                     *******************************
                                              **************************************
                                       *********************************************
                                ****************************************************
                         ***********************************************************
                  ******************************************************************
           *************************************************************************
    ******************************************************************************** 10.0 keV
    Spectrum[3062][10.0 keV, Unknown, 525000.0 counts]

`Spectrum` implements indexing using various different mechanisms.  If `spec` is a `Spectrum` then

    spec[123] # will return the number of counts in channel 123
	spec[123:222] # will return a Vector of counts from channel 123:222
    spec[134.] # will return the number of counts in the channel at energy 134.0 eV
    spec[134.0:270.0] # will return a Vector of counts for channels with energies between 134.0 eV and 270.0 eV
    spec[:Comment] # will return the property named :Comment

Metadata is identified by a symbol. These Symbols are used within NeXLSpectrum.

    :BeamEnergy    # In eV
	:Elevation     # In radians
	:TakeOffAngle  # In radians (Detector position)
    :Azimuthal     # In radians (Detector position)
	:WorkingDistance # In cm
    :LiveTime      # In seconds
    :RealTime      # In seconds
    :ProbeCurrent  # In nano-amps
    :Name          # A string
    :Owner         # A string
    :StagePosition # A Dict{Symbol,Real} with entries :X, :Y, :Z, :R, :T, B: in cm and degrees
    :Comment       # A string
    :Composition   # A Material (known composition, not measured)
    :Elements      # A collection of elements in the material
    :ReferenceROIS # A collection of reference ROIs (as Vector{ReferenceROI})
    :Detector      # A Detector like a BasicEDS or another EDSDetector
    :Filename      # Source filename
    :Coating       # A Film or Film[] (eg. 10 nm of C|Au etc.)
	:AcquisitionTime # Date and time of acquisition (DateTime struct)
	:Signature     # Dict{Element,Real} with the "particle signature"

Less common items:

	:ImageMag	   # Magnification (assuming a 3.5\" image) of the first image
	:ImageZoom     # Additional zoom for second image in a two image TIFF
	:Operator      # Analyst in ASPEX TIFF files
    :Image1, :Image2 ... # Images associated with the spectrum
    :BrukerThroughtput # Nominal throughtput setting on a Bruker detector
    :DetectorSerialNumber # EDS detector serial number
    :DetectorModel # Vendor model name
    :DetectorThickness # Thickness of detector active area
    :DeadLayerThickness # Thickness of Si dead layer on the entrance surface of the detector
    :Window        # Window construction details
    :DetectorSolidAngle # Collection solid angle of the X-ray detector
    :ChamberPressure # Vacuum presure in the sample chamber
    :ChamberAtmosphere # Nominally the composition of the residual gas in the chamber

XRF related items:

    :BeamEnergy  # Accelarating voltage within X-ray tube (eV)
    :XRFTubeAnode    # Element from which the X-ray tube is constructed
    :ProbeCurrent  # Electron current in the X-ray tube
    :XRFTubeIncidentAngle # Incident angle of electron beam in tube
    :XRFTubeTakeOffAngle # Take-off angle from tube
    :XRFExcitationAngle # Angle of incidence of the X-ray beam on the sample
    :XRFDetectionAngle # Angle of the detector relative to the sample
    :XRFExcitationPathLength # Distance from X-ray source to sample
    :XRFDetectionPathLength # Distance from the sample to the X-ray detector
    :XRFSampleTilt    #  Additional tilt of the sample
    :XRFTubeWindow   # Construction of the tube window

Not all spectra will define all properties.  Algorithms can define the `NeXLCore.minproperties(ty::Type)` method to specify
which properties are required by an algorithm of `ty::Type`.  Then `hasminrequired` and `requiredbutmissing` methods
will determine whether a `Spectrum` or `Dict{Symbol,Any}` is suitable for an algorithm.
"""
struct Spectrum{T<:Real} <: AbstractVector{T}
    energy::EnergyScale
    counts::Vector{T}
    properties::Dict{Symbol,Any}
    hash::UInt  # random number (stays fixed as underlying data changes)
    function Spectrum(energy::EnergyScale, data::Vector{<:Real}, props::Dict{Symbol,Any})
        props[:Name] = get(props, :Name, "Spectrum[$(spectrumCounter())]")
        return new{typeof(data[1])}(energy, data, props, hash(energy, hash(data, hash(props))))
    end
end

Base.hash(spec::Spectrum, h::UInt) = hash(spec.hash, h)
Base.isequal(spec1::Spectrum, spec2::Spectrum) =
    (hash(spec1) == hash(spec2)) &&
    isequal(spec1.energy, spec2.energy) &&
    isequal(spec1.properies, spec2.properties) && isequal(spec1.counts, spec2.counts)
Base.isless(s1::Spectrum, s2::Spectrum) =
    isequal(s1[:Name], s2[:Name]) ? isless(s1.hash, s2.hash) : isless(s1[:Name], s2[:Name])
# Make it act like an AbstractVector
Base.eltype(spec::Spectrum) = eltype(spec.counts)
Base.length(spec::Spectrum) = length(spec.counts)
Base.ndims(spec::Spectrum) = ndims(spec.counts)
Base.size(spec::Spectrum) = size(spec.counts)
Base.size(spec::Spectrum, n) = size(spec.counts, n)
Base.axes(spec::Spectrum) = Base.axes(spec.counts)
Base.axes(spec::Spectrum, n) = Base.axes(spec.counts, n)
Base.eachindex(spec::Spectrum) = eachindex(spec.counts)
Base.stride(spec::Spectrum, k) = stride(spec.counts, k)
Base.strides(spec::Spectrum) = strides(spec.counts)
# Integer indices
Base.getindex(spec::Spectrum, idx::Integer) = spec.counts[idx]
Base.getindex(spec::Spectrum, ur::AbstractRange{<:Integer}) = spec.counts[ur]
# AbstractFloat indices
Base.getindex(spec::Spectrum, energy::AbstractFloat) = spec.counts[channel(energy, spec)]
Base.getindex(spec::Spectrum, sr::StepRangeLen{<:AbstractFloat}) = spec.counts[channel(sr[1], spec):channel(sr[end], spec)]

Base.get(spec::Spectrum, idx::Int, def = convert(eltype(spec.counts), 0)) = get(spec.counts, idx, def)
Base.setindex!(spec::Spectrum, val::Real, idx::Int) = spec.counts[idx] = convert(eltype(spec.counts), val)
Base.setindex!(spec::Spectrum, vals, ur::AbstractRange{<:Integer}) = spec.counts[ur] = vals
Base.copy(spec::Spectrum) = Spectrum(spec.energy, copy(spec.counts), copy(spec.properties))
Base.merge!(spec::Spectrum, props::Dict{Symbol,Any}) = merge!(spec.properties, props)
Base.first(spec::Spectrum) = first(spec.counts)
Base.last(spec::Spectrum) = last(spec.counts)

"""
    rangeofenergies(spec::Spectrum, ch)

Returns the low and high energy extremes for the channels `ch`.
"""
rangeofenergies(spec::Spectrum, ch) = (energy(ch, spec.energy), energy(ch + 1, spec.energy))

NeXLCore.hasminrequired(ty::Type, spec::Spectrum) = hasminrequired(ty, spec.properties)
NeXLCore.requiredbutmissing(ty::Type, spec::Spectrum) = requiredbutmissing(ty, spec.properties)

maxproperty(specs::AbstractVector{<:Spectrum}, prop::Symbol) = maximum(spec -> spec[prop], specs)
minproperty(specs::AbstractVector{<:Spectrum}, prop::Symbol) = minimum(spec -> spec[prop], specs)
sameproperty(specs::AbstractVector{<:Spectrum}, prop::Symbol) = all(spec -> spec[prop] == specs[1][prop], specs) ? #
    specs[1][prop] : #
    error("The property $prop is not equal for all these spectra.")

function Base.show(io::IO, ::MIME"text/plain", spec::Spectrum{<:Real})
    comp = haskey(spec, :Composition) ? name(spec[:Composition]) : "Unknown"
    e0 = haskey(spec, :BeamEnergy) ? "$(round(spec[:BeamEnergy]/1000.0,sigdigits=3)) keV" : "Unknown keV"
    textplot(io, spec, size = (12, 80))
    print(io, "\n$(spec[:Name])[$e0, $comp, $(round(sum(spec.counts),sigdigits=3)) counts]")
end

function textplot(io::IO, spec::Spectrum; size = (16, 80))
    (rows, cols) = size
    # how much to plot
    e0_eV = haskey(spec, :BeamEnergy) ? spec[:BeamEnergy] : energy(length(spec), spec)
    maxCh = min(channel(convert(Float64, e0_eV), spec), length(spec))
    step, max = maxCh ÷ cols, maximum(spec.counts)
    maxes = [rows * (maximum(spec.counts[(i-1)*step+1:i*step]) / max) for i = 1:cols]
    for r = 1:rows
        print(io, join(map(i -> r ≥ rows - maxes[i] ? '*' : ' ', 1:cols)))
        if r == 1
            println(io, " $(round(max,digits=0))")
        elseif r == rows
            print(io, " $(round(0.001*e0_eV,digits=2)) keV")
        else
            println(io)
        end
    end
end

textplot(spec::Spectrum; size = (16, 80)) =  textplot(stdout, spec, size=size)

"""
    NeXLUncertainties.asa(::Type{DataFrame}, spec::Spectrum; properties::Bool = false)

Converts the spectrum energy and counts data into a DataFrame.
"""
NeXLUncertainties.asa(::Type{DataFrame}, spec::Spectrum; properties::Bool = false)::DataFrame =
    properties ? DataFrame(Keys = [keys(spec.properties)...], Values = repr.([values(spec.properties)...])) : #
    DataFrame(E = energyscale(spec), I = counts(spec))

"""
    apply(spec::Spectrum, det::EDSDetector)::Spectrum

Applys the specified detector to this spectrum by ensuring that the energy scales match and spec[:Detector] = det.
Creates a copy of the original spectrum unless the detector is already det.
"""

function apply(spec::Spectrum, det::EDSDetector)::Spectrum
    if (haskey(spec, :Detector)) && (spec[:Detector] == det)
        return spec
    else
        props = copy(spec.properties)
        props[:Detector] = det
        return Spectrum(det.scale, spec.counts, props)
    end
end

"""
	matching(spec::Spectrum, resMnKa::Float64, lld::Int=1)::BasicEDS

Build an EDSDetector to match the channel count and energy scale in this spectrum.
"""
matching(spec::Spectrum, resMnKa::Float64, lld::Int = 1)::BasicEDS =
    BasicEDS(length(spec), spec.energy, MnKaResolution(resMnKa), lld)

matching(spec::Spectrum, resMnKa::Float64, lld::Int, minByFam::Dict{Shell,Element})::BasicEDS =
    BasicEDS(length(spec), spec.energy, MnKaResolution(resMnKa), lld, minByFam)

Base.get(spec::Spectrum, sym::Symbol, def::Any = missing) = get(spec.properties, sym, def)
Base.getindex(spec::Spectrum, sym::Symbol)::Any = spec.properties[sym]
Base.setindex!(spec::Spectrum, val::Any, sym::Symbol) = spec.properties[sym] = val

"""
    Base.keys(spec::Spectrum)

Return the defined properties as a set of `Symbol`s.
"""
Base.keys(spec::Spectrum) = keys(spec.properties)

"""
    Base.haskey(spec::Spectrum, sym::Symbol)

Is the specified key defined?
"""
Base.haskey(spec::Spectrum, sym::Symbol) = haskey(spec.properties, sym)

"""
    elms(spec::Spectrum, withcoating = false, def=missing)

Returns a list of the elements associated with this spectrum. `withcoating` determines whether the coating
elements are also added.
"""
function NeXLCore.elms(spec::Spectrum, withcoating = false, def = missing)
    res = Set{Element}()
    if haskey(spec, :Elements)
        append!(res, spec[:Elements])
    elseif haskey(spec, :Composition)
        union!(res, keys(spec[:Composition]))
    elseif haskey(spec, :Signature)
        union!(res, keys(spec[:Signature]))
    end
    if withcoating && haskey(spec, :Coating)
        union!(res, keys(material(spec[:Coating])))
    end
    return length(res) == 0 ? def : res
end

"""
    dose(spec::Spectrum, def=missing)
    dose(spec::Spectrum)

The probe dose in nano-amp seconds
"""
function dose(spec::Spectrum, def::Union{Float64,Missing})::Union{Float64,Missing}
    res = get(spec.properties, :LiveTime, missing) * get(spec, :ProbeCurrent, missing)
    return isequal(res, missing) ? def : res
end

function dose(spec::Spectrum)
    if haskey(spec.properties, :LiveTime) && haskey(spec.properties, :ProbeCurrent)
        return get(spec.properties, :LiveTime, missing) * get(spec, :ProbeCurrent, missing)
    else
        @error "One or more properties necessary to calculate the dose is missing.\n  You must provide both :ProbeCurrent and :LiveTime."
    end
end

NeXLCore.energy(ch::Int, spec::Spectrum)::Float64 = energy(ch, spec.energy)

"""
    channelwidth(ch::Int, spec::Spectrum)::Float64

Returns the width of the `ch` channel in eV.
"""
channelwidth(ch::Int, spec::Spectrum) = energy(ch + 1, spec) - energy(ch, spec)

channel(eV::Float64, spec::Spectrum)::Int = channel(eV, spec.energy)

"""
    counts(spec::Spectrum, numType::Type{T}, applyLLD=false)::Vector{T} where {T<:Number}
    counts(spec::Spectrum, channels::AbstractUnitRange{<:Integer}, numType::Type{T}, applyLLD=false)::Vector{T} where {T<:Number}

Creates a copy of the spectrum counts data as the specified Number type. If the spectrum has a :Detector
property then the detector's lld (low-level discriminator) and applyLLD=true then the lld is applied to the result
by setting all channels less-than-or-equal to det.lld to zero.
"""
function counts(spec::Spectrum, numType::Type{T} = Float64, applyLLD = false) where {T<:Number}
    res = map(n -> convert(numType, n), spec.counts)
    if applyLLD && haskey(spec, :Detector)
        fill!(view(res, 1:lld(spec[:Detector])), zero(numType))
    end
    return res
end

function counts(spec::Spectrum, channels::AbstractRange{<:Integer}, numType::Type{T}, applyLLD = false) where {T<:Real}
    if (first(channels) >= 1) && (last(channels)<=length(spec))
        res = map(n -> convert(numType, n), spec.counts[channels])
    else
        res = zeros(numType, length(channels))
        r = max(first(channels),1):min(last(channels), length(spec))
        res[first(r)-first(channels) + 1:last(r)-first(channels)+1] = spec.counts[r]
    end
    if applyLLD && haskey(spec, :Detector) && (lld(spec)<=first(channels))
        fill!(view(res, 1:lld(spec)-first(channels)+1), zero(numType))
    end
    return res
end

"""
    lld(spec::Spectrum)

Gets the low-level discriminator associated with this spectrum if there is one.
"""
lld(spec::Spectrum) = haskey(spec.properties, :Detector) ? lld(spec.properties[:Detector]) : 1

"""
	Base.findmax(spec::Spectrum, chs::AbstractRange{<:Integer})
    Base.findmax(spec::Spectrum)

Returns the (maximum intensity, channel index) over the specified range of channels
"""
function Base.findmax(spec::Spectrum, chs::AbstractRange{<:Integer})
    max = findmax(spec.counts[chs])
    return (max[1] + first(chs) - 1, max[2])
end
function Base.findmax(spec::Spectrum)
    last = min(haskey(spec, :BeamEnergy) ? channel(spec[:BeamEnergy], spec) : length(spec.counts), length(spec.counts))
    return findmax(spec.counts, lld(spec):last)
end


"""
    integrate(spec::Spectrum, channels::AbstractUnitRange{<:Integer})
    integrate(spec::Spectrum, energyRange::StepRangeLen{Float64})

Sums all the counts in the specified channels.  No background correction.

    integrate(spec::Spectrum, back1::AbstractUnitRange{<:Integer}, peak::AbstractUnitRange{<:Integer}, back2::AbstractUnitRange{<:Integer})::UncertainValue
    integrate(spec::Spectrum, back1::StepRangeLen{Float64}, peak::StepRangeLen{Float64}, back2::StepRangeLen{Float64})::UncertainValue

Sums all the counts in the specified channels with background correction using the background intervals.

    integrate(spec::Spectrum)

Total integral of all counts from the LLD to the beam energy

"""
integrate(spec::Spectrum, channels::AbstractUnitRange{<:Integer}) = sum(spec.counts[channels])

integrate(spec::Spectrum, energyRange::StepRangeLen{Float64}) =
    sum(spec.counts[channel(energyRange[1], spec):channel(energyRange[end], spec)])

function integrate(spec::Spectrum, back1::AbstractUnitRange{<:Integer}, peak::AbstractUnitRange{<:Integer}, back2::AbstractUnitRange{<:Integer})::UncertainValue
    bL, bH = mean(spec.counts[back1]), mean(spec.counts[back2])
    cL, cH, cP = mean(back1), mean(back2), mean(peak)
    iP, w, t = sum(spec.counts[peak]), length(peak), ((cP-cL)/(cH-cL))
    return uv(iP - w*(bL*(1.0-t)+bH*t), sqrt(iP + (sqrt(bL)*w*(1.0-t))^2 + (sqrt(bH)*w*t)^2))
end

function integrate(
    spec::Spectrum,
    back1::StepRangeLen{Float64},
    peak::StepRangeLen{Float64},
    back2::StepRangeLen{Float64},
)::UncertainValue
    b1i = channel(back1[1], spec):channel(back1[end], spec)
    b2i = channel(back2[1], spec):channel(back2[end], spec)
    pi = channel(peak[1], spec):channel(peak[end], spec)
    integrate(spec, b1i, pi, b2i)
end

function integrate(spec::Spectrum)
    last = min(haskey(spec, :BeamEnergy) ? channel(spec[:BeamEnergy], spec) : length(spec.counts), length(spec.counts))
    return integrate(spec, lld(spec):last)
end

"""
    kratio(unk::Spectrum, std::Spectrum, back1::AbstractUnitRange{<:Integer}, peak::AbstractUnitRange{<:Integer}, back2::AbstractUnitRange{<:Integer})::UncertainValue
    kratio(unk::Spectrum, std::Spectrum, back1::StepRangeLen{Float64}, peak::StepRangeLen{Float64}, back2::StepRangeLen{Float64})::UncertainValue

The k-ratio of unk relative to std corrected for dose.  Requires that `unk` and `std` have the properties
`:LiveTime` and `:ProbeCurrent` defined.
"""
function kratio(unk::Spectrum, std::Spectrum, back1::AbstractUnitRange{<:Integer}, peak::AbstractUnitRange{<:Integer}, back2::AbstractUnitRange{<:Integer})
    iunk, istd = integrate(unk, back1, peak, back2)/dose(unk), integrate(std, back1, peak, back2)/dose(std)
    f=NeXLUncertainties.value(iunk)/NeXLUncertainties.value(istd)
    return uv(f, abs(f)*sqrt((σ(iunk)/NeXLUncertainties.value(iunk))^2+(σ(istd)/NeXLUncertainties.value(istd))^2))
end

kratio(unk::Spectrum, std::Spectrum, back1::StepRangeLen, peak::StepRangeLen, back2::StepRangeLen) =
    kratio(unk, std, #
        channel(back1[1], unk):channel(back1[end], unk), #
        channel(peak[1], unk):channel(peak[end], unk), #
        channel(back2[1], unk):channel(back2[end], unk))


"""
    energyscale(spec::Spectrum)

Returns an array with the bin-by-bin energies
"""
energyscale(spec::Spectrum) = energyscale(spec.energy, eachindex(spec))

"""
    simpleEDS(spec::Spectrum, fwhmatmnka::Float64)

Build a `EDSDetector` object for this spectrum with the specified FWHM at Mn Kα.
"""
simpleEDS(spec::Spectrum, fwhmatmnka::Float64) = BasicEDS(length(spec), spec.energy, MnKaResolution(fwhmatmnka))


"""
    subsample(spec::Spectrum, frac::Float64)

Subsample the counts data in a spectrum according to a statistically valid algorithm.  Returns
`spec` if frac>=1.0.
"""
function subsample(spec::Spectrum, frac::Float64)::Spectrum
    @assert frac > 0.0 "frac must be larger than zero."
    @assert frac <= 1.0 "frac must be less than or equal to 1.0."
    @assert haskey(spec, :LiveTime) "Please specify a :LiveTime in subsample"
    ss(n, f) = n > 0 ? sum(rand() <= f ? 1 : 0 for _ = 1:n) : 0
    frac = max(0.0, min(frac, 1.0))
    if frac < 1.0
        props = deepcopy(spec.properties)
        props[:LiveTime] = frac * spec[:LiveTime] # Must have
        if haskey(spec, :RealTime)
            props[:RealTime] = frac * spec[:RealTime] # Might have
        end
        return Spectrum(spec.energy, map(n -> ss(floor(Int, n), frac), spec.counts), props)
    else
        @warn "Not actually subsampling the spectrum because $frac > 1.0."
        return spec
    end
end
"""
    subdivide(spec::Spectrum, n::Int)::Vector{Spectrum}

Splits the event data in one spectrum into n spectra by assigning each event
to a pseudo-random choice of one of the n result spectra.  Produces n spectra
that act as though the original spectrum was collected in n time intervals
of LiveTime/n.  This is quite slow because it needs to call rand() for each
count in the spectrum (not just each channel).
"""
function subdivide(spec::Spectrum, n::Int)::Vector{Spectrum}
    res = zeros(Int, n, length(spec.counts))
    for ch in eachindex(spec.counts)
        # Assign each event to one and only one detector
        si = rand(1:n, floor(Int, spec[ch]))
        for i in 1:n
            res[i, ch] = count(e -> e == i, si)
        end
    end
    specs = Spectrum[]
    for i in 1:n
        props = deepcopy(spec.properties)
        props[:Name] = "Sub[$(spec[:Name]),$(i) of $(n)]"
        props[:LiveTime] = spec[:LiveTime] / n # Must have
        if haskey(spec, :RealTime)
            props[:RealTime] = spec[:RealTime] / n # Might have
        end
        push!(specs, Spectrum(spec.energy, res[i, :], props))
    end
    return specs
end


"""
    estimatebackground(data::AbstractArray{Float64}, channel::Int, width::Int=5, order::Int=2)

Returns the tangent to the a quadratic fit to the counts data centered at channel with width
"""
function estimatebackground(data::AbstractArray{Float64}, channel::Int, width::Int = 5, order::Int = 2)::ImmutablePolynomial
    minCh, maxCh = max(1, channel - width), min(length(data), channel + width)
    if maxCh - minCh >= order
        fr = fit(ImmutablePolynomial, (minCh-channel):(maxCh-channel), data[minCh:maxCh], order)
        return ImmutablePolynomial([fr(0), derivative(fr)(0)]) # Linear
    else
        return ImmutablePolynomial([mean(data[minCh:maxCh]), 0.0])
    end
end

"""
    modelBackground(spec::Spectrum, chs::AbstractUnitRange{<:Integer}, ash::AtomicSubShell)

spec: A spectrum containing a peak centered on chs
chs:  A range of channels containing a peak
ash:  The edge (as an AtomicSubShell)

A simple model for modeling the background under a characteristic x-ray peak. The model
fits a line to low and high energy background regions around firsr(chs) and last(chs). If
the low energy line extended out to the edge energy is larger than the high energy line
at the same energy, then a negative going edge is fit between the two. Otherwise a line
is fit between the low energy side and the high energy side. This model only works when
there are no peak interference over the range chs.


    modelBackground(spec::Spectrum, chs::AbstractUnitRange{<:Integer})
    modelBackground(spec::Spectrum, chs::AbstractUnitRange{<:Integer}, ash::AtomicSubShell)

`spec`: A spectrum containing a peak centered on chs
`chs`:  A range of channels containing a peak
`ash`:  The largest edge within the range of channels `chs` associated with the characteristic peak

A simple model for modeling the background under a characteristic x-ray peak. The model
fits a line between the  low and high energy background regions around first(chs) and last(chs).
This model only works when there are no peak interference over the range chs.
"""
function modelBackground(spec::Spectrum, chs::AbstractUnitRange{<:Integer}, ash::AtomicSubShell)
    cnts, ec = counts(spec), channel(energy(ash), spec)
    bl, bh = estimatebackground(cnts, first(chs), 5), estimatebackground(cnts, last(chs), 5)
    # bh = ch-> mean(cnts[last(chs):min(length(cnts),last(chs)+5)])
    if (ec < last(chs)) && (bl(ec - first(chs)) > bh(ec - last(chs))) && (energy(ash) < 2.0e3)
        res = zeros(Float64, length(chs))
        res[1:ec-first(chs)] .= ( bl(y-1) for y in 1:ec-first(chs) )
        res[ec-first(chs)+1] = 0.5*(bl(ec-first(chs)+1)+bh(ec-last(chs)))
        res[ec-first(chs)+2:last(chs)-first(chs)+1] .= ( bh(y-last(chs)) for y in ec+1:last(chs))
    else
        s = (bh(0) - bl(0)) / length(chs)
        back = ImmutablePolynomial([bl(0), s])
        res = back.(collect(0:length(chs)-1))
    end
    return res
end

function modelBackground(spec::Spectrum, chs::AbstractUnitRange{<:Integer})
    cxs = counts(spec)
    bl = estimatebackground(cxs, first(chs), 5)
    bh = estimatebackground(cxs, last(chs), 5)
    s = (bh(0) - bl(0)) / length(chs)
    back = ImmutablePolynomial([bl(0), s])
    return back.(collect(0:length(chs)-1))
end

"""
    extractcharacteristic(spec::Spectrum, lowBack::AbstractUnitRange{<:Integer}, highBack::AbstractUnitRange{<:Integer})::Vector{Float64}

Extract the characteristic intensity for the peak located within chs with an edge at ash.
"""
function extractcharacteristic(spec::Spectrum, chs::AbstractUnitRange{<:Integer}, ash::AtomicSubShell)::Vector{Float64}
    return counts(spec, chs, Float64) - modelBackground(spec, chs, ash)
end


"""
    peak(spec::Spectrum, chs::AbstractUnitRange{<:Integer}, ash::AtomicSubShell)::Float64

Estimates the peak intensity for the characteristic X-ray in the specified range of channels.
"""
peak(spec::Spectrum, chs::AbstractUnitRange{<:Integer})::Float64 = return sum(counts(spec, chs, Float64)) - background(spec, chs)

"""
    background(spec::Spectrum, chs::AbstractUnitRange{<:Integer}, ash::AtomicSubShell)::Float64

Estimates the background intensity for the characteristic X-ray in the specified range of channels.
"""
background(spec::Spectrum, chs::AbstractUnitRange{<:Integer})::Float64 = sum(modelBackground(spec, chs))


"""
    peaktobackground(spec::Spectrum, chs::AbstractUnitRange{<:Integer}, ash::AtomicSubShell)::Float64

Estimates the peak-to-background ratio for the characteristic X-ray intensity in the specified range of channels
which encompass the specified AtomicSubShell.
"""
function peaktobackground(spec::Spectrum, chs::AbstractUnitRange{<:Integer}, ash::AtomicSubShell)::Float64
    back = sum(modelBackground(spec, chs, ash))
    return (sum(counts(spec, chs, Float64)) - back) / back
end

"""
    estkratio(unk::Spectrum, std::Spectrum, chs::AbstractUnitRange{<:Integer})

Estimates the k-ratio from niave models of peak and background intensity.  Only works if the peak is not interfered.
"""
estkratio(unk::Spectrum, std::Spectrum, chs::AbstractUnitRange{<:Integer}) = peak(unk, chs) * dose(std) / (peak(std, chs) * dose(unk))


"""
    NeXLUncertainties.asa(::Type{DataFrame}, spec::AbstractVector{Spectrum})::DataFrame

Returns a DataFrame that summarizes the list of spectra.
"""
function NeXLUncertainties.asa(::Type{DataFrame}, specs::AbstractVector{Spectrum})::DataFrame
    _asname(comp) = ismissing(comp) ? missing : name(comp)
    unf, unl, uns = Union{Float64,Missing}, Union{Film,Nothing}, Union{String,Missing}
    nme, e0, pc, lt, rt, coat, integ, comp = String[], unf[], unf[], unf[], unf[], unl[], Float64[], uns[]
    for spec in specs
        push!(nme, spec[:Name])
        push!(e0, get(spec, :BeamEnergy, missing))
        push!(pc, get(spec, :ProbeCurrent, missing))
        push!(lt, get(spec, :LiveTime, missing))
        push!(rt, get(spec, :RealTime, missing))
        push!(coat, get(spec, :Coating, nothing))
        push!(integ, integrate(spec))
        push!(comp, _asname(get(spec, :Composition, missing)))
    end
    return DataFrame(
        Name = nme,
        BeamEnergy = e0,
        ProbeCurrent = pc,
        LiveTime = lt,
        RealTime = rt,
        Coating = coat,
        Integral = integ,
        Material = comp,
    )
end

"""
    NeXLUncertainties.asa(::Type{DataFrame}, spec::AbstractDict{Element, Spectrum})::DataFrame

Returns a DataFrame that summarizes a dictionary of standard spectra.
"""
function NeXLUncertainties.asa(::Type{DataFrame}, stds::AbstractDict{Element,Spectrum})::DataFrame
    _asname(comp) = ismissing(comp) ? missing : name(comp)
    unf, unl, uns = Union{Float64,Missing}, Union{Film,Nothing}, Union{String,Missing}
    elm, zs, mfs, nme, e0, pc, lt, rt, coat, integ, comp =
        String[], Int[], Float64[], String[], unf[], unf[], unf[], unf[], unl[], Float64[], uns[]
    for el in sort(collect(keys(stds)))
        spec = stds[el]
        push!(elm, el.symbol)
        push!(zs, el.number)
        push!(nme, spec[:Name])
        push!(mfs, ismissing(spec[:Composition]) ? missing : spec[:Composition][el])
        push!(e0, get(spec, :BeamEnergy, missing))
        push!(pc, get(spec, :ProbeCurrent, missing))
        push!(lt, get(spec, :LiveTime, missing))
        push!(rt, get(spec, :RealTime, missing))
        push!(coat, get(spec, :Coating, nothing))
        push!(integ, integrate(spec))
        push!(comp, _asname(get(spec, :Composition, missing)))
    end
    return DataFrame(
        Element = elm,
        Z = zs,
        Name = nme,
        Material = comp,
        MassFrac = mfs,
        BeamEnergy = e0,
        ProbeCurrent = pc,
        LiveTime = lt,
        RealTime = rt,
        Coating = coat,
        Integral = integ,
    )
end

"""
    details(io, spec::Spectrum)
    details(spec::Spectrum)

Outputs a description of the data in the spectrum.
"""
function details(io::IO, spec::Spectrum)
    println(io, "           Name:   $(spec[:Name])")
    println(io, "    Beam energy:   $(get(spec, :BeamEnergy, missing)/1000.0) keV")
    println(io, "  Probe current:   $(get(spec, :ProbeCurrent, missing)) nA")
    println(io, "      Live time:   $(get(spec, :LiveTime, missing)) s")
    println(io, "        Coating:   $(get(spec,:Coating, "None"))")
    println(io, "       Detector:   $(get(spec, :Detector, missing))")
    println(io, "        Comment:   $(get(spec, :Comment, missing))")
    println(io, "       Integral:   $(integrate(spec)) counts")
    comp = get(spec, :Composition, missing)
    if !ismissing(comp)
        println(io, "    Composition:   $(comp)")
        det = get(spec, :Detector, missing)
        if !ismissing(det)
            coating = get(spec, :Coating, missing)
            comp2 = collect(keys(comp))
            if !ismissing(coating)
                append!(comp2, keys(coating.material))
            end
            for elm1 in keys(comp)
                for ext1 in extents(elm1, det, 1.0e-4)
                    print(io, "            ROI:   $(elm1.symbol)[$(ext1)]")
                    intersects = []
                    for elm2 in comp2
                        if elm2 ≠ elm1
                            for ext2 in extents(elm2, det, 1.0e-4)
                                if length(intersect(ext1, ext2)) > 0
                                    push!(intersects, "$(elm2.symbol)[$(ext2)]")
                                end
                            end
                        end
                    end
                    if length(intersects) > 0
                        println(io, " intersects $(join(intersects,", "))")
                    else
                        p, b = peak(spec, ext1), background(spec, ext1)
                        σ = p / sqrt(b)
                        println(io, " = $(round(Int,p)) counts over $(round(Int,b)) counts - σ = $(round(Int,σ))")
                    end
                end
            end
        end
    end
    return nothing
end

details(spec::Spectrum) = details(stdout, spec)

"""
    commonproperties(specs::AbstractArray{Spectrum})
    commonproperties(props1::Dict{Symbol,Any}, props2::Dict{Symbol,Any})

Return the properties that are held in common by all the spectra.
"""
function commonproperties(props1::Dict{Symbol,Any}, props2::Dict{Symbol,Any})
    res = Dict{Symbol,Any}()
    for (key, sp1) in props1
        if isequal(sp1, get(props2, key, missing))
            res[key] = sp1
        end
    end
    return res
end

function commonproperties(specs::AbstractArray{<:Spectrum})
    props = specs[1].properties
    for sp2 in specs[2:end]
        props = commonproperties(props, sp2.properties)
    end
    return props
end

"""
    maxspectrum(specs::AbstractArray{Spectrum{T}})::Spectrum{T} where T<:Real

Compute the max-pixel spectrum for the specified spectra.
"""
function maxspectrum(specs::AbstractArray{Spectrum{T}})::Spectrum{T} where T<:Real
    res = zeros(T, maximum(length.(specs)))
    for spec in specs
        for i in eachindex(spec)
            res[i] = max(res[i], spec[i])
        end
    end
    props = commonproperties(specs)
    props[:Name] = "MaxSpectrum[$(length(specs)) spectra]"
    return Spectrum(spec1.energy, res, props)
end

"""
    minspectrum(specs::AbstractArray{Spectrum{T}})::Spectrum{T} where T<:Real

Compute the min-pixel spectrum for the specified spectra.
"""
function minspectrum(specs::AbstractArray{Spectrum{T}})::Spectrum{T} where T<:Real
    res = zeros(T, maximum(length.(specs)))
    fill!(res, typemax(T))
    for spec in specs
        for i in eachindex(spec)
            res[i] = min(res[i], spec[i])
        end
    end
    props = commonproperties(specs)
    props[:Name] = "MinSpectrum[$(length(specs)) spectra]"
    return Spectrum(spec1.energy, res, props)
end


"""
    Base.sum(specs::AbstractVector{Spectrum{T}}; restype::Type{<:Real}=Tapplylld=false)::Spectrum{T}

Computes the sum spectrum over an `AbstractVector{Spectrum}` where the :ProbeCurrent and :LiveTime will be maintained
in a way that maintains the sum of the individual doses.  This function assumes (but does not check) that the energy
scales are equivalent for all the spectra.  The resultant energy scale is the scale of the first spectrum.  Other than
:ProbeCurrent, :LiveTime and :RealTime, only the properties that the spectra hold in common will be maintained.
"""
function Base.sum(specs::AbstractVector{Spectrum{T}}, restype::Type{<:Real}=T; applylld=false)::Spectrum where T <: Real
    props = commonproperties(specs)
    cxs, ds, pc, rt = zeros(restype, maximum(length.(specs))), 0.0, 0.0, 0.0
    for spec in specs
        cxs .+= counts(spec, eachindex(cxs), restype, applylld)
        ds += dose(spec)
        pc += spec[:ProbeCurrent]
        rt += get(spec, :RealTime, NaN64)
    end
    pc /= length(specs)
    props[:ProbeCurrent] = pc
    props[:LiveTime] = ds / pc
    if !isnan(rt)
        props[:RealTime] = rt
    end
    props[:Name] = "Sum[$(length(specs)) spectra]"
    return Spectrum(specs[1].energy, cxs, props)
end

"""
    measure_dissimilarity(specs::AbstractVector{Spectrum)::Vector{Float64}

Returns a vector of χ²s which measure how different the i-th `Spectrum` is from the other spectra.
"""
function measure_dissimilarity(specs::AbstractVector{Spectrum{T}})::Vector{Float64} where T <: Real
    function χ2(sp,m)
        m1(v) = max(v, oneunit(v))
        cxs = counts(sp, eachindex(m), Float64, true)
        return sum( ((cxs / dose(sp) .- m) ./ (sqrt.(m1.(cxs))/dose(sp))).^2 )/(length(sp)-1)
    end
    χ2s = zeros(Float64,length(specs))
    for (i, rmspec) in enumerate(specs)
        # Remove one spectrum
        others = filter(s->s!=rmspec, specs)
        # Compute the mean counts/(nA⋅s)
        mcpnas = zeros(Float64, maximum(length.(others)))
        for spec in others
            mcpnas .+= counts(spec, eachindex(mcpnas), Float64, true) / dose(spec) # counts/(nA⋅s)
        end
        mcpnas /= length(others) # mean counts/(nA⋅s)
        # Compute how different this spectrum is from the others
        χ2s[i] = χ2(rmspec, mcpnas)
    end
    return χ2s
end

"""
    findsimilar(specs::AbstractVector{Spectrum{T}}; tol = 1.8, minspecs=3)::Vector{Spectrum{T}}

Filters a collection of spectra for the ones most similar to the average by
removing the least similar spectrum sequentially until all the remaining spectra are within
tol times the mean(χ²).  This is useful for finding which of a set of replicate spectra are
sufficiently similar to each other.
"""
function findsimilar(specs::AbstractVector{Spectrum{T}}; tol = 1.8, minspecs=3)::Vector{Spectrum{T}} where T <: Real
    if length(specs) > minspecs
        σs = measure_dissimilarity(specs)
        ( fmσ, fmi ) = findmax(σs)
        rem = filter(σ -> σ ≠ fmσ, σs)
        # Now perform this recursively until all are within tol or we hit minspecs
        if fmσ > tol*Statistics.mean(rem)
            return findsimilar(filter(s -> s != specs[fmi], specs), tol=tol, minspecs=minspecs)
        end
    end
    return specs
end
