# Test custom defaults for read and write callbacks
using Test
using ManagedProperties
using Clocks

# Define custom default callbacks
custom_read_cb(props, name, val) = "Custom Read: $val"
custom_write_cb(props, name, val::String) = uppercase(val)
custom_write_cb(props, name, val::Number) = val  # Pass through for numbers

# Create a simple structure with default properties
@properties TestDefaultCallbacks begin
    name::String
    age::Int
end

export test_default_callbacks

function test_default_callbacks()
    # Create an instance with custom default callbacks
    t = TestDefaultCallbacks(
        default_read_callback=custom_read_cb, 
        default_write_callback=custom_write_cb
    )

    # Set properties
    set_property!(t, :name, "Alice")
    set_property!(t, :age, 30)

    # Test that the custom default read callback is used
    @test get_property(t, :name) == "Custom Read: ALICE"
    @test get_property(t, :age) == "Custom Read: 30"

    # Test that the custom default write callback is used
    prop_meta = getfield(t, :name)
    @test prop_meta.value == "ALICE"  # Should be uppercase due to write callback
    
    # Create with regular defaults for comparison
    t2 = TestDefaultCallbacks()
    set_property!(t2, :name, "Alice")
    @test get_property(t2, :name) == "Alice" # Regular default callbacks
end
