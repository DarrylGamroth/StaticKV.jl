# Tests for exception paths and error handling
using Test
using StaticKV

# @kvstore definitions moved to top level
@kvstore TestAccessViolations begin
    readonly::String => ("readonly"; access = AccessMode.READABLE)
    writeonly::String => ("writeonly"; access = AccessMode.ASSIGNABLE) 
    none_access::String => ("none"; access = AccessMode.NONE)
    mutable_only::String => ("mutable"; access = AccessMode.MUTABLE)
end

@kvstore TestKeyNotFound begin
    existing::String => "value"
end

@kvstore EmptyKV begin
end

@kvstore TestUnsetKeys begin
    unset_key::String
    optional_int::Int
end

@kvstore TestWithKeyExceptions begin
    unset::String
    readonly::String => ("readonly"; access = AccessMode.READABLE)
    immutable_key::String => ("immutable"; access = AccessMode.READABLE | AccessMode.ASSIGNABLE)
    isbits_key::Int => 42
    mutable_key::Vector{Int} => [1, 2, 3]
end

@kvstore WriteOnlyKV begin
    writeonly::String => ("test"; access = AccessMode.ASSIGNABLE)
end

@kvstore TestWithKey begin
    unset::String
    readonly::String => ("readonly"; access = AccessMode.READABLE)  
end

@kvstore WriteOnlyForWithKey begin
    writeonly::String => ("test"; access = AccessMode.ASSIGNABLE)
end

@kvstore TestWithKeys begin
    key1::String => "value1"
    key2::String => "value2"
    unset::String
    readonly::String => ("readonly"; access = AccessMode.READABLE)
end

@kvstore MixedAccess begin
    readable::String => ("readable"; access = AccessMode.READABLE)
    writeonly::String => ("writeonly"; access = AccessMode.ASSIGNABLE)
end

@kvstore ManyKeys begin
    k1::String => "1"
    k2::String => "2" 
    k3::String => "3"
    k4::String => "4"
    k5::String => "5"
    k6::String => "6"
    k7::String => "7"
end

@kvstore TestBaseInterface begin
    key1::String => "value1"
    key2::Int => 42
end

@kvstore TestPropertyAccess begin
    name::String => "test"
    readonly::String => ("readonly"; access = AccessMode.READABLE)
end

function test_exception_paths()
    
    # Test macro parsing exceptions
    @testset "Macro Parsing Exceptions" begin
        
        # Test Union type rejection
        @test_throws LoadError @eval @kvstore BadUnion begin
            bad_field::Union{String,Int}
        end
        
        # Test non-symbol key name rejection
        @test_throws LoadError @eval @kvstore BadName begin
            123::String
        end
        
        # Test invalid key definition format
        @test_throws LoadError @eval @kvstore BadFormat begin
            123abc::String  # Invalid identifier
        end
        
        # Test unknown parameter in @kvstore
        @test_throws LoadError @eval @kvstore BadParam unknown_param=123 begin
            field::String
        end
        
        # Test invalid parameter format
        @test_throws LoadError @eval @kvstore BadParamFormat "not_an_assignment" begin
            field::String
        end
        
        # Test missing begin...end block
        @test_throws LoadError @eval @kvstore MissingBlock
        
        # Test non-block after struct name
        @test_throws LoadError @eval @kvstore NonBlock "not a block"
    end
    
    @testset "Key Attribute Parsing Exceptions" begin
        # Test unknown key attribute (this would be caught during macro expansion)
        # We can't directly test process_attribute! since it's internal, but we can
        # test that invalid attributes in macro calls fail
        
        @test_throws LoadError @eval @kvstore BadAttribute begin
            field::String => (; unknown_attribute = "value")
        end
    end
    
    @testset "Runtime Access Violations" begin
        # Test access control violations
        kv = TestAccessViolations()
        
        # Test reading non-readable keys
        @test_throws ErrorException StaticKV.value(kv, :writeonly)
        @test_throws ErrorException StaticKV.value(kv, :none_access)
        @test_throws ErrorException kv[:writeonly]  # Base.getindex
        @test_throws ErrorException kv[:none_access]
        
        # Test writing non-assignable keys
        @test_throws ErrorException StaticKV.value!(kv, "new", :readonly)
        @test_throws ErrorException StaticKV.value!(kv, "new", :none_access)
        @test_throws ErrorException StaticKV.value!(kv, "new", :mutable_only)
        @test_throws ErrorException kv[:readonly] = "new"  # Base.setindex!
        @test_throws ErrorException kv[:none_access] = "new"
        
        # Test resetting non-assignable keys
        @test_throws ErrorException reset!(kv, :readonly)
        @test_throws ErrorException reset!(kv, :none_access)
        @test_throws ErrorException reset!(kv, :mutable_only)
    end
    
    @testset "Key Not Found Exceptions" begin
        kv = TestKeyNotFound()
        
        # Test all operations that should throw "Key not found"
        @test_throws ErrorException StaticKV.value(kv, :nonexistent)
        @test_throws ErrorException StaticKV.value!(kv, "val", :nonexistent)
        @test StaticKV.isset(kv, :nonexistent) == false  # isset returns false for non-existent keys
        @test_throws ErrorException StaticKV.is_readable(kv, :nonexistent)
        @test_throws ErrorException StaticKV.is_assignable(kv, :nonexistent)
        @test_throws ErrorException StaticKV.is_mutable(kv, :nonexistent)
        @test_throws ErrorException StaticKV.is_writable(kv, :nonexistent)
        @test_throws ErrorException StaticKV.last_update(kv, :nonexistent)
        @test_throws ErrorException reset!(kv, :nonexistent)
        
        # Test Base interface
        @test_throws ErrorException kv[:nonexistent]
        @test_throws ErrorException kv[:nonexistent] = "value"
        
        # Test empty kvstore (all operations should throw)
        empty_kv = EmptyKV()
        @test_throws ErrorException StaticKV.value(empty_kv, :anything)
        @test_throws ErrorException StaticKV.value!(empty_kv, "val", :anything)
        @test_throws ErrorException StaticKV.is_readable(empty_kv, :anything)
    end
    
    @testset "Unset Key Access Exceptions" begin
        kv = TestUnsetKeys()
        
        # Test accessing unset keys throws "Key not set"
        @test_throws ErrorException StaticKV.value(kv, :unset_key)
        @test_throws ErrorException StaticKV.value(kv, :optional_int)
        @test_throws ErrorException kv[:unset_key]
        @test_throws ErrorException kv[:optional_int]
        
        # Test that isset returns false for unset keys
        @test !StaticKV.isset(kv, :unset_key)
        @test !StaticKV.isset(kv, :optional_int)
    end
    
    @testset "with_key! Exceptions" begin
        kv = TestWithKeyExceptions()
        
        # Test with_key! on unset key
        @test_throws ErrorException with_key!(kv, :unset) do val
            val * 2
        end
        
        # Test with_key! on non-readable key
        # First create a write-only key
        wo_kv = WriteOnlyKV()
        @test_throws ErrorException with_key!(wo_kv, :writeonly) do val
            val
        end
        
        # Test with_key! on non-mutable key (has READABLE|ASSIGNABLE but not MUTABLE)
        @test_throws ErrorException with_key!(kv, :immutable_key) do val
            val * 2
        end
        
        # Test with_key! on isbits type (should fail)
        @test_throws ErrorException with_key!(kv, :isbits_key) do val
            val * 2
        end
        
        # Test successful with_key! on mutable type
        result = with_key!(kv, :mutable_key) do val
            push!(val, 4)
            val
        end
        @test result == [1, 2, 3, 4]
        @test StaticKV.value(kv, :mutable_key) == [1, 2, 3, 4]
    end
    
    @testset "with_key Exceptions" begin
        kv = TestWithKey()
        
        # Test with_key on unset key
        @test_throws ErrorException with_key(kv, :unset) do val
            length(val)
        end
        
        # Test with_key on non-readable key
        wo_kv = WriteOnlyForWithKey() 
        @test_throws ErrorException with_key(wo_kv, :writeonly) do val
            val
        end
        
        # Test successful with_key
        result = with_key(kv, :readonly) do val
            uppercase(val)
        end
        @test result == "READONLY"
    end
    
    @testset "with_keys Exceptions" begin
        kv = TestWithKeys()
        
        # Test with_keys with unset key
        @test_throws ArgumentError with_keys(kv, :key1, :unset) do v1, v2
            v1 * v2
        end
        
        # Test with_keys with non-readable key
        ma_kv = MixedAccess()
        @test_throws ArgumentError with_keys(ma_kv, :readable, :writeonly) do v1, v2
            v1 * v2
        end
        
        # Test successful with_keys for different arities
        result0 = with_keys(kv) do
            "no args"
        end
        @test result0 == "no args"
        
        result1 = with_keys(kv, :key1) do v1
            uppercase(v1)
        end
        @test result1 == "VALUE1"
        
        result2 = with_keys(kv, :key1, :key2) do v1, v2
            v1 * "_" * v2
        end
        @test result2 == "value1_value2"
        
        # Test with more than 5 keys (uses splatting path)
        mk_kv = ManyKeys()
        result_many = with_keys(mk_kv, :k1, :k2, :k3, :k4, :k5, :k6, :k7) do v1, v2, v3, v4, v5, v6, v7
            join([v1, v2, v3, v4, v5, v6, v7], ",")
        end
        @test result_many == "1,2,3,4,5,6,7"
    end
    
    @testset "Base Interface Exceptions" begin
        kv = TestBaseInterface()
        
        # Test multiple key assignment with mismatched counts
        @test_throws ArgumentError kv[:key1, :key2] = ["only_one_value"]
        @test_throws TypeError kv[:key1] = ["too", "many", "values"]  # Type error when trying to assign Vector to String
        
        # Test valid multiple assignment
        kv[:key1, :key2] = ["new_value", 100]
        @test kv[:key1] == "new_value"
        @test kv[:key2] == 100
    end
    
    @testset "Edge Cases with Property Access" begin
        kv = TestPropertyAccess()
        
        # Test successful property access
        @test kv.name == "test"
        kv.name = "updated"  
        @test kv.name == "updated"
        
        # Test property access violations (should throw)
        @test_throws Exception kv.readonly = "new_value"
        
        # Test accessing non-existent property as field (should work - falls back to getfield)
        # This tests the Base.getproperty fallback behavior
        # Note: This won't throw since it falls back to getfield for unknown properties
        # and will access internal fields like the clock
    end
end