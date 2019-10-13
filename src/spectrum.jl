using Polynomials
using DataFrames
using PeriodicTable

# Keeps track of the number of spectra in this session.

let spectrumIndex = 1
    global spectrumCounter() = (spectrumIndex += 1)
end;

"""
    Spectrum
A structure to hold spectrum data (energy scale, counts and metadata).
Metadata is identified by a symbol. Predefined symbols include
    :BeamEnergy    # In eV
    :Elevation     # In degrees
    :LiveTime      # In seconds
    :RealTime      # In seconds
    :ProbeCurrent  # In nano-amps
    :Name          # A string
    :Owner         # A string
    :StagePosition # A Dict with entries :X, :Y, :Z, :R, :TX in millimeters and degrees
    :Comment       # A string
    :Composition   # A Material
    :Detector      # A Detector like a SimpleEDS
    :Filename      # Source filename
    :Coating       # A Film (eg. 10 nm of C|Au etc.)

Not all spectra will define all properties.
If spec is a Spectrum then
    spec[123] # will return the number of counts in channel 123
    spec[134.] # will return the number of counts in the channel at energy 134.0 eV
    spec[:Comment] # will return the property comment
"""
struct Spectrum
    energy::EnergyScale
    counts::Array{<:Real}
    properties::Dict{Symbol,Any}
    function Spectrum(energy::EnergyScale, data::Array{<:Real},props::Dict{Symbol,Any})
        props[:Name] = get(props, :Name, "Spectrum[$(spectrumCounter())]")
        return new(energy, data, props)
    end
end

function Base.show(io::IO, spec::Spectrum)
    print(io, "Spectrum[")
    print(io, "name = ",get(spec, :Name, "None"),", ")
    println(io, "owner = ",get(spec, :Owner, "Unknown"))
    cols, rows = 80, 16
    # how much to plot
    e0_eV = haskey(spec,:BeamEnergy) ?
        e0_eV=spec.properties[:BeamEnergy] :
        energy(length(spec), spec)
    maxCh = min(channel(e0_eV, spec),length(spec))
    step = maxCh ÷ cols
    max = maximum(spec.counts)
    maxes = fill(0.0,cols)
    for i in 1:cols
        maxes[i] = rows*(maximum(spec.counts[(i-1)*step+1:i*step])/max)
    end
    for r in 1:rows
        ss=""
        for i in 1:cols
            ss = ss * (r ≥ rows - maxes[i] ? "*" : " ")
        end
        if r==1
            println(io, ss, " ", max)
        elseif r==rows
            println(io, ss," ",0.001*get(spec,:BeamEnergy,-1.0)," keV]")
        else
            println(io, ss)
        end
    end
end

"""
    tabulate(spec::Spectrum)

Converts the spectrum energy and counts data into a table.
"""
tabulate(spec::Spectrum)::DataFrame =
    DataFrame(E=energyscale(spec),I=counts(spec))

function split_emsa_header_item(line::AbstractString)
    p = findfirst(":",line)
    if p ≠ nothing
        tmp = uppercase(strip(SubString(line,2:p.start-1)))
        pp = findfirst("-",tmp)
        if pp ≠ nothing
            key, mod = strip(SubString(tmp,0::pp.start-1)), strip(SubString(tmp,pp.start+1))
        else
            key, mod = tmp, nothing
        end
        value = strip(SubString(line,p.stop+1))
        # println(key," = ",value)
        return (key, value, mod)
    else
        return nothing
    end
end

function parsed2stdcmp(value::AbstractString)::Material
	try
		sp=split(value,",")
		name=sp[1]
		mf = Dict{Element,Float64}()
		den = missing
		for item in sp[2:end]
			if item[1]=='(' && item[end]==')'
				sp2=split(item[2:end-1],":")
				mf[element(sp2[1])]=parse(Float64,sp2[2])
			else
				den = parse(Float64,item)
			end
		end
		return material(name, mf, den)
	catch err
		warn("Error parsing composition $(value) - $(err)")
	end
end

function parsecoating(value::AbstractString)::Union{Film,Missing}
    i=findfirst(value," nm of ")
	if !ismissing(i)
		try
			thk = parse(Float64,value[1:i])*1.0e-7 // cm
			mat = parse2stdcmp(Material, value[i+7:end])
			return Film(mat,thickness)
		catch err
			warn("Error parsing $(value) as a coating $(value)")
		end
	end
    return missing
end

"""
    readEMSA(filename::AbstractString)::Union{Spectrum,Nothing}

Read an ISO/EMSA format spectrum from a disk file at the specified path.
"""
function readEMSA(filename::AbstractString)::Union{Spectrum,Nothing}
    open(filename,"r") do f
        energy, counts = LinearEnergyScale(0.0,10.0), Float64[]
        props = Dict{Symbol,Any}()
        props[:Filename]=filename
        inData, lx = 0, 0
        stgpos = Dict{Symbol,Float64}()
        for line in eachline(f)
            lx+=1
            if (lx ≤ 2)
                res = split_emsa_header_item(line)
                if (res==nothing) || ((lx==1) && (res[1]!="FORMAT" || uppercase(res[2])!="EMSA/MAS SPECTRAL DATA FILE"))
                    return nothing
                end
                if (res==nothing) || ((lx==2) && (res[1]!="VERSION" || res[2]!="1.0"))
                    return nothing
                end
            elseif inData>0
                if startswith(line, "#ENDOFDATA")
                    break
                else
                    for cc in split(line, ",")
                        num = match(r"[-+]?[0-9]*\.?[0-9]+", cc)
                        if num ≠ nothing
                            append!(counts, floor(Int, parse(Float64, num.match)))
                        end
                        inData=inData+1
                    end
                end
            elseif startswith(line,"#")
                res = split_emsa_header_item(line)
                if res ≠ nothing
                    key, value = res
                    if key == "SPECTRUM"
                        inData = 1
                    elseif key == "BEAMKV"
                        props[:BeamEnergy]=1000.0*parse(Float64,value) # in eV
                    elseif key == "XPERCHAN"
                        energy = LinearEnergyScale(energy.offset, parse(Float64,value))
                    elseif key == "LIVETIME"
                        props[:LiveTime]=parse(Float64,value)
                    elseif key == "REALTIME"
                        props[:RealTime]=parse(Float64,value)
                    elseif key == "PROBECUR"
                        props[:ProbeCurrent]=parse(Float64,value)
                    elseif key == "OFFSET"
                        energy = LinearEnergyScale(parse(Float64,value), energy.width)
                    elseif key == "TITLE"
                        props[:Name]=value
                    elseif key == "OWNER"
                        props[:Owner]=value
                    elseif key == "ELEVANGLE"
                        props[:Elevation] = parse(Float64, value)
                    elseif key == "XPOSITION"
                        stgpos[:X] = parse(Float64, value)
                    elseif key == "YPOSITION"
                        stgpos[:Y] = parse(Float64, value)
                    elseif key == "ZPOSITION"
                        stgpos[:Z] = parse(Float64, value)
                    elseif key == "COMMENT"
                        prev = getindex(props,:Comment,missing)
                        props[:Comment] = prev ≠ missing ? prev*"\n"*value : value
                    elseif key== "#D2STDCMP"
                        props[:Composition] = parsed2stdcmp(value)
                    elseif key== "#CONDCOATING"
                        props[:Coating] = parsecoating(value)
                    end
                end
            end
        end
        if startswith( props[:Name], "Bruker Nano")
            if haskey(props, :Composition)
                props[:Name]=name(props[:Composition])
            else
                props[:Name]=basename(filename[1:end-4])
            end
        end
        props[:StagePosition] = stgpos
        return Spectrum(energy, counts, props)
    end
end

setproperty!(spec::Spectrum, sym::Symbol, val) = setindex!(props,sym,val)

Base.get(spec::Spectrum, sym::Symbol, def) = get(spec.properties,sym,def)

Base.getindex(spec::Spectrum,sym::Symbol) = spec.properties[sym]

Base.getindex(spec::Spectrum,idx) = spec.counts[idx]

Base.setindex!(spec::Spectrum, val, sym::Symbol) =
    spec.properties[sym] = val

Base.setindex!(spec::Spectrum, val::Real, idx::Int) =
    spec.counts[idx] = convert(typeof(spec.counts[1]), val)

Base.haskey(spec::Spectrum, sym::Symbol) = haskey(spec.properties,sym)


"""
    dose(spec::Spectrum, def=missing)

The probe dose in nano-amp seconds
"""
function dose(spec::Spectrum, def=missing)::Union{Float64,Missing}
    res = get(spec.properties,:RealTime, missing)*get(spec,:ProbeCurrent, missing)
    return isequal(res,missing) ? def : res
end

"""
    length(spec::Spectrum)

The length of a spectrum is the number of channels.
"""
Base.length(spec::Spectrum) = size(spec.counts)[1]

"""
    NeXLCore.energy(ch::Int, spec::Spectrum)

The energy of the start of the ch-th channel.
"""
NeXLCore.energy(ch::Int, spec::Spectrum)::Float64 = energy(ch, spec.energy)

"""
    channel(eV::Float64, spec::Spectrum)

The index of the channel containing the specified energy.
"""
channel(eV::Float64, spec::Spectrum)::Int = channel(eV, spec.energy)

"""
    counts(spec::Spectrum, numType::Type{T})::Vector{T} where {T<:Number}

Creates a copy of the spectrum counts data as the specified Number type.
"""
counts(spec::Spectrum, numType::Type{T}=Float64) where {T<:Number} = map(n->convert(numType,n), spec.counts)

"""
    counts(spec::Spectrum, channels::UnitRange{Int}, numType::Type{T})::Vector{T} where {T<:Number}

Creates a copy of the spectrum counts data as the specified Number type.
"""
counts(spec::Spectrum, channels::UnitRange{Int}, numType::Type{T}) where {T<:Real} =
    map(n->convert(numType,n), spec.counts[channels])

"""
   integrate(spec, channels)

Sums all the counts in the specified channels.  No background correction.
"""
integrate(spec::Spectrum, channels::UnitRange{Int}) = sum(spec.counts[channels])

"""
   integrate(spec, channels)

Sums all the counts in the specified energy range.  No background correction.
"""
integrate(spec::Spectrum, energyRange::StepRangeLen{Float64}) =
    sum(spec.counts[channel(energyRange[1],spec):channel(energyRange[end],spec)])

"""
    integrate(spec::Spectrum, back1::UnitRange{Int}, peak::UnitRange{Int}, back2::UnitRange{Int})::Float64
Perform a background corrected peak integration using channel ranges. Fits a line to each background region and
extrapolates the background from the closest background channel through the peak region.
"""
function integrate(spec::Spectrum, back1::UnitRange{Int}, peak::UnitRange{Int}, back2::UnitRange{Int})::Float64
    p1=polyfit(back1, spec.counts[back1], 1)
    p2=polyfit(back2, spec.counts[back2], 1)
    c1, c2 = back1.stop, back2.start
    i1, i2 = p1(c1), p2(c2)
    m = (i2-i1)/(c2-c1)
    back = Poly([i1-m*c1, m])
    sum(spec.counts[peak]-map(back,peak))
end

"""
    integrate(spec::Spectrum, back1::StepRangeLen{Float64}, peak::StepRangeLen{Float64}, back2::StepRangeLen{Float64})::Float64
Perform a background corrected peak integration using energy (eV) ranges. Converts the energy ranges to channels
ranges before performing the integral.
"""
function integrate(spec::Spectrum, back1::StepRangeLen{Float64}, peak::StepRangeLen{Float64}, back2::StepRangeLen{Float64})::Float64
    b1i = channel(back1[back1.offset],spec):channel(back1[end],spec)
    b2i = channel(back2[back2.offset],spec):channel(back2[end],spec)
    pi = channel(peak[peak.offset],spec):channel(peak[end],spec)
    integrate(spec, b1i, pi, b2i)
end

"""
    energyscale(spec::Spectrum)

Returns an array with the bin-by-bin energies
"""
energyscale(spec::Spectrum) =
    energyscale(spec.energy, 1:length(spec))

"""
    basicEDS(spec::Spectrum, fwhmatmnka::Float64)

Build a SimpleEDS object for this spectrum with the specified FWHM at Mn Kα.
"""
basicEDS(spec::Spectrum, fwhmatmnka::Float64) =
    SimpleEDS(length(spec),spec.energy,MnKaResolution(fwhmatmnka))


"""
    subsample(spec::Spectrum, frac::Float64)

Subsample the counts data in a spectrum according to a statistically valid algorithm.
"""
function subsample(spec::Spectrum, frac::Float64)::Spectrum
    ss(n, f) = n > 0 ? mapreduce(i -> rand() < f ? 1 : 0, + , 1:n) : 0
    frac = min(frac, 1.0)
    props = deepcopy(spec.properties)
    props[:LiveTime]=frac*get(spec, :LiveTime, 1.0)
    props[:RealTime]=frac*get(spec, :RealTime, 1.0)
    Spectrum(spec.energy, map(n -> ss(floor(Int,n), frac), spec.counts), props)
end


"""
    estimateBackground(data::AbstractArray{Float64}, channel::Int, width::Int=5, order::Int=2)

Returns the tangent to the a quadratic fit to the counts data centered at channel with width
"""
function estimateBackground(data::AbstractArray{Float64}, channel::Int, width::Int = 5, order::Int = 2)::Poly
    fit = polyfit(-width:width, data[max(1, channel - width):min(length(data), channel + width)], order)
    return Poly([fit(0), polyder(fit)(0)])
end

"""
    modelBackground(spec::Spectrum, chs::UnitRange{Int}, ash::AtomicShell)

spec: A spectrum containing a peak centered on chs
chs:  A range of channels containing a peak
ash:  The edge (as an AtomicShell)

A simple model for modeling the background under a characteristic x-ray peak. The model
fits a line to low and high energy background regions around chs.start and chs.end. If
the low energy line extended out to the edge energy is larger than the high energy line
at the same energy, then a negative going edge is fit between the two. Otherwise a line
is fit between the low energy side and the high energy side. This model only works when
there are no peak interference over the range chs.
"""
function modelBackground(spec::Spectrum, chs::UnitRange{Int}, ash::AtomicShell)
    bl=estimateBackground(counts(spec),chs.start,5)
    bh=estimateBackground(counts(spec),chs.stop,5)
    ec = channel(energy(ash),sp)
    if (ec<chs.stop) && (bl(ec-chs.start)>bh(ec-chs.stop)) && (energy(ec,spec)<2.0e3)
        res=zeros(Float64,length(chs))
        for y in chs.start:ec-1
            res[y-chs.start+1]=bl(y-chs.start)
        end
        res[ec-chs.start+1]=0.5*(bl(ec-chs.start)+bh(ec-chs.stop))
        for y in ec+1:chs.stop
            res[y-chs.start+1]=bh(y-chs.stop)
        end
    else
        s=(bh(0)-bl(0))/length(chs)
        back = Poly([bl(0), s])
        res=back.(collect(0:length(chs)-1))
    end
    return res
end


"""
    modelBackground(spec::Spectrum, chs::UnitRange{Int})

spec: A spectrum containing a peak centered on chs
chs:  A range of channels containing a peak

A simple model for modeling the background under a characteristic x-ray peak. The model
fits a line between the  low and high energy background regions around chs.start and chs.end.
This model only works when there are no peak interference over the range chs.
"""
function modelBackground(spec::Spectrum, chs::UnitRange{Int})
    bl=estimateBackground(counts(spec),chs.start,5)
    bh=estimateBackground(counts(spec),chs.stop,5)
    s=(bh(0)-bl(0))/length(chs)
    back = Poly([bl(0), s])
    return back.(collect(0:length(chs)-1))
end

"""
    extractcharacteristic(spec::Spectrum, lowBack::UnitRange{Int}, highBack::UnitRange{Int})::Vector{Float64}

Extract the characteristic intensity for the peak located within chs with an edge at ash.
"""
function extractcharacteristic(spec::Spectrum, chs::UnitRange{Int}, ash::AtomicShell)::Vector{Float64}
    return counts(spec,chs,Float64)-modelBackground(spec,chs,ash)
end

"""
    peaktobackground(spec::Spectrum, chs::UnitRange{Int}, ash::AtomicShell)::Float64

Estimates the peak-to-background ratio for the characteristic X-ray intensity in the specified range of channels
which encompass the specified AtomicShell.
"""
function peaktobackground(spec::Spectrum, chs::UnitRange{Int}, ash::AtomicShell)::Float64
    back = sum(modelBackground(spec,chs,ash))
    return (sum(counts(spec,chs,Float64))-back)/back
end
