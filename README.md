# StaticKV.jl

A high-performance Julia package that provides a macro-based system for creating static key-value stores with compile-time metadata. This package creates **concrete, non-parametric structs** that are easy to use as fields in other structs while maintaining zero-allocation key access.

## Features

- **Direct Field Storage**: Values stored as `Union{Nothing,T}` with separate timestamp fields
- **Compile-time Metadata**: Access control and callbacks stored at type level for zero overhead
- **Concrete Types**: No parametric complexity - structs can be used as fields anywhere
- **Key Access Control**: Define each key as readable and/or writable
- **Custom Callbacks**: Define custom get and write transformations for keys
- **Time Tracking**: Automatically track when keys were last modified
- **Type Safety**: Full type system integration with Julia's type system
- **Zero Allocations**: Key access operations allocate no memory after warmup
- **Performance**: Sub-nanosecond key access with compile-time optimization

## Key Benefits

✅ **Concrete, non-parametric types** - Easy to use as struct fields
✅ **Zero-allocation key access** - No memory allocations for get/set operations
✅ **Compile-time callback optimization** - Default callbacks optimized away completely
✅ **Type-stable usage** - Works perfectly in collections and as struct fields
✅ **Named function callbacks** - Full support for custom callback functions

## Installation

```julia
using Pkg
Pkg.add("StaticKV")
```

## Limitations

- **No Union Types**: Union types (like `Union{Nothing, String}`) are not allowed as key types because they conflict with the internal representation of unset keys. The package uses `nothing` to represent unset keys, so Union types containing `Nothing` would create ambiguity.

## Quick Start

```julia
using StaticKV

# Define a type with static key-value store
@kvstore Person begin
    name::String
    age::Int => (access => AccessMode.READABLE_WRITABLE)
    address::String => (
        on_get => (obj, key, val) -> "REDACTED",  # Custom get transformation
        on_set => (obj, key, val) -> uppercase(val)  # Custom set transformation
    )
    email::String => (
        on_set => (obj, key, val) -> lowercase(val)  # Always store lowercase
    )
    score::Int => (
        value => 0,
        on_get => (obj, key, val) -> val * 2,      # Double when getting
        on_set => (obj, key, val) -> max(0, val)  # Ensure non-negative
    )
end

# Create an instance
person = Person()

# The generated struct is concrete and can be used as fields
struct Company
    ceo::Person              # ✅ Concrete type, no parameters!
    employees::Vector{Person} # ✅ Works in collections too
end

# Set keys
setkey!(person, :name, "Alice")
setkey!(person, :age, 30)
setkey!(person, :email, "alice@example.com")
setkey!(person, :address, "123 Main St")

# Access keys
println(getkey(person, :name))    # "Alice"
println(getkey(person, :address)) # "REDACTED" (get callback applied)
println(getkey(person, :email))   # "alice@example.com" (stored lowercase)

# Check key status
println(isset(person, :name))          # true

# Reset a key to unset state
resetkey!(person, :address)
println(isset(person, :address))       # false
println(allkeysset(person))             # false (address key was reset)
println(is_readable(person, :email))    # true
println(is_writable(person, :address))  # true
```

## Key Definition Syntax

The `@kvstore` macro allows defining keys with various attributes:

```julia

function transform_for_getting(obj, key, val)
end

function transform_for_setting(obj, key, val)
end

@kvstore TypeName begin
    # Basic key with default settings
    basic_key::Type

    # Key with initial value
    with_value::Type => (value => initial_value)

    # Key with access control
    readonly_key::Type => (access => AccessMode.READABLE)

    # Key with custom callbacks
    custom_key::Type => (
        on_get => transform_for_getting(obj, key, val),
        on_set => transform_for_setting(obj, key, val)
    )

    # Combining multiple attributes
    complex_key::Type => (
        value => initial_value,
        access => AccessMode.READABLE_WRITABLE,
        on_get => my_get_fn,
        on_set => my_set_fn
    )
end
```

## Access Control Flags

The `AccessMode` module provides flags to control key access:

- `AccessMode.NONE`: No access (0x00)
- `AccessMode.READABLE`: Key can be read (0x01)
- `AccessMode.WRITABLE`: Key can be written (0x02)
- `AccessMode.READABLE_WRITABLE`: Key can be both read and written (READABLE | WRITABLE)

## Key Callbacks

Callbacks in StaticKV.jl provide a powerful way to transform, validate, or process values during read and write operations.

### Callback Function Signatures

Both read and set callbacks follow the same function signature:

```julia
callback_function(obj, key_name, value) -> transformed_value
```

Where:
- `obj`: The instance of your type that owns the key
- `key_name`: The Symbol representing the key name
- `value`: The current value (for get callbacks) or the input value (for set callbacks)
- `transformed_value`: The value returned after transformation (must be of the same type as the key)

### Get Callbacks

Get callbacks are executed when `getkey` is called and allow you to transform the raw stored value before it's returned to the caller:

- Executed during: `getkey(obj, key_name)`
- Input: The actual stored value
- Output: The transformed value returned to the caller
- Common uses: Masking sensitive data, formatting values, applying transformations, computing derived values

### Set Callbacks

Set callbacks are executed when `setkey!` is called and allow you to transform or validate input values before they're stored:

- Executed during: `setkey!(obj, key_name, value)`
- Input: The value provided to `setkey!`
- Output: The transformed value that will be stored
- Common uses: Validation, normalization, type conversion, enforcement of business rules

### Callback Order and Flow

1. When setting a key (`setkey!`):
   - The set callback is applied first to transform the input value
   - The transformed value is then stored in the key
   - The timestamp is updated

2. When getting a key (`getkey`):
   - The raw stored value is retrieved
   - The get callback is applied to transform the value
   - The transformed value is returned

### Examples

```julia
# Simple validation example
age_validator(obj, key, val) = max(0, min(120, val))  # Clamp age between 0-120

# Data privacy example
card_masker(obj, key, val) = "XXXX-XXXX-XXXX-" * last(val, 4)  # Show only last 4 digits

# Data transformation example
name_normalizer(obj, key, val) = titlecase(val)  # Ensure consistent capitalization

# Using callbacks in key definition
@kvstore Person begin
    name::String => (on_set => name_normalizer)
    age::Int => (on_set => age_validator)
    credit_card::String => (on_get => card_masker)
end
```

## Advanced Usage

### Clock Type Optimization

For maximum performance, the generated structs are parametric on the clock type, eliminating runtime dispatch:

```julia
using Clocks

# Define your struct - it will be parametric on the clock type
@kvstore Sensor begin
    value::Float64
    timestamk::Int64
end

# Default: uses EpochClock (concrete type, zero overhead)
sensor1 = Sensor()  # Type: Sensor{EpochClock}

# For high-frequency operations, use CachedEpochClock for even better performance
cached_clock = Clocks.CachedEpochClock(Clocks.EpochClock())
sensor2 = Sensor(cached_clock)  # Type: Sensor{CachedEpochClock{EpochClock}}

# Both instances have concrete clock types for zero dispatch overhead
println(typeof(sensor1))  # Sensor{EpochClock}
println(typeof(sensor2))  # Sensor{CachedEpochClock{EpochClock}}
```

### Using Anonymous Functions for Callbacks

As seen in the `Person` example above, you can use anonymous functions for key callbacks:

```julia
@kvstore CustomCallbacks begin
    # Anonymous function for get callback
    username::String => (
        on_get => (obj, key, val) -> uppercase(val)  # Always show uppercase
    )

    # Anonymous function for set callback
    password::String => (
        on_get => (obj, key, val) -> "********",     # Hide actual value
        on_set => (obj, key, val) -> hash(val)      # Store hashed value
    )

    # Data validation with callbacks
    age::Int => (
        value => 18,
        on_set => (obj, key, val) -> max(0, min(120, val))  # Clamp between 0-120
    )

    # Combined read/write transformations
    score::Int => (
        value => 0,
        on_get => (obj, key, val) -> val * 2,      # Double the score when read
        on_set => (obj, key, val) -> max(0, val)  # Ensure non-negative
    )
end
```

### Key Operations with Callbacks

```julia
# Increment age using with_key!
result = with_key!(person, :age) do age
    age + 1
end
setkey!(person, :age, result)  # Need to explicitly update the key

# Calculate numeric values without modifying keys
average_score = with_keys(person, :age, :score) do age, score
    (age + score) / 2  # Calculate average of age and score
end

# To update multiple keys, you need to get and set them individually
name = getkey(person, :name) * " Smith"  # Add surname
age = getkey(person, :age) + 1          # Increment age
setkey!(person, :name, name)
setkey!(person, :age, age)
```

### Key Metadata and Information

```julia
# Get key type
println(keytype(person, :age))     # Int64
println(keytype(person, :address)) # String

# Check when a key was last updated
last_updated = last_update(person, :name)  # Timestamp in nanoseconds

# Check access permissions
println(is_readable(person, :address))  # true
println(is_writable(person, :address))  # true
println(is_writable(person, :score))    # true
```

## Full API Documentation

### Key Access

- `getkey(obj, key_name)`: Get a key value
- `setkey!(obj, key_name, value)`: Set a key value
- `resetkey!(obj, key_name)`: Reset a key to an unset state
- `isset(obj, key_name)`: Check if a key is set (not `nothing`)
- `allkeysset(obj)`: Check if all keys are set
- `keytype(obj, key_name)`: Get a key's type

### Key Information

- `is_readable(obj, key_name)`: Check if a key is readable
- `is_writable(obj, key_name)`: Check if a key is writable
- `last_update(obj, key_name)`: Get the timestamp of the last update

### Key Operations

- `with_key(fn, obj, key_name)`: Apply a function to a key value (read-only)
- `with_key!(fn, obj, key_name)`: Apply a function and update a mutable key
- `with_keys(fn, obj, key_names...)`: Apply a function to multiple keys (read-only)

## License

This project is licensed under the MIT License - see the LICENSE file for details.
