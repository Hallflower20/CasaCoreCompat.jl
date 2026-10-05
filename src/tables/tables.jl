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

@noinline table_exists_error() = err("Table already exists.")
@noinline table_does_not_exist_error() = err("Table does not exist.")
@noinline table_readonly_error() = err("Table is read-only.")
@noinline table_closed_error() = err("Table is closed.")

@enum TableStatus closed = 0 readonly = 1 readwrite = 5

"""
    mutable struct Table

This type is used to interact with CasaCore tables (including measurement sets).

**Fields:**

- `path` - the path to the table
- `status` - the current status of the table
- `ref` - the Casacore.jl (CxxWrap) handle of the open table, or `nothing` once closed

**Usage:**

```jldoctest
julia> table = Tables.create("/tmp/my-table.ms")
Table: /tmp/my-table.ms (read/write)

julia> Tables.add_rows!(table, 3)
3

julia> table["DATA"] = ComplexF64[1+2im, 3+4im, 5+6im]
3-element Array{Complex{Float32},1}:
 1.0+2.0im
 3.0+4.0im
 5.0+6.0im

julia> Tables.close(table)
closed::CasaCore.Tables.TableStatus = 0

julia> table = Tables.open("/tmp/my-table.ms")
Table: /tmp/my-table.ms (read-only)

julia> table["DATA"]
3-element Array{Complex{Float32},1}:
 1.0+2.0im
 3.0+4.0im
 5.0+6.0im

julia> Tables.delete(table)
```

**See also:** [`Tables.create`](@ref), [`Tables.open`](@ref), [`Tables.close`](@ref),
[`Tables.delete`](@ref)
"""
mutable struct Table
    path::String
    status::TableStatus
    ref::Any # Casacore.jl `LibCasacore.Table` handle, or `nothing` when closed
    function Table(path, status, ref)
        table = new(path, status, ref)
        # The C++ table object is deleted by CxxWrap's own finalizer once `ref` is unreachable.
        finalizer(t -> (t.status = closed; t.ref = nothing), table)
        return table
    end
end

"""
    create(path)

Create a CasaCore table at the given path.

**Arguments:**

- `path` - the path where the table will be created

**Usage:**

```jldoctest
julia> table = Tables.create("/tmp/my-table.ms")
Table: /tmp/my-table.ms (read/write)

julia> Tables.delete(table)
```

**See also:** [`Tables.open`](@ref), [`Tables.close`](@ref), [`Tables.delete`](@ref)
"""
function create(path)
    path = table_fix_path(path)
    if isfile(path) || isdir(path)
        table_exists_error()
    end
    ref = LC.Table(LC.Plain)
    LC.rename(ref, LC.String(path), Int(CasacoreTables.New))
    LC.flush(ref, false, true) # make sure the table exists on disk (subtables may follow)
    return Table(path, readwrite, ref)
end

"""
    open(path; write=false)

Open the CasaCore table at the given path.

**Arguments:**

- `path` - the path to the table that will be opened

**Keyword Arguments:**

- `write` - if `false` (the default) the table will be opened read-only

**Usage:**

```jldoctest
julia> table = Tables.create("/tmp/my-table.ms")
Table: /tmp/my-table.ms (read/write)

julia> table′ = Tables.open("/tmp/my-table.ms")
Table: /tmp/my-table.ms (read-only)

julia> table″ = Tables.open("/tmp/my-table.ms", write=true)
Table: /tmp/my-table.ms (read/write)

julia> Tables.close(table′)
       Tables.close(table″)
       Tables.delete(table)
```

**See also:** [`Tables.create`](@ref), [`Tables.close`](@ref), [`Tables.delete`](@ref)
"""
function open(path; write=false)
    path = table_fix_path(path)
    if !isdir(path)
        table_does_not_exist_error()
    end
    mode = write ? readwrite : readonly
    ref = LC.Table(LC.String(path), Int(mode))
    return Table(path, mode, ref)
end

function open(table::Table; write=false)
    if !isopen(table)
        path = table_fix_path(table.path)
        if !isdir(path)
            table_does_not_exist_error()
        end
        mode = write ? readwrite : readonly
        ref = LC.Table(LC.String(path), Int(mode))
        table.path = path
        table.status = mode
        table.ref = ref
    end
    return table
end

"""
    close(table)

Close the given CasaCore table.

**Arguments:**

- `table` - the table to be closed

**Usage:**

```jldoctest
julia> table = Tables.create("/tmp/my-table.ms")
Table: /tmp/my-table.ms (read/write)

julia> Tables.close(table)
closed::CasaCore.Tables.TableStatus = 0

julia> Tables.delete(table)
```

**See also:** [`Tables.create`](@ref), [`Tables.open`](@ref), [`Tables.delete`](@ref)
"""
function close(table::Table)
    if isopen(table)
        ref = table.ref
        table.ref = nothing
        table.status = closed
        # delete the C++ object now (this writes the table to disk and releases its lock)
        ref === nothing || finalize(ref)
    end
    return table.status
end

"""
    delete(table)

Close and delete the given CasaCore table.

**Arguments:**

- `table` - the table to be deleted

**Usage:**

```jldoctest
julia> table = Tables.create("/tmp/my-table.ms")
Table: /tmp/my-table.ms (read/write)

julia> Tables.delete(table)
```

**See also:** [`Tables.create`](@ref), [`Tables.open`](@ref), [`Tables.create`](@ref)
"""
function delete(table::Table)
    close(table)
    return rm(table.path; recursive=true, force=true)
end

isopen(table::Table) = table.status != closed
iswritable(table::Table) = table.status == readwrite

function table_fix_path(path)
    # Remove the "Table: " prefix, if it exists
    if startswith(path, "Table: ")
        path = path[8:end]
    end
    # Expand a tilde to the home directory
    path = expanduser(path)
    # Normalize "." and ".."
    return path = normpath(path)
end

function Base.show(io::IO, table::Table)
    if table.status == closed
        str = " (closed)"
    elseif table.status == readonly
        str = " (read-only)"
    elseif table.status == readwrite
        str = " (read/write)"
    end
    return print(io, "Table: ", table.path, str)
end

"""
    Tables.unlock(table)

Release the lock held on the given table (and flush its contents to disk) so that other
processes can access it.
"""
function unlock(table::Table)
    isopen(table) || table_closed_error()
    LC.unlock(table.ref)
    return nothing
end

"""
    Tables.lock(table; writelock = true, attempts = 5)

Lock the given table.

Casacore.jl does not expose casacore's `Table::lock`, so this is a no-op: tables are opened with
casacore's default *auto-locking* mode, in which the lock is re-acquired automatically the next
time the table is read or written after [`Tables.unlock`](@ref).
"""
function lock(table::Table; writelock::Bool=true, attempts::Int=5)
    isopen(table) || table_closed_error()
    return nothing
end
