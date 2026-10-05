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

function Base.getindex(table::Table, column::String, row::Integer)
    isopen(table) || table_closed_error()
    check_column_row(table, column, row)
    T, shape = column_info(table, column)
    return read_cell(table, column, row, T, shape[1:(end-1)])
end

function Base.setindex!(table::Table, value, column::String, row::Integer)
    isopen(table) || table_closed_error()
    iswritable(table) || table_readonly_error()
    check_column_row(table, column, row)
    value isa AbstractArray && !(value isa Array) && (value = collect(value)) # dense copy
    T, shape = column_info(table, column)
    check_cell(value, column, T, shape)
    return write_cell!(table, value, column, row)
end

function check_column_row(table, column, row)
    if !column_exists(table, column)
        column_missing_error(column)
    end
    if row ≤ 0 || row > num_rows(table)
        row_out_of_bounds_error(row)
    end
end

function check_cell(value::Array, column, T, shape)
    if T != eltype(value)
        column_element_type_error(column)
    end
    if shape[1:(end-1)] != size(value)
        column_shape_error(column)
    end
end

function check_cell(value, column, T, shape)
    if T != typeof(value)
        column_element_type_error(column)
    end
    if length(shape) != 1
        column_shape_error(column)
    end
end

function read_cell(table::Table, column::String, row::Integer, ::Type{T}, shape::Tuple) where {T}
    with_column(table, column) do col
        if Bool(LC.isScalar(column_desc(table, column)))
            return col[row]
        elseif column_is_fixed_shape(table, column)
            return col[ntuple(_ -> :, length(shape))..., row]
        else
            return col[row]
        end
    end
end

function write_cell!(table::Table, value::T, column::String, row::Int) where {T}
    with_column(table, column) do col
        cxx_value = T === String ? LC.String(value) : convert(LC.getcxxtype(T), value)
        LC.put(col.columnref, row - 1, cxx_value)
    end
    return value
end

function write_cell!(table::Table, value::Array{T}, column::String, row::Int) where {T}
    with_column(table, column) do col
        GC.@preserve value LC.put(col.columnref, row - 1, cxx_array(value))
    end
    return value
end
