# Test edge cases for the StaticKV package
using Test
using StaticKV

function test_edge_cases()
    # Use the pre-defined TestEdgeCases
    t1 = TestEdgeCases()
    
    # Test complex number key
    setkey!(t1, :complex, 1.0 + 2.0im)
    @test getkey(t1, :complex) == 1.0 + 2.0im
    
    # Test string value key
    @test isset(t1, :string_val)  # Default is empty string, which is considered set
    @test setkey!(t1, :string_val, "value") == "value"
    @test getkey(t1, :string_val) == "value"
    
    # Test mutable container key
    @test getkey(t1, :mutable_container) == [1, 2, 3]
    mutable_val = getkey(t1, :mutable_container)
    push!(mutable_val, 4)
    @test getkey(t1, :mutable_container) == [1, 2, 3, 4]
    
    # Test Any type key
    @test isset(t1, :any_type)  # It has a default value of "default"
    setkey!(t1, :any_type, "string")
    @test getkey(t1, :any_type) == "string"
    setkey!(t1, :any_type, 42)
    @test getkey(t1, :any_type) == 42
    
    # Use the pre-defined TestExtendedEdgeCases
    t2 = TestExtendedEdgeCases()
    
    # Test Nothing type
    @test !isset(t2, :nothing_val)  # Default is nothing, which is treated as not set
    
    # Test String and Int type keys
    setkey!(t2, :string_type, "test string")
    @test getkey(t2, :string_type) == "test string"
    
    setkey!(t2, :int_type, 100)
    @test getkey(t2, :int_type) == 100
    
    # Test parametric types
    param_value = [Dict{Symbol, Any}(:a => 1, :b => "test")]
    setkey!(t2, :parametric, param_value)
    @test getkey(t2, :parametric) == param_value
    
    # Test tuple type
    setkey!(t2, :tuple_type, (1, "test", true))
    @test getkey(t2, :tuple_type) == (1, "test", true)
    
    # Test abstract types
    @test getkey(t2, :abstract_num) == 1
    setkey!(t2, :abstract_num, 3.14)
    @test getkey(t2, :abstract_num) == 3.14
    
    @test getkey(t2, :abstract_collection) == [1, 2, 3]
    setkey!(t2, :abstract_collection, [4, 5, 6])
    @test getkey(t2, :abstract_collection) == [4, 5, 6]
    
    # Test complex callbacks with bounds
    @test getkey(t2, :recursive_cb) == 1
    setkey!(t2, :recursive_cb, 50)
    @test getkey(t2, :recursive_cb) == 50
    setkey!(t2, :recursive_cb, 200)
    @test getkey(t2, :recursive_cb) == 100  # Clamped to 100
    
    # Test with_key! for matrix in-place modification
    # First, verify initial matrix is all zeros
    initial_matrix = getkey(t2, :matrix)
    @test all(initial_matrix .== 0.0)
    
    # Now use with_key! to modify the matrix in-place
    with_key!(t2, :matrix) do m
        m .+= 1.0  # In-place modification
        m[1:3, 1:3] .= 0.0  # Modify specific region
    end
    
    # Verify modifications
    modified_matrix = getkey(t2, :matrix)
    @test all(modified_matrix[1:3, 1:3] .== 0.0)  # Check the zeroed region
    @test all(modified_matrix[4:end, 4:end] .== 1.0)  # Check the incremented region
end
