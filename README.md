# ManagedProperties.jl

A Julia package that provides a macro-based system for creating objects with managed properties. Properties can have access control, custom read/write callbacks, and automatic timestamp tracking.

## Features

- **Property Access Control**: Define each property as readable and/or writable
- **Custom Callbacks**: Define custom read and write transformations for properties
- **Time Tracking**: Automatically track when properties were last modified
- **Type Safety**: Full type system integration with Julia's type system
- **Performance**: Designed with performance in mind, using specialized types and precompilation

## Installation

```julia
using Pkg
Pkg.add("ManagedProperties")
```

## Limitations

- **No Union Types**: Union types (like `Union{Nothing, String}`) are not allowed as property types because they conflict with the internal representation of unset properties. The package uses `nothing` to represent unset properties, so Union types containing `Nothing` would create ambiguity.

## Quick Start

```julia
using ManagedProperties
using Clocks  # For timestamp functionality

# Define a type with managed properties
@properties Person begin
    name::String
    age::Int => (value => 0, access => AccessMode.READABLE_WRITABLE)
    ssn::String => (access => AccessMode.READABLE)  # Write-once, read-only
    address::String => (
        read_callback => (obj, name, val) -> "REDACTED",  # Custom read transformation
        write_callback => (obj, name, val) -> uppercase(val)  # Custom write transformation
    )
end

# Create an instance
person = Person()

# Set properties
set_property!(person, :name, "Alice")
set_property!(person, :age, 30)
set_property!(person, :ssn, "123-45-6789")
set_property!(person, :address, "123 Main St")

# Access properties
println(get_property(person, :name))    # "Alice"
println(get_property(person, :address)) # "REDACTED" (read callback applied)

# Check property status
println(is_set(person, :name))          # true

# Reset a property to unset state
reset_property!(person, :address)
println(is_set(person, :address))       # false
println(all_properties_set(person))     # true if all properties are set
println(is_readable(person, :ssn))      # true
println(is_writable(person, :ssn))      # false
```

## Property Definition Syntax

The `@properties` macro allows defining properties with various attributes:

```julia
@properties TypeName begin
    # Basic property with default settings
    basic_prop::Type

    # Property with initial value
    with_value::Type => (value => initial_value)
    
    # Property with access control
    readonly_prop::Type => (access => AccessMode.READABLE)
    
    # Property with custom callbacks
    custom_prop::Type => (
        read_callback => (obj, name, val) -> transform_for_reading(val),
        write_callback => (obj, name, val) -> transform_for_writing(val)
    )
    
    # Combining multiple attributes
    complex_prop::Type => (
        value => initial_value,
        access => AccessMode.READABLE_WRITABLE,
        read_callback => my_read_fn,
        write_callback => my_write_fn
    )
end
```

## Access Control Flags

The `AccessMode` module provides flags to control property access:

- `AccessMode.NONE`: No access (0x00)
- `AccessMode.READABLE`: Property can be read (0x01)
- `AccessMode.WRITABLE`: Property can be written (0x02)
- `AccessMode.READABLE_WRITABLE`: Property can be both read and written (READABLE | WRITABLE)

## Advanced Usage

### Using Anonymous Functions for Callbacks

You can use anonymous functions for property callbacks:

```julia
@properties Person begin
    # Anonymous function for read callback
    name::String => (
        read_callback => (obj, name, val) -> uppercase(val)
    )
    
    # Anonymous function for write callback
    email::String => (
        write_callback => (obj, name, val) -> lowercase(val)
    )
    
    # Both read and write callbacks
    score::Int => (
        read_callback => (obj, name, val) -> val * 2,
        write_callback => (obj, name, val) -> max(0, val)  # Ensure non-negative
    )
end
```

### Property Operations with Callbacks

```julia
# Increment age using with_property!
result = with_property!(person, :age) do age
    age + 1
end
set_property!(person, :age, result)  # Need to explicitly update the property

# Calculate area without modifying properties
area = with_properties(person, :width, :height) do width, height
    width * height
end

# Update multiple properties at once
with_properties!(person, :x, :y) do x, y
    x += 10
    y += 5
    return nothing
end
```

### Property Metadata

```julia
# Get property type
println(property_type(person, :age))  # Int64

# Check when a property was last updated
last_updated = last_update(person, :name)  # Timestamp in nanoseconds
```

## Full API Documentation

### Property Access

- `get_property(obj, prop_name)`: Get a property value
- `set_property!(obj, prop_name, value)`: Set a property value
- `reset_property!(obj, prop_name)`: Reset a property to an unset state
- `is_set(obj, prop_name)`: Check if a property is set (not `nothing`)
- `all_properties_set(obj)`: Check if all properties are set
- `property_type(obj, prop_name)`: Get a property's type

### Property Information

- `is_readable(obj, prop_name)`: Check if a property is readable
- `is_writable(obj, prop_name)`: Check if a property is writable
- `last_update(obj, prop_name)`: Get the timestamp of the last update

### Property Operations

- `with_property(fn, obj, prop_name)`: Apply a function to a property value (read-only)
- `with_property!(fn, obj, prop_name)`: Apply a function and update the property
- `with_properties(fn, obj, prop_names...)`: Apply a function to multiple properties (read-only)
- `with_properties!(fn, obj, prop_names...)`: Apply a function and update multiple properties

## License

This project is licensed under the MIT License - see the LICENSE file for details.
