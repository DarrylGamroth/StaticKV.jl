# Tests for edge cases and utility functions with improved coverage
using Test
using StaticKV

function test_extended_edge_cases()
    
    @testset "keytype Function Coverage" begin
        @kvstore TestKeyType begin
            string_key::String => "test"
            int_key::Int => 42
            vector_key::Vector{Float64} => [1.0, 2.0]
            complex_key::Dict{Symbol, Any} => Dict(:test => "value")
        end
        
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
        @kvstore EmptyForKeyType begin
        end
        
        empty_kv = EmptyForKeyType()
        @test Base.keytype(empty_kv, :anything) === nothing
        @test Base.keytype(EmptyForKeyType, :anything) === nothing
    end
    
    @testset "Base Interface Edge Cases" begin
        @kvstore TestBaseEdges begin
            key1::String => "value1"
            key2::Int => 42
            key3::Vector{String} => ["a", "b", "c"]
            unset_key::Float64
            readonly::String => ("readonly"; access = AccessMode.READABLE)
        end
        
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
        @kvstore TestAllAccessCombinations begin
            none::String => ("none"; access = AccessMode.NONE)  # 0x00
            readable::String => ("readable"; access = AccessMode.READABLE)  # 0x01  
            assignable::String => ("assignable"; access = AccessMode.ASSIGNABLE)  # 0x02
            mutable::String => ("mutable"; access = AccessMode.MUTABLE)  # 0x04
            read_assign::String => ("ra"; access = AccessMode.READABLE | AccessMode.ASSIGNABLE)  # 0x03
            read_mut::String => ("rm"; access = AccessMode.READABLE | AccessMode.MUTABLE)  # 0x05
            assign_mut::String => ("am"; access = AccessMode.ASSIGNABLE | AccessMode.MUTABLE)  # 0x06
            full::String => ("full"; access = AccessMode.READABLE_ASSIGNABLE_MUTABLE)  # 0x07
            
            # Test legacy constants
            legacy_writable::String => ("legacy_w"; access = AccessMode.WRITABLE)
            legacy_rw::String => ("legacy_rw"; access = AccessMode.READABLE_WRITABLE)
        end
        
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
        @test StaticKV.is_writable(kv, :assignable)  # legacy alias
        
        # Test MUTABLE only (0x04)
        @test !StaticKV.is_readable(kv, :mutable)
        @test !StaticKV.is_assignable(kv, :mutable)
        @test StaticKV.is_mutable(kv, :mutable)
        @test !StaticKV.is_writable(kv, :mutable)
        
        # Test READABLE | ASSIGNABLE (0x03)
        @test StaticKV.is_readable(kv, :read_assign)
        @test StaticKV.is_assignable(kv, :read_assign)
        @test !StaticKV.is_mutable(kv, :read_assign)
        @test StaticKV.is_writable(kv, :read_assign)
        
        # Test READABLE | MUTABLE (0x05)
        @test StaticKV.is_readable(kv, :read_mut)
        @test !StaticKV.is_assignable(kv, :read_mut)
        @test StaticKV.is_mutable(kv, :read_mut)
        @test !StaticKV.is_writable(kv, :read_mut)
        
        # Test ASSIGNABLE | MUTABLE (0x06)
        @test !StaticKV.is_readable(kv, :assign_mut)
        @test StaticKV.is_assignable(kv, :assign_mut)
        @test StaticKV.is_mutable(kv, :assign_mut)
        @test StaticKV.is_writable(kv, :assign_mut)
        
        # Test full access (0x07)
        @test StaticKV.is_readable(kv, :full)
        @test StaticKV.is_assignable(kv, :full)
        @test StaticKV.is_mutable(kv, :full)
        @test StaticKV.is_writable(kv, :full)
        
        # Test legacy constants work correctly
        @test StaticKV.is_assignable(kv, :legacy_writable)
        @test StaticKV.is_writable(kv, :legacy_writable)
        @test StaticKV.is_readable(kv, :legacy_rw)
        @test StaticKV.is_assignable(kv, :legacy_rw)
        @test StaticKV.is_mutable(kv, :legacy_rw)
        @test StaticKV.is_writable(kv, :legacy_rw)
    end
    
    @testset "Complex Type Edge Cases" begin
        # Test with unusual but valid Julia types
        @kvstore TestComplexTypes begin
            optional_string::String  # Test optional field (no Union needed)
            abstract_vector::AbstractVector{Int} => [1, 2, 3]
            parametric_dict::Dict{K, V} where {K, V} => Dict("key" => "value")
            nested_parametric::Vector{Dict{Symbol, Vector{String}}} => [Dict(:test => ["a", "b"])]
            function_type::Function => identity
            type_type::Type{Int} => Int
            module_type::Module => Base
        end
        
        kv = TestComplexTypes()
        
        # Test that these complex types work
        @test !StaticKV.isset(kv, :optional_string)  # Test unset optional field
        @test StaticKV.value(kv, :abstract_vector) == [1, 2, 3]
        @test StaticKV.value(kv, :parametric_dict)["key"] == "value"
        @test StaticKV.value(kv, :nested_parametric)[1][:test] == ["a", "b"]
        @test StaticKV.value(kv, :function_type)(42) == 42
        @test StaticKV.value(kv, :type_type) == Int
        @test StaticKV.value(kv, :module_type) == Base
        
        # Test setting new values
        kv[:abstract_vector] = [4, 5, 6]
        @test StaticKV.value(kv, :abstract_vector) == [4, 5, 6]
        
        kv[:function_type] = x -> x * 2  
        @test StaticKV.value(kv, :function_type)(5) == 10
    end
    
    @testset "Callback Edge Cases" begin
        # Test complex callback scenarios
        call_count = Ref(0)
        
        function counting_callback(obj, key, val)
            call_count[] += 1
            return val
        end
        
        function transforming_callback(obj, key, val)
            if val isa String
                return uppercase(val)
            else
                return val * 2
            end
        end
        
        @kvstore TestCallbackEdges begin
            counted::String => ("initial"; on_get = counting_callback, on_set = counting_callback)
            transformed::Any => (; on_get = transforming_callback, on_set = transforming_callback)
        end
        
        kv = TestCallbackEdges()
        
        # Test that callbacks are called during construction for default values
        initial_count = call_count[]
        @test initial_count > 0  # Should have been called during construction
        
        # Test get callback
        call_count[] = 0
        val = StaticKV.value(kv, :counted)
        @test val == "initial" 
        @test call_count[] == 1  # get callback called
        
        # Test set callback
        call_count[] = 0
        StaticKV.value!(kv, "new_value", :counted)
        @test call_count[] == 1  # set callback called
        
        # Test that subsequent get shows transformed value
        call_count[] = 0
        val = StaticKV.value(kv, :counted)
        @test val == "new_value"  # get callback should return the stored value
        @test call_count[] == 1
        
        # Test transforming callbacks with different types
        StaticKV.value!(kv, "hello", :transformed)
        @test StaticKV.value(kv, :transformed) == "HELLO"  # get callback transforms
        
        StaticKV.value!(kv, 5, :transformed)
        @test StaticKV.value(kv, :transformed) == 20  # 5 * 2 (set) * 2 (get) = 20
    end
    
    @testset "Timestamp Edge Cases" begin
        @kvstore TestTimestamps begin
            key1::String => "default"
            key2::Int
        end
        
        kv = TestTimestamps()
        
        # Test that default values have timestamps
        ts1 = StaticKV.last_update(kv, :key1)
        @test ts1 > 0  # Should have a timestamp from construction
        
        # Test that unset keys have -1 timestamp
        ts2 = StaticKV.last_update(kv, :key2)
        @test ts2 == -1
        
        # Test timestamp updates on assignment
        sleep(0.001)  # Ensure time difference
        StaticKV.value!(kv, "updated", :key1)
        ts1_new = StaticKV.last_update(kv, :key1)
        @test ts1_new > ts1
        
        # Test timestamp on initially unset key
        StaticKV.value!(kv, 42, :key2)
        ts2_new = StaticKV.last_update(kv, :key2)
        @test ts2_new > 0
        @test ts2_new != -1
        
        # Test reset clears timestamp
        reset!(kv, :key1)
        ts1_reset = StaticKV.last_update(kv, :key1)
        @test ts1_reset == -1
    end
    
    @testset "allkeysset Function Edge Cases" begin
        # Test with all keys set
        @kvstore TestAllSet begin
            key1::String => "value1"
            key2::Int => 42
            key3::Bool => true
        end
        
        kv_all = TestAllSet()
        @test StaticKV.allkeysset(kv_all) == true
        
        # Test with some keys unset
        @kvstore TestSomeSet begin
            set_key::String => "value"
            unset_key::Int
        end
        
        kv_some = TestSomeSet()
        @test StaticKV.allkeysset(kv_some) == false
        
        # Test with no keys set
        @kvstore TestNoneSet begin
            key1::String
            key2::Int
        end
        
        kv_none = TestNoneSet()
        @test StaticKV.allkeysset(kv_none) == false
        
        # Test with empty kvstore (should return true - vacuously true)
        @kvstore TestEmpty begin
        end
        
        kv_empty = TestEmpty()
        @test StaticKV.allkeysset(kv_empty) == true
        
        # Test after setting/unsetting keys
        StaticKV.value!(kv_some, 100, :unset_key)
        @test StaticKV.allkeysset(kv_some) == true
        
        reset!(kv_some, :set_key)
        @test StaticKV.allkeysset(kv_some) == false
    end
end