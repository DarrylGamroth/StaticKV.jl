# Test edge cases for the StaticKV package
using Test
using StaticKV

function test_edge_cases()
    # Use the pre-defined TestEdgeCases
    t1 = TestEdgeCases()
    
    # Test complex number key
    setindex!(t1, :complex, 1.0 + 2.0im)
    @test getindex(t1, :complex) == 1.0 + 2.0im
    
    # Test string value key
    @test isset(t1, :string_val)  # Default is empty string, which is considered set
    @test setindex!(t1, :string_val, "value") == "value"
    @test getindex(t1, :string_val) == "value"
    
    # Test mutable container key
    @test getindex(t1, :mutable_container) == [1, 2, 3]
    mutable_val = getindex(t1, :mutable_container)
    push!(mutable_val, 4)
    @test getindex(t1, :mutable_container) == [1, 2, 3, 4]
    
    # Test Any type key
    @test isset(t1, :any_type)  # It has a default value of "default"
    setindex!(t1, :any_type, "string")
    @test getindex(t1, :any_type) == "string"
    setindex!(t1, :any_type, 42)
    @test getindex(t1, :any_type) == 42
    
    # Use the pre-defined TestExtendedEdgeCases
    t2 = TestExtendedEdgeCases()
    
    # Test Nothing type
    @test !isset(t2, :nothing_val)  # Default is nothing, which is treated as not set
    
    # Test String and Int type keys
    setindex!(t2, :string_type, "test string")
    @test getindex(t2, :string_type) == "test string"
    
    setindex!(t2, :int_type, 100)
    @test getindex(t2, :int_type) == 100
    
    # Test parametric types
    param_value = [Dict{Symbol, Any}(:a => 1, :b => "test")]
    setindex!(t2, :parametric, param_value)
    @test getindex(t2, :parametric) == param_value
    
    # Test tuple type
    setindex!(t2, :tuple_type, (1, "test", true))
    @test getindex(t2, :tuple_type) == (1, "test", true)
    
    # Test abstract types
    @test getindex(t2, :abstract_num) == 1
    setindex!(t2, :abstract_num, 3.14)
    @test getindex(t2, :abstract_num) == 3.14
    
    @test getindex(t2, :abstract_collection) == [1, 2, 3]
    setindex!(t2, :abstract_collection, [4, 5, 6])
    @test getindex(t2, :abstract_collection) == [4, 5, 6]
    
    # Test complex callbacks with bounds
    @test getindex(t2, :recursive_cb) == 1
    setindex!(t2, :recursive_cb, 50)
    @test getindex(t2, :recursive_cb) == 50
    setindex!(t2, :recursive_cb, 200)
    @test getindex(t2, :recursive_cb) == 100  # Clamped to 100
    
    # Test with_key! for matrix in-place modification
    # First, verify initial matrix is all zeros
    initial_matrix = getindex(t2, :matrix)
    @test all(initial_matrix .== 0.0)
    
    # Now use with_key! to modify the matrix in-place
    with_key!(t2, :matrix) do m
        m .+= 1.0  # In-place modification
        m[1:3, 1:3] .= 0.0  # Modify specific region
    end
    
    # Verify modifications
    modified_matrix = getindex(t2, :matrix)
    @test all(modified_matrix[1:3, 1:3] .== 0.0)  # Check the zeroed region
    @test all(modified_matrix[4:end, 4:end] .== 1.0)  # Check the incremented region
end
