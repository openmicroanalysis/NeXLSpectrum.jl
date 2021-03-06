using Test
using Pkg.Artifacts
using NeXLSpectrum
using DataFrames

# Download the necessary data using the Artifact mechanism from Google Drive
rrpath = artifact"rplraw"

@testset "HyperSpectrum" begin
    les = LinearEnergyScale(0.0, 10.0)
    raw = readrplraw(joinpath(rrpath, "map[15]"), les, Dict{Symbol,Any}(:LiveTime => 0.004, :BeamEnergy => 20.0e3))

    @test size(raw) == (2048, 128, 128)
    @test eltype(raw) == UInt16
    @test raw[640, 64, 64] == 0x0007

    mpr = maxpixel(raw)
    @test mpr isa Vector
    @test mpr[640] == 0x0013
    @test raw[640, indexofmaxpixel(raw, 640)] == 0x0013

    hs = ashyperspectrum(raw)
    @test size(hs) == (128, 128)
    @test eltype(hs) == Spectrum
    @test hs[64, 64] isa Spectrum
    @test hs[64, 64][640] == 0x0007

    mp = maxpixel(hs)
    @test mp isa Spectrum
    @test mp[640] == 0x0013
    @test indexofmaxpixel(hs, 640) == CartesianIndex(64, 51)
    @test hs[indexofmaxpixel(hs, 640)][640] == 0x0013

    @test sum(raw)[:] == sum(hs)[:]
    @test all(sum(hs, (sig, i) -> sig[640, i] > 3) .<= sum(hs))
    @test all(sum(raw, (sig, i) -> sig[640, i] > 3) .<= sum(raw))
    raw=nothing
    GC.gc()
end

@testset "QQHyperspec" begin
    les = LinearEnergyScale(0.0, 10.0)
    raw = readrplraw(joinpath(rrpath, "map[15]"), les, #
        Dict{Symbol,Any}(:LiveTime => 0.01, :BeamEnergy => 20.0e3, :ProbeCurrent=>1.0))
    hs = ashyperspectrum(raw, "Map[15]")
    mp = maxpixel(hs)
    cstd, festd, fes2std, mgostd, sistd = map(n->loadspectrum(joinpath(rrpath, "standards", "$n std.msa")), ("C", "Fe", "FeS2", "MgO", "Si"))
    det = matching(festd, 132.0, 10)
    refs = (
        ( cstd, n"C", mat"C" ),
        ( festd, n"Fe", mat"Fe" ),
        ( fes2std, n"S", mat"FeS2" ),
        ( mgostd, n"O", mat"MgO" ),
        ( sistd, n"Si", mat"Si" )
    )
    filt = buildfilter(det)
    frs = filterreferences(filt, refs...)
    qq = VectorQuant(frs, filt)
    res=fit(qq, hs)
    @test all(map(a->isapprox(a..., atol=0.00001), zip(res.results[:,12,23], ( 1.10457, 0.006895, 0.0, 0.0, 0.0, 0.063778, 0.0 ))))
    @test all(map(a->isapprox(a..., atol=0.00001), zip(res.results[:,60,29], ( 1.070000, 0.01006, 0.36027, 0.20048, 0.025442, 1.11138, 0.002127 ))))
    NeXLSpectrum.asimage(res,3,transform=x->log10(1.0+99.0x)/2.0)
    @test res[64,64] isa BasicFitResult
    df=asa(DataFrame, [res[i,64] for i in 32:95])
    @test df[2,2] ≈ res.results[1,33,64]
    @test df[12,6] ≈ res.results[5,43,64]
    raw = nothing
    GC.gc()
end
