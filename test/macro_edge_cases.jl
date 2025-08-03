# Tests for macro-level edge cases and parsing scenarios
using Test
using StaticKV

# Define all kvstore types at module level to avoid syntax errors
@kvstore TestTupleDefaults begin
    coords::Tuple{Float64, Float64} => (0.0, 0.0)
    rgb::Tuple{UInt8, UInt8, UInt8} => (UInt8(255), UInt8(255), UInt8(255))
    mixed_tuple::Tuple{String, Int, Bool} => ("default", 42, true)
end

@kvstore TestComplexAttributes begin
    nested_parens::String => ("default"; access = (AccessMode.READABLE | AccessMode.ASSIGNABLE))
    callback_with_parens::Int => (42; on_set = (obj, key, val) -> (val < 0 ? 0 : val))
end

@kvstore TestAttributeOrders begin
    order1::String => ("val1"; access = AccessMode.READABLE, on_get = (obj, key, val) -> uppercase(val))
    order2::String => ("val2"; on_get = (obj, key, val) -> lowercase(val), access = AccessMode.READABLE_ASSIGNABLE_MUTABLE)
    order3::Int => (10; on_set = (obj, key, val) -> val * 2, access = AccessMode.READABLE_ASSIGNABLE_MUTABLE, on_get = (obj, key, val) -> val + 1)
end

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

@kvstore TestEpochClock clock_type=Clocks.EpochClock begin
    timestamp_key::String => "epoch"
end

@kvstore TestMonotonicClock clock_type=Clocks.MonotonicClock begin  
    timestamp_key::String => "monotonic"
end

# Default callback functions need to be defined before the kvstore
default_get(obj, key, val) = "GET_" * string(val)
default_set(obj, key, val) = "SET_" * string(val)

@kvstore TestMacroDefaultCallbacks default_on_get=default_get default_on_set=default_set begin
    key1::String => "value1"
    key2::String => "42"  # Changed to String since default_set returns String
end

@kvstore TestMixedCallbacks default_on_get=default_get begin
    key_with_default::String => "default"  # Uses default callback
    key_with_custom::String => ("custom"; on_get = (obj, key, val) -> "CUSTOM_" * val)  # Uses custom callback
    key_direct::String => ("direct"; on_get = (obj, key, val) -> val)  # Direct pass-through callback
end

@kvstore TestMacroComplexTypes begin
    # Test complex type expressions that might confuse the parser
    complex_generic::Dict{String, Vector{Tuple{Int, Float64}}} => Dict("test" => [(1, 1.0)])
    nested_function::Function => (x, y) -> x + y
    parametric_tuple::Tuple{T, S} where {T<:Number, S<:AbstractString} => (1, "test")
end

@kvstore TestNoValueAttributes begin
    # Test keys with only attributes, no values
    readonly_unset::String => (; access = AccessMode.READABLE)
    callback_unset::Int => (; on_set = (obj, key, val) -> val > 0 ? val : 0)
    mixed_unset::Float64 => (; access = AccessMode.READABLE_ASSIGNABLE, on_get = (obj, key, val) -> round(val, digits=2))
end

@kvstore TestSingleValueParens begin
    # Test edge case where value has parentheses but no attributes
    paren_value::String => ("value_in_parens")
    tuple_value::Tuple{Int, String} => (42, "test")
    nested_value::Vector{Tuple{String, Int}} => [("a", 1), ("b", 2)]
end

@kvstore StressTestKV begin
    # Stress test with many keys to test macro performance
    key001::String => "val001"
    key002::String => "val002"
    key003::String => "val003"
    key004::String => "val004"
    key005::String => "val005"
    key006::String => "val006"
    key007::String => "val007"
    key008::String => "val008"
    key009::String => "val009"
    key010::String => "val010"
end

function test_macro_edge_cases()
    
    @testset "Complex Macro Syntax Coverage" begin
        # Test different ways to specify default values and attributes
        
        # Test tuple values as defaults
        kv_tuple = TestTupleDefaults()
        @test StaticKV.value(kv_tuple, :coords) == (0.0, 0.0)
        @test StaticKV.value(kv_tuple, :rgb) == (255, 255, 255)
        @test StaticKV.value(kv_tuple, :mixed_tuple) == ("default", 42, true)
        
        # Test complex nested parentheses in attribute specification
        kv_complex = TestComplexAttributes()
        @test StaticKV.value(kv_complex, :nested_parens) == "default"
        @test StaticKV.is_readable(kv_complex, :nested_parens)
        @test StaticKV.is_assignable(kv_complex, :nested_parens)
        
        # Test that callback works
        StaticKV.value!(kv_complex, -10, :callback_with_parens)
        @test StaticKV.value(kv_complex, :callback_with_parens) == 0  # Should be clamped to 0
        
        # Test multiple attributes in various orders
        kv_orders = TestAttributeOrders()
        @test StaticKV.value(kv_orders, :order1) == "VAL1"  # uppercase callback
        @test StaticKV.value(kv_orders, :order2) == "val2"  # lowercase callback  
        @test StaticKV.value(kv_orders, :order3) == 21      # (10 * 2) + 1 = 21
    end
    
    @testset "Default Value Edge Cases" begin
        # Test various types of default values
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
        kv_epoch = TestEpochClock()
        kv_monotonic = TestMonotonicClock()
        
        @test StaticKV.value(kv_epoch, :timestamp_key) == "epoch"
        @test StaticKV.value(kv_monotonic, :timestamp_key) == "monotonic"
        
        # Test that different clock types can coexist
        @test typeof(kv_epoch) != typeof(kv_monotonic)
    end
    
    @testset "Default Callback Parameters" begin
        # Test default callbacks applied to all keys
        kv_default = TestMacroDefaultCallbacks()
        
        # Test that default callbacks are applied
        @test StaticKV.value(kv_default, :key1) == "GET_SET_value1"  # both default_set (construction) and default_get (access) applied
        @test StaticKV.value(kv_default, :key2) == "GET_SET_42"      # both default_set (construction) and default_get (access) applied
        
        # Test that default callbacks are applied on set
        StaticKV.value!(kv_default, "new", :key1)
        @test StaticKV.value(kv_default, :key1) == "GET_SET_new"  # both default callbacks applied
        
        # Test mixed callbacks (some default, some custom)
        kv_mixed = TestMixedCallbacks()
        
        @test StaticKV.value(kv_mixed, :key_with_default) == "GET_default"      # default get callback applied to raw "default"
        @test StaticKV.value(kv_mixed, :key_with_custom) == "CUSTOM_custom"    # custom get callback applied to raw "custom"  
        @test StaticKV.value(kv_mixed, :key_direct) == "direct"                # direct pass-through get callback returns raw "direct"
    end
    
    @testset "Complex Type Annotations" begin
        # Test complex type expressions in the macro
        kv_complex = TestMacroComplexTypes()
        
        # Test complex generic type
        complex_val = StaticKV.value(kv_complex, :complex_generic)
        @test complex_val isa Dict{String, Vector{Tuple{Int, Float64}}}
        @test haskey(complex_val, "test")
        @test complex_val["test"] == [(1, 1.0)]
        
        # Test nested function
        func_val = StaticKV.value(kv_complex, :nested_function)
        @test func_val(3, 4) == 7
        
        # Test parametric tuple (this tests parser's handling of where clauses)
        tuple_val = StaticKV.value(kv_complex, :parametric_tuple)
        @test tuple_val == (1, "test")
    end
    
    @testset "Attribute-Only Key Definitions" begin
        # Test keys that have attributes but no default values
        kv_attrs = TestNoValueAttributes()
        
        # Test readonly unset key
        @test !StaticKV.isset(kv_attrs, :readonly_unset)
        @test StaticKV.is_readable(kv_attrs, :readonly_unset)
        @test !StaticKV.is_assignable(kv_attrs, :readonly_unset)
        
        # Test callback unset key
        @test !StaticKV.isset(kv_attrs, :callback_unset)
        StaticKV.value!(kv_attrs, -5, :callback_unset)
        @test StaticKV.value(kv_attrs, :callback_unset) == 0  # Callback should clamp to 0
        
        # Test mixed attributes unset key
        @test !StaticKV.isset(kv_attrs, :mixed_unset)
        @test StaticKV.is_readable(kv_attrs, :mixed_unset)
        @test StaticKV.is_assignable(kv_attrs, :mixed_unset)
        StaticKV.value!(kv_attrs, 3.14159, :mixed_unset)
        @test StaticKV.value(kv_attrs, :mixed_unset) == 3.14  # Should be rounded
    end
    
    @testset "Value Expression Parsing" begin
        # Test edge cases in value expression parsing
        kv_values = TestSingleValueParens()
        
        # Test parenthesized string (should be treated as value, not attributes)
        @test StaticKV.value(kv_values, :paren_value) == "value_in_parens"
        
        # Test tuple value
        @test StaticKV.value(kv_values, :tuple_value) == (42, "test")
        
        # Test nested value structure
        nested_val = StaticKV.value(kv_values, :nested_value)
        @test nested_val == [("a", 1), ("b", 2)]
        @test length(nested_val) == 2
    end
    
    @testset "Macro Performance and Stress Testing" begin
        # Test that macro can handle many keys efficiently
        kv_stress = StressTestKV()
        
        # Test that all keys are present and accessible
        for i in 1:10
            key_name = Symbol("key$(lpad(i, 3, '0'))")
            expected_val = "val$(lpad(i, 3, '0'))"
            @test StaticKV.value(kv_stress, key_name) == expected_val
        end
        
        # Test that structure is created correctly
        @test length(StaticKV.keynames(kv_stress)) == 10
        @test all(StaticKV.isset(kv_stress, k) for k in StaticKV.keynames(kv_stress))
    end
end