using BenchmarkTools, Random, DataStructures, Printf

include("../src/robin_dict.jl")

function add_entries(h::AbstractDict, entries::Vector{Pair{K, V}}) where {K, V}
	for (k, v) in entries
		h[k] = v
	end
end

sample1 = rand(Int, 10^6, 2)
entries1 = Vector{Pair{Int, Int}}()
sizehint!(entries1, 10^6)
for i = 1 : 10^6
	push!(entries1, Pair{Int, Int}(sample1[i, 1], sample1[i, 2]))
end

@printf("	add_entries for RobinDict()\n")
@btime add_entries(RobinDict(), entries1)

@printf("	add_entries for RobinDict{Int, Int}()\n")
@btime add_entries(RobinDict{Int, Int}(), entries1)

@printf("	add_entries for Dict()\n")
@btime add_entries(Dict(), entries1)

@printf("	add_entries for Dict{Int, Int}()\n")
@btime add_entries(Dict{Int, Int}(), entries1)

@printf(".\n.\n")

sample2 = rand(Float32, 10^6, 2)
entries2 = Vector{Pair{Float32, Float32}}()
sizehint!(entries2, 10^6)
for i = 1 : 10^6
	push!(entries2, Pair{Float32, Float32}(sample1[i, 1], sample1[i, 2]))
end

@printf("	add_entries for RobinDict()\n")
@btime add_entries(RobinDict(), entries2)

@printf("	add_entries for RobinDict{Float32, Float32}()\n")
@btime add_entries(RobinDict{Float32, Float32}(), entries2)

@printf("	add_entries for Dict()\n")
@btime add_entries(Dict(), entries2)

@printf("	add_entries for Dict{Float32, Float32}()\n")
@btime add_entries(Dict{Float32, Float32}(), entries2)




