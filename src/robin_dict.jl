import Base: setindex!, sizehint!, empty!, isempty, length

mutable struct RobinDict{K,V} <: AbstractDict{K,V}
    #there is no need to maintain an table_size as an additional variable
    slots::Array{UInt8,1} # indicator, to be used later on
    keys::Array{K,1}
    vals::Array{V,1}
    dibs::Array{Int,1} # distance to initial bucket - critical for implementation
    count::Int
    totalcost::Int
    maxprobe::Int    # length of longest probe
    
    function RobinDict{K, V}() where {K, V}
        n = 16 # default size of an empty Dict in Julia
        new(zeros(UInt, n), Vector{K}(undef, n), Vector{V}(undef, n), zeros(Int, n), 0, 0, 0)
    end

    function RobinDict{K, V}(d::RobinDict{K, V}) where {K, V}
        new(copy(d.slots), copy(d.keys), copy(d.vals), copy(d.dibs), d.count, d.totalcost, d.maxprobe)
    end
    
    function RobinDict{K, V}(slots, keys, vals, dibs, count, totalcost, maxprobe) where {K, V}
        new(slots, keys, dibs, vals, count, totalcost, maxprobe)
    end     
end

function RobinDict{K,V}(kv) where {K, V}
    h = RobinDict{K,V}()
    for (k,v) in kv
        h[k] = v
    end
    h
end
RobinDict{K,V}(p::Pair) where {K,V} = setindex!(Dict{K,V}(), p.second, p.first)
function RobinDict{K,V}(ps::Pair...) where {K, V}
    h = RobinDict{K,V}()
#     sizehint!(h, length(ps))
    for p in ps
        h[p.first] = p.second
    end
    return h
end

RobinDict() = RobinDict{Any,Any}()

# default hashing scheme used by Julia
hashindex(key, sz) = (((hash(key)%Int) & (sz-1)) + 1)::Int

# insert algorithm 
function rh_insert!(h::RobinDict{K, V}, key, val) where {K, V}
    # table full
    if h.count == size(h.keys)[1] 
        return -1
    end
    
    ckey, cval, cdibs = key, val, 0 
    sz = size(h.keys)[1]
    index = hashindex(key, sz) # this is going to be critical
    @inbounds while h.slots[index] != 0x0
        if h.dibs[index] < cdibs
            h.vals[index], cval = cval, h.vals[index]
            h.keys[index], ckey = ckey, h.keys[index]
            h.dibs[index], cdibs = cdibs, h.dibs[index]
        end
        cdibs += 1
        index = (index & (sz - 1)) + 1
    end
    println("Successfully inserted at $index")
    @inbounds h.slots[index] = 0x1
    @inbounds h.vals[index] = cval
    @inbounds h.keys[index] = ckey
    @inbounds h.dibs[index] = cdibs
    h.count += 1
    return index
end
    
function setindex!(h::RobinDict{K,V}, v0, key0) where V where K
    key = convert(K, key0)
    isequal(key, key0) || throw(ArgumentError("$key0 is not a valid key for type $K"))
    _setindex!(h, v0, key)
end

function _setindex!(h::RobinDict{K,V}, v0::V, key::K) where V where K
    v = convert(V, v0)
    index = rh_insert!(h, key, v)
    if index > 0
        println("Successfully inserted at $index")
    else
        throw(error("Dictionary table full"))
    end
    h
end

isempty(d::RobinDict) = (d.count == 0)
length(d::RobinDict) = d.count
