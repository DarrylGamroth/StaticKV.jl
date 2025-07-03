# Top-level test types for this file
@kvstore MutableTest begin
    arr::Vector{Int} => (value => [1,2,3])
end

@kvstore MultiMutableTest begin
    a::Vector{Int} => (value => [1])
    b::Vector{Int} => (value => [2])
end

function test_key_value_basics()
    # Test default constructor
    t = TestBasic()
    
    # Test setting and getting keys
    @test setkey!(t, :name, "Alice") == "Alice"
    @test getkey(t, :name) == "Alice"
    
    # Test default values
    @test getkey(t, :age) == 0
    
    # Test isset functionality
    @test isset(t, :name) == true
    @test isset(t, :age) == true
    @test isset(t, :optional) == false
    
    # Test allkeysset
    @test allkeysset(t) == false
    setkey!(t, :optional, 3.14)
    @test allkeysset(t) == true
    
    # Test key type information
    @test keytype(t, :name) === String
    @test keytype(t, :age) === Int
    @test keytype(t, :optional) === Float64
    
    # Test key type from type (not instance)
    @test keytype(TestBasic, :name) === String
    @test keytype(TestBasic, :age) === Int
    @test keytype(TestBasic, :optional) === Float64
    
    # Test error handling for non-existent keys
    @test_throws ErrorException getkey(t, :nonexistent)
    @test_throws ErrorException setkey!(t, :nonexistent, "value")
    @test isset(t, :nonexistent) == false
    @test keytype(t, :nonexistent) === nothing
    
    # Test error for accessing unset key
    t2 = TestBasic()
    @test_throws ErrorException getkey(t2, :name)

    @testset "with_key! does not mutate isbits in-place" begin
        setkey!(t, :age, 100)
        @test_throws ErrorException with_key!(t, :age) do val
            val + 23
        end
    end

    @testset "with_key! mutates mutable key in-place" begin
        mt = MutableTest()
        setkey!(mt, :arr, [1,2,3])
        result = with_key!(mt, :arr) do vec
            push!(vec, 99)
            vec
        end
        @test result == [1,2,3,99]
        @test getkey(mt, :arr) == [1,2,3,99]
    end


end
