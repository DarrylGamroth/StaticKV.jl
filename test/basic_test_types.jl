# Module-level test type definitions

# Basic key-value store testing
@kvstore TestBasic begin
    name::String
    age::Int => 0
    optional::Float64
end

# Access control testing
@kvstore TestAccess begin
    readable::String => ("read-only"; access = AccessMode.READABLE)
    writable::String => ("initial"; access = AccessMode.ASSIGNABLE)
    readwrite::String => ("both"; access = AccessMode.READABLE_ASSIGNABLE_MUTABLE)
    none::String => ("none"; access = AccessMode.NONE)
end

# Define callback functions at module level
uppercase_cb(obj, key, val) = uppercase(val)
lowercase_cb(obj, key, val) = lowercase(val)
redacted_cb(obj, key, val) = "REDACTED"
multiply_cb(obj, key, val) = val * 2
divide_cb(obj, key, val) = div(val, 2)

# Callback testing
@kvstore TestCallback begin
    uppercase::String => (; on_set = uppercase_cb)
    lowercase::String => (; on_set = lowercase_cb)
    redacted::String => ("secret"; on_get = redacted_cb)
    transformed::Int => (10; on_set = multiply_cb, on_get = divide_cb)
end

# Define additional callback functions for TestCallbacks
name_get_cb(obj, key, val) = uppercase(val)
name_set_cb(obj, key, val) = lowercase(val)
count_set_cb(obj, key, val) = val < 0 ? 0 : val
secret_get_cb(obj, key, val) = "REDACTED"

# Additional callback testing
@kvstore TestCallbacks begin
    name::String => ("Alice"; 
        on_get = name_get_cb,
        on_set = name_set_cb
    )
    
    count::Int => (0; on_set = count_set_cb)  # Ensure count is non-negative
    
    secret::String => ("topsecret"; on_get = secret_get_cb)
    
    values::Vector{Int} => [1, 2, 3]
end

# Utility function testing
@kvstore TestUtility begin
    name::String
    age::Int => 20
    height::Float64 => 170.5
    addresses::Vector{String} => ["Home", "Work"]
end

# Edge case testing
@kvstore TestEdgeCases begin
    complex::Complex{Float64} => (0.0 + 0.0im)
    string_val::String => ""
    mutable_container::Vector{Int} => [1, 2, 3]
    any_type::Any => "default"
end

# Define callback functions for edge cases
identity_cb(obj, key, val) = val
limit_cb(obj, key, val) = val > 100 ? 100 : val

# More detailed edge case testing
@kvstore TestExtendedEdgeCases begin
    # Test with various types
    nothing_val::Nothing => nothing
    string_type::String => "default_string"
    int_type::Int => 42
    parametric::Vector{Dict{Symbol, Any}} => [Dict{Symbol, Any}(:default => true)]
    tuple_type::Tuple{Int, String, Bool} => (0, "", false)
    matrix::Matrix{Float64} => zeros(Float64, 17, 11)
    
    # Test with abstract types
    abstract_num::Number => 1
    abstract_collection::AbstractVector{Int} => [1, 2, 3]
    
    # Test with complex callbacks
    recursive_cb::Int => (1; on_get = identity_cb, on_set = limit_cb)
end
