# Copyright (c) 2015-2017 Michael Eastwood
# Copyright (c) 2026 Xander Hall (CasaCoreCompat: reimplementation on top of Casacore.jl)
#
# This program is free software: you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation, either version 3 of the License, or
# (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program.  If not, see <http://www.gnu.org/licenses/>.

const LC = LibCasacore
const CxxWrap = LibCasacore.CxxWrap

const typelist = (Bool, Int32, Float32, Float64, ComplexF32, ComplexF64, String)

# Name of each element type in TaQL (used for keyword casts)
const type2taql = IdDict(Bool => "BOOL", Int32 => "INT", Float32 => "FLOAT",
    Float64 => "DOUBLE", ComplexF32 => "COMPLEX", ComplexF64 => "DCOMPLEX", String => "STRING")

"Translate a casacore `DataType` into the Julia type used by the old CasaCore.jl API."
function julia_type(datatype)
    for (tp, T) in ((LC.TpBool, Bool), (LC.TpInt, Int32), (LC.TpFloat, Float32),
                    (LC.TpDouble, Float64), (LC.TpComplex, ComplexF32),
                    (LC.TpDComplex, ComplexF64), (LC.TpString, String),
                    (LC.TpArrayBool, Array{Bool}), (LC.TpArrayInt, Array{Int32}),
                    (LC.TpArrayFloat, Array{Float32}), (LC.TpArrayDouble, Array{Float64}),
                    (LC.TpArrayComplex, Array{ComplexF32}),
                    (LC.TpArrayDComplex, Array{ComplexF64}), (LC.TpArrayString, Array{String}),
                    (LC.TpTable, Table))
        datatype == tp && return T
    end
    err("unsupported casacore data type $datatype")
end

"Convert a casacore `IPosition` into a tuple of `Int`s."
totuple(ipos) = ntuple(i -> Int(ipos[i]), length(ipos))

# Element type of a column as seen from Julia (Casacore.jl's mapping)
element_type(datatype) = LC.getjuliatype(LC.getcxxtype(datatype))

# Build a casacore Array/Vector holding the contents of a Julia array. Numeric arrays share
# memory with `value` (the caller must `GC.@preserve value`), strings are copied.
function cxx_array(value::Array{T}; vector=false) where {T}
    shape = LC.IPosition(size(value))
    A = vector ? LC.Vector : LC.Array
    if T === String
        arr = A{LC.String}(shape)
        LC.copy!(arr, Any[LC.String(s) for s in vec(value)])
        return arr
    else
        return A{LC.getcxxtype(T)}(shape, convert(Ptr{Cvoid}, pointer(value)), LC.SHARE)
    end
end

"""
    taql(command, tables...)

Run a TaQL command where `\$1`, `\$2`, ... refer to the given casacore table handles and return
the resulting casacore table handle. (Casacore.jl's own `taql` does not work with the CxxWrap
version used on Julia 1.13, so we build the `std::vector` ourselves.)
"""
function taql(command::AbstractString, tables...)
    vec = CxxWrap.StdLib.StdVector{CxxWrap.ConstCxxPtr{LC.Table}}()
    for table in tables
        push!(vec, Ref(CxxWrap.ConstCxxPtr(table)))
    end
    GC.@preserve tables vec begin
        return LC.tableCommand(String(command), vec)
    end
end
