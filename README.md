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
    address::String => (
        read_callback => (obj, name, val) -> "REDACTED",  # Custom read transformation
        write_callback => (obj, name, val) -> uppercase(val)  # Custom write transformation
    )
    email::String => (
        write_callback => (obj, name, val) -> lowercase(val)  # Always store lowercase
    )
    score::Int => (
        value => 0,
        read_callback => (obj, name, val) -> val * 2,      # Double when reading
        write_callback => (obj, name, val) -> max(0, val)  # Ensure non-negative
    )
end

# Create an instance
person = Person()

# Set properties
set_property!(person, :name, "Alice")
set_property!(person, :age, 30)
set_property!(person, :email, "alice@example.com")
set_property!(person, :address, "123 Main St")

# Access properties
println(get_property(person, :name))    # "Alice"
println(get_property(person, :address)) # "REDACTED" (read callback applied)
println(get_property(person, :email))   # "alice@example.com" (stored lowercase)

# Check property status
println(is_set(person, :name))          # true

# Reset a property to unset state
reset_property!(person, :address)
println(is_set(person, :address))       # false
println(all_properties_set(person))     # false (address property was reset)
println(is_readable(person, :email))    # true
println(is_writable(person, :address))  # true
```

## Property Definition Syntax

The `@properties` macro allows defining properties with various attributes:

```julia

function transform_for_reading(obj, name, val)
end

function transform_for_writing(obj, name, val)
end

@properties TypeName begin
    # Basic property with default settings
    basic_prop::Type

    # Property with initial value
    with_value::Type => (value => initial_value)
    
    # Property with access control
    readonly_prop::Type => (access => AccessMode.READABLE)
    
    # Property with custom callbacks
    custom_prop::Type => (
        read_callback => transform_for_reading(obj, name, val),
        write_callback => transform_for_writing(obj, name, val)
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

## Property Callbacks

Callbacks in ManagedProperties.jl provide a powerful way to transform, validate, or process values during read and write operations.

### Callback Function Signatures

Both read and write callbacks follow the same function signature:

```julia
callback_function(obj, prop_name, value) -> transformed_value
```

Where:
- `obj`: The instance of your type that owns the property
- `prop_name`: The Symbol representing the property name
- `value`: The current value (for read callbacks) or the input value (for write callbacks)
- `transformed_value`: The value returned after transformation (must be of the same type as the property)

### Read Callbacks

Read callbacks are executed when `get_property` is called and allow you to transform the raw stored value before it's returned to the caller:

- Executed during: `get_property(obj, prop_name)`
- Input: The actual stored value
- Output: The transformed value returned to the caller
- Common uses: Masking sensitive data, formatting values, applying transformations, computing derived values

### Write Callbacks

Write callbacks are executed when `set_property!` is called and allow you to transform or validate input values before they're stored:

- Executed during: `set_property!(obj, prop_name, value)`
- Input: The value provided to `set_property!`
- Output: The transformed value that will be stored
- Common uses: Validation, normalization, type conversion, enforcement of business rules

### Callback Order and Flow

1. When writing a property (`set_property!`):
   - The write callback is applied first to transform the input value
   - The transformed value is then stored in the property
   - The timestamp is updated

2. When reading a property (`get_property`):
   - The raw stored value is retrieved
   - The read callback is applied to transform the value
   - The transformed value is returned

### Examples

```julia
# Simple validation example
age_validator(obj, name, val) = max(0, min(120, val))  # Clamp age between 0-120

# Data privacy example
card_masker(obj, name, val) = "XXXX-XXXX-XXXX-" * last(val, 4)  # Show only last 4 digits

# Data transformation example
name_normalizer(obj, name, val) = titlecase(val)  # Ensure consistent capitalization

# Using callbacks in property definition
@properties Person begin
    name::String => (write_callback => name_normalizer)
    age::Int => (write_callback => age_validator)
    credit_card::String => (read_callback => card_masker)
end
```

## Advanced Usage

### Using Anonymous Functions for Callbacks

As seen in the `Person` example above, you can use anonymous functions for property callbacks:

```julia
@properties CustomCallbacks begin
    # Anonymous function for read callback
    username::String => (
        read_callback => (obj, name, val) -> uppercase(val)  # Always show uppercase
    )
    
    # Anonymous function for write callback
    password::String => (
        read_callback => (obj, name, val) -> "********",     # Hide actual value
        write_callback => (obj, name, val) -> hash(val)      # Store hashed value
    )
    
    # Data validation with callbacks
    age::Int => (
        value => 18,
        write_callback => (obj, name, val) -> max(0, min(120, val))  # Clamp between 0-120
    )
    
    # Combined read/write transformations
    score::Int => (
        value => 0,
        read_callback => (obj, name, val) -> val * 2,      # Double the score when read
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

# Calculate numeric values without modifying properties
average_score = with_properties(person, :age, :score) do age, score
    (age + score) / 2  # Calculate average of age and score
end

# To update multiple properties, you need to get and set them individually
name = get_property(person, :name) * " Smith"  # Add surname
age = get_property(person, :age) + 1          # Increment age
set_property!(person, :name, name)
set_property!(person, :age, age)
```

### Property Metadata and Information

```julia
# Get property type
println(property_type(person, :age))     # Int64
println(property_type(person, :address)) # String

# Check when a property was last updated
last_updated = last_update(person, :name)  # Timestamp in nanoseconds

# Check access permissions
println(is_readable(person, :address))  # true
println(is_writable(person, :address))  # true
println(is_writable(person, :score))    # true
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
- `with_property!(fn, obj, prop_name)`: Apply a function and update a mutable property
- `with_properties(fn, obj, prop_names...)`: Apply a function to multiple properties (read-only)

## License

This project is licensed under the MIT License - see the LICENSE file for details.
