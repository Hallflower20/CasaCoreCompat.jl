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

@noinline function keyword_missing_error(keyword)
    return err("keyword \"$keyword\" is missing from the table")
end

@noinline function keyword_element_type_error(keyword)
    return err("element type mismatch for keyword \"$keyword\"")
end

struct Keyword
    name::String
end

Base.convert(::Type{String}, keyword::Keyword) = keyword.name
Base.show(io::IO, keyword::Keyword) = print(io, keyword.name)
Base.String(keyword::Keyword) = convert(String, keyword)

macro kw_str(string)
    quote
        Keyword($string)
    end
end

"""
    num_keywords(table)

Returns the number of keywords associated with the given table.

**Arguments:**

- `table` - the relevant table

**Usage:**

```jldoctest
julia> table = Tables.create("/tmp/my-table.ms")
       Tables.num_keywords(table)
0

julia> table[kw"RICK_PERLEY_IS_A_BOSS"] = true
       Tables.num_keywords(table)
1

julia> table[kw"NOT_SO_BAD"] = "yourself"
       Tables.num_keywords(table)
2

julia> Tables.delete(table)
```

**See also:** [`Tables.num_rows`](@ref), [`Tables.num_columns`](@ref)
"""
function num_keywords(table::Table)
    isopen(table) || table_closed_error()
    return Int(LC.size(LC.keywordSet(table.ref)))
end

"Query whether the keyword exists."
function keyword_exists(table::Table, keyword::Keyword)
    isopen(table) || table_closed_error()
    return keyword_index(table, keyword) ≥ 0
end

function keyword_exists(table::Table, column::String, keyword::Keyword)
    isopen(table) || table_closed_error()
    copy = copy_keyword(table, keyword_ref(column, keyword))
    copy === nothing && return false
    finalize(copy)
    return true
end

"""
    Tables.remove_keyword!(table, keyword)

Remove the specified keyword from the table.

**Arguments:**

- `table` - the relevant table
- `keyword` - the keyword to be removed

**Usage:**

```jldoctest
julia> table = Tables.create("/tmp/my-table.ms")
       table[kw"HELLO"] = "world"
       Tables.num_keywords(table)
1

julia> Tables.remove_keyword!(table, kw"HELLO")
       Tables.num_keywords(table)
0

julia> Tables.delete(table)
```

**See also:** [`Tables.num_keywords`](@ref)
"""
function remove_keyword!(table::Table, keyword::Keyword)
    isopen(table) || table_closed_error()
    iswritable(table) || table_readonly_error()
    taql("ALTER TABLE \$1 DROP KEYWORD " * keyword_ref("", keyword), table.ref) |> finalize
    return keyword
end

function remove_keyword!(table::Table, column::String, keyword::Keyword)
    isopen(table) || table_closed_error()
    iswritable(table) || table_readonly_error()
    taql("ALTER TABLE \$1 DROP KEYWORD " * keyword_ref(column, keyword), table.ref) |> finalize
    return nothing
end

"Get the keyword element type and shape."
function keyword_info(table::Table, keyword::Keyword)
    isopen(table) || table_closed_error()
    keywords = LC.keywordSet(table.ref)
    T = julia_type(LC.type(keywords, keyword_index(table, keyword)))
    return T, keyword_shape(T, () -> read_keyword(table, keyword, T, ()))
end

function keyword_info(table::Table, column::String, keyword::Keyword)
    isopen(table) || table_closed_error()
    copy = copy_keyword(table, keyword_ref(column, keyword))
    copy === nothing && keyword_missing_error(keyword)
    try
        T = julia_type(LC.type(LC.keywordSet(copy), 0))
        return T, keyword_shape(T, () -> read_scratch_keyword(copy, T))
    finally
        finalize(copy)
    end
end

keyword_shape(::Type, value) = ()
keyword_shape(::Type{<:Array}, value) = size(value())

function Base.getindex(table::Table, keyword::Keyword)
    isopen(table) || table_closed_error()
    index = keyword_index(table, keyword)
    index ≥ 0 || keyword_missing_error(keyword)
    T = julia_type(LC.type(LC.keywordSet(table.ref), index))
    return read_keyword(table, keyword, T, ()) # one TaQL round trip (none for subtables)
end

function Base.setindex!(table::Table, value, keyword::Keyword)
    isopen(table) || table_closed_error()
    index = keyword_index(table, keyword)
    if index ≥ 0
        T = julia_type(LC.type(LC.keywordSet(table.ref), index))
        if T != typeof(value)
            keyword_element_type_error(keyword)
        end
    end
    return write_keyword!(table, value, keyword)
end

function Base.getindex(table::Table, column::String, keyword::Keyword)
    isopen(table) || table_closed_error()
    if !column_exists(table, column)
        column_missing_error(column)
    end
    copy = copy_keyword(table, keyword_ref(column, keyword)) # one TaQL round trip
    copy === nothing && keyword_missing_error(keyword)
    try
        return read_scratch_keyword(copy, julia_type(LC.type(LC.keywordSet(copy), 0)))
    finally
        finalize(copy)
    end
end

function Base.setindex!(table::Table, value, column::String, keyword::Keyword)
    isopen(table) || table_closed_error()
    iswritable(table) || table_readonly_error()
    if !column_exists(table, column)
        column_missing_error(column)
    end
    copy = copy_keyword(table, keyword_ref(column, keyword))
    if copy !== nothing
        T = julia_type(LC.type(LC.keywordSet(copy), 0))
        finalize(copy)
        if T != eltype(value)
            keyword_element_type_error(keyword)
        end
    end
    return write_keyword!(table, value, column, keyword)
end

# Casacore.jl exposes no generic accessors for `TableRecord` fields, so keyword values are
# written and read with TaQL:
#
# * writing uses `ALTER TABLE \$1 SET KEYWORD name=value AS type` (the cast keeps the exact
#   element type, e.g. Int32 or Float32);
# * reading copies the keyword (`COPY KEYWORD`, which preserves its stored type) into a
#   scratch in-memory table, inspects its type there, and then selects its value.

"Index of a table keyword in the table's keyword set (-1 if it does not exist)."
keyword_index(table::Table, keyword::Keyword) =
    Int(LC.fieldNumber(LC.keywordSet(table.ref), LC.String(keyword.name)))

"Escape a column or keyword name for use in TaQL."
function taql_name(name::AbstractString)
    io = IOBuffer()
    for (i, c) in enumerate(name)
        if i == 1 && isletter(c)
            print(io, '\\', c) # protects against names that are TaQL reserved words
        elseif isascii(c) && (isletter(c) || isdigit(c) || c == '_')
            print(io, c)
        else
            print(io, '\\', c)
        end
    end
    return String(take!(io))
end

"TaQL reference to a table keyword (`column == \"\"`) or column keyword."
keyword_ref(column::AbstractString, keyword::Keyword) =
    (isempty(column) ? "" : taql_name(column)) * "::" * taql_name(keyword.name)

taql_literal(x::Bool) = x ? "T" : "F"
taql_literal(x::Integer) = string(x)
function taql_literal(x::AbstractFloat)
    isnan(x) && return "(1e400-1e400)"
    isinf(x) && return x > 0 ? "1e400" : "-1e400"
    return repr(Float64(x))
end
taql_literal(x::Complex) = "COMPLEX(" * taql_literal(real(x)) * ", " * taql_literal(imag(x)) * ")"
function taql_literal(x::AbstractString)
    # TaQL takes backslashes in string literals literally, but has no way to write a newline
    ('\n' in x || '\r' in x) && err("keyword strings containing newlines are not supported")
    '"' in x || return '"' * x * '"'
    '\'' in x || return "'" * x * "'"
    return join(('"' * part * '"' for part in split(x, '"')), " + '\"' + ")
end

taql_value(x::T) where {T} = taql_literal(x) * " AS " * type2taql[T]
function taql_value(x::Array{T}) where {T}
    isempty(x) && err("empty arrays cannot be stored as keywords")
    values = join((taql_literal(v) for v in x), ", ")
    shape = join(size(x), ", ")
    return "ARRAY([" * values * "], [" * shape * "]) AS " * type2taql[T]
end

function set_keyword!(table::Table, ref::String, value)
    command = "ALTER TABLE \$1 SET KEYWORD " * ref * " = " * taql_value(value)
    taql(command, table.ref) |> finalize
    return value
end

"Copy the referenced keyword into a scratch memory table as `TMP` (`nothing` if missing)."
function copy_keyword(table::Table, ref::String)
    scratch = LC.Table(LC.Memory)
    try
        taql("ALTER TABLE \$1 FROM \$2 t2 COPY KEYWORD TMP = t2." * ref, scratch, table.ref) |> finalize
    catch e
        finalize(scratch)
        # casacore reports a missing keyword as "Keyword t2.<ref> does not exist"
        e isa ErrorException && occursin("does not exist", e.msg) && return nothing
        rethrow()
    end
    return scratch
end

"Read the keyword `TMP` from a scratch table created by `copy_keyword`."
function read_scratch_keyword(scratch, ::Type{T}) where {T}
    Bool(LC.nrow(scratch) == 0) && LC.addRow(scratch, 1, true)
    result = taql("SELECT ::TMP AS VALUE FROM \$1", scratch)
    try
        col = CasacoreTables.Column(result, LC.String("VALUE"))
        try
            return convert_keyword(T, col[1])
        finally
            finalize(col.columnref)
        end
    finally
        finalize(result)
    end
end

# TaQL evaluates integers as Int64, reals as Float64 and complex numbers as ComplexF64; the
# conversion back to the stored type is exact.
convert_keyword(::Type{T}, value) where {T} = convert(T, value)
convert_keyword(::Type{Array{T}}, value) where {T} = convert(Array{T}, value)

function read_keyword(table::Table, keyword::Keyword, ::Type{T}, shape) where {T}
    copy = copy_keyword(table, keyword_ref("", keyword))
    copy === nothing && keyword_missing_error(keyword)
    try
        return read_scratch_keyword(copy, T)
    finally
        finalize(copy)
    end
end

function read_keyword(table::Table, column::String, keyword::Keyword, ::Type{T}, shape) where {T}
    copy = copy_keyword(table, keyword_ref(column, keyword))
    copy === nothing && keyword_missing_error(keyword)
    try
        return read_scratch_keyword(copy, T)
    finally
        finalize(copy)
    end
end

const KeywordValue = Union{typelist...,(Array{T} for T in typelist)...}

function write_keyword!(table::Table, value::KeywordValue, keyword::Keyword)
    iswritable(table) || table_readonly_error()
    return set_keyword!(table, keyword_ref("", keyword), value)
end

function write_keyword!(table::Table, value::KeywordValue, column::String, keyword::Keyword)
    return set_keyword!(table, keyword_ref(column, keyword), value)
end

function read_keyword(table::Table, keyword::Keyword, ::Type{Table}, shape)
    keywords = LC.keywordSet(table.ref)
    ref = LC.asTable(keywords, LC.RecordFieldId(LC.String(keyword.name)))
    path = String(LC.tableName(ref))
    return Table(path, table.status, ref)
end

@noinline unsupported_keyword_type(T) = err("unsupported keyword type $T")
write_keyword!(table::Table, value, keyword::Keyword) = unsupported_keyword_type(typeof(value))
write_keyword!(table::Table, value, column::String, keyword::Keyword) =
    unsupported_keyword_type(typeof(value))

function write_keyword!(table::Table, value::Table, keyword::Keyword)
    iswritable(table) || table_readonly_error()
    isopen(value) || table_closed_error()
    keywords = LC.rwKeywordSet(table.ref)
    LC.defineTable(keywords, LC.RecordFieldId(LC.String(keyword.name)), value.ref)
    return value
end
