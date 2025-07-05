# Top-level test types for this file
@kvstore MutableTest begin
    arr::Vector{Int} => [1,2,3]
end

@kvstore MultiMutableTest begin
    a::Vector{Int} => [1]
    b::Vector{Int} => [2]
end

function test_key_value_basics()
    # Test default constructor
    t = TestBasic()
    
    # Test setting and getting keys
    @test StaticKV.setkey!(t, "Alice", :name) == "Alice"
    @test StaticKV.getkey(t, :name) == "Alice"
    
    # Test default values
    @test StaticKV.getkey(t, :age) == 0
    
    # Test isset functionality
    @test isset(t, :name) == true
    @test isset(t, :age) == true
    @test isset(t, :optional) == false
    
    # Test allkeysset
    @test allkeysset(t) == false
    StaticKV.setkey!(t, 3.14, :optional)
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
    @test_throws ErrorException StaticKV.getkey(t, :nonexistent)
    @test_throws ErrorException StaticKV.setkey!(t, "value", :nonexistent)
    @test isset(t, :nonexistent) == false
    @test keytype(t, :nonexistent) === nothing
    
    # Test error for accessing unset key
    t2 = TestBasic()
    @test_throws ErrorException StaticKV.getkey(t2, :name)

    @testset "with_key! does not mutate isbits in-place" begin
        StaticKV.setkey!(t, 100, :age)
        @test_throws ErrorException with_key!(t, :age) do val
            val + 23
        end
    end

    @testset "with_key! mutates mutable key in-place" begin
        mt = MutableTest()
        StaticKV.setkey!(mt, [1,2,3], :arr)
        result = with_key!(mt, :arr) do vec
            push!(vec, 99)
            vec
        end
        @test result == [1,2,3,99]
        @test StaticKV.getkey(mt, :arr) == [1,2,3,99]
    end


end
