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
    CasaCoreCompat

Re-creates the API of Michael Eastwood's (unmaintained) CasaCore.jl package -- the
`CasaCore.Measures` and `CasaCore.Tables` modules -- on top of the maintained JuliaAstro
Casacore.jl package. Replace `using CasaCore.Measures` with `using CasaCoreCompat.Measures`
(and likewise for `Tables`).
"""
module CasaCoreCompat

include("Tables.jl")
include("Measures.jl")

end
