# Test edge cases for the StaticKV package
using Test
using StaticKV

function test_edge_cases()
    # Use the pre-defined TestEdgeCases
    t1 = TestEdgeCases()
    
    # Test complex number key
    StaticKV.value!(t1, 1.0 + 2.0im, :complex)
    @test StaticKV.value(t1, :complex) == 1.0 + 2.0im
    
    # Test string value key
    @test isset(t1, :string_val)  # Default is empty string, which is considered set
    @test StaticKV.value!(t1, "value", :string_val) == "value"
    @test StaticKV.value(t1, :string_val) == "value"
    
    # Test mutable container key
    @test StaticKV.value(t1, :mutable_container) == [1, 2, 3]
    mutable_val = StaticKV.value(t1, :mutable_container)
    push!(mutable_val, 4)
    @test StaticKV.value(t1, :mutable_container) == [1, 2, 3, 4]
    
    # Test Any type key
    @test isset(t1, :any_type)  # It has a default value of "default"
    StaticKV.value!(t1, "string", :any_type)
    @test StaticKV.value(t1, :any_type) == "string"
    StaticKV.value!(t1, 42, :any_type)
    @test StaticKV.value(t1, :any_type) == 42
    
    # Use the pre-defined TestExtendedEdgeCases
    t2 = TestExtendedEdgeCases()
    
    # Test Nothing type
    @test !isset(t2, :nothing_val)  # Default is nothing, which is treated as not set
    
    # Test String and Int type keys
    StaticKV.value!(t2, "test string", :string_type)
    @test StaticKV.value(t2, :string_type) == "test string"
    
    StaticKV.value!(t2, 100, :int_type)
    @test StaticKV.value(t2, :int_type) == 100
    
    # Test parametric types
    param_value = [Dict{Symbol, Any}(:a => 1, :b => "test")]
    StaticKV.value!(t2, param_value, :parametric)
    @test StaticKV.value(t2, :parametric) == param_value
    
    # Test tuple type
    StaticKV.value!(t2, (1, "test", true), :tuple_type)
    @test StaticKV.value(t2, :tuple_type) == (1, "test", true)
    
    # Test abstract types
    @test StaticKV.value(t2, :abstract_num) == 1
    StaticKV.value!(t2, 3.14, :abstract_num)
    @test StaticKV.value(t2, :abstract_num) == 3.14
    
    @test StaticKV.value(t2, :abstract_collection) == [1, 2, 3]
    StaticKV.value!(t2, [4, 5, 6], :abstract_collection)
    @test StaticKV.value(t2, :abstract_collection) == [4, 5, 6]
    
    # Test complex callbacks with bounds
    @test StaticKV.value(t2, :recursive_cb) == 1
    StaticKV.value!(t2, 50, :recursive_cb)
    @test StaticKV.value(t2, :recursive_cb) == 50
    StaticKV.value!(t2, 200, :recursive_cb)
    @test StaticKV.value(t2, :recursive_cb) == 100  # Clamped to 100
    
    # Test with_key! for matrix in-place modification
    # First, verify initial matrix is all zeros
    initial_matrix = StaticKV.value(t2, :matrix)
    @test all(initial_matrix .== 0.0)
    
    # Now use with_key! to modify the matrix in-place
    with_key!(t2, :matrix) do m
        m .+= 1.0  # In-place modification
        m[1:3, 1:3] .= 0.0  # Modify specific region
    end
    
    # Verify modifications
    modified_matrix = StaticKV.value(t2, :matrix)
    @test all(modified_matrix[1:3, 1:3] .== 0.0)  # Check the zeroed region
    @test all(modified_matrix[4:end, 4:end] .== 1.0)  # Check the incremented region
end
