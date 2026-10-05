# Copyright (c) 2015-2017 Michael Eastwood
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

# Ported from the test suite of CasaCore.jl v0.3.0. The `Data` and `MeasurementSets` modules
# are not provided by CasaCoreCompat, so their tests (and the `CasaCoreError` test in
# common.jl, which refers to a type CasaCore.jl itself never defined) are omitted.

using CasaCoreCompat.Tables
using CasaCoreCompat.Measures
using Unitful
using Test
using Random
using Dates
using LinearAlgebra
using Statistics

Random.seed!(123)

@testset "CasaCoreCompat Tests" begin
    include("tables.jl")
    include("measures.jl")
    include("compat.jl")
end
