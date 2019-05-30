import Base: setindex!, sizehint!, empty!, isempty, length, getindex, getkey, haskey, iterate, @propagate_inbounds, pop!, delete!, get, get!, isbitstype, in, isiterable, dict_with_eltype, KeySet, Callable

# the load factor arter which the dictionary `rehash` happens
const ROBIN_DICT_LOAD_FACTOR = 0.80

"""
    RobinDict([itr])

`RobinDict{K,V}()` constructs a hash table with keys of type `K` and values of type `V`.
Keys are compared with [`isequal`](@ref) and hashed with [`hash`](@ref).
Given a single iterable argument, constructs a [`RobinDict`](@ref) whose key-value pairs
are taken from 2-tuples `(key,value)` generated by the argument.

# Examples
```jldoctest
julia> RobinDict([("A", 1), ("B", 2)])
RobinDict{String,Int64} with 2 entries:
  "B" => 2
  "A" => 1
```

Alternatively, a sequence of pair arguments may be passed.

```jldoctest
julia> RobinDict("A"=>1, "B"=>2)
RobinDict{String,Int64} with 2 entries:
  "B" => 2
  "A" => 1
```
"""
mutable struct RobinDict{K,V} <: AbstractDict{K,V}
    #there is no need to maintain an table_size as an additional variable
    slots::Array{UInt8,1} # indicator, to be used later on
    keys::Array{K,1}
    vals::Array{V,1}
    dibs::Array{Int,1} # distance to initial bucket - critical for implementation
    count::Int
    totalcost::Int
    maxprobe::Int    # length of longest probe
    idxfloor::Int
    max_lf :: Float32

    function RobinDict{K, V}() where {K, V}
        n = 16 # default size of an empty Dict in Julia
        new(zeros(UInt, n), Vector{K}(undef, n), Vector{V}(undef, n), zeros(Int, n), 0, 0, 0, 0, 0)
    end

    function RobinDict{K, V}(d::RobinDict{K, V}) where {K, V}
        new(copy(d.slots), copy(d.keys), copy(d.vals), copy(d.dibs), d.count, d.totalcost, d.maxprobe, d.idxfloor, d.max_lf)
    end

    function RobinDict{K, V}(slots, keys, vals, dibs, count, totalcost, maxprobe, idxfloor, max_lf) where {K, V}
        new(slots, keys, dibs, vals, count, totalcost, maxprobe, idxfloor, max_lf)
    end
end

function RobinDict{K,V}(kv) where {K, V}
    h = RobinDict{K,V}()
    for (k,v) in kv
        h[k] = v
    end
    h
end
RobinDict{K,V}(p::Pair) where {K,V} = setindex!(RobinDict{K,V}(), p.second, p.first)
function RobinDict{K,V}(ps::Pair{K, V}...) where {K, V}
    h = RobinDict{K,V}()
    sizehint!(h, length(ps))
    for p in ps
        h[p.first] = p.second
    end
    return h
end

RobinDict() = RobinDict{Any,Any}()
RobinDict(kv::Tuple{}) = RobinDict()

RobinDict(kv::Tuple{Vararg{Pair{K,V}}}) where {K,V}       = RobinDict{K,V}(kv)
RobinDict(kv::Tuple{Vararg{Pair{K}}}) where {K}           = RobinDict{K,Any}(kv)
RobinDict(kv::Tuple{Vararg{Pair{K,V} where K}}) where {V} = RobinDict{Any,V}(kv)
RobinDict(kv::Tuple{Vararg{Pair}})                        = RobinDict{Any,Any}(kv)

RobinDict(kv::AbstractArray{Tuple{K,V}}) where {K,V} = RobinDict{K,V}(kv)
RobinDict(kv::AbstractArray{Pair{K,V}}) where {K,V}  = RobinDict{K,V}(kv)
RobinDict(kv::AbstractDict{K,V}) where {K,V} = RobinDict{K,V}(kv)

RobinDict(ps::Pair{K,V}...) where {K,V} = RobinDict{K,V}(ps)
RobinDict(ps::Pair{K}...,) where {K}             = RobinDict{K,Any}(ps)
RobinDict(ps::(Pair{K,V} where K)...,) where {V} = RobinDict{Any,V}(ps)
RobinDict(ps::Pair...) = RobinDict{Any,Any}(ps)

function RobinDict(kv)
    try
        dict_with_eltype(kv, eltype(kv))
    catch e
        if isempty(methods(iterate, (typeof(kv),))) ||
            !all(x->isa(x,Union{Tuple,Pair}),kv)
            throw(ArgumentError("RobinDict(kv): kv needs to be an iterator of tuples or pairs"))
        else
            rethrow(e)
        end
    end
end

dict_with_eltype(kv, ::Type{Tuple{K,V}}) where {K,V} = RobinDict{K,V}(kv)
dict_with_eltype(kv, ::Type{Pair{K,V}}) where {K,V} = RobinDict{K,V}(kv)
dict_with_eltype(kv, t) = RobinDict{Any,Any}(kv)

# default hashing scheme used by Julia
hashindex(key, sz) = (((hash(key)%Int) & (sz-1)) + 1)::Int

_tablesz(x::Integer) = x < 16 ? 16 : one(x)<<((sizeof(x)<<3)-leading_zeros(x-1))

# insert algorithm
function rh_insert!(h::RobinDict{K, V}, key::K, val::V) where {K, V}
    # table full
    if h.count == length(h.keys)
        return -1
    end
    ckey, cval, cdibs = key, val, 1
    sz = length(h.keys)
    index = hashindex(ckey, sz)
    @inbounds while true
    	if (h.slots[index] == 0x0) || (h.slots[index] == 0x1 && h.keys[index] == ckey)
    		break
    	end
        if h.dibs[index] < cdibs
            h.vals[index], cval = cval, h.vals[index]
            h.keys[index], ckey = ckey, h.keys[index]
            h.maxprobe = max(h.maxprobe, cdibs)
            h.dibs[index], cdibs = cdibs, h.dibs[index]
        end
        cdibs += 1
        h.totalcost += 1
        index = (index & (sz - 1)) + 1
    end
    
    
    @inbounds if h.slots[index] == 0x1 && h.keys[index] == ckey
        h.vals[index] = cval
        return index
    end

    @inbounds if h.slots[index] == 0x0
    	h.count += 1
    end

    @inbounds h.slots[index] = 0x1
    @inbounds h.vals[index] = cval
    @inbounds h.keys[index] = ckey
    
    @assert cdibs > 0
    @inbounds h.dibs[index] = cdibs
    
    h.totalcost += 1
    h.maxprobe = max(h.maxprobe, cdibs)
    if h.idxfloor == 0
        h.idxfloor = index
    else
        h.idxfloor = min(h.idxfloor, index)
    end
    return index
end

#same as rh_insert but totalcost doesn't increase here
function rh_insert_for_rehash!(h::RobinDict{K, V}, key::K, val::V) where {K, V}
    # table full
    if h.count == length(h.keys)
        return -1
    end
    ckey, cval, cdibs = key, val, 1
    sz = length(h.keys)
    index = hashindex(ckey, sz)
    @inbounds while true
        if (h.slots[index] == 0x0) || (h.slots[index] == 0x1 && h.keys[index] == ckey)
            break
        end
        if h.dibs[index] < cdibs
            h.vals[index], cval = cval, h.vals[index]
            h.keys[index], ckey = ckey, h.keys[index]
            h.maxprobe = max(h.maxprobe, cdibs)
            h.dibs[index], cdibs = cdibs, h.dibs[index]
        end
        cdibs += 1
        index = (index & (sz - 1)) + 1
    end
    
    @inbounds if h.slots[index] == 0x1 && h.keys[index] == ckey
        h.vals[index] = cval
        return index
    end

    @inbounds if h.slots[index] == 0x0
        h.count += 1
    end

    @inbounds h.slots[index] = 0x1
    @inbounds h.vals[index] = cval
    @inbounds h.keys[index] = ckey
    
    @assert cdibs > 0
    @inbounds h.dibs[index] = cdibs
    
    h.maxprobe = max(h.maxprobe, cdibs)
    if h.idxfloor == 0
        h.idxfloor = index
    else
        h.idxfloor = min(h.idxfloor, index)
    end
    return index
end

#rehash! algorithm
function rehash!(h::RobinDict{K,V}, newsz = length(h.keys)) where {K, V}
    olds = h.slots
    oldk = h.keys
    oldv = h.vals
    oldd = h.dibs
    sz = length(olds)
    newsz = _tablesz(newsz)
    h.totalcost += 1
    h.idxfloor = 1
    if h.count == 0
        resize!(h.slots, newsz)
        fill!(h.slots, 0)
        resize!(h.keys, sz)
        resize!(h.vals, sz)
        resize!(h.dibs, sz)
        h.count = 0
        h.maxprobe = 0
        h.totalcost = 0
        h.idxfloor = 0
        return h
    end

    h.slots = zeros(UInt8,newsz)
    h.keys = Vector{K}(undef, newsz)
    h.vals = Vector{V}(undef, newsz)
    h.dibs = Vector{Int}(undef, newsz)
    fill!(h.dibs, 0)
    totalcost0 = h.totalcost
    h.count = 0
    h.maxprobe = 0
    h.idxfloor = 0

    for i = 1:sz
        @inbounds if olds[i] == 0x1
            k = oldk[i]
            v = oldv[i]
            rh_insert_for_rehash!(h, k, v)
            if h.totalcost != totalcost0
                # if `h` is changed by a finalizer, retry
                return rehash!(h, newsz)
            end
        end
    end
    @assert h.totalcost == totalcost0
    return h
end

function sizehint!(d::RobinDict, newsz)
    newsz = _tablesz(newsz*2)  # *2 for keys and values in same array
    oldsz = length(d.keys)
    # grow at least 25%
    if newsz < (oldsz*5)>>2
        return d
    end
    rehash!(d, newsz)
end

@propagate_inbounds isslotempty(h::RobinDict{K, V}, i) where {K, V} = h.slots[i] == 0x0
@propagate_inbounds isslotfilled(h::RobinDict{K, V}, i) where {K, V} = h.slots[i] == 0x1

function setindex!(h::RobinDict{K,V}, v0, key0) where {K, V}
    key = convert(K, key0)
    isequal(key, key0) || throw(ArgumentError("$key0 is not a valid key for type $K"))
    _setindex!(h, key, v0)
end

function _setindex!(h::RobinDict{K,V}, key::K, v0) where {K, V}
    v = convert(V, v0)
    sz = length(h.keys)
    (h.count > ROBIN_DICT_LOAD_FACTOR * sz) && rehash!(h, h.count > 64000 ? h.count*2 : h.count*4)
    h.max_lf = max(h.max_lf, h.count / sz)
    index = rh_insert!(h, key, v)
    @assert index > 0
    h
end

isempty(d::RobinDict) = (d.count == 0)
length(d::RobinDict) = d.count

"""
    empty!(collection) -> collection

Remove all elements from a `collection`.

# Examples
```jldoctest
julia> A = RobinDict("a" => 1, "b" => 2)
RobinDict{String,Int64} with 2 entries:
  "b" => 2
  "a" => 1

julia> empty!(A);

julia> A
RobinDict{String,Int64} with 0 entries
```
"""
function empty!(h::RobinDict{K,V}) where {K, V}
    fill!(h.slots, 0x0)
    sz = length(h.slots)
    empty!(h.dibs)
    empty!(h.keys)
    empty!(h.vals)
    resize!(h.keys, sz)
    resize!(h.vals, sz)
    resize!(h.dibs, sz)
    h.count = 0
    h.maxprobe = 0
    h.totalcost = 0
    h.idxfloor = 0
    return h
end
 
function rh_search(h::RobinDict{K, V}, key::K) where {K, V}
	sz = length(h.keys)
	index = hashindex(key, sz)
	cdibs = 1
	while true
		if h.slots[index] == 0x0
			return -1
		elseif cdibs > h.dibs[index]
			return -1
		elseif h.keys[index] == key 
			return index
		end
		index = (index & (sz - 1)) + 1
	end
end

"""
    get!(collection, key, default)

Return the value stored for the given key, or if no mapping for the key is present, store
`key => default`, and return `default`.

# Examples
```jldoctest
julia> d = RobinDict("a"=>1, "b"=>2, "c"=>3);

julia> get!(d, "a", 5)
1

julia> get!(d, "d", 4)
4

julia> d
RobinDict{String,Int64} with 4 entries:
  "c" => 3
  "b" => 2
  "a" => 1
  "d" => 4
```
"""
get!(collection, key, default)

get!(h::RobinDict{K,V}, key0, default) where {K,V} = get!(()->default, h, key0)

"""
    get!(f::Function, collection, key)

Return the value stored for the given key, or if no mapping for the key is present, store
`key => f()`, and return `f()`.

This is intended to be called using `do` block syntax:
```julia
get!(dict, key) do
    # default value calculated here
    time()
end
```
"""
get!(f::Function, collection, key)

function get!(default::Callable, h::RobinDict{K,V}, key0) where {K, V}
    isa(convert(K, key0), MethodError) && throw(MethodError("Cannot `convert` an object of type $(typeof(key0)) to an object of type $K"))
    key = convert(K, key0)
    if !isequal(key, key0)
        throw(ArgumentError("$(limitrepr(key0)) is not a valid key for type $K"))
    end
    return _get!(default, h, key)
end

function _get!(default::Callable, h::RobinDict{K,V}, key::K) where V where K
    index = rh_search(h, key)
    
    index > 0 && return h.vals[index]

    v = convert(V, default())
    rh_insert!(h, key, v)
    return v
end

function getindex(h::RobinDict{K, V}, key0) where {K, V}
    key = convert(K, key0)
    index = rh_search(h, key)
    @inbounds return (index < 0) ? throw(KeyError(key)) : h.vals[index]
end

"""
    get(collection, key, default)

Return the value stored for the given key, or the given default value if no mapping for the
key is present.

# Examples
```jldoctest
julia> d = RobinDict("a"=>1, "b"=>2);

julia> get(d, "a", 3)
1

julia> get(d, "c", 3)
3
```
"""
get(collection, key, default)

function get(h::RobinDict{K,V}, key0, default) where {K, V}
    isa(convert(K, key0), MethodError) && throw(MethodError("Cannot `convert` an object of type $(typeof(key0)) to an object of type $K"))
    key = convert(K, key0)
    if !isequal(key, key0)
        throw(ArgumentError("$(limitrepr(key0)) is not a valid key for type $K"))
    end
    index = rh_search(h, key)
    @inbounds return (index < 0) ? default : h.vals[index]::V
end

"""
    get(f::Function, collection, key)

Return the value stored for the given key, or if no mapping for the key is present, return
`f()`.  Use [`get!`](@ref) to also store the default value in the dictionary.

This is intended to be called using `do` block syntax

```julia
get(dict, key) do
    # default value calculated here
    time()
end
```
"""
get(::Function, collection, key)

function get(default::Callable, h::RobinDict{K,V}, key0) where {K, V}
    isa(convert(K, key0), MethodError) && throw(MethodError("Cannot `convert` an object of type $(typeof(key0)) to an object of type $K"))
    key = convert(K, key0) 
    if !isequal(key, key0)
        throw(ArgumentError("$(limitrepr(key0)) is not a valid key for type $K"))
    end
    index = rh_search(h, key)
    @inbounds return (index < 0) ? default() : h.vals[index]::V
end

"""
    haskey(collection, key) -> Bool

Determine whether a collection has a mapping for a given `key`.

# Examples
```jldoctest
julia> D = RobinDict('a'=>2, 'b'=>3)
RobinDict{Char,Int64} with 2 entries:
  'a' => 2
  'b' => 3

julia> haskey(D, 'a')
true

julia> haskey(D, 'c')
false
```
"""
haskey(h::RobinDict, key) = (rh_search(h, key) > 0) 
in(key, v::KeySet{<:Any, <:RobinDict}) = (rh_search(v.dict, key) >= 0)

"""
    getkey(collection, key, default)

Return the key matching argument `key` if one exists in `collection`, otherwise return `default`.

# Examples
```jldoctest
julia> D = RobinDict('a'=>2, 'b'=>3)
RobinDict{Char,Int64} with 2 entries:
  'a' => 2
  'b' => 3

julia> getkey(D, 'a', 1)
'a': ASCII/Unicode U+0061 (category Ll: Letter, lowercase)

julia> getkey(D, 'd', 'a')
'a': ASCII/Unicode U+0061 (category Ll: Letter, lowercase)
```
"""
function getkey(h::RobinDict{K,V}, key0, default) where {K, V}
    isa(convert(K, key0), MethodError) && throw(MethodError("Cannot `convert` an object of type $(typeof(key0)) to an object of type $K"))
    key = convert(K, key0) 
    if !isequal(key, key0)
        throw(ArgumentError("$(limitrepr(key0)) is not a valid key for type $K"))
    end
    index = rh_search(h, key)
    @inbounds return (index < 0) ? default : h.keys[index]::K
end

# backward shift deletion by not keeping any tombstones
function rh_delete!(h::RobinDict{K, V}, index) where {K, V}
    #forceful
    (index < 0) && return false;

    #this assumes that  the key is present in the dictionary at index 
    index0 = index
    sz = length(h.keys)
    while true
        index0 = (index0 & (sz - 1)) + 1
        if h.slots[index0] == 0x0 || h.slots[index0] == 0x1 && h.dibs[index0] == 1
            break
        end
    end
    #index0 represents the position before which we have to shift backwards 
    
    # the backwards shifting algorithm
    curr = index
    next = (index & (sz - 1)) + 1
    
    while next != index0 
        if h.dibs[next] > 1
            h.slots[curr] = 0x1
            h.vals[curr] = h.vals[next]
            h.keys[curr] = h.keys[next]
            h.dibs[curr] = (h.dibs[next] - 1)
            curr = next
            next = (next & (sz-1)) + 1
        else
            break
        end
    end
    
    #curr is at the last position, reset back to normal
    if (h.slots[curr] == 0x1)
        h.slots[curr] = 0x0
        ccall(:jl_arrayunset, Cvoid, (Any, UInt), h.keys, curr-1)
        ccall(:jl_arrayunset, Cvoid, (Any, UInt), h.vals, curr-1)
        h.dibs[curr] = 0
    end

    h.count -= 1
    h.totalcost += 1
    # this is necessary because key at idxfloor might get deleted 
    h.idxfloor = get_idxfloor(h)
    return h
end

function _pop!(h::RobinDict, index)
    @inbounds val = h.vals[index]
    rh_delete!(h, index)
    return val
end

function pop!(h::RobinDict{K, V}, key0) where {K, V}
    isa(convert(K, key0), MethodError) && throw(MethodError("Cannot `convert` an object of type $(typeof(key0)) to an object of type $K"))
    key = convert(K, key0) 
    if !isequal(key, key0)
        throw(ArgumentError("$(limitrepr(key0)) is not a valid key for type $K"))
    end
    index = rh_search(h, key)
    return index > 0 ? _pop!(h, index) : throw(KeyError(key))
end

"""
    pop!(collection, key[, default])

Delete and return the mapping for `key` if it exists in `collection`, otherwise return
`default`, or throw an error if `default` is not specified.

# Examples
```jldoctest
julia> d = RobinDict("a"=>1, "b"=>2, "c"=>3);

julia> pop!(d, "a")
1

julia> pop!(d, "d")
ERROR: KeyError: key "d" not found
Stacktrace:
[...]

julia> pop!(d, "e", 4)
4
```
"""
pop!(collection, key, default)

function pop!(h::RobinDict{K, V}, key0, default) where {K, V}
    isa(convert(K, key0), MethodError) && throw(MethodError("Cannot `convert` an object of type $(typeof(key0)) to an object of type $K"))
    key = convert(K, key0) 
    if !isequal(key, key0)
        throw(ArgumentError("$(limitrepr(key0)) is not a valid key for type $K"))
    end
    index = rh_search(h, key)
    return index > 0 ? _pop!(h, index) : default
end

function pop!(h::RobinDict)
    isempty(h) && throw(ArgumentError("dict must be non-empty"))
    idx = h.idxfloor
    @inbounds key = h.keys[idx]
    @inbounds val = h.vals[idx]
    rh_delete!(h, idx)
    key => val
end

"""
    delete!(collection, key)

Delete the mapping for the given key in a collection, and return the collection.

# Examples
```jldoctest
julia> d = RobinDict("a"=>1, "b"=>2)
RobinDict{String,Int64} with 2 entries:
  "b" => 2
  "a" => 1

julia> delete!(d, "b")
RobinDict{String,Int64} with 1 entry:
  "a" => 1
```
"""
function delete!(h::RobinDict{K, V}, key0) where {K, V}
    isa(convert(K, key0), MethodError) && throw(MethodError("Cannot `convert` an object of type $(typeof(key0)) to an object of type $K"))
    key = convert(K, key0) 
    if !isequal(key, key0)
        throw(ArgumentError("$(limitrepr(key0)) is not a valid key for type $K"))
    end
    index = rh_search(h, key)
    if index > 0
        rh_delete!(h, index)
    end
    return h
end

function get_idxfloor(h::RobinDict)
    @inbounds for i = 1 : length(h.slots)
        if h.slots[i] == 0x1
            return i
        end
    end
    return 0
end

function get_next_filled(h::RobinDict, i)
    L = length(h.slots)
    (1 <= i <= L) || return 0 
    for j = i:L
        @inbounds if h.slots[j] == 0x1
            return  j
        end
    end
    return 0
end

@propagate_inbounds _iterate(t::RobinDict{K,V}, i) where {K,V} = i == 0 ? nothing : (Pair{K,V}(t.keys[i],t.vals[i]), i == typemax(Int) ? 0 : get_next_filled(t, i+1))
@propagate_inbounds function iterate(t::RobinDict)
    _iterate(t, t.idxfloor)
end
@propagate_inbounds iterate(t::RobinDict, i) = _iterate(t, get_next_filled(t, i))
