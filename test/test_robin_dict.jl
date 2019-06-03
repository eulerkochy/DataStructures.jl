
@testset "Constructors" begin
    h1 = RobinDict()
    @test length(h1) == 0
    @test isempty(h1) == true
    @test h1.totalcost == 0
    @test h1.idxfloor == 0
    @test length(h1.keys) == 16
    @test length(h1.vals) == 16
    @test length(h1.dibs) == 16
    @test eltype(h1) == Pair{Any, Any}
    @test keytype(h1) == Any
    @test valtype(h1) == Any
end

@testset "RobinDict" begin
    h = RobinDict()
    for i=1:10000
        h[i] = i+1
    end
    for i=1:10000
        @test (h[i] == i+1)
    end
    for i=1:2:10000
        delete!(h, i)
    end
    for i=1:2:10000
        h[i] = i+1
    end
    for i=1:10000
        @test (h[i] == i+1)
    end
    for i=1:10000
        delete!(h, i)
    end
    @test isempty(h)
    h[77] = 100
    @test h[77] == 100
    for i=1:10000
        h[i] = i+1
    end
    for i=1:2:10000
        delete!(h, i)
    end
    for i=10001:20000
        h[i] = i+1
    end
    for i=2:2:10000
        @test h[i] == i+1
    end
    for i=10000:20000
        @test h[i] == i+1
    end
    h = RobinDict{Any,Any}("a" => 3)
    @test h["a"] == 3
    h["a","b"] = 4
    @test h["a","b"] == h[("a","b")] == 4
    h["a","b","c"] = 4
    @test h["a","b","c"] == h[("a","b","c")] == 4

    @testset "eltype, keytype and valtype" begin
        @test eltype(h) == Pair{Any,Any}
        @test keytype(h) == Any
        @test valtype(h) == Any

        td = RobinDict{AbstractString,Float64}()
        @test eltype(td) == Pair{AbstractString,Float64}
        @test keytype(td) == AbstractString
        @test valtype(td) == Float64
        @test keytype(Dict{AbstractString,Float64}) === AbstractString
        @test valtype(Dict{AbstractString,Float64}) === Float64
    end
    # test rethrow of error in ctor
    @test_throws DomainError RobinDict((sqrt(p[1]), sqrt(p[2])) for p in zip(-1:2, -1:2))
end

@testset "RobinDict on pairs" begin
	let x = RobinDict(3=>3, 5=>5, 8=>8, 6=>6)
	    pop!(x, 5)
	    for k in keys(x)
	        RobinDict{Int,Int}(x)
	        @test k in [3, 8, 6]
	    end
	end
end

@testset "KeyError" begin
    let z = RobinDict()
        get_KeyError = false
        try
            z["a"]
        catch _e123_
            get_KeyError = isa(_e123_,KeyError)
        end
        @test get_KeyError
    end
end

@testset "Filter function" begin
    _d = RobinDict("a"=>0)
    @test isa([k for k in filter(x->length(x)==1, collect(keys(_d)))], Vector{String})
end

@testset "typeof" begin
    d = RobinDict(((1, 2), (3, 4)))
    @test d[1] === 2
    @test d[3] === 4
    d2 = RobinDict(1 => 2, 3 => 4)
    d3 = RobinDict((1 => 2, 3 => 4))
    @test d == d2 == d3
    @test typeof(d) == typeof(d2) == typeof(d3) == RobinDict{Int,Int}

    d = RobinDict(((1, 2), (3, "b")))
    @test d[1] === 2
    @test d[3] == "b"
    d2 = RobinDict(1 => 2, 3 => "b")
    d3 = RobinDict((1 => 2, 3 => "b"))
    @test d == d2 == d3
    @test typeof(d) == typeof(d2) == typeof(d3) == RobinDict{Int,Any}

    d = RobinDict(((1, 2), ("a", 4)))
    @test d[1] === 2
    @test d["a"] === 4
    d2 = RobinDict(1 => 2, "a" => 4)
    d3 = RobinDict((1 => 2, "a" => 4))
    @test d == d2 == d3
    @test typeof(d) == typeof(d2) == typeof(d3) == RobinDict{Any,Int}

    d = RobinDict(((1, 2), ("a", "b")))
    @test d[1] === 2
    @test d["a"] == "b"
    d2 = RobinDict(1 => 2, "a" => "b")
    d3 = RobinDict((1 => 2, "a" => "b"))
    @test d == d2 == d3
    @test typeof(d) == typeof(d2) == typeof(d3) == RobinDict{Any,Any}
end

@testset "type of RobinDict constructed from varargs of Pairs" begin
    @test RobinDict(1=>1, 2=>2.0) isa RobinDict{Int,Any}
    @test RobinDict(1=>1, 2.0=>2) isa RobinDict{Any,Int}
    @test RobinDict(1=>1.0, 2.0=>2) isa RobinDict{Any,Any}

    for T in (Nothing, Missing)
        @test RobinDict(1=>1, 2=>T()) isa RobinDict{Int,Any}
        @test RobinDict(1=>T(), 2=>2) isa RobinDict{Int,Any}
        @test RobinDict(1=>1, T()=>2) isa RobinDict{Any,Int}
        @test RobinDict(T()=>1, 2=>2) isa RobinDict{Any,Int}
    end
end

@testset "equality" for eq in (isequal, ==)
    @test  eq(RobinDict(), RobinDict())
    @test  eq(RobinDict(1 => 1), RobinDict(1 => 1))
    @test !eq(RobinDict(1 => 1), RobinDict())
    @test !eq(RobinDict(1 => 1), RobinDict(1 => 2))
    @test !eq(RobinDict(1 => 1), RobinDict(2 => 1))

    # Generate some data to populate dicts to be compared
    data_in = [ (rand(1:1000), randstring(2)) for _ in 1:1001 ]

    # Populate the first dict
    d1 = RobinDict{Int, AbstractString}()
    for (k, v) in data_in
        d1[k] = v
    end
    data_in = collect(d1)
    # shuffle the data
    for i in 1:length(data_in)
        j = rand(1:length(data_in))
        data_in[i], data_in[j] = data_in[j], data_in[i]
    end
    # Inserting data in different (shuffled) order should result in
    # equivalent dict.
    d2 = RobinDict{Int, AbstractString}()
    for (k, v) in data_in
        d2[k] = v
    end

    @test eq(d1, d2)
    d3 = copy(d2)
    d4 = copy(d2)
    # Removing an item gives different dict
    delete!(d1, data_in[rand(1:length(data_in))][1])
    @test !eq(d1, d2)
    # Changing a value gives different dict
    d3[data_in[rand(1:length(data_in))][1]] = randstring(3)
    !eq(d1, d3)
    # Adding a pair gives different dict
    d4[1001] = randstring(3)
    @test !eq(d1, d4)

    @test eq(RobinDict(), sizehint!(RobinDict(),96))

    # Dictionaries of different types
    @test_throws MethodError eq(RobinDict(1 => 2), RobinDict("dog" => "bone"))
    @test eq(RobinDict{Int,Int}(), RobinDict{AbstractString,AbstractString}())
end

@testset "equality special cases" begin
    @test RobinDict(1=>0.0) == RobinDict(1=>-0.0)
    @test !isequal(RobinDict(1=>0.0), RobinDict(1=>-0.0))

    @test RobinDict(0.0=>1) != RobinDict(-0.0=>1)
    @test !isequal(RobinDict(0.0=>1), RobinDict(-0.0=>1))

    @test RobinDict(1=>NaN) != RobinDict(1=>NaN)
    @test isequal(RobinDict(1=>NaN), RobinDict(1=>NaN))

    # @test RobinDict(NaN=>1) == RobinDict(NaN=>1)
    # @test isequal(RobinDict(NaN=>1), RobinDict(NaN=>1))

    @test ismissing(RobinDict(1=>missing) == RobinDict(1=>missing))
    @test isequal(RobinDict(1=>missing), RobinDict(1=>missing))

    # @test RobinDict(missing=>1) == RobinDict(missing=>1)
    # @test isequal(RobinDict(missing=>1), RobinDict(missing=>1))
end

@testset "get!" begin 
    f(x) = x^2
    d = RobinDict(8=>19)
    @test get!(d, 8, 5) == 19
    @test get!(d, 19, 2) == 2

    @test get!(d, 42) do  # d is updated with f(2)
        f(2)
    end == 4

    @test get!(d, 42) do  # d is not updated
        f(200)
    end == 4

    @test get(d, 13) do   # d is not updated
        f(4)
    end == 16

    @test d == RobinDict(8=>19, 19=>2, 42=>4)
end

@testset "push!" begin
    d = RobinDict()
    @test push!(d, 'a' => 1) === d
    @test d['a'] == 1
    @test push!(d, 'b' => 2, 'c' => 3) === d
    @test d['b'] == 2
    @test d['c'] == 3
    @test push!(d, 'd' => 4, 'e' => 5, 'f' => 6) === d
    @test d['d'] == 4
    @test d['e'] == 5
    @test d['f'] == 6
    @test length(d) == 6
end

@testset "pop!" begin
    d = RobinDict(1=>2, 3=>4)
    @test pop!(d, 1) == 2
    @test_throws KeyError pop!(d, 1)
    @test pop!(d, 1, 0) == 0
    @test pop!(d) == (3=>4)
    @test_throws ArgumentError pop!(d)
end

@testset "keys as a set" begin
    d = RobinDict(1=>2, 3=>4)
    @test keys(d) isa AbstractSet
    @test empty(keys(d)) isa AbstractSet
    let i = keys(d) ∩ Set([1,2])
        @test i isa AbstractSet
        @test i == Set([1])
    end
    @test Set(string(k) for k in keys(d)) == Set(["1","3"])
end

@testset "find" begin
    @test findall(isequal(1), RobinDict(:a=>1, :b=>2)) == [:a]
    @test sort(findall(isequal(1), RobinDict(:a=>1, :b=>1))) == [:a, :b]
    @test isempty(findall(isequal(1), RobinDict()))
    @test isempty(findall(isequal(1), RobinDict(:a=>2, :b=>3)))

    @test findfirst(isequal(1), RobinDict(:a=>1, :b=>2)) == :a
    @test findfirst(isequal(1), RobinDict(:a=>1, :b=>1, :c=>3)) in (:a, :b)
    @test findfirst(isequal(1), RobinDict()) === nothing
    @test findfirst(isequal(1), RobinDict(:a=>2, :b=>3)) === nothing
end

@testset "haskey" begin
    h = RobinDict(1=>2, 2=>3)
    @test haskey(h, 1) == true
    @test haskey(h, 2) == true
    @test haskey(h, 3) == false
end

@testset "empty" begin
    h = RobinDict()
    for i=1:1000
        h[i] = i+1
    end
    length0 = length(h.dibs)
    empty!(h)
    @test h.count == 0
    @test h.maxprobe == 0
    @test h.idxfloor == 0
    @test h.totalcost == 0
    @test length(h.dibs) == length(h.keys) == length(h.vals) == length0
end