using Test

module Casacore
module Measures
export measure_marker
const measure_marker = :measure_ok
end

module Tables
export table_marker
const table_marker = :table_ok
end
end

using CasaCoreCompat

@testset "CasaCoreCompat" begin
    @test CasaCoreCompat.Measures === Main.Casacore.Measures
    @test CasaCoreCompat.Tables === Main.Casacore.Tables

    @eval using CasaCoreCompat.Measures
    @eval using CasaCoreCompat.Tables

    @test Main.measure_marker === :measure_ok
    @test Main.table_marker === :table_ok
end
