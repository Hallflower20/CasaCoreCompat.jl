# CasaCoreCompat.jl

`CasaCoreCompat.jl` is a thin compatibility wrapper that exposes `Casacore.jl` modules under `CasaCore`-style names used by older packages such as `TTCal.jl` and `BPJSpec.jl`.

## Usage

```julia
using CasaCoreCompat.Measures
using CasaCoreCompat.Tables
```

This package forwards `Measures` and `Tables` to `Casacore.Measures` and `Casacore.Tables`.
