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

@noinline function column_length_mismatch_error(column_length, table_rows)
    return err("column length ($column_length) must match the number of rows ($table_rows)")
end

@noinline function column_missing_error(column)
    return err("column \"$column\" is missing from the table")
end

@noinline function column_element_type_error(column)
    return err("element type mismatch for column \"$column\"")
end

@noinline function column_shape_error(column)
    return err("array shape mismatch for column \"$column\"")
end

"""
    Tables.num_columns(table)

Returns the number of columns in the given table.

**Arguments:**

- `table` - the relevant table

**Usage:**

```jldoctest
julia> table = Tables.create("/tmp/my-table.ms")
       Tables.num_columns(table)
0

julia> Tables.add_rows!(table, 10)
       table["TEST_COLUMN"] = randn(10)
       Tables.num_columns(table)
1

julia> Tables.delete(table)
```

**See also:** [`Tables.num_rows`](@ref), [`Tables.num_keywords`](@ref)
"""
function num_columns(table::Table)
    isopen(table) || table_closed_error()
    return Int(LC.ncolumn(LC.tableDesc(table.ref)))
end

function column_exists(table::Table, column::String)
    isopen(table) || table_closed_error()
    return column in String.(LC.columnNames(LC.tableDesc(table.ref)))
end

for T in typelist
    @eval function add_column!(table::Table, column::String, ::Type{$T}, shape::Tuple{Int})
        isopen(table) || table_closed_error()
        iswritable(table) || table_readonly_error()
        Nrows = num_rows(table)
        if shape[1] != Nrows
            column_length_mismatch_error(shape[1], Nrows)
        end
        CasacoreTables.Table(table.ref)[Symbol(column)] = CasacoreTables.ScalarColumnDesc{$T}()
        return column
    end

    @eval function add_column!(table::Table, column::String, ::Type{$T}, shape::Tuple)
        isopen(table) || table_closed_error()
        iswritable(table) || table_readonly_error()
        Nrows = num_rows(table)
        if shape[end] != Nrows
            column_length_mismatch_error(shape[end], Nrows)
        end
        cell_shape = shape[1:(end-1)]
        desc = CasacoreTables.ArrayColumnDesc{$T,length(cell_shape)}(cell_shape) # fixed shape
        CasacoreTables.Table(table.ref)[Symbol(column)] = desc
        return column
    end
end

"""
    Tables.remove_column!(table, column)

Remove the specified column from the table.

**Arguments:**

- `table` - the relevant table
- `column` - the column that will be removed from the table

**Usage:**

```jldoctest
julia> table = Tables.create("/tmp/my-table.ms")
       Tables.add_rows!(table, 10)
       table["TEST"] = rand(Bool, 10)
       Tables.num_columns(table)
1

julia> Tables.remove_column!(table, "TEST")
       Tables.num_columns(table)
0

julia> Tables.delete(table)
```

**See also:** [`Tables.num_columns`](@ref)
"""
function remove_column!(table::Table, column::String)
    isopen(table) || table_closed_error()
    iswritable(table) || table_readonly_error()
    LC.removeColumn(table.ref, LC.String(column))
    return nothing
end

column_desc(table::Table, column::String) =
    LC.columnDesc(LC.tableDesc(table.ref), LC.String(column))

"Run `f` on a Casacore.jl `Column` of the table, then free the C++ column object."
function with_column(f, table::Table, column::String)
    col = CasacoreTables.Column(table.ref, LC.String(column))
    try
        return f(col)
    finally
        finalize(col.columnref)
    end
end

"Get the column element type and shape."
function column_info(table::Table, column::String)
    isopen(table) || table_closed_error()
    desc = column_desc(table, column)
    T = element_type(LC.dataType(desc))
    Nrows = num_rows(table)
    if Bool(LC.isScalar(desc))
        return T, (Nrows,)
    elseif column_is_fixed_shape(table, column)
        return T, (totuple(LC.shape(desc))..., Nrows)
    else
        # if the column doesn't have a fixed shape, we rely on the shape of the array in the
        # first row to get the shape of the entire column (as the original C++ wrapper did)
        cell_shape = with_column(table, column) do col
            if Nrows > 0 && Bool(LC.isDefined(col.columnref, 0))
                totuple(LC.shape(col.columnref, 0))
            else
                ()
            end
        end
        return T, (cell_shape..., Nrows)
    end
end

"Check to see if the column shape is fixed."
function column_is_fixed_shape(table::Table, column::String)
    return Bool(LC.isFixedShape(column_desc(table, column)))
end

"""
Check to see if the column shape can be changed.

(Casacore.jl does not expose `TableColumn::canChangeShape`; a column that is not fixed shape is
assumed to be able to change shape.)
"""
function column_can_change_shape(table::Table, column::String)
    return !column_is_fixed_shape(table, column)
end

function Base.getindex(table::Table, column::String)
    isopen(table) || table_closed_error()
    if !column_exists(table, column)
        column_missing_error(column)
    end
    T, shape = column_info(table, column)
    return read_column(table, column, T, shape)
end

function Base.setindex!(table::Table, value, column::String)
    isopen(table) || table_closed_error()
    value isa AbstractArray && !(value isa Array) && (value = collect(value)) # dense copy
    iswritable(table) || table_readonly_error()
    if !column_exists(table, column)
        add_column!(table, column, eltype(value), size(value))
    end
    T, shape = column_info(table, column)
    if T != eltype(value)
        column_element_type_error(column)
    end
    if column_is_fixed_shape(table, column) || !column_can_change_shape(table, column)
        shape != size(value) && column_shape_error(column)
    else
        # cell size can change, but the number of rows should still match
        shape[end] != size(value)[end] && column_shape_error(column)
    end
    return write_column!(table, value, column)
end

function read_column(table::Table, column::String, ::Type{T}, shape) where {T}
    is_scalar = Bool(LC.isScalar(column_desc(table, column)))
    shape[end] == 0 && return Array{T}(undef, shape)
    is_scalar || length(shape) > 1 || column_shape_error(column) # first cell is undefined
    with_column(table, column) do col
        if is_scalar
            return col[:]
        else
            return col[(1:n for n in shape[1:(end-1)])..., :]
        end
    end
end

function write_column!(table::Table, value::Array{T}, column::String) where {T}
    is_scalar = Bool(LC.isScalar(column_desc(table, column)))
    with_column(table, column) do col
        if is_scalar
            size(value, 1) == 0 || (col[:] = value)
        elseif T === String
            for row in 1:size(value, ndims(value))
                cell = value[ntuple(_ -> :, ndims(value) - 1)..., row]
                LC.put(col.columnref, row - 1, cxx_array(cell))
            end
        else
            GC.@preserve value LC.putColumn(col.columnref, cxx_array(value))
        end
    end
    return value
end
