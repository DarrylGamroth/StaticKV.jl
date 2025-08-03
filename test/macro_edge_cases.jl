# Tests for macro-level edge cases and parsing scenarios
using Test
using StaticKV

function test_macro_edge_cases()
    
    @testset "Complex Macro Syntax Coverage" begin
        # Test different ways to specify default values and attributes
        
        # Test tuple values as defaults
        @kvstore TestTupleDefaults begin
            coords::Tuple{Float64, Float64} => (0.0, 0.0)
            rgb::Tuple{UInt8, UInt8, UInt8} => (255, 255, 255)
            mixed_tuple::Tuple{String, Int, Bool} => ("default", 42, true)
        end
        
        kv_tuple = TestTupleDefaults()
        @test StaticKV.value(kv_tuple, :coords) == (0.0, 0.0)
        @test StaticKV.value(kv_tuple, :rgb) == (255, 255, 255)
        @test StaticKV.value(kv_tuple, :mixed_tuple) == ("default", 42, true)
        
        # Test complex nested parentheses in attribute specification
        @kvstore TestComplexAttributes begin
            nested_parens::String => ("default"; access = (AccessMode.READABLE | AccessMode.ASSIGNABLE))
            callback_with_parens::Int => (42; on_set = (obj, key, val) -> (val < 0 ? 0 : val))
        end
        
        kv_complex = TestComplexAttributes()
        @test StaticKV.value(kv_complex, :nested_parens) == "default"
        @test StaticKV.is_readable(kv_complex, :nested_parens)
        @test StaticKV.is_assignable(kv_complex, :nested_parens)
        
        # Test that callback works
        StaticKV.value!(kv_complex, -10, :callback_with_parens)
        @test StaticKV.value(kv_complex, :callback_with_parens) == 0  # Should be clamped to 0
        
        # Test multiple attributes in various orders
        @kvstore TestAttributeOrders begin
            order1::String => ("val1"; access = AccessMode.READABLE, on_get = (obj, key, val) -> uppercase(val))
            order2::String => ("val2"; on_get = (obj, key, val) -> lowercase(val), access = AccessMode.READABLE_ASSIGNABLE_MUTABLE)
            order3::Int => (10; on_set = (obj, key, val) -> val * 2, access = AccessMode.READABLE_ASSIGNABLE_MUTABLE, on_get = (obj, key, val) -> val + 1)
        end
        
        kv_orders = TestAttributeOrders()
        @test StaticKV.value(kv_orders, :order1) == "VAL1"  # uppercase callback
        @test StaticKV.value(kv_orders, :order2) == "val2"  # lowercase callback  
        @test StaticKV.value(kv_orders, :order3) == 21      # (10 * 2) + 1 = 21
    end
    
    @testset "Default Value Edge Cases" begin
        # Test various types of default values
        @kvstore TestDefaultTypes begin
            # Primitive types
            char_val::Char => 'A'
            symbol_val::Symbol => :default
            
            # Collection types
            empty_vector::Vector{Int} => Int[]
            empty_dict::Dict{String, Int} => Dict{String, Int}()
            range_val::UnitRange{Int} => 1:10
            
            # Complex expressions as defaults
            computed_val::Int => (2 + 3 * 4)
            string_interp::String => "Hello $(2+2)"
            
            # Function values
            func_val::Function => x -> x^2
            
            # Type values
            type_val::Type => String
        end
        
        kv_defaults = TestDefaultTypes()
        
        @test StaticKV.value(kv_defaults, :char_val) == 'A'
        @test StaticKV.value(kv_defaults, :symbol_val) == :default
        @test StaticKV.value(kv_defaults, :empty_vector) == Int[]
        @test StaticKV.value(kv_defaults, :empty_dict) == Dict{String, Int}()
        @test StaticKV.value(kv_defaults, :range_val) == 1:10
        @test StaticKV.value(kv_defaults, :computed_val) == 14  # 2 + 3*4
        @test StaticKV.value(kv_defaults, :string_interp) == "Hello 4"
        @test StaticKV.value(kv_defaults, :func_val)(5) == 25  # 5^2
        @test StaticKV.value(kv_defaults, :type_val) == String
    end
    
    @testset "Clock Type Variations" begin
        # Test with different clock types
        @kvstore TestEpochClock clock_type=Clocks.EpochClock begin
            timestamp_key::String => "epoch"
        end
        
        @kvstore TestCachedClock clock_type=Clocks.CachedEpochClock begin  
            timestamp_key::String => "cached"
        end
        
        kv_epoch = TestEpochClock()
        kv_cached = TestCachedClock()
        
        @test StaticKV.value(kv_epoch, :timestamp_key) == "epoch"
        @test StaticKV.value(kv_cached, :timestamp_key) == "cached"
        
        # Test that timestamps work with both clock types
        ts1 = StaticKV.last_update(kv_epoch, :timestamp_key)
        ts2 = StaticKV.last_update(kv_cached, :timestamp_key)
        @test ts1 > 0
        @test ts2 > 0
    end
    
    @testset "Default Callback Parameters" begin
        # Test struct-level default callbacks
        global_get_count = Ref(0)
        global_set_count = Ref(0)
        
        default_get(obj, key, val) = (global_get_count[] += 1; val)
        default_set(obj, key, val) = (global_set_count[] += 1; val)
        
        @kvstore TestDefaultCallbacks default_on_get=default_get default_on_set=default_set begin
            key1::String => "value1"
            key2::Int => 42
            key3::String  # No default value, but should use default callbacks
        end
        
        kv_def_cb = TestDefaultCallbacks()
        
        # Reset counters
        global_get_count[] = 0
        global_set_count[] = 0
        
        # Test that default callbacks are used
        val1 = StaticKV.value(kv_def_cb, :key1)
        @test val1 == "value1"
        @test global_get_count[] == 1
        
        StaticKV.value!(kv_def_cb, "new_value", :key3)
        @test global_set_count[] == 1
        
        val3 = StaticKV.value(kv_def_cb, :key3)
        @test val3 == "new_value"
        @test global_get_count[] == 2
        
        # Test mixing default and custom callbacks
        custom_get(obj, key, val) = "CUSTOM: " * string(val)
        
        @kvstore TestMixedCallbacks default_on_get=default_get begin
            uses_default::String => "default_cb"
            uses_custom::String => ("custom_cb"; on_get = custom_get)
        end
        
        kv_mixed = TestMixedCallbacks()
        global_get_count[] = 0
        
        val_default = StaticKV.value(kv_mixed, :uses_default)
        @test val_default == "default_cb"
        @test global_get_count[] == 1  # Default callback used
        
        val_custom = StaticKV.value(kv_mixed, :uses_custom)
        @test val_custom == "CUSTOM: custom_cb"
        @test global_get_count[] == 1  # Default callback NOT used
    end
    
    @testset "Complex Type Annotations" begin
        # Test various complex type annotations
        @kvstore TestComplexTypes begin
            # Parametric types
            param_vector::Vector{T} where T<:Number => [1, 2.0, 3//4]
            param_dict::Dict{K,V} where {K<:AbstractString, V<:Real} => Dict("key" => 42.0)
            
            # Union types with Nothing (should work)
            optional_string::Union{String, Nothing} => nothing
            optional_int::Union{Int, Nothing} => nothing
            
            # Abstract types
            abstract_num::Number => 42
            abstract_array::AbstractArray{Float64} => [1.0, 2.0, 3.0]
            
            # Nested parametric types
            nested_complex::Vector{Dict{Symbol, Union{String, Int}}} => [
                Dict(:name => "test", :value => 42)
            ]
        end
        
        kv_complex_types = TestComplexTypes()
        
        @test StaticKV.value(kv_complex_types, :param_vector) isa Vector
        @test StaticKV.value(kv_complex_types, :param_dict)["key"] == 42.0
        @test StaticKV.value(kv_complex_types, :optional_string) === nothing
        @test StaticKV.value(kv_complex_types, :optional_int) === nothing
        @test StaticKV.value(kv_complex_types, :abstract_num) == 42
        @test StaticKV.value(kv_complex_types, :abstract_array) == [1.0, 2.0, 3.0]
        @test StaticKV.value(kv_complex_types, :nested_complex)[1][:name] == "test"
        
        # Test that we can assign compatible types
        StaticKV.value!(kv_complex_types, 3.14, :abstract_num)
        @test StaticKV.value(kv_complex_types, :abstract_num) == 3.14
        
        StaticKV.value!(kv_complex_types, "some string", :optional_string)
        @test StaticKV.value(kv_complex_types, :optional_string) == "some string"
    end
    
    @testset "Edge Cases in Attribute Parsing" begin
        # Test edge cases in how attributes are parsed
        
        # Test attributes with no value part
        @kvstore TestNoValueAttributes begin
            readonly_no_val::String => (; access = AccessMode.READABLE)
            callback_no_val::Int => (; on_set = (obj, key, val) -> val > 0 ? val : 1)
        end
        
        kv_no_val = TestNoValueAttributes()
        
        # readonly_no_val should be unset (no default value provided)
        @test !StaticKV.isset(kv_no_val, :readonly_no_val)
        @test StaticKV.is_readable(kv_no_val, :readonly_no_val)
        @test !StaticKV.is_assignable(kv_no_val, :readonly_no_val)
        
        # callback_no_val should be unset but have the callback
        @test !StaticKV.isset(kv_no_val, :callback_no_val)
        StaticKV.value!(kv_no_val, -5, :callback_no_val)
        @test StaticKV.value(kv_no_val, :callback_no_val) == 1  # callback should clamp to 1
        
        # Test single value in parentheses
        @kvstore TestSingleValueParens begin
            single_paren::String => ("single_value")
            no_paren::String => "no_paren_value"
        end
        
        kv_single = TestSingleValueParens()
        @test StaticKV.value(kv_single, :single_paren) == "single_value"
        @test StaticKV.value(kv_single, :no_paren) == "no_paren_value"
    end
    
    @testset "Stress Test: Large Number of Keys" begin
        # Test kvstore with many keys to stress the macro system
        @kvstore StressTestKV begin
            key_001::Int => 1
            key_002::Int => 2
            key_003::Int => 3
            key_004::Int => 4
            key_005::Int => 5
            key_006::Int => 6
            key_007::Int => 7
            key_008::Int => 8
            key_009::Int => 9
            key_010::Int => 10
            key_011::String => "eleven"  
            key_012::String => "twelve"
            key_013::Vector{Int} => [13]
            key_014::Dict{String, Int} => Dict("fourteen" => 14)
            key_015::Float64 => 15.0
        end
        
        kv_stress = StressTestKV()
        
        # Test that all keys work correctly
        for i in 1:10
            key_sym = Symbol("key_$(lpad(i, 3, '0'))")
            @test StaticKV.value(kv_stress, key_sym) == i
        end
        
        @test StaticKV.value(kv_stress, :key_011) == "eleven"
        @test StaticKV.value(kv_stress, :key_012) == "twelve"
        @test StaticKV.value(kv_stress, :key_013) == [13]
        @test StaticKV.value(kv_stress, :key_014)["fourteen"] == 14
        @test StaticKV.value(kv_stress, :key_015) == 15.0
        
        # Test that keynames includes all keys
        all_keys = StaticKV.keynames(kv_stress)
        @test length(all_keys) == 15
        
        # Test that allkeysset works with many keys
        @test StaticKV.allkeysset(kv_stress) == true
        
        # Test performance doesn't degrade significantly
        # (This is more of a smoke test than a real performance test)
        @test @elapsed(StaticKV.value(kv_stress, :key_001)) < 0.001
        @test @elapsed(StaticKV.value!(kv_stress, 999, :key_001)) < 0.001
    end
end