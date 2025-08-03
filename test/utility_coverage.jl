# Tests for utility functions and potential unreachable code paths
using Test
using StaticKV

# Define all kvstore types at module level to avoid syntax errors
@kvstore TestModuleRefs begin
    # These should work and exercise the module qualification stripping
    access_mode_ref::String => ("test"; access = StaticKV.AccessMode.READABLE)
    multiple_refs::Int => (42; access = StaticKV.AccessMode.READABLE_ASSIGNABLE_MUTABLE)
end

@kvstore TestUtilityCallbackEdges begin  
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
    parametric_vector::Vector{T} where T<:Number => [1, 2, 3]
    complex_nested::Dict{Symbol, Tuple{String, Int}} => Dict(:test => ("key", 42))
end

export test_utility_coverage

function test_utility_coverage()
    
    @testset "Internal Utility Functions" begin
        # These tests target internal functions that might not be fully covered
        
        # Test strip_module_qualifications with various expression types
        # This function is used internally by the macro system
        
        # Note: We can't directly test strip_module_qualifications since it's internal,
        # but we can test that kvstores with module-qualified references work
        kv_mod = TestModuleRefs()
        @test StaticKV.value(kv_mod, :access_mode_ref) == "test"
        @test StaticKV.value(kv_mod, :multiple_refs) == 42
        
        # Test exception handling in callbacks
        kv_callbacks = TestUtilityCallbackEdges()
        
        # Test callback with side effects
        @test StaticKV.value(kv_callbacks, :callback_with_side_effects) == 0
        StaticKV.value!(kv_callbacks, -5, :callback_with_side_effects)  # Should become 0
        @test StaticKV.value(kv_callbacks, :callback_with_side_effects) == 0
        StaticKV.value!(kv_callbacks, 10, :callback_with_side_effects)  # Should stay 10
        @test StaticKV.value(kv_callbacks, :callback_with_side_effects) == 10
        
        # Test callback that might error (but won't in this case)
        @test StaticKV.value(kv_callbacks, :callback_with_error) == "DEFAULT"
        StaticKV.value!(kv_callbacks, "hello", :callback_with_error)
        @test StaticKV.value(kv_callbacks, :callback_with_error) == "HELLO"
        
        # Test type system edge cases
        kv_types = TestTypeSystem()
        
        # Test abstract type field
        @test StaticKV.value(kv_types, :abstract_type_field) == "concrete"
        @test typeof(StaticKV.value(kv_types, :abstract_type_field)) <: AbstractString
        
        # Test parametric type
        param_vec = StaticKV.value(kv_types, :parametric_vector)
        @test param_vec == [1, 2, 3]
        @test eltype(param_vec) <: Number
        
        # Test complex nested type
        nested = StaticKV.value(kv_types, :complex_nested)
        @test nested == Dict(:test => ("key", 42))
        @test typeof(nested) <: Dict{Symbol, Tuple{String, Int}}
    end
end