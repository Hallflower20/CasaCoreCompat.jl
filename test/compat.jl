# Copyright (c) 2026 Xander Hall
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

# Additional tests for the API surface used by TTCal.jl and BPJSpec.jl.

@testset "compat extras" begin
    @testset "measures are plain bits types" begin
        for T in (Epoch, Direction, Position, Baseline, Measures.UnnormalizedDirection)
            @test isbitstype(T)
        end
    end

    @testset "broadcasting and statistics" begin
        frame = ReferenceFrame()
        ovro = Position(pos"WGS84", 1207.969u"m", -118.284441u"°", 37.232271u"°")
        itrf = measure(frame, ovro, pos"ITRF")
        positions = [itrf, itrf + Position(pos"ITRF", 10, 0, 0), itrf - Position(pos"ITRF", 10, 0, 0)]
        converted = measure.(frame, positions, pos"WGS84")
        @test converted isa Vector{Position}
        @test converted[1] ≈ ovro
        @test mean(positions) ≈ itrf
        @test Direction(itrf) == Direction(dir"ITRF", itrf.x, itrf.y, itrf.z)
        @test norm(itrf) ≈ hypot(itrf.x, itrf.y, itrf.z) * u"m"
    end

    @testset "planets" begin
        frame = ReferenceFrame()
        set!(frame, observatory("VLA"))
        set!(frame, Epoch(epoch"UTC", 57365.5u"d"))
        for planet in (dir"SUN", dir"MOON", dir"JUPITER")
            j2000 = measure(frame, Direction(planet), dir"J2000")
            azel = measure(frame, Direction(planet), dir"AZEL")
            itrf = measure(frame, Direction(planet), dir"ITRF")
            @test j2000.sys === dir"J2000"
            @test azel.sys === dir"AZEL"
            @test itrf.sys === dir"ITRF"
            @test norm(j2000) == 1
            # (no J2000 -> AZEL round trip check: the direct conversion includes topocentric
            # parallax, which is large for the Moon)
        end
        # the Sun is at RA ≈ 17h03m, Dec ≈ -22d50m on 2015-12-09
        sun = measure(frame, Direction(dir"SUN"), dir"J2000")
        @test abs(ustrip(uconvert(u"°", longitude(sun))) - (-104.25)) < 0.5
        @test abs(ustrip(uconvert(u"°", latitude(sun))) - (-22.85)) < 0.5
    end

    @testset "table lifecycle" begin
        path = tempname() * ".ms"
        table = Tables.create(path)
        @test isdir(path)
        Tables.add_rows!(table, 3)
        table["DATA"] = rand(ComplexF32, 2, 4, 3)
        table["FLAG"] = rand(Bool, 2, 4, 3)
        sub = Tables.create("$path/ANTENNA")
        Tables.add_rows!(sub, 2)
        sub["NAME"] = ["a", "b"]
        table[kw"ANTENNA"] = sub
        Tables.close(sub)
        table["DATA", kw"UNIT"] = "Jy"
        table["DATA", kw"SCALE"] = Float32(0.5)
        Tables.unlock(table)
        Tables.lock(table)
        data = table["DATA"]
        Tables.close(table)

        table = Tables.open(path, write=true)
        @test table["DATA"] == data
        @test eltype(table["DATA"]) == ComplexF32
        @test size(table["FLAG"]) == (2, 4, 3)
        @test table["DATA", kw"UNIT"] == "Jy"
        @test table["DATA", kw"SCALE"] === Float32(0.5)
        antenna = table[kw"ANTENNA"]
        @test antenna isa Table
        @test antenna["NAME"] == ["a", "b"]
        Tables.close(antenna)
        @test Tables.column_exists(table, "DATA")
        @test !Tables.column_exists(table, "CORRECTED_DATA")
        table["CORRECTED_DATA"] = 2 .* data
        @test table["CORRECTED_DATA"] == 2 .* data
        table["CORRECTED_DATA", 2] = zeros(ComplexF32, 2, 4)
        @test table["CORRECTED_DATA", 2] == zeros(ComplexF32, 2, 4)
        Tables.delete(table)
        @test !isdir(path)
    end

    @testset "cached frames" begin
        function fresh_frame(epoch, position, direction)
            frame = ReferenceFrame()
            set!(frame, epoch); set!(frame, position); set!(frame, direction)
            return frame
        end
        epoch = Epoch(epoch"UTC", 57365.5u"d")
        position = observatory("VLA")
        zenith = Direction(dir"AZEL", 0u"°", 90u"°")
        cached = fresh_frame(epoch, position, zenith)
        cases = [(Epoch(epoch"UTC", 57000.25u"d"), epoch"TAI"),
                 (Epoch(epoch"UTC", 57000.25u"d"), epoch"LAST"),
                 (Direction(dir"J2000", "19h59m28.35663s", "+40d44m02.0970s"), dir"AZEL"),
                 (Direction(dir"AZEL", "40d", "50d"), dir"J2000"),
                 (Direction(dir"J2000", "1h", "-10d"), dir"ITRF"),
                 (Direction(dir"SUN"), dir"J2000"), (Direction(dir"MOON"), dir"AZEL"),
                 (Direction(dir"JUPITER"), dir"ITRF"),
                 (Position(pos"WGS84", 1000u"m", "10d", "20d"), pos"ITRF"),
                 (Baseline(baseline"ITRF", 1.234, 5.678, 0.1), baseline"J2000")]
        for _ in 1:2, (value, sys) in cases # second pass hits the cache
            @test measure(cached, value, sys) === measure(fresh_frame(epoch, position, zenith), value, sys)
        end
        dirs = [Direction(dir"AZEL", az * u"°", el * u"°") for az in 0:30:330, el in 10:20:70]
        expected = [measure(fresh_frame(epoch, position, zenith), d, dir"J2000") for d in dirs]
        @test measure(cached, dirs, dir"J2000") == expected
        @test measure.(cached, dirs, dir"J2000") == expected
        @test measure(cached, Measures.UnnormalizedDirection.(dirs), dir"J2000") == expected

        # mutating the frame invalidates the cached converters
        before = measure(cached, dirs[1], dir"J2000")
        set!(cached, Epoch(epoch"UTC", 57365.75u"d"))
        after = measure(cached, dirs[1], dir"J2000")
        @test after != before
        @test after === measure(fresh_frame(Epoch(epoch"UTC", 57365.75u"d"), position, zenith),
                                dirs[1], dir"J2000")
        set!(cached, observatory("ALMA"))
        @test measure(cached, dirs[1], dir"J2000") != after
        cached.epoch = epoch # direct field assignment also invalidates
        @test measure(cached, Direction(dir"SUN"), dir"AZEL") ===
              measure(fresh_frame(epoch, observatory("ALMA"), zenith), Direction(dir"SUN"), dir"AZEL")
    end

    @testset "keyword and column edge cases" begin
        table = Tables.create(tempname() * ".ms")
        Tables.add_rows!(table, 4)
        for s in ("back\\slash", "both \"quotes' here", "tab\there")
            table[kw"S"] = s
            @test table[kw"S"] == s
            Tables.remove_keyword!(table, kw"S")
        end
        @test_throws CasaCoreTablesError table[kw"S"] = "new\nline"
        @test_throws CasaCoreTablesError table[kw"I"] = Int64(1)
        @test_throws CasaCoreTablesError table[kw"I"] = Float16[1, 2]
        table["COL"] = 1.0:4.0                      # AbstractRange
        @test table["COL"] == [1.0, 2.0, 3.0, 4.0]
        table["ARR"] = view(rand(Float32, 3, 8), :, 1:2:8) # SubArray
        table["ARR", 2] = view(ones(Float32, 3, 2), :, 1)
        @test table["ARR", 2] == ones(Float32, 3)
        @test_throws CasaCoreTablesError table["COL", kw"X"] = Int64(1)
        Tables.delete(table)
    end
end
