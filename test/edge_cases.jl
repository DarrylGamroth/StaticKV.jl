# Test edge cases for the ManagedProperties package

function test_edge_cases()
    # Use the pre-defined TestEdgeCases
    t1 = TestEdgeCases()
    
    # Test complex number property
    set_property!(t1, :complex, 1.0 + 2.0im)
    @test get_property(t1, :complex) == 1.0 + 2.0im
    
    # Test nullable property - not set but has a type that can be nothing
    @test !is_set(t1, :nullable)  # Default is nothing, which is treated as not set
    @test set_property!(t1, :nullable, "value") == "value"
    @test get_property(t1, :nullable) == "value"
    
    # Test mutable container property
    @test get_property(t1, :mutable_container) == [1, 2, 3]
    mutable_val = get_property(t1, :mutable_container)
    push!(mutable_val, 4)
    @test get_property(t1, :mutable_container) == [1, 2, 3, 4]
    
    # Test Any type property
    @test is_set(t1, :any_type)  # It has a default value of "default"
    set_property!(t1, :any_type, "string")
    @test get_property(t1, :any_type) == "string"
    set_property!(t1, :any_type, 42)
    @test get_property(t1, :any_type) == 42
    
    # Use the pre-defined TestExtendedEdgeCases
    t2 = TestExtendedEdgeCases()
    
    # Test Nothing type
    @test !is_set(t2, :nothing_val)  # Default is nothing, which is treated as not set
    
    # Test Union type
    set_property!(t2, :union_type, "string")
    @test get_property(t2, :union_type) == "string"
    set_property!(t2, :union_type, 42)
    @test get_property(t2, :union_type) == 42
    
    # Test parametric types
    param_value = [Dict{Symbol, Any}(:a => 1, :b => "test")]
    set_property!(t2, :parametric, param_value)
    @test get_property(t2, :parametric) == param_value
    
    # Test tuple type
    set_property!(t2, :tuple_type, (1, "test", true))
    @test get_property(t2, :tuple_type) == (1, "test", true)
    
    # Test abstract types
    @test get_property(t2, :abstract_num) == 1
    set_property!(t2, :abstract_num, 3.14)
    @test get_property(t2, :abstract_num) == 3.14
    
    @test get_property(t2, :abstract_collection) == [1, 2, 3]
    set_property!(t2, :abstract_collection, [4, 5, 6])
    @test get_property(t2, :abstract_collection) == [4, 5, 6]
    
    # Test complex callbacks with bounds
    @test get_property(t2, :recursive_cb) == 1
    set_property!(t2, :recursive_cb, 50)
    @test get_property(t2, :recursive_cb) == 50
    set_property!(t2, :recursive_cb, 200)
    @test get_property(t2, :recursive_cb) == 100  # Clamped to 100
end
