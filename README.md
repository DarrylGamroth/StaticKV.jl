# StaticKV.jl

[![CI](https://github.com/DarrylGamroth/StaticKV.jl/actions/workflows/ci.yml/badge.svg)](https://github.com/DarrylGamroth/StaticKV.jl/actions/workflows/ci.yml)
[![codecov](https://codecov.io/gh/DarrylGamroth/StaticKV.jl/branch/main/graph/badge.svg)](https://codecov.io/gh/DarrylGamroth/StaticKV.jl)

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

- **Concrete, non-parametric types** - Easy to use as struct fields
- **Zero-allocation key access** - No memory allocations for get/set operations
- **Compile-time callback optimization** - Default callbacks optimized away completely
- **Type-stable usage** - Works perfectly in collections and as struct fields
- **Named function callbacks** - Full support for custom callback functions

## Installation

```julia
using Pkg
Pkg.add("StaticKV")
```

## Limitations

- **No Union Types**: Union types (like `Union{Nothing, String}`) are not allowed as key types because they conflict with the internal representation of unset keys. The package uses `nothing` to represent unset keys, so Union types containing `Nothing` would create ambiguity.

## API Levels: Internal vs External

StaticKV provides two distinct API levels to support different use cases:

### Internal API (StaticKV module functions)

Use these functions in your implementation code where you need full control:

```julia
StaticKV.value(obj, key)         # Direct key read (NO access checks)
StaticKV.value!(obj, value, key) # Direct key write (NO access checks)
StaticKV.reset!(obj, key)        # Reset key to unset state (checks ASSIGNABLE)
```

These functions are intended for **internal use** within your package/module. `value` and `value!` bypass all access control checks, while `reset!` enforces ASSIGNABLE access. This is useful for:
- Implementation logic that needs to update fields
- Internal state management
- System-level operations

### External/Interface API (Base functions)

Use these functions for public interfaces where you want strict access control:

```julia
getindex(obj, key) or obj[key]           # Respects access control
setindex!(obj, value, key) or obj[key] = value  # Respects access control
```

These functions **enforce access control** modes, making them suitable for:
- Public APIs
- Messaging interfaces
- External integrations
- Any context where unauthorized access should be prevented

### Example: Messaging System

```julia
@kvstore Message begin
    # Readable externally, but only writable internally
    payload::String => (; access = AccessMode.READABLE)
    timestamp::Int => (; access = AccessMode.READABLE)
end

# Internal code (your implementation) - bypasses access control
function process_incoming!(msg::Message, data::String)
    StaticKV.value!(msg, data, :payload)        # Works - unchecked access
    StaticKV.value!(msg, time(), :timestamp)    # Works - unchecked access
end

# External/public API (user code) - enforces access control
function get_message_data(msg::Message)
    msg[:payload]                               # Works - readable
end

function try_modify_message(msg::Message)
    msg[:payload] = "hacked"                    # Throws error - read-only
end
```

This two-tier approach prevents accidental misuse while giving you full control when needed.

### Function Reference: All Ways to Access Keys

StaticKV provides multiple function interfaces for accessing keys, all of which ultimately enforce the same access control rules:

#### Internal API Functions
```julia
# Raw value access (NO access control checks - use in internal code only)
StaticKV.value(obj, key)            # Direct read (bypasses READABLE check)
StaticKV.value!(obj, value, key)    # Direct write (bypasses ASSIGNABLE check)

# Other internal functions
StaticKV.reset!(obj, key)           # Reset key to unset state (checks ASSIGNABLE)
StaticKV.isset(obj, key)            # Check if key is set
StaticKV.is_readable(obj, key)      # Check if key can be read
StaticKV.is_assignable(obj, key)    # Check if key can be assigned
StaticKV.is_mutable(obj, key)       # Check if key can be mutated in place
```

#### External/Interface API Functions
```julia
# Bracket notation (most convenient)
obj[key]                # Calls Base.getindex(obj, key) → [checks READABLE] → StaticKV.value(obj, key)
obj[key] = value        # Calls Base.setindex!(obj, value, key) → [checks ASSIGNABLE] → StaticKV.value!(obj, value, key)

# Explicit function calls (more explicit)
getindex(obj, key)           # Same as obj[key]
setindex!(obj, value, key)   # Same as obj[key] = value

# Dot notation (property-style)
obj.key                 # Calls Base.getproperty(obj, :key) → Base.getindex(obj, :key) → [checks READABLE] → StaticKV.value(obj, :key)
obj.key = value         # Calls Base.setproperty!(obj, :key, value) → Base.setindex!(obj, value, :key) → [checks ASSIGNABLE] → StaticKV.value!(obj, value, :key)
```

#### Function Call Hierarchy
All external functions enforce access control before calling the raw internal `StaticKV.value` and `StaticKV.value!` functions:

```
obj[key]      → Base.getindex    → [checks READABLE] → StaticKV.value   
obj.key       → Base.getproperty → Base.getindex → [checks READABLE] → StaticKV.value
                                                                       ├→ Applies on_get callback
                                                                       └→ Returns field value

obj[key] = v  → Base.setindex!   → [checks ASSIGNABLE] → StaticKV.value!
obj.key = v   → Base.setproperty → Base.setindex! → [checks ASSIGNABLE] → StaticKV.value!
                                                                         ├→ Applies on_set callback
                                                                         └→ Updates field + timestamp

Internal (bypasses checks):
  StaticKV.value(obj, key)       → Directly reads field, applies on_get
  StaticKV.value!(obj, val, key) → Directly writes field, applies on_set
```

**Key Takeaway**: The choice between `obj[key]`, `obj.key`, or `getindex(obj, key)` is purely stylistic. 
They all enforce the same access control checks before calling `StaticKV.value/value!`. 

Use `StaticKV.value/value!` directly **only** in internal implementation code where you need to bypass 
access control for legitimate reasons (e.g., internal state management, privileged operations).

**Security Note**: Since `StaticKV.value/value!` bypass all access checks, they should be used carefully 
and only within trusted code. For public-facing APIs, always use the external functions (`obj[key]`, etc.) 
that enforce access control.

## Quick Start

```julia
using StaticKV

# Define a type with static key-value store
@kvstore Person begin
    name::String
    age::Int => (; access = AccessMode.READABLE)          # Read-only access
    address::String => (; 
        on_get = (obj, key, val) -> "REDACTED",          # Custom get transformation
        on_set = (obj, key, val) -> uppercase(val)       # Custom set transformation
    )
    email::String => (; 
        on_set = (obj, key, val) -> lowercase(val)       # Always store lowercase
    )
    score::Int => (0; 
        access = AccessMode.READABLE_ASSIGNABLE_MUTABLE,  # Full access (default)
        on_get = (obj, key, val) -> val * 2,             # Double when getting
        on_set = (obj, key, val) -> max(0, val)          # Ensure non-negative
    )
    data::Vector{String} => ([]; access = AccessMode.READABLE | AccessMode.MUTABLE)  # Read and mutate, but not assign
end

# Create an instance
person = Person()

# The generated struct is concrete and can be used as fields
struct Company
    ceo::Person                                          # Concrete type, no parameters
    employees::Vector{Person}                            # Works in collections
end

# Set keys
person[:name] = "Alice"
person[:email] = "ALICE@EXAMPLE.COM"
person[:address] = "123 Main St"
person[:data] = ["item1", "item2"]

# Access keys
println(person[:name])                                  # "Alice"
println(person[:address])                               # "REDACTED" (get callback applied)
println(person[:email])                                 # "alice@example.com" (stored lowercase)

# Mutate mutable keys in place
StaticKV.with_key!(person, :data) do data
    push!(data, "item3")                                 # Modify the vector in place
end
println(person[:data])                                  # ["item1", "item2", "item3"]

# Check key status
println(StaticKV.isset(person, :name))                  # true
println(StaticKV.is_readable(person, :age))             # true
println(StaticKV.is_assignable(person, :age))           # false (read-only)
println(StaticKV.is_mutable(person, :data))             # true (can mutate in place)
println(ismutable(person, :data))                       # true (Base.ismutable support)
println(ismutable(person))                              # true (struct itself is mutable)

# Reset a key to unset state
StaticKV.reset!(person, :address)
println(StaticKV.isset(person, :address))               # false
println(StaticKV.allkeysset(person))                    # false (address key was reset)
println(StaticKV.is_readable(person, :email))           # true
println(StaticKV.is_assignable(person, :address))       # true
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
    with_value::Type => (initial_value)

    # Key with access control
    readonly_key::Type => (; access = AccessMode.READABLE)
    
    # Key with assignable access (can replace but not mutate)
    assignable_key::Type => (; access = AccessMode.READABLE | AccessMode.ASSIGNABLE)
    
    # Key with mutable access (can mutate in-place but not replace)
    mutable_key::Vector{String} => ([]; access = AccessMode.READABLE | AccessMode.MUTABLE)

    # Key with custom callbacks
    custom_key::Type => (; 
        on_get = (obj, key, val) -> transform_for_getting(obj, key, val),
        on_set = (obj, key, val) -> transform_for_setting(obj, key, val)
    )

    # Combining multiple attributes
    complex_key::Type => (initial_value; 
        access = AccessMode.READABLE_ASSIGNABLE_MUTABLE, # Full access (default)
        on_get = my_get_fn,
        on_set = my_set_fn
    )
end
```

## Access Control Flags

The `AccessMode` module provides flags to control key access:

- `AccessMode.NONE`: No access (0x00)
- `AccessMode.READABLE`: Key can be read (0x01)
- `AccessMode.ASSIGNABLE`: Key can be assigned/replaced with new values (0x02)
- `AccessMode.MUTABLE`: Key can be mutated in-place but not replaced (0x04)
- `AccessMode.READABLE_ASSIGNABLE_MUTABLE`: Key can be read, assigned, and mutated (default) (0x07)

### Legacy Access Modes (for backward compatibility)
- `AccessMode.WRITABLE`: Alias for `ASSIGNABLE` (0x02)
- `AccessMode.READABLE_WRITABLE`: Alias for `READABLE_ASSIGNABLE_MUTABLE` (0x07)

### Access Mode Combinations

You can combine access modes using bitwise OR (`|`):

```julia
# Read-only access
readonly_mode = AccessMode.READABLE

# Read and assign, but no in-place mutation
read_assign_mode = AccessMode.READABLE | AccessMode.ASSIGNABLE

# Read and mutate in-place, but no assignment of new values
read_mutate_mode = AccessMode.READABLE | AccessMode.MUTABLE

# Full access (default)
full_access_mode = AccessMode.READABLE_ASSIGNABLE_MUTABLE
```

### Key Access Semantics

- **READABLE**: Allows `getindex()`, `with_key()`, and `with_keys()` operations
- **ASSIGNABLE**: Allows `setindex!()` to replace the entire value with a new one
- **MUTABLE**: Allows `with_key!()` to modify the value in-place (for non-isbits types)

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

Get callbacks are executed when `getindex` is called and allow you to transform the raw stored value before it's returned to the caller:

- Executed during: `getindex(obj, key_name)`
- Input: The actual stored value
- Output: The transformed value returned to the caller
- Common uses: Masking sensitive data, formatting values, applying transformations, computing derived values

### Set Callbacks

Set callbacks are executed when `setindex!` is called and allow you to transform or validate input values before they're stored:

- Executed during: `setindex!(obj, key_name, value)`
- Input: The value provided to `setindex!`
- Output: The transformed value that will be stored
- Common uses: Validation, normalization, type conversion, enforcement of business rules

### Callback Order and Flow

1. When setting a key (`setindex!`):
   - The set callback is applied first to transform the input value
   - The transformed value is then stored in the key
   - The timestamp is updated

2. When getting a key (`getindex`):
   - The raw stored value is retrieved
   - The get callback is applied to transform the value
   - The transformed value is returned

### Examples

```julia
# Simple validation example
age_validator(obj, key, val) = max(0, min(120, val))    # Clamp age between 0-120

# Data privacy example
card_masker(obj, key, val) = "XXXX-XXXX-XXXX-" * last(val, 4)  # Show only last 4 digits

# Data transformation example
name_normalizer(obj, key, val) = titlecase(val)         # Ensure consistent capitalization

# Using callbacks in key definition
@kvstore Person begin
    name::String => (; on_set = name_normalizer)
    age::Int => (; on_set = age_validator)
    credit_card::String => (; on_get = card_masker)
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
sensor1 = Sensor()                                       # Type: Sensor{EpochClock}

# For high-frequency operations, use CachedEpochClock for even better performance
cached_clock = Clocks.CachedEpochClock(Clocks.EpochClock())
sensor2 = Sensor(cached_clock)                           # Type: Sensor{CachedEpochClock{EpochClock}}

# Both instances have concrete clock types for zero dispatch overhead
println(typeof(sensor1))                                # Sensor{EpochClock}
println(typeof(sensor2))                                # Sensor{CachedEpochClock{EpochClock}}
```

### Using Anonymous Functions for Callbacks

As seen in the `Person` example above, you can use anonymous functions for key callbacks:

```julia
@kvstore CustomCallbacks begin
    # Anonymous function for get callback
    username::String => (; 
        on_get = (obj, key, val) -> uppercase(val)      # Always show uppercase
    )

    # Anonymous function for set callback
    password::String => (; 
        on_get = (obj, key, val) -> "********",         # Hide actual value
        on_set = (obj, key, val) -> hash(val)           # Store hashed value
    )

    # Data validation with callbacks
    age::Int => (18; 
        on_set = (obj, key, val) -> max(0, min(120, val))  # Clamp between 0-120
    )

    # Combined read/write transformations
    score::Int => (0; 
        on_get = (obj, key, val) -> val * 2,            # Double the score when read
        on_set = (obj, key, val) -> max(0, val)         # Ensure non-negative
    )
end
```

### Key Operations with Callbacks

```julia
# Increment age using with_key!
result = StaticKV.with_key!(person, :age) do age
    age + 1
end
person[:age] = result                                   # Need to explicitly update the key

# Mutate collections in place with with_key!
StaticKV.with_key!(person, :data) do data_array
    push!(data_array, "new_item")                       # Modifies the array in place
    # Return value is ignored for in-place mutations
end

# Calculate numeric values without modifying keys
average_score = StaticKV.with_keys(person, :age, :score) do age, score
    (age + score) / 2                                   # Calculate average of age and score
end

# To update multiple keys, you need to get and set them individually
name = person[:name] * " Smith"                         # Add surname
age = person[:age] + 1                                  # Increment age
person[:name] = name
person[:age] = age
```

### Key Metadata and Information

```julia
# Get key value type
println(valtype(person, :age))                          # Int64
println(valtype(person, :address))                      # String

# Check when a key was last updated
last_updated = StaticKV.last_update(person, :name)      # Timestamp in nanoseconds

# Check access permissions
println(StaticKV.is_readable(person, :address))         # true
println(StaticKV.is_assignable(person, :address))       # true  
println(StaticKV.is_mutable(person, :data))             # true (if data is a Vector)
println(StaticKV.is_writable(person, :score))           # true (legacy function)

# Check mutability using Base.ismutable
println(ismutable(person, :data))                       # true (key-specific mutability)
println(ismutable(person))                              # true (struct is mutable)
```

## Full API Documentation

### Key Access (External API)

- `obj[key]` or `getindex(obj, key)`: Get a key value (enforces READABLE)
- `obj[key] = value` or `setindex!(obj, value, key)`: Set a key value (enforces ASSIGNABLE)
- `obj.key` or `getproperty(obj, :key)`: Get a key value using dot syntax (enforces READABLE)
- `obj.key = value` or `setproperty!(obj, :key, value)`: Set a key value using dot syntax (enforces ASSIGNABLE)

### Key Access (Internal API)

- `StaticKV.value(obj, key)`: Direct key read (NO access checks)
- `StaticKV.value!(obj, value, key)`: Direct key write (NO access checks)
- `StaticKV.reset!(obj, key)`: Reset a key to unset state (enforces ASSIGNABLE)

### Key Status

- `StaticKV.isset(obj, key)`: Check if a key is set (not `nothing`)
- `StaticKV.allkeysset(obj)`: Check if all keys are set
- `valtype(obj, key)`: Get a key's value type

### Key Permissions

- `StaticKV.is_readable(obj, key)`: Check if a key is readable
- `StaticKV.is_assignable(obj, key)`: Check if a key can be assigned/replaced
- `StaticKV.is_mutable(obj, key)`: Check if a key can be mutated in place
- `StaticKV.is_writable(obj, key)`: Check if a key is writable (legacy: alias for `is_assignable`)
- `StaticKV.last_update(obj, key)`: Get the timestamp of the last update

### Base Interface Support

- `ismutable(obj, key)`: Check if a specific key is mutable (integrates with Julia's Base)
- `ismutable(obj)`: Check if the struct itself is mutable (always `true` for StaticKV structs)

### Key Operations

- `StaticKV.with_key(fn, obj, key)`: Apply a function to a key value (read-only)
- `StaticKV.with_key!(fn, obj, key)`: Apply a function to mutate a key in place
- `StaticKV.with_keys(fn, obj, keys...)`: Apply a function to multiple keys (read-only)
- `StaticKV.keynames(obj)`: Get a tuple of all key names

## License

This project is licensed under the MIT License - see the LICENSE file for details.
