# Test custom defaults for read and set callbacks
using Test
using ManagedProperties

# Define custom default callbacks
custom_get_cb(props, name, val) = "Custom Get: $val"
custom_set_cb(props, name, val::String) = uppercase(val)
custom_set_cb(props, name, val::Number) = val  # Pass through for numbers

# Create a simple structure with default properties
@properties TestCustomDefaultCallbacks default_on_get=custom_get_cb default_on_set=custom_set_cb begin
    name::String
    age::Int
end

@properties TestDefaultCallbacks begin
    name::String
    age::Int
end

export test_default_callbacks

function test_default_callbacks()
    # Create an instance with custom default callbacks
    t = TestCustomDefaultCallbacks()

    # Set properties
    set_property!(t, :name, "Alice")
    set_property!(t, :age, 30)

    # Test that the custom default get callback is used
    @test get_property(t, :name) == "Custom Get: ALICE"
    @test get_property(t, :age) == "Custom Get: 30"

    # Test that the custom default set callback is used
    raw_value = getfield(t, :name)
    @test raw_value == "ALICE"  # Should be uppercase due to set callback
    
    # Create with regular defaults for comparison
    t2 = TestDefaultCallbacks()
    set_property!(t2, :name, "Alice")
    @test get_property(t2, :name) == "Alice" # Regular default callbacks
end
