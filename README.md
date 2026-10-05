# CasaCoreCompat.jl

A compatibility layer that brings back the API of Michael Eastwood's
[CasaCore.jl](https://github.com/mweastwood/CasaCore.jl) (the `CasaCore.Measures` and
`CasaCore.Tables` modules). It is implemented on top of the maintained JuliaAstro
[Casacore.jl](https://github.com/JuliaAstro/Casacore.jl).

The original package is unmaintained and its binaries do not load on current Julia (1.13).

What is the same as the original:

- the names and the export lists of `Measures` and `Tables`;
- the measure types: `Epoch`, `Direction`, `Position`, `Baseline` and `UnnormalizedDirection`
  are still immutable `isbits` structs of `Float64` fields, and never hold a C++ handle;
- the behaviour pinned by the original test suite, which is included here and passes
  unchanged.

The exceptions are listed under
[Semantic deviations](#semantic-deviations-and-implementation-notes). Casacore.jl's C++ objects
are only created inside `measure`, `observatory`, the `Tables` functions and the per-frame
cache.

## Migrating downstream code (TTCal.jl, BPJSpec.jl)

1. Change the `using` lines:

   ```julia
   using CasaCore.Measures   # before
   using CasaCoreCompat.Measures   # after

   using CasaCore.Tables     # before
   using CasaCoreCompat.Tables     # after
   ```

2. In the downstream `Project.toml`, replace the `CasaCore` dependency with:

   ```toml
   [deps]
   CasaCoreCompat = "ac24a7dd-83c5-45b5-8923-fca2a646bec5"

   [sources]
   CasaCoreCompat = {path = "../CasaCoreCompat.jl"}
   ```

   `[sources]` needs Julia 1.11 or later.

## Installation

CasaCoreCompat currently depends on a sibling checkout of Casacore.jl: `Project.toml` has a
`[sources]` entry, and the committed `Manifest.toml` has `path = "../Casacore.jl"`. Expected
layout:

```
revamp-mmode-pipeline/
├── Casacore.jl/        # JuliaAstro Casacore.jl (v0.4.1)
└── CasaCoreCompat.jl/  # this package
```

Casacore.jl must be built once. The build downloads the casacore ephemeris/IERS data (WSRT
Measures) that frame conversions need:

```julia
julia> using Pkg; Pkg.build("Casacore")
```

Requires Julia ≥ 1.11. Run the tests with `julia --project=. -e 'using Pkg; Pkg.test()'`.

## Omitted features

- `CasaCore.MeasurementSets` and `CasaCore.Data` are not provided. TTCal.jl and BPJSpec.jl do
  not use them.

## Semantic deviations and implementation notes

- **Cached `ReferenceFrame`s are not thread-safe.** `ReferenceFrame` keeps a cache of
  casacore objects: the `MeasFrame`, plus the converter for each (measure type, input system,
  output system).
  - `set!`, or assigning a field directly, clears the cache.
  - The cache makes repeated conversions in one frame about 10× faster, including
    `measure.(frame, vec, sys)`.
  - `measure(frame, array, sys)` converts a whole array.
  - **Once a frame has been used, do not share it between threads.** Give each task its own
    `ReferenceFrame`.
- **`Tables.lock` / `Tables.unlock`.** The Julia 0.6 CasaCore.jl had these commented out, but
  they are provided here. `unlock` calls casacore's `Table::unlock`, which flushes the table
  and releases the lock. Casacore.jl does not expose `Table::lock`, so `lock` is a documented
  no-op. Tables are opened in casacore's default auto-locking mode, so the lock is taken again
  automatically on the next access.
- **Keywords go through TaQL.** Casacore.jl does not expose generic `TableRecord` field
  accessors, so non-table keywords are written with
  `ALTER TABLE ... SET KEYWORD name = value AS <type>`. They are read back by copying them
  (`COPY KEYWORD`, which keeps the stored type) into a scratch in-memory table. Stored types are
  preserved exactly (`Int32`, `Float32`, `ComplexF32`, ...). The limitations are:
  - keyword names that start with a digit are not supported;
  - empty arrays cannot be stored as keywords;
  - string values cannot contain newlines (backslashes are fine);
  - only the old API's types are accepted (`Bool`, `Int32`, `Float32`, `Float64`,
    `ComplexF32`, `ComplexF64`, `String` and arrays of these). Other types, such as `Int64`,
    throw `CasaCoreTablesError("unsupported keyword type ...")`;
  - keyword access is slower than in the original.

  **TODO:** the proper fix is typed `TableRecord` get/define bindings in Casacore.jl's
  `casacorecxx`; once those exist, the TaQL layer can be replaced.

  Subtable keywords (`table[kw"ANTENNA"]`, `table[kw"SPECTRAL_WINDOW"] = subtable`) use
  casacore's `defineTable`/`asTable` directly.
- **Shape changes are not checked separately.** `Tables.column_can_change_shape` is reported as
  `!column_is_fixed_shape` because Casacore.jl does not expose
  `TableColumn::canChangeShape`.
- **Table keyword writes need a writable table.** Writing a table keyword to a table opened
  read-only throws `CasaCoreTablesError`. The original passed the call to C++, which then
  failed.
- **Epoch conversions use the frame.** `measure(frame, ::Epoch, sys)` passes the reference
  frame to casacore, where the original ignored it. Conversions that worked before give the
  same results. Conversions that need a frame (e.g. to `LAST`) now work when the frame has a
  position.
- **`ReferenceFrame` stores missing values as `nothing`.** Its fields are
  `Union{Nothing,...}` instead of `Nullable`.
- **Column and cell writes accept any `AbstractArray`.** Values such as ranges and views are
  first copied to a dense `Array`. The element type must still match the column.
- **Broadcasting.** `ReferenceFrame` and all measures broadcast as scalars, so
  `measure.(frame, positions, pos"ITRF")` works.
- **`observatory("OVRO_MMA")` returns a misplaced position.** The casacore observatory table
  entry is tagged `ITRF` but holds a vector of about 1.2 km. The Julia 0.6 build returns the
  same value, so this comes from the data, not from this package. Use an explicit
  `Position(pos"WGS84", ...)` for OVRO.

## License

GPL-3.0-or-later. The pure-Julia code is derived from CasaCore.jl
(Copyright (c) 2015-2017 Michael Eastwood, GPL-3). See `LICENSE`.
