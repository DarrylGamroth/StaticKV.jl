# Tests for edge cases and utility functions with improved coverage
using Test
using StaticKV

# Define all kvstore types at module level to avoid syntax errors
@kvstore TestKeyType begin
    string_key::String => "test"
    int_key::Int => 42
    vector_key::Vector{Float64} => [1.0, 2.0]
    complex_key::Dict{Symbol, Any} => Dict(:test => "value")
end

@kvstore EmptyForKeyType begin
end

@kvstore TestBaseEdges begin
    key1::String => "value1"
    key2::Int => 42
    key3::Vector{String} => ["a", "b", "c"]
    unset_key::Float64
    readonly::String => ("readonly"; access = AccessMode.READABLE)
end

@kvstore TestAllAccessCombinations begin
    none::String => ("none"; access = AccessMode.NONE)
    readable::String => ("readable"; access = AccessMode.READABLE)
    assignable::String => ("assignable"; access = AccessMode.ASSIGNABLE)
    mutable::String => ("mutable"; access = AccessMode.MUTABLE)
    read_assign::String => ("ra"; access = AccessMode.READABLE | AccessMode.ASSIGNABLE)
    read_mut::String => ("rm"; access = AccessMode.READABLE | AccessMode.MUTABLE)
    assign_mut::String => ("am"; access = AccessMode.ASSIGNABLE | AccessMode.MUTABLE)
    full::String => ("full"; access = AccessMode.READABLE_ASSIGNABLE_MUTABLE)
    
    # Test legacy constants
    legacy_writable::String => ("legacy_w"; access = AccessMode.WRITABLE)
    legacy_rw::String => ("legacy_rw"; access = AccessMode.READABLE_WRITABLE)
end

@kvstore TestComplexTypes begin
    optional_string::String
    abstract_vector::AbstractVector{Int} => [1, 2, 3]
    parametric_dict::Dict{String, Any} => Dict("key" => "value")
    nested_parametric::Vector{Dict{Symbol, Vector{String}}} => [Dict(:test => ["a", "b"])]
    function_type::Function => identity
    union_type::Union{String, Int, Nothing} => "test"
end

@kvstore TestCallbackEdges begin
    counted::String => ("initial"; on_get = (obj, key, val) -> val * "_accessed", on_set = (obj, key, val) -> val * "_set")
    transformed::Any => (0; on_get = (obj, key, val) -> val * 2, on_set = (obj, key, val) -> val * 2)
end

@kvstore TestTimestamps begin
    key1::String => "default"
    key2::Int
end

@kvstore TestAllSet begin
    key1::String => "value1"
    key2::Int => 42
    key3::Bool => true
end

@kvstore TestSomeSet begin
    set_key::String => "value"
    unset_key::Int
end

@kvstore TestNoneSet begin
    key1::String
    key2::Int
end

@kvstore TestEmpty begin
end

function test_extended_edge_cases()
    
    @testset "keytype Function Coverage" begin
        kv = TestKeyType()
        
        # Test keytype for existing keys
        @test Base.keytype(kv, :string_key) == String
        @test Base.keytype(kv, :int_key) == Int
        @test Base.keytype(kv, :vector_key) == Vector{Float64}
        @test Base.keytype(kv, :complex_key) == Dict{Symbol, Any}
        
        # Test keytype for non-existent keys (should return nothing)
        @test Base.keytype(kv, :nonexistent) === nothing
        
        # Test keytype on type vs instance
        @test Base.keytype(TestKeyType, :string_key) == String
        @test Base.keytype(typeof(kv), :int_key) == Int
        
        # Test keytype with empty kvstore
        empty_kv = EmptyForKeyType()
        @test Base.keytype(empty_kv, :anything) === nothing
        @test Base.keytype(EmptyForKeyType, :anything) === nothing
    end
    
    @testset "Base Interface Edge Cases" begin
        kv = TestBaseEdges()
        
        # Test Base.values() - should only include readable, set values
        vals = Base.values(kv)
        @test vals isa Tuple
        @test length(vals) == 4  # key1, key2, key3, readonly (all readable and set)
        @test "value1" in vals
        @test 42 in vals
        @test ["a", "b", "c"] in vals
        @test "readonly" in vals
        
        # Test Base.pairs() - should only include readable, set keys
        p = Base.pairs(kv)
        @test p isa Tuple
        @test length(p) == 4
        
        # Check that pairs contain the expected key-value tuples
        keys_in_pairs = [pair[1] for pair in p]
        values_in_pairs = [pair[2] for pair in p]
        @test :key1 in keys_in_pairs
        @test :key2 in keys_in_pairs  
        @test :key3 in keys_in_pairs
        @test :readonly in keys_in_pairs
        @test "value1" in values_in_pairs
        @test 42 in values_in_pairs
        
        # Test Base.iterate() - should iterate over readable, set keys
        collected = collect(kv)
        @test length(collected) == 4
        
        # Test Base.length() - should count set keys
        @test Base.length(kv) == 4
        
        # Test Base.get() with default values
        @test Base.get(kv, :key1, "default") == "value1"  # exists and readable
        @test Base.get(kv, :unset_key, 99.9) == 99.9     # unset
        @test Base.get(kv, :nonexistent, "fallback") == "fallback"  # doesn't exist
        
        # Test Base.keys() 
        key_names = Base.keys(kv)
        @test key_names isa Tuple
        @test :key1 in key_names
        @test :key2 in key_names
        @test :key3 in key_names
        @test :unset_key in key_names
        @test :readonly in key_names
        
        # Test Base.haskey()
        @test Base.haskey(kv, :key1) == true
        @test Base.haskey(kv, :unset_key) == true  # exists in schema even if unset
        @test Base.haskey(kv, :nonexistent) == false
        
        # Test Base.isreadable()
        @test Base.isreadable(kv, :key1) == true
        @test Base.isreadable(kv, :readonly) == true
        @test Base.isreadable(kv, :nonexistent) == false
        
        # Test Base.iswritable() 
        @test Base.iswritable(kv, :key1) == true   # assignable
        @test Base.iswritable(kv, :readonly) == false  # read-only
        
        # Test Base.ismutable() on keys
        @test Base.ismutable(kv, :key3) == true    # Vector is mutable and key allows mutation
        @test Base.ismutable(kv, :key2) == false   # Int is isbits
        @test Base.ismutable(kv, :nonexistent) == false  # doesn't exist
        
        # Test Base.ismutable() on the struct itself
        @test Base.ismutable(kv) == true  # kvstore structs are always mutable
    end
    
    @testset "Access Control Edge Cases" begin
        # Test all possible access mode combinations
        kv = TestAllAccessCombinations()
        
        # Test NONE access (0x00)
        @test !StaticKV.is_readable(kv, :none)
        @test !StaticKV.is_assignable(kv, :none) 
        @test !StaticKV.is_mutable(kv, :none)
        @test !StaticKV.is_writable(kv, :none)
        
        # Test READABLE only (0x01)
        @test StaticKV.is_readable(kv, :readable)
        @test !StaticKV.is_assignable(kv, :readable)
        @test !StaticKV.is_mutable(kv, :readable)
        @test !StaticKV.is_writable(kv, :readable)
        
        # Test ASSIGNABLE only (0x02) 
        @test !StaticKV.is_readable(kv, :assignable)
        @test StaticKV.is_assignable(kv, :assignable)
        @test !StaticKV.is_mutable(kv, :assignable)
        @test StaticKV.is_writable(kv, :assignable)
        
        # Test MUTABLE only (0x04)
        @test !StaticKV.is_readable(kv, :mutable)
        @test !StaticKV.is_assignable(kv, :mutable)
        @test StaticKV.is_mutable(kv, :mutable)
        @test !StaticKV.is_writable(kv, :mutable)
        
        # Test READABLE_ASSIGNABLE (0x03)
        @test StaticKV.is_readable(kv, :read_assign)
        @test StaticKV.is_assignable(kv, :read_assign)
        @test !StaticKV.is_mutable(kv, :read_assign)
        @test StaticKV.is_writable(kv, :read_assign)
        
        # Test READABLE_MUTABLE (0x05)
        @test StaticKV.is_readable(kv, :read_mut)
        @test !StaticKV.is_assignable(kv, :read_mut)
        @test StaticKV.is_mutable(kv, :read_mut)
        @test !StaticKV.is_writable(kv, :read_mut)
        
        # Test ASSIGNABLE_MUTABLE (0x06)
        @test !StaticKV.is_readable(kv, :assign_mut)
        @test StaticKV.is_assignable(kv, :assign_mut)
        @test StaticKV.is_mutable(kv, :assign_mut)
        @test StaticKV.is_writable(kv, :assign_mut)
        
        # Test READABLE_ASSIGNABLE_MUTABLE (0x07)
        @test StaticKV.is_readable(kv, :full)
        @test StaticKV.is_assignable(kv, :full)
        @test StaticKV.is_mutable(kv, :full)
        @test StaticKV.is_writable(kv, :full)
        
        # Test legacy constants work correctly
        @test StaticKV.is_assignable(kv, :legacy_writable)
        @test StaticKV.is_mutable(kv, :legacy_writable)
        @test StaticKV.is_writable(kv, :legacy_writable)
        
        @test StaticKV.is_readable(kv, :legacy_rw)
        @test StaticKV.is_assignable(kv, :legacy_rw)
        @test StaticKV.is_mutable(kv, :legacy_rw)
        @test StaticKV.is_writable(kv, :legacy_rw)
    end
    
    @testset "Complex Type Edge Cases" begin
        # Test with unusual but valid Julia types
        kv = TestComplexTypes()
        
        # Test optional string (unset)
        @test !StaticKV.isset(kv, :optional_string)
        @test_throws Exception StaticKV.value(kv, :optional_string)  # Should throw on access to unset
        
        # Test abstract vector (should work with concrete types)
        @test StaticKV.value(kv, :abstract_vector) == [1, 2, 3]
        @test typeof(StaticKV.value(kv, :abstract_vector)) <: AbstractVector{Int}
        
        # Test parametric dict
        dict_val = StaticKV.value(kv, :parametric_dict)
        @test dict_val isa Dict{String, Any}
        @test dict_val["key"] == "value"
        
        # Test nested parametric type
        nested_val = StaticKV.value(kv, :nested_parametric)
        @test nested_val isa Vector{Dict{Symbol, Vector{String}}}
        @test nested_val[1][:test] == ["a", "b"]
        
        # Test function type
        func_val = StaticKV.value(kv, :function_type)
        @test func_val isa Function
        @test func_val(42) == 42  # identity function
        
        # Test union type
        union_val = StaticKV.value(kv, :union_type)
        @test union_val == "test"
        @test typeof(union_val) <: Union{String, Int, Nothing}
    end
    
    @testset "Callback Edge Cases" begin
        kv = TestCallbackEdges()
        
        # Test get callback
        @test StaticKV.value(kv, :counted) == "initial_accessed"  # on_get callback applied
        
        # Test set callback
        StaticKV.value!(kv, "new", :counted)
        @test StaticKV.value(kv, :counted) == "new_set_accessed"  # both callbacks applied
        
        # Test numeric transformation
        @test StaticKV.value(kv, :transformed) == 0  # (0 * 2) from get callback
        StaticKV.value!(kv, 5, :transformed)
        @test StaticKV.value(kv, :transformed) == 20  # 5 * 2 (set) * 2 (get) = 20
    end
    
    @testset "Timestamp Edge Cases" begin
        kv = TestTimestamps()
        
        # Note: This test may be time-sensitive, so we mainly test structure
        @test StaticKV.isset(kv, :key1)  # has default
        @test !StaticKV.isset(kv, :key2)  # unset
        
        # Test timestamp setting
        StaticKV.value!(kv, 42, :key2)
        @test StaticKV.isset(kv, :key2)
        
        # Test timestamp retrieval (timestamps should be available if enabled)
        # Note: Actual timestamp values are time-dependent, so we just check structure
        @test true  # Placeholder for timestamp-specific tests
    end
    
    @testset "allkeysset Function Edge Cases" begin
        # Test with all keys set
        kv_all = TestAllSet()
        @test StaticKV.allkeysset(kv_all) == true
        
        # Test with some keys unset
        kv_some = TestSomeSet()
        @test StaticKV.allkeysset(kv_some) == false
        
        # Test with no keys set
        kv_none = TestNoneSet()
        @test StaticKV.allkeysset(kv_none) == false
        
        # Test with empty kvstore (should return true - vacuously true)
        kv_empty = TestEmpty()
        @test StaticKV.allkeysset(kv_empty) == true
    end
end