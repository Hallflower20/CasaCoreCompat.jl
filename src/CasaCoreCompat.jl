module CasaCoreCompat

const _CASACORE_PKGID = Base.PkgId(Base.UUID("72bb1062-94f5-49fa-bb69-94b615203ad9"), "Casacore")
const _aliases_initialized = Ref(false)

export Measures, Tables

function _load_casacore()
    if isdefined(Main, :Casacore)
        casacore = getfield(Main, :Casacore)
        casacore isa Module && return casacore
    end

    Base.require(_CASACORE_PKGID)

    if isdefined(Main, :Casacore)
        casacore = getfield(Main, :Casacore)
        casacore isa Module && return casacore
    end

    return Base.root_module(_CASACORE_PKGID)
end

function __init__()
    _aliases_initialized[] && return

    casacore = try
        _load_casacore()
    catch err
        throw(ArgumentError("CasaCoreCompat requires Casacore.jl to be installed and loadable. Original error: $(sprint(showerror, err))"))
    end

    @eval begin
        const Measures = $(getfield(casacore, :Measures))
        const Tables = $(getfield(casacore, :Tables))
    end

    _aliases_initialized[] = true
end

end
