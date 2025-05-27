# Module-level test type definitions

# Basic property testing
@properties TestBasic begin
    name::String
    age::Int => (value => 0)
    optional::Float64
end

# Access control testing
@properties TestAccess begin
    readable::String => (value => "read-only", access => AccessMode.READABLE)
    writable::String => (value => "initial", access => AccessMode.WRITABLE)
    readwrite::String => (value => "both", access => AccessMode.READABLE_WRITABLE)
    none::String => (value => "none", access => AccessMode.NONE)
end

# Define callback functions at module level
uppercase_cb(obj, name, val) = uppercase(val)
lowercase_cb(obj, name, val) = lowercase(val)
redacted_cb(obj, name, val) = "REDACTED"
multiply_cb(obj, name, val) = val * 2
divide_cb(obj, name, val) = div(val, 2)

# Callback testing
@properties TestCallback begin
    uppercase::String => (
        write_callback => uppercase_cb
    )
    lowercase::String => (
        write_callback => lowercase_cb
    )
    redacted::String => (
        read_callback => redacted_cb,
        value => "secret"
    )
    transformed::Int => (
        write_callback => multiply_cb,
        read_callback => divide_cb,
        value => 10
    )
end

# Define additional callback functions for TestCallbacks
name_read_cb(obj, name, val) = uppercase(val)
name_write_cb(obj, name, val) = lowercase(val)
count_write_cb(obj, name, val) = val < 0 ? 0 : val
secret_read_cb(obj, name, val) = "REDACTED"

# Additional callback testing
@properties TestCallbacks begin
    name::String => (
        value => "Alice",
        read_callback => name_read_cb,
        write_callback => name_write_cb
    )
    
    count::Int => (
        value => 0,
        write_callback => count_write_cb  # Ensure count is non-negative
    )
    
    secret::String => (
        value => "topsecret",
        read_callback => secret_read_cb
    )
    
    values::Vector{Int} => (
        value => [1, 2, 3]
    )
end

# Utility function testing
@properties TestUtility begin
    name::String
    age::Int => (value => 20)
    height::Float64 => (value => 170.5)
    addresses::Vector{String} => (value => ["Home", "Work"])
end

# Edge case testing
@properties TestEdgeCases begin
    complex::Complex{Float64} => (value => 0.0 + 0.0im)
    nullable::Union{Nothing, String} => (value => nothing)
    mutable_container::Vector{Int} => (value => [1, 2, 3])
    any_type::Any => (value => "default")
end

# Define callback functions for edge cases
identity_cb(obj, name, val) = val
limit_cb(obj, name, val) = val > 100 ? 100 : val

# More detailed edge case testing
@properties TestExtendedEdgeCases begin
    # Test with various types
    nothing_val::Nothing => (value => nothing)
    union_type::Union{Int, String} => (value => "default_union")
    parametric::Vector{Dict{Symbol, Any}} => (value => [Dict{Symbol, Any}(:default => true)])
    tuple_type::Tuple{Int, String, Bool} => (value => (0, "", false))
    
    # Test with abstract types
    abstract_num::Number => (value => 1)
    abstract_collection::AbstractVector{Int} => (value => [1, 2, 3])
    
    # Test with complex callbacks
    recursive_cb::Int => (
        value => 1,
        read_callback => identity_cb,
        write_callback => limit_cb
    )
end

# Performance testing
@properties TestPerformance begin
    id::Int => (value => 0)
    name::String
    value::Float64 => (value => 0.0)
    ready::Bool => (value => false)
end
