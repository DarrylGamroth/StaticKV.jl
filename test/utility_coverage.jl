# Tests for utility functions and potential unreachable code paths
using Test
using StaticKV

# Define all kvstore types at module level to avoid syntax errors
@kvstore TestModuleRefs begin
    # These should work and exercise the module qualification stripping
    access_mode_ref::String => ("test"; access = StaticKV.AccessMode.READABLE)
    multiple_refs::Int => (42; access = StaticKV.AccessMode.READABLE_ASSIGNABLE_MUTABLE)
end

@kvstore TestKeyOperationEdges begin
    normal_key::String => "normal"
    long_key_name_that_might_cause_issues_with_symbol_generation::Int => 42
    key_with_unicode_αβγδε::Float64 => 3.14
    key123::Bool => true
end

@kvstore TestBoundaries begin
    # Test boundary conditions in various data types
    max_int::Int => typemax(Int)
    min_int::Int => typemin(Int)
    inf_float::Float64 => Inf
    neg_inf_float::Float64 => -Inf
    nan_float::Float64 => NaN  
    empty_string::String => ""
    single_char::String => "a"
    very_long_string::String => repeat("x", 1000)
end

@kvstore TestMemoryStress begin
    # Test with types that might stress the memory system
    large_vector::Vector{Float64} => zeros(10000)
    large_dict::Dict{String, Int} => Dict(string(i) => i for i in 1:1000)
    nested_structure::Vector{Dict{Symbol, Vector{String}}} => [Dict(:key => ["value$i" for i in 1:100]) for _ in 1:10]
end

@kvstore TestCallbackEdges begin  
    # Test edge cases in callback functions
    callback_with_side_effects::Int => (0; on_set = (obj, key, val) -> begin
        # This callback has side effects - not pure
        println("Setting $key to $val")  # Side effect
        return val > 0 ? val : 0
    end)
    
    callback_with_error::String => ("default"; on_get = (obj, key, val) -> begin
        # This might throw an error in some cases
        if val == "error"
            error("Intentional error in callback")
        end
        return uppercase(val)
    end)
end

@kvstore TestTypeSystem begin
    # Test edge cases in the type system
    abstract_type_field::AbstractString => "concrete"
    union_with_nothing::Union{Int, Nothing} => nothing
    parametric_vector::Vector{T} where T<:Number => [1, 2, 3]
    complex_nested::Dict{Symbol, Tuple{String, Union{Int, Float64}}} => Dict(:test => ("key", 42))
end

function test_utility_coverage()
    
    @testset "Internal Utility Functions" begin
        # These tests target internal functions that might not be fully covered
        
        # Test strip_module_qualifications with various expression types
        # This function is used internally by the macro system
        
        # Note: We can't directly test strip_module_qualifications since it's internal,
        # but we can test scenarios that would exercise different paths through it
        
        @testset "Complex Module Qualification Scenarios" begin
            # Test macro expansion with complex expressions that would 
            # exercise strip_module_qualifications
            
            # Test with nested module references (this would get processed internally)
            kv_refs = TestModuleRefs()
            @test StaticKV.value(kv_refs, :access_mode_ref) == "test"
            @test StaticKV.is_readable(kv_refs, :access_mode_ref)
            @test !StaticKV.is_assignable(kv_refs, :access_mode_ref)
            
            @test StaticKV.value(kv_refs, :multiple_refs) == 42
            @test StaticKV.is_readable(kv_refs, :multiple_refs)
            @test StaticKV.is_assignable(kv_refs, :multiple_refs)
            @test StaticKV.is_mutable(kv_refs, :multiple_refs)
        end
    end
    
    @testset "AccessMode Module Functions" begin
        # Test all the AccessMode module functions directly
        using StaticKV.AccessMode
        
        # Test individual flag checks
        @test is_readable(READABLE) == true
        @test is_readable(ASSIGNABLE) == false
        @test is_readable(MUTABLE) == false
        @test is_readable(NONE) == false
        
        @test is_assignable(READABLE) == false
        @test is_assignable(ASSIGNABLE) == true
        @test is_assignable(MUTABLE) == false
        @test is_assignable(NONE) == false
        
        @test is_mutable(READABLE) == false
        @test is_mutable(ASSIGNABLE) == false
        @test is_mutable(MUTABLE) == true
        @test is_mutable(NONE) == false
        
        # Test legacy function
        @test is_writable(ASSIGNABLE) == true
        @test is_writable(READABLE) == false
        @test is_writable(WRITABLE) == true  # Legacy constant
        
        # Test combined flags
        combined = READABLE | ASSIGNABLE
        @test is_readable(combined) == true
        @test is_assignable(combined) == true
        @test is_mutable(combined) == false
        
        full_access = READABLE_ASSIGNABLE_MUTABLE
        @test is_readable(full_access) == true
        @test is_assignable(full_access) == true
        @test is_mutable(full_access) == true
        
        # Test legacy combined flags
        legacy_rw = READABLE_WRITABLE
        @test is_readable(legacy_rw) == true
        @test is_assignable(legacy_rw) == true
        @test is_mutable(legacy_rw) == true
        @test is_writable(legacy_rw) == true
    end
    
    @testset "Edge Cases in Key Operations" begin
        # Test edge cases that might exercise less common code paths
        kv_edges = TestKeyOperationEdges()
        
        # Test that long key names work
        long_key = :long_key_name_that_might_cause_issues_with_symbol_generation
        @test StaticKV.value(kv_edges, long_key) == 42
        @test StaticKV.isset(kv_edges, long_key) == true
        
        # Test unicode in key names
        @test StaticKV.value(kv_edges, :key_with_unicode_αβγδε) == 3.14
        @test StaticKV.isset(kv_edges, :key_with_unicode_αβγδε) == true
        
        # Test numeric suffixes in key names
        @test StaticKV.value(kv_edges, :key123) == true
        
        # Test normal keys still work
        @test StaticKV.value(kv_edges, :normal_key) == "normal"
        
        # Test that key name retrieval works
        key_names = StaticKV.key_names(kv_edges)
        @test :normal_key in key_names
        @test long_key in key_names
        @test :key_with_unicode_αβγδε in key_names
        @test :key123 in key_names
    end
    
    @testset "Boundary Value Testing" begin
        # Test boundary conditions that might reveal edge cases
        kv_boundaries = TestBoundaries()
        
        # Test extreme integer values
        @test StaticKV.value(kv_boundaries, :max_int) == typemax(Int)
        @test StaticKV.value(kv_boundaries, :min_int) == typemin(Int)
        
        # Test special float values
        @test StaticKV.value(kv_boundaries, :inf_float) == Inf
        @test StaticKV.value(kv_boundaries, :neg_inf_float) == -Inf
        @test isnan(StaticKV.value(kv_boundaries, :nan_float))
        
        # Test string edge cases
        @test StaticKV.value(kv_boundaries, :empty_string) == ""
        @test StaticKV.value(kv_boundaries, :single_char) == "a"
        @test length(StaticKV.value(kv_boundaries, :very_long_string)) == 1000
        
        # Test that all boundary values can be modified (if assignable)
        StaticKV.value!(kv_boundaries, typemax(Int) - 1, :max_int)
        @test StaticKV.value(kv_boundaries, :max_int) == typemax(Int) - 1
    end
    
    @testset "Memory and Performance Edge Cases" begin
        # Test scenarios that might stress memory management
        kv_memory = TestMemoryStress()
        
        # Test large vector handling
        large_vec = StaticKV.value(kv_memory, :large_vector)
        @test length(large_vec) == 10000
        @test all(x -> x == 0.0, large_vec)
        
        # Test large dictionary handling
        large_dict = StaticKV.value(kv_memory, :large_dict)
        @test length(large_dict) == 1000
        @test large_dict["1"] == 1
        @test large_dict["500"] == 500
        @test large_dict["1000"] == 1000
        
        # Test nested structure handling
        nested = StaticKV.value(kv_memory, :nested_structure)
        @test length(nested) == 10
        @test length(nested[1][:key]) == 100
        @test nested[1][:key][1] == "value1"
        
        # Test that large structures can be replaced
        new_large_vec = ones(5000)
        StaticKV.value!(kv_memory, new_large_vec, :large_vector)
        @test length(StaticKV.value(kv_memory, :large_vector)) == 5000
        @test all(x -> x == 1.0, StaticKV.value(kv_memory, :large_vector))
    end
    
    @testset "Callback Function Edge Cases" begin  
        # Test edge cases in callback functions
        kv_callbacks = TestCallbackEdges()
        
        # Test callback with side effects (should still work)
        # Note: In real tests, we'd capture the output, but here we just test it doesn't crash
        @test StaticKV.value(kv_callbacks, :callback_with_side_effects) == 0
        StaticKV.value!(kv_callbacks, 5, :callback_with_side_effects)
        @test StaticKV.value(kv_callbacks, :callback_with_side_effects) == 5
        
        # Test that negative values get clamped to 0
        StaticKV.value!(kv_callbacks, -10, :callback_with_side_effects)
        @test StaticKV.value(kv_callbacks, :callback_with_side_effects) == 0
        
        # Test callback error handling
        @test StaticKV.value(kv_callbacks, :callback_with_error) == "DEFAULT"  # uppercase of "default"
        
        # Test that callback error propagates when it should
        StaticKV.value!(kv_callbacks, "error", :callback_with_error)
        @test_throws ErrorException StaticKV.value(kv_callbacks, :callback_with_error)
        
        # Test that normal values work after error
        StaticKV.value!(kv_callbacks, "normal", :callback_with_error)
        @test StaticKV.value(kv_callbacks, :callback_with_error) == "NORMAL"
    end
    
    @testset "Type System Edge Cases" begin
        # Test complex type system interactions
        kv_types = TestTypeSystem()
        
        # Test abstract type with concrete value
        @test StaticKV.value(kv_types, :abstract_type_field) == "concrete"
        @test typeof(StaticKV.value(kv_types, :abstract_type_field)) <: AbstractString
        
        # Test union with nothing
        @test StaticKV.value(kv_types, :union_with_nothing) === nothing
        StaticKV.value!(kv_types, 42, :union_with_nothing)
        @test StaticKV.value(kv_types, :union_with_nothing) == 42
        StaticKV.value!(kv_types, nothing, :union_with_nothing)
        @test StaticKV.value(kv_types, :union_with_nothing) === nothing
        
        # Test parametric type
        param_vec = StaticKV.value(kv_types, :parametric_vector)
        @test param_vec == [1, 2, 3]
        @test eltype(param_vec) <: Number
        
        # Test complex nested type
        complex_val = StaticKV.value(kv_types, :complex_nested)
        @test complex_val isa Dict{Symbol, Tuple{String, Union{Int, Float64}}}
        @test complex_val[:test] == ("key", 42)
        
        # Test that type constraints are enforced
        StaticKV.value!(kv_types, [4.0, 5.0, 6.0], :parametric_vector)  # Float64 <: Number, should work
        @test StaticKV.value(kv_types, :parametric_vector) == [4.0, 5.0, 6.0]
    end
    
    @testset "Stress Testing and Performance" begin
        # Test scenarios that might reveal performance issues or edge cases
        # under stress
        
        # Test repeated operations
        kv = TestKeyOperationEdges()
        
        # Stress test key access
        for _ in 1:1000
            @test StaticKV.value(kv, :normal_key) == "normal"
        end
        
        # Stress test key modification
        for i in 1:100
            StaticKV.value!(kv, i, :long_key_name_that_might_cause_issues_with_symbol_generation)
            @test StaticKV.value(kv, :long_key_name_that_might_cause_issues_with_symbol_generation) == i
        end
        
        # Test that the kvstore is still functional after stress
        @test StaticKV.isset(kv, :normal_key)
        @test StaticKV.isset(kv, :key_with_unicode_αβγδε)
        @test length(StaticKV.key_names(kv)) == 4
    end
end