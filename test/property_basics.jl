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
end
