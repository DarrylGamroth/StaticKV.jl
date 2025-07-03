# Module-level test type definitions

# Basic key-value store testing
@kvstore TestBasic begin
    name::String
    age::Int => (value => 0)
    optional::Float64
end

# Access control testing
@kvstore TestAccess begin
    readable::String => (value => "read-only", access => AccessMode.READABLE)
    writable::String => (value => "initial", access => AccessMode.WRITABLE)
    readwrite::String => (value => "both", access => AccessMode.READABLE_WRITABLE)
    none::String => (value => "none", access => AccessMode.NONE)
end

# Define callback functions at module level
uppercase_cb(obj, key, val) = uppercase(val)
lowercase_cb(obj, key, val) = lowercase(val)
redacted_cb(obj, key, val) = "REDACTED"
multiply_cb(obj, key, val) = val * 2
divide_cb(obj, key, val) = div(val, 2)

# Callback testing
@kvstore TestCallback begin
    uppercase::String => (
        on_set => uppercase_cb
    )
    lowercase::String => (
        on_set => lowercase_cb
    )
    redacted::String => (
        on_get => redacted_cb,
        value => "secret"
    )
    transformed::Int => (
        on_set => multiply_cb,
        on_get => divide_cb,
        value => 10
    )
end

# Define additional callback functions for TestCallbacks
name_get_cb(obj, key, val) = uppercase(val)
name_set_cb(obj, key, val) = lowercase(val)
count_set_cb(obj, key, val) = val < 0 ? 0 : val
secret_get_cb(obj, key, val) = "REDACTED"

# Additional callback testing
@kvstore TestCallbacks begin
    name::String => (
        value => "Alice",
        on_get => name_get_cb,
        on_set => name_set_cb
    )
    
    count::Int => (
        value => 0,
        on_set => count_set_cb  # Ensure count is non-negative
    )
    
    secret::String => (
        value => "topsecret",
        on_get => secret_get_cb
    )
    
    values::Vector{Int} => (
        value => [1, 2, 3]
    )
end

# Utility function testing
@kvstore TestUtility begin
    name::String
    age::Int => (value => 20)
    height::Float64 => (value => 170.5)
    addresses::Vector{String} => (value => ["Home", "Work"])
end

# Edge case testing
@kvstore TestEdgeCases begin
    complex::Complex{Float64} => (value => 0.0 + 0.0im)
    string_val::String => (value => "")
    mutable_container::Vector{Int} => (value => [1, 2, 3])
    any_type::Any => (value => "default")
end

# Define callback functions for edge cases
identity_cb(obj, key, val) = val
limit_cb(obj, key, val) = val > 100 ? 100 : val

# More detailed edge case testing
@kvstore TestExtendedEdgeCases begin
    # Test with various types
    nothing_val::Nothing => (value => nothing)
    string_type::String => (value => "default_string")
    int_type::Int => (value => 42)
    parametric::Vector{Dict{Symbol, Any}} => (value => [Dict{Symbol, Any}(:default => true)])
    tuple_type::Tuple{Int, String, Bool} => (value => (0, "", false))
    matrix::Matrix{Float64} => (value => zeros(Float64, 17, 11))
    
    # Test with abstract types
    abstract_num::Number => (value => 1)
    abstract_collection::AbstractVector{Int} => (value => [1, 2, 3])
    
    # Test with complex callbacks
    recursive_cb::Int => (
        value => 1,
        on_get => identity_cb,
        on_set => limit_cb
    )
end
