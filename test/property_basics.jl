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
    # @test property_type(TestBasic, :name) === String
    # @test property_type(TestBasic, :age) === Int
    # @test property_type(TestBasic, :optional) === Float64
    
    # Test error handling for non-existent properties
    @test_throws ErrorException get_property(t, :nonexistent)
    @test_throws ErrorException set_property!(t, :nonexistent, "value")
    @test is_set(t, :nonexistent) == false
    @test property_type(t, :nonexistent) === nothing
    
    # Test error for accessing unset property
    t2 = TestBasic()
    @test_throws ErrorException get_property(t2, :name)

    # Test with_property! for isbits (immutable) type: should throw error
    set_property!(t, :age, 10)
    @test_throws ErrorException with_property!(t, :age) do age
        age + 5
    end
    @test get_property(t, :age) == 10  # property is unchanged

    # Test with_property! with Ref for isbits type: should throw error
    set_property!(t, :age, 20)
    @test_throws ErrorException with_property!(t, :age) do age
        r = Ref(age)
        r[] += 1
        r[]
    end
    @test get_property(t, :age) == 20  # property is unchanged

    # Test with_property! for mutable type: can mutate in-place
    mt = MutableTest()
    result = with_property!(mt, :arr) do arr
        push!(arr, 4)
        arr
    end
    @test result == [1,2,3,4]
    @test get_property(mt, :arr) == [1,2,3,4]

    # Test with_properties! for isbits types: should throw error
    set_property!(t, :age, 30)
    set_property!(t, :optional, 2.5)
    @test_throws ErrorException with_properties!(t, :age, :optional) do age, opt
        age += 10
        opt += 1.5
        (age, opt)
    end

    # Test with_properties! for mutable types: can mutate in-place
    mmt = MultiMutableTest()
    result = with_properties!(mmt, :a, :b) do a, b
        push!(a, 10)
        push!(b, 20)
        nothing
    end
    @test get_property(mmt, :a) == [1,10]
    @test get_property(mmt, :b) == [2,20]
end
