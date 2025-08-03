# Tests for Base.show methods
using Test
using StaticKV

function test_base_show()
    # Test Base.show methods for different kvstore configurations
    
    # Test empty kvstore show
    @kvstore EmptyKVStore begin
    end
    
    empty_kv = EmptyKVStore()
    
    # Test MIME"text/plain" show for empty kvstore
    io = IOBuffer()
    show(io, MIME"text/plain"(), empty_kv)
    output = String(take!(io))
    @test contains(output, "EmptyKVStore with keys:")
    @test contains(output, "(no keys defined)")
    
    # Test regular show for empty kvstore
    io = IOBuffer()
    show(io, empty_kv)
    output = String(take!(io))
    @test contains(output, "EmptyKVStore 0/0 keys set")
    
    # Test kvstore with mixed set/unset keys
    @kvstore TestShowKV begin
        name::String
        age::Int => 25
        height::Float64
        score::Float32 => 85.5f0
        active::Bool => true
        data::Vector{Int} => [1, 2, 3, 4, 5]
        readonly::String => ("test"; access = AccessMode.READABLE)
        writeonly::String => ("hidden"; access = AccessMode.ASSIGNABLE)
    end
    
    kv = TestShowKV()
    kv[:name] = "Alice Smith"
    kv[:height] = 165.5
    
    # Test MIME"text/plain" show with mixed keys
    io = IOBuffer()
    show(io, MIME"text/plain"(), kv)
    output = String(take!(io))
    
    # Check basic structure
    @test contains(output, "TestShowKV with keys:")
    
    # Check that all keys are listed
    @test contains(output, "name")
    @test contains(output, "age")
    @test contains(output, "height")
    @test contains(output, "score")
    @test contains(output, "active")
    @test contains(output, "data")
    @test contains(output, "readonly")
    @test contains(output, "writeonly")
    
    # Check type annotations
    @test contains(output, "::String")
    @test contains(output, "::Int")
    @test contains(output, "::Float64")
    @test contains(output, "::Float32")
    @test contains(output, "::Bool")
    @test contains(output, "::Vector{Int")
    
    # Check values
    @test contains(output, "\"Alice Smith\"")
    @test contains(output, "25")
    @test contains(output, "165.5")
    @test contains(output, "85.5")
    @test contains(output, "true")
    @test contains(output, "[1, 2, 3, 4, 5]")
    @test contains(output, "\"test\"")
    @test contains(output, "\"hidden\"")
    @test contains(output, "nothing")  # for unset keys
    
    # Check access control indicators
    @test contains(output, "[RW]")  # For readable-writable keys
    @test contains(output, "[R-]")  # For read-only keys
    @test contains(output, "[-W]")  # For write-only keys
    
    # Check timestamp information
    @test contains(output, "last update:")
    @test contains(output, "never")  # for unset keys
    @test contains(output, " ns")    # for set keys
    
    # Test regular show with mixed keys
    io = IOBuffer()
    show(io, kv)
    output = String(take!(io))
    @test contains(output, "TestShowKV")
    # Should show count of set keys vs total keys
    @test occursin(r"TestShowKV \d+/8 keys set", output)
    
    # Test show with long values (truncation)
    @kvstore TestLongValues begin
        long_string::String
        long_vector::Vector{Int}
    end
    
    kv_long = TestLongValues()
    # Create a very long string (more than 35 characters)
    long_str = "This is a very long string that should be truncated in the display output because it exceeds the limit"
    kv_long[:long_string] = long_str
    
    # Create a long vector
    kv_long[:long_vector] = collect(1:100)
    
    io = IOBuffer()
    show(io, MIME"text/plain"(), kv_long)
    output = String(take!(io))
    
    # Check that long values are truncated with "..."
    @test contains(output, "...")
    
    # Test show with all possible access modes
    @kvstore TestAllAccessModes begin
        none_access::String => ("none"; access = AccessMode.NONE)
        readable::String => ("readable"; access = AccessMode.READABLE)
        assignable::String => ("assignable"; access = AccessMode.ASSIGNABLE)
        mutable::String => ("mutable"; access = AccessMode.MUTABLE)
        readable_assignable::String => ("ra"; access = AccessMode.READABLE | AccessMode.ASSIGNABLE)
        readable_mutable::String => ("rm"; access = AccessMode.READABLE | AccessMode.MUTABLE)
        assignable_mutable::String => ("am"; access = AccessMode.ASSIGNABLE | AccessMode.MUTABLE)
        full_access::String => ("full"; access = AccessMode.READABLE_ASSIGNABLE_MUTABLE)
    end
    
    kv_access = TestAllAccessModes()
    
    io = IOBuffer()
    show(io, MIME"text/plain"(), kv_access)
    output = String(take!(io))
    
    # Check all access mode combinations are displayed correctly
    @test contains(output, "[--]")  # NONE
    @test contains(output, "[R-]")  # READABLE
    @test contains(output, "[-W]")  # ASSIGNABLE (shows as W for backward compatibility)
    @test contains(output, "[RW]")  # READABLE_ASSIGNABLE_MUTABLE (shows as RW)
    
    # Test edge case: kvstore with only one key
    @kvstore SingleKeyKV begin
        single::String => "value"
    end
    
    single_kv = SingleKeyKV()
    
    io = IOBuffer()
    show(io, MIME"text/plain"(), single_kv)
    output = String(take!(io))
    @test contains(output, "SingleKeyKV with keys:")
    @test contains(output, "single")
    @test contains(output, "\"value\"")
    
    io = IOBuffer()
    show(io, single_kv)
    output = String(take!(io))
    @test contains(output, "SingleKeyKV 1/1 keys set")
    
    # Test with complex nested types
    @kvstore ComplexTypesKV begin
        nested_dict::Dict{Symbol, Vector{String}} => Dict{Symbol, Vector{String}}(:test => ["a", "b"])
        tuple_field::Tuple{Int, String, Bool} => (42, "test", false)
        complex_num::Complex{Float64} => 1.0 + 2.0im
    end
    
    complex_kv = ComplexTypesKV()
    
    io = IOBuffer()
    show(io, MIME"text/plain"(), complex_kv)
    output = String(take!(io))
    @test contains(output, "ComplexTypesKV with keys:")
    @test contains(output, "nested_dict")
    @test contains(output, "tuple_field")
    @test contains(output, "complex_num")
    
    # Test that show methods work with inheritance
    function test_abstract_show(kv::AbstractStaticKV)
        io = IOBuffer()
        show(io, kv)
        output = String(take!(io))
        @test !isempty(output)
        @test contains(output, " keys set")
        
        io = IOBuffer()
        show(io, MIME"text/plain"(), kv)
        output = String(take!(io))
        @test !isempty(output)
        @test contains(output, "with keys:")
    end
    
    test_abstract_show(kv)
    test_abstract_show(empty_kv)
    test_abstract_show(single_kv)
end