# Top-level test types for this file
@properties MutableTest begin
    arr::Vector{Int} => (value => [1,2,3])
end

@properties MultiMutableTest begin
    a::Vector{Int} => (value => [1])
    b::Vector{Int} => (value => [2])
end

function test_property_basics()
    # Test default constructor
    t = TestBasic()
    
    # Test setting and getting properties
    @test set_property!(t, :name, "Alice") == "Alice"
    @test get_property(t, :name) == "Alice"
    
    # Test default values
    @test get_property(t, :age) == 0
    
    # Test is_set functionality
    @test is_set(t, :name) == true
    @test is_set(t, :age) == true
    @test is_set(t, :optional) == false
    
    # Test all_properties_set
    @test all_properties_set(t) == false
    set_property!(t, :optional, 3.14)
    @test all_properties_set(t) == true
    
    # Test property type information
    @test property_type(t, :name) === String
    @test property_type(t, :age) === Int
    @test property_type(t, :optional) === Float64
    
    # Test property type from type (not instance)
    @test property_type(TestBasic, :name) === String
    @test property_type(TestBasic, :age) === Int
    @test property_type(TestBasic, :optional) === Float64
    
    # Test error handling for non-existent properties
    @test_throws ErrorException get_property(t, :nonexistent)
    @test_throws ErrorException set_property!(t, :nonexistent, "value")
    @test is_set(t, :nonexistent) == false
    @test property_type(t, :nonexistent) === nothing
    
    # Test error for accessing unset property
    t2 = TestBasic()
    @test_throws ErrorException get_property(t2, :name)

    @testset "with_property! does not mutate isbits in-place" begin
        set_property!(t, :age, 100)
        @test_throws ErrorException with_property!(t, :age) do val
            val + 23
        end
    end

    @testset "with_property! mutates mutable property in-place" begin
        mt = MutableTest()
        set_property!(mt, :arr, [1,2,3])
        result = with_property!(mt, :arr) do vec
            push!(vec, 99)
            vec
        end
        @test result == [1,2,3,99]
        @test get_property(mt, :arr) == [1,2,3,99]
    end


end
