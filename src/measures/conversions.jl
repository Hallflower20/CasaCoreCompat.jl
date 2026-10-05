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

"""
    measure(frame, value, newsys)

Converts the value measured in the given frame of reference into a new coordinate system.

**Arguments:**

* `frame` - an instance of the `ReferenceFrame` type
* `value` - an `Epoch`, `Direction`, or `Position` that will be converted from its current
            coordinate system into the new one
* `newsys` - the new coordinate system

Note that the reference frame must have all the required information to convert between the
coordinate systems. Not all conversions require the same information!

**Examples:**

``` julia
# Compute the azimuth and elevation of the Sun
measure(frame, Direction(dir"SUN"), dir"AZEL")

# Compute the ITRF position of the VLA
measure(frame, observatory("VLA"), pos"ITRF")

# Compute the atomic time from a UTC time
measure(frame, Epoch(epoch"UTC", 50237.29*u"d"), epoch"TAI")
```
"""
measure

# Casacore objects needed to convert into one (measure type, input system, output system).
struct Converter
    ref::Any       # MXxx!Ref carrying the frame
    converter::Any # MXxx!Convert
    output::Any    # scratch measure that receives the converted value
end

# Casacore objects derived from a `ReferenceFrame`. They are built lazily by `measure` and
# discarded by every `set!`. A frame (and therefore this cache) must not be used from several
# threads at once.
mutable struct FrameCache
    measures::Vector{Any} # the casacore measures the MeasFrame was built from (kept alive)
    mframe::Any           # casacore MeasFrame
    converters::Dict{Tuple{DataType,Int,Int},Converter}
end

mutable struct ReferenceFrame
    epoch::Union{Nothing,Epoch}
    direction::Union{Nothing,Direction}
    position::Union{Nothing,Position}
    cache::Union{Nothing,FrameCache}
end

"""
    ReferenceFrame

The `ReferenceFrame` type contains information about the frame of reference to use when converting
between coordinate systems. For example converting from J2000 coordinates to AZEL coordinates
requires knowledge of the observer's location, and the current time. However converting between
B1950 coordinates and J2000 coordinates requires no additional information about the observer's
frame of reference.

Use the `set!` function to add information to the given frame of reference.

**Example:**

``` julia
frame = ReferenceFrame()
set!(frame, observatory("VLA")) # set the observer's position to the location of the VLA
set!(frame, Epoch(epoch"UTC", 50237.29*u"d")) # set the current UTC time
```
"""
ReferenceFrame() = ReferenceFrame(nothing, nothing, nothing)
ReferenceFrame(epoch, direction, position) = ReferenceFrame(epoch, direction, position, nothing)

set!(frame::ReferenceFrame, epoch::Epoch) = (frame.cache = nothing; frame.epoch = epoch)
set!(frame::ReferenceFrame, direction::Direction) = (frame.cache = nothing; frame.direction = direction)
set!(frame::ReferenceFrame, position::Position) = (frame.cache = nothing; frame.position = position)

# A frame whose fields are reassigned directly (`frame.epoch = ...`) must also drop its cache.
function Base.setproperty!(frame::ReferenceFrame, name::Symbol, value)
    name === :cache || setfield!(frame, :cache, nothing)
    return setfield!(frame, name, convert(fieldtype(ReferenceFrame, name), value))
end

# `measure.(frame, positions, pos"ITRF")` should treat the frame as a scalar
Base.broadcastable(frame::ReferenceFrame) = Ref(frame)

# Translation between the plain Julia measure structs and casacore (via Casacore.jl's
# LibCasacore CxxWrap bindings). Casacore objects only ever live inside `measure`.

const LC = LibCasacore

# casacore unit string "s"; CxxWrap objects cannot be created at precompile time
const SECONDS = Ref{Any}(nothing)
__init__() = (SECONDS[] = LC.String("s"); nothing)

to_casacore(epoch::Epoch) =
    LC.MEpoch(LC.MVEpoch(LC.Quantity(epoch.time, SECONDS[])), Int(epoch.sys))
to_casacore(direction::Direction) =
    LC.MDirection(LC.MVDirection(direction.x, direction.y, direction.z), Int(direction.sys))
to_casacore(position::Position) =
    LC.MPosition(LC.MVPosition(position.x, position.y, position.z), Int(position.sys))
to_casacore(baseline::Baseline) =
    LC.MBaseline(LC.MVBaseline(baseline.x, baseline.y, baseline.z), Int(baseline.sys))

function from_casacore(::Type{Epoch}, m)
    # MVEpoch stores (whole days, fraction of a day)
    days = LC.getValue(m, 0) + LC.getValue(m, 1)
    return Epoch(Epochs.System(LC.getType(LC.getRef(m))), days * 86400)
end
for (T, Sys) in ((Direction, Directions), (Position, Positions), (Baseline, Baselines))
    @eval function from_casacore(::Type{$T}, m)
        sys = $Sys.System(LC.getType(LC.getRef(m)))
        return $T(sys, LC.getValue(m, 0), LC.getValue(m, 1), LC.getValue(m, 2))
    end
end

function frame_cache(frame::ReferenceFrame)
    cache = frame.cache
    cache === nothing || return cache
    measures = Any[]
    frame.epoch === nothing || push!(measures, to_casacore(frame.epoch))
    frame.direction === nothing || push!(measures, to_casacore(frame.direction))
    frame.position === nothing || push!(measures, to_casacore(frame.position))
    cache = FrameCache(measures, LC.MeasFrame(measures...), Dict{Tuple{DataType,Int,Int},Converter}())
    setfield!(frame, :cache, cache)
    return cache
end

# Mirrors the original C++ wrapper: the input measure carries no frame, the output reference
# carries the full frame, and the result is read back into a plain Julia struct.
for (T, Sys, RefT, ConvertT) in ((Epoch, Epochs, :(LC.MEpoch!Ref), :(LC.MEpoch!Convert)),
                               (Direction, Directions, :(LC.MDirection!Ref), :(LC.MDirection!Convert)),
                               (Position, Positions, :(LC.MPosition!Ref), :(LC.MPosition!Convert)),
                               (Baseline, Baselines, :(LC.MBaseline!Ref), :(LC.MBaseline!Convert)))
    @eval function converter(frame::ReferenceFrame, value::$T, newsys::$Sys.System)
        cache = frame_cache(frame)
        key = ($T, Int(value.sys), Int(newsys))
        return get!(cache.converters, key) do
            ref = $RefT(Int(newsys), cache.mframe)
            Converter(ref, $ConvertT(Int(value.sys), ref), to_casacore(value))
        end
    end

    @eval function measure(frame::ReferenceFrame, value::$T, newsys::$Sys.System)
        c = converter(frame, value, newsys)
        input = to_casacore(value)
        GC.@preserve c input begin
            LC.convert!(c.converter, input, c.output)
            return from_casacore($T, c.output)
        end
    end

    @eval function measure(frame::ReferenceFrame, values::AbstractArray{<:$T}, newsys::$Sys.System)
        return map(value -> measure(frame, value, newsys), values)
    end
end

function measure(frame::ReferenceFrame, direction::UnnormalizedDirection, newsys)
    return measure(frame, Direction(direction), newsys)
end

function measure(frame::ReferenceFrame, directions::AbstractArray{UnnormalizedDirection}, newsys)
    return measure(frame, Direction.(directions), newsys)
end

# Define conversions and routines for comparing the different kinds of measures.

@noinline inconsistent_coordinate_system_error() = err("inconsistent coordinate system")

function check_coordinate_system(measure1, measure2)
    if measure1.sys != measure2.sys
        inconsistent_coordinate_system_error()
    end
end

function Base.:(==)(lhs::Directions.System, rhs::Positions.System)
    if lhs == Directions.ITRF && rhs == Positions.ITRF
        return true
    else
        return false
    end
end

function Base.:(==)(lhs::Directions.System, rhs::Baselines.System)
    return Int32(lhs) == Int32(rhs)
end

function Base.:(==)(lhs::Positions.System, rhs::Baselines.System)
    if lhs == Positions.ITRF && rhs == Baselines.ITRF
        return true
    else
        return false
    end
end

Base.:(==)(lhs::Positions.System, rhs::Directions.System) = rhs == lhs
Base.:(==)(lhs::Baselines.System, rhs::Directions.System) = rhs == lhs
Base.:(==)(lhs::Baselines.System, rhs::Positions.System) = rhs == lhs

function Direction(position::Position)
    if position.sys == pos"ITRF"
        Direction(dir"ITRF", position.x, position.y, position.z)
    else
        err("cannot convert given coordinate system to a `Direction`")
    end
end
