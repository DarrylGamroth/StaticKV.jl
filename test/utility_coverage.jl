# Tests for utility functions and potential unreachable code paths
using Test
using StaticKV

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
            @kvstore TestModuleRefs begin
                # These should work and exercise the module qualification stripping
                access_mode_ref::String => ("test"; access = StaticKV.AccessMode.READABLE)
                multiple_refs::Int => (42; access = StaticKV.AccessMode.READABLE_ASSIGNABLE_MUTABLE)
            end
            
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
        
        @kvstore TestKeyOperationEdges begin
            normal_key::String => "normal"
            long_key_name_that_might_cause_issues_with_symbol_generation::Int => 42
            key_with_unicode_αβγδε::Float64 => 3.14
            key123::Bool => true
        end
        
        kv_edges = TestKeyOperationEdges()
        
        # Test that long key names work
        long_key = :long_key_name_that_might_cause_issues_with_symbol_generation
        @test StaticKV.value(kv_edges, long_key) == 42
        @test StaticKV.isset(kv_edges, long_key) == true
        
        # Test unicode in key names
        unicode_key = :key_with_unicode_αβγδε
        @test StaticKV.value(kv_edges, unicode_key) == 3.14
        @test StaticKV.last_update(kv_edges, unicode_key) > 0
        
        # Test numeric suffix keys
        @test StaticKV.value(kv_edges, :key123) == true
        
        # Test all utility functions work with these edge case keys
        @test StaticKV.keynames(kv_edges) isa Tuple
        @test long_key in StaticKV.keynames(kv_edges)
        @test unicode_key in StaticKV.keynames(kv_edges)
        @test :key123 in StaticKV.keynames(kv_edges)
        
        # Test allkeysset with edge case keys
        @test StaticKV.allkeysset(kv_edges) == true
        
        reset!(kv_edges, long_key)
        @test StaticKV.allkeysset(kv_edges) == false
        @test !StaticKV.isset(kv_edges, long_key)
    end
    
    @testset "Boundary Conditions" begin
        # Test boundary conditions that might reveal edge cases
        
        @kvstore TestBoundaries begin
            empty_string::String => ""
            zero_int::Int => 0
            negative_int::Int => -1
            max_int::Int => typemax(Int)
            min_int::Int => typemin(Int)
            nan_float::Float64 => NaN
            inf_float::Float64 => Inf
            neg_inf_float::Float64 => -Inf
        end
        
        kv_bounds = TestBoundaries()
        
        # Test boundary values are handled correctly
        @test StaticKV.value(kv_bounds, :empty_string) == ""
        @test StaticKV.value(kv_bounds, :zero_int) == 0
        @test StaticKV.value(kv_bounds, :negative_int) == -1
        @test StaticKV.value(kv_bounds, :max_int) == typemax(Int)
        @test StaticKV.value(kv_bounds, :min_int) == typemin(Int)
        @test isnan(StaticKV.value(kv_bounds, :nan_float))
        @test StaticKV.value(kv_bounds, :inf_float) == Inf
        @test StaticKV.value(kv_bounds, :neg_inf_float) == -Inf
        
        # Test that isset works correctly with these boundary values
        @test StaticKV.isset(kv_bounds, :empty_string) == true  # Empty string is still "set"
        @test StaticKV.isset(kv_bounds, :zero_int) == true
        @test StaticKV.isset(kv_bounds, :negative_int) == true
        
        # Test show methods with boundary values
        io = IOBuffer()
        show(io, MIME"text/plain"(), kv_bounds)
        output = String(take!(io))
        @test contains(output, "\"\"")  # empty string
        @test contains(output, "0")
        @test contains(output, "-1")
        @test contains(output, "NaN")
        @test contains(output, "Inf")
    end
    
    @testset "Memory and Performance Edge Cases" begin
        # Test scenarios that might stress memory or performance
        
        @kvstore TestMemoryStress begin
            large_vector::Vector{Int} => collect(1:10000)
            large_string::String => repeat("x", 1000)
            nested_structure::Dict{String, Vector{Dict{Symbol, String}}} => Dict(
                "level1" => [
                    Dict(:a => "test1", :b => "test2", :c => "test3"),
                    Dict(:d => "test4", :e => "test5", :f => "test6")
                ]
            )
        end
        
        kv_memory = TestMemoryStress()
        
        # Test that large data structures work correctly
        large_vec = StaticKV.value(kv_memory, :large_vector)
        @test length(large_vec) == 10000
        @test large_vec[1] == 1
        @test large_vec[end] == 10000
        
        large_str = StaticKV.value(kv_memory, :large_string)
        @test length(large_str) == 1000
        @test all(c == 'x' for c in large_str)
        
        nested = StaticKV.value(kv_memory, :nested_structure)
        @test nested["level1"][1][:a] == "test1"
        @test nested["level1"][2][:f] == "test6"
        
        # Test that modifications work with large structures
        new_vec = collect(1:5000)
        StaticKV.value!(kv_memory, new_vec, :large_vector)
        @test length(StaticKV.value(kv_memory, :large_vector)) == 5000
        
        # Test show methods don't crash with large data (should truncate)
        io = IOBuffer()
        show(io, MIME"text/plain"(), kv_memory)
        output = String(take!(io))
        @test !isempty(output)
        # Large values should be truncated in display
        @test contains(output, "...")
    end
    
    @testset "Callback Function Edge Cases" begin
        # Test edge cases in callback functions
        
        # Callback that returns different types
        polymorphic_cb(obj, key, val) = val isa String ? Symbol(val) : string(val)
        
        # Callback that modifies the object (though this is not recommended)
        side_effect_cb(obj, key, val) = (obj.other_key = "modified"; val)
        
        # Callback that throws an exception
        error_cb(obj, key, val) = val == "error" ? error("Callback error!") : val
        
        @kvstore TestCallbackEdges begin  
            other_key::String => "initial"
            polymorphic::Any => ("string_val"; on_get = polymorphic_cb)
            side_effect::String => ("test"; on_set = side_effect_cb)
            error_prone::String => ("safe"; on_set = error_cb)
        end
        
        kv_cb = TestCallbackEdges()
        
        # Test polymorphic callback
        @test StaticKV.value(kv_cb, :polymorphic) == :string_val  # converted to Symbol
        
        StaticKV.value!(kv_cb, 42, :polymorphic)
        @test StaticKV.value(kv_cb, :polymorphic) == "42"  # converted to String
        
        # Test callback with side effects (not recommended but should work)
        old_other = StaticKV.value(kv_cb, :other_key)
        StaticKV.value!(kv_cb, "new_value", :side_effect)
        # The side effect callback should have modified other_key
        # Note: This tests the callback mechanism but isn't recommended practice
        
        # Test callback that can throw
        StaticKV.value!(kv_cb, "safe_value", :error_prone)  # Should work
        @test StaticKV.value(kv_cb, :error_prone) == "safe_value"
        
        # This should propagate the callback's exception
        @test_throws ErrorException StaticKV.value!(kv_cb, "error", :error_prone)
    end
    
    @testset "Type System Edge Cases" begin
        # Test edge cases in the type system
        
        @kvstore TestTypeSystem begin
            # Test with type aliases
            string_alias::AbstractString => "alias_test"
            
            # Test with concrete vs abstract types
            concrete_vector::Vector{Int} => [1, 2, 3]
            abstract_vector::AbstractVector{Int} => [4, 5, 6]
            
            # Test with parametric types
            parametric::Vector{T} where T => ["a", "b", "c"]
        end
        
        kv_types = TestTypeSystem()
        
        # Test that type aliases work
        @test StaticKV.value(kv_types, :string_alias) == "alias_test"
        StaticKV.value!(kv_types, "new_alias", :string_alias)  # String is <: AbstractString
        @test StaticKV.value(kv_types, :string_alias) == "new_alias"
        
        # Test concrete vs abstract
        @test StaticKV.value(kv_types, :concrete_vector) == [1, 2, 3]
        @test StaticKV.value(kv_types, :abstract_vector) == [4, 5, 6]
        
        # Test parametric types
        @test StaticKV.value(kv_types, :parametric) == ["a", "b", "c"]
        StaticKV.value!(kv_types, [1, 2, 3], :parametric)  # Should work with different element type
        @test StaticKV.value(kv_types, :parametric) == [1, 2, 3]
    end
end