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

@noinline function row_out_of_bounds_error(index)
       return err("The given row index is out of bounds: $index")
end

"""
    Tables.num_rows(table)

Returns the number of rows in the given table.

**Arguments:**

- `table` - the relevant table

**Usage:**

```jldoctest
julia> table = Tables.create("/tmp/my-table.ms")
       Tables.num_rows(table)
0

julia> Tables.add_rows!(table, 10)
       Tables.num_rows(table)
10

julia> Tables.remove_rows!(table, 1:2:10)
       Tables.num_rows(table)
5

julia> Tables.delete(table)
```

**See also:** [`Tables.num_columns`](@ref), [`Tables.num_keywords`](@ref)
"""
function num_rows(table::Table)
       isopen(table) || table_closed_error()
       return Int(LC.nrow(table.ref))
end

"""
    Tables.add_rows!(table, number)

Add the given number of rows to the table.

**Arguments:**

- `table` - the relevant table
- `number` - the number of rows that will be added to the table

**Usage:**

```jldoctest
julia> table = Tables.create("/tmp/my-table.ms")
       Tables.add_rows!(table, 10)
       Tables.num_rows(table)
10

julia> Tables.add_rows!(table, 123)
       Tables.num_rows(table)
133

julia> Tables.delete(table)
```

**See also:** [`Tables.remove_rows!`](@ref)
"""
function add_rows!(table::Table, number::Integer)
       isopen(table) || table_closed_error()
       iswritable(table) || table_readonly_error()
       LC.addRow(table.ref, number, true)
       return number
end

"""
    Tables.remove_rows!(table, rows)

Remove the specified rows from the table.

**Arguments:**

- `tables` - the relevant table
- `rows` - the row or rows that will be deleted from the table

**Usage:**

```jldoctest
julia> table = Tables.create("/tmp/my-table.ms")
       Tables.add_rows!(table, 10)
       Tables.remove_rows!(table, 1:2:10)
       Tables.num_rows(table)
5

julia> Tables.remove_rows!(table, 4)
       Tables.num_rows(table)
4

julia> Tables.remove_rows!(table, [1, 2, 3])
       Tables.num_rows(table)
1

julia> Tables.delete(table)
```

**See also:** [`Tables.add_rows!`](@ref)
"""
function remove_rows!(table::Table, rows)
       isopen(table) || table_closed_error()
       iswritable(table) || table_readonly_error()
       N = num_rows(table)
       if any(rows .≤ 0) || any(rows .≥ N + 1)
              row_out_of_bounds_error(rows)
       end
       deleteat!(CasacoreTables.Table(table.ref), rows)
       return rows
end
