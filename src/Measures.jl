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

"The `Measures` module is used to interact with CasaCore measures."
module Measures

export CasaCoreMeasuresError

export Epoch, Direction, Position, Baseline
export @epoch_str, @dir_str, @pos_str, @baseline_str

export ReferenceFrame
export set!, measure

export longitude, latitude, observatory, sexagesimal
export angle_between, gram_schmidt

using StaticArrays
using Unitful
using Printf
using LinearAlgebra
using Dates
using Casacore: LibCasacore

# See https://github.com/ajkeller34/Unitful.jl/issues/38 for a discussion of angle units in the
# Unitful package. We decided that it makes sense for angles to be dimensionless, but Andrew was
# hesitant to commit to this typealias within Unitful.
const Angle{T} = Unitful.DimensionlessQuantity{T}

struct CasaCoreMeasuresError <: Exception
    msg::String
end
function Base.show(io::IO, err::CasaCoreMeasuresError)
    return print(io, "CasaCoreMeasuresError: ", err.msg)
end
err(msg) = throw(CasaCoreMeasuresError(msg))

abstract type Measure end

# Measures are plain values; treat them (and the reference frame) as scalars when broadcasting.
Base.broadcastable(x::Measure) = Ref(x)

include("measures/sexagesimal.jl")
include("measures/epochs.jl")
include("measures/directions.jl")
include("measures/positions.jl")
include("measures/baselines.jl")
include("measures/conversions.jl")
include("measures/mathematics.jl")
include("measures/rotations.jl")

end
