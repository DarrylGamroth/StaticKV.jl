module StaticKV

"""
    StaticKV

A high-performance static key-value store implementation with direct field storage and compile-time metadata.
Creates concrete, type-safe structs that behave like key-value stores but with struct-level performance.

# Key Features
- **Direct field storage**: `Union{Nothing,T}` for values, `Int64` for timestamps
- **Compile-time metadata**: Access control and callbacks stored at type level
- **Zero overhead**: Default callbacks optimized away completely
- **Type-stable**: All operations fully optimized by Julia compiler
- **Static keys**: Keys are known at compile time for maximum performance

# Example
```julia
using StaticKV

@kvstore Person begin
    name::String
    age::Int => (; access = AccessMode.READABLE)
    email::String => (""; 
        on_get = (obj, key, val) -> "***@***.com",
        on_set = (obj, key, val) -> lowercase(val)
    )
end

person = Person()
person[:name] = "Alice"        # Key-value syntax
println(person[:name])         # "Alice"

# Can be used as concrete field types
struct Company
    ceo::Person
    employees::Vector{Person}
end
```
"""

using Clocks
using MacroTools

# Export public API
export @kvstore, AccessMode
export resetindex!, keytype, isset, allkeysset
export is_readable, is_assignable, is_mutable, is_writable, last_update
export with_key, with_key!, with_keys
export keynames
export Clocks

"""
    AccessMode

Module containing access control constants for key access.

# Constants
- `NONE`: No access (0x00)
- `READABLE`: Key can be read (0x01)
- `ASSIGNABLE`: Key can be assigned/replaced with new values (0x02)
- `MUTABLE`: Key can be mutated in-place but not replaced (0x04)
- `READABLE_ASSIGNABLE_MUTABLE`: Key can be read, assigned, and mutated (default) (0x07)

# Legacy constants (for backward compatibility)
- `WRITABLE`: Alias for `ASSIGNABLE` (0x02)
- `READABLE_WRITABLE`: Alias for `READABLE_ASSIGNABLE_MUTABLE` (0x07)
"""
module AccessMode
const AccessModeType = UInt8

const NONE::AccessModeType = 0x00
const READABLE::AccessModeType = 0x01
const ASSIGNABLE::AccessModeType = 0x02
const MUTABLE::AccessModeType = 0x04
const READABLE_ASSIGNABLE_MUTABLE::AccessModeType = READABLE | ASSIGNABLE | MUTABLE

# Legacy aliases for backward compatibility
const WRITABLE::AccessModeType = ASSIGNABLE
const READABLE_WRITABLE::AccessModeType = READABLE_ASSIGNABLE_MUTABLE

"""
    is_readable(flags)

Check if the key has readable access based on its access flags.
"""
@inline is_readable(flags) = !iszero(flags & READABLE)

"""
    is_assignable(flags)

Check if the key has assignable access (can replace/assign new values) based on its access flags.
"""
@inline is_assignable(flags) = !iszero(flags & ASSIGNABLE)

"""
    is_mutable(flags)

Check if the key has mutable access (can mutate in-place but not replace) based on its access flags.
"""
@inline is_mutable(flags) = !iszero(flags & MUTABLE)

"""
    is_writable(flags)

Legacy function: Check if the key has writable access based on its access flags.
This is an alias for `is_assignable` for backward compatibility.
"""
@inline is_writable(flags) = is_assignable(flags)

end # AccessMode module

# Default callback functions (zero overhead when inlined)
@inline _direct_default_callback(obj, key, value) = value

# Base function definitions that will be extended by generated methods
# These must be defined in the StaticKV module so that generated methods can extend them

"""
    resetkey!(kvstore, key)
    resetkey!(kvstore, Val(key))

Reset a key to its unset state.
"""
function resetkey! end

"""
    isset(kvstore, key)
    isset(kvstore, Val(key))

Check if a key is set (has a value).
"""
function isset end

"""
    is_readable(kvstore, key)
    is_readable(kvstore, Val(key))

Check if a key can be read.
"""
function is_readable end

"""
    is_assignable(kvstore, key)
    is_assignable(kvstore, Val(key))

Check if a key can be assigned (replaced with a new value).
"""
function is_assignable end

"""
    is_mutable(kvstore, key)
    is_mutable(kvstore, Val(key))

Check if a key can be mutated in place.
"""
function is_mutable end

"""
    is_writable(kvstore, key)
    is_writable(kvstore, Val(key))

Legacy function: Check if a key can be written to.
This is an alias for `is_assignable` for backward compatibility.
"""
function is_writable end

"""
    last_update(kvstore, key)
    last_update(kvstore, Val(key))

Get the timestamp of when a key was last updated.
"""
function last_update end

"""
    keynames(kvstore)

Get a tuple of all key names in the key-value store.
"""
function keynames end

"""
    keytype(kvstore, key)
    keytype(Type{<:KVStore}, key)

Get the type of a key.
"""
function keytype end

"""
    allkeysset(kvstore)

Check if all keys in the key-value store are set.
"""
function allkeysset end

"""
    with_key(f, kvstore, key)

Execute a function with the value of a key if it's set and readable.
"""
function with_key end

"""
    with_key!(f, kvstore, key)

Execute a function with the value of a key for in-place mutation if it's set, readable, and mutable.
"""
function with_key! end

"""
    with_keys(f, kvstore, keys...)

Execute a function with the values of multiple keys if they're all set and readable.
"""
function with_keys end

# Helper function to process key attributes
function process_attribute!(result, key, value)
    if key === :value
        result[:value] = value
    elseif key === :access
        result[:access] = value
    elseif key === :on_get
        result[:on_get] = value
    elseif key === :on_set
        result[:on_set] = value
    else
        throw(ErrorException("Unknown key attribute: $key"))
    end
end

"""
    parse_key_def(expr)

Parse a key definition expression into a dictionary containing the key's
name, type, default value, access mode, and callbacks.

Uses MacroTools for AST manipulation and simple pattern analysis.
"""
function parse_key_def(expr)
    # Key definition parser

    result = Dict{Symbol,Any}()

    # Initialize with defaults
    result[:value] = nothing
    result[:access] = :(StaticKV.AccessMode.READABLE_ASSIGNABLE_MUTABLE)
    result[:on_get] = nothing
    result[:on_set] = nothing

    # Helper function to check if type expression is a Union
    function is_union_type(type_expr)
        if type_expr isa Expr && type_expr.head == :curly && type_expr.args[1] == :Union
            return true
        end
        return false
    end

    # Make sure expr is an Expr
    if !(expr isa Expr)
        throw(ErrorException("Expected key definition, got: $(typeof(expr))"))
    end

    # Ensure expr is fully cleaned by stripping any module qualifications
    clean_expr = strip_module_qualifications(expr)

    # Handle simple type annotation: name::Type
    if clean_expr.head == :(::)
        name_expr = clean_expr.args[1]
        type_expr = clean_expr.args[2]

        # Extract the name (must be a symbol)
        if name_expr isa Symbol
            result[:name] = name_expr
        else
            throw(ErrorException("Key name must be a symbol, got: $(typeof(name_expr))"))
        end

        # Extract the type
        result[:type] = type_expr

        # Check for Union types
        if is_union_type(result[:type])
            throw(ErrorException("Union types are not allowed in key definitions as they conflict with the internal representation of unset keys"))
        end

        return result
    end

    # Handle new syntax: name::Type => value or name::Type => (value; kwargs...)
    if clean_expr.head == :call && length(clean_expr.args) >= 3 && clean_expr.args[1] == :(=>)
        type_expr = clean_expr.args[2]
        value_expr = clean_expr.args[3]

        if !(type_expr isa Expr) || type_expr.head != :(::)
            throw(ErrorException("Expected name::type on left side of =>, got: $type_expr"))
        end

        # Extract name and type
        name_expr = type_expr.args[1]
        type_value = type_expr.args[2]

        # Name must be a symbol
        if name_expr isa Symbol
            result[:name] = name_expr
        else
            throw(ErrorException("Key name must be a symbol, got: $(typeof(name_expr))"))
        end

        # Extract the type
        result[:type] = type_value

        # Check for Union types
        if is_union_type(result[:type])
            throw(ErrorException("Union types are not allowed in key definitions as they conflict with the internal representation of unset keys"))
        end

        # Parse the value and keyword arguments
        if value_expr isa Expr
            if value_expr.head == :tuple
                # Handle (value; kwargs...) or (; kwargs...)
                args = value_expr.args
                
                # Separate parameters (keyword arguments) from regular arguments
                parameters = nothing
                value_args = []
                
                for arg in args
                    if arg isa Expr && arg.head == :parameters
                        parameters = arg
                        # Handle keyword arguments: (; access = ..., on_get = ...)
                        for kw in arg.args
                            if kw isa Expr && kw.head == :kw
                                key = kw.args[1]
                                value = kw.args[2]
                                process_attribute!(result, key, value)
                            else
                                throw(ErrorException("Expected keyword argument, got: $kw"))
                            end
                        end
                    elseif !(arg isa LineNumberNode)
                        # Regular value argument (not a keyword parameter or line number)
                        push!(value_args, arg)
                    end
                end
                
                # Set the value based on what we found
                if !isnothing(parameters)
                    # We have keyword arguments, so extract only the value part
                    if length(value_args) == 0
                        # No value specified: (; access = ...)
                        result[:value] = nothing
                    elseif length(value_args) == 1
                        # Single value: (value; access = ...)
                        result[:value] = value_args[1]
                    else
                        # Multiple values form a tuple: (a, b; access = ...)
                        result[:value] = Expr(:tuple, value_args...)
                    end
                else
                    # No parameters, so this is just a tuple value: (a, b, c)
                    result[:value] = value_expr
                end
            elseif value_expr.head == :parameters
                # Handle (; kwargs...) with no value
                for kw in value_expr.args
                    if kw isa Expr && kw.head == :kw
                        key = kw.args[1]
                        value = kw.args[2]
                        process_attribute!(result, key, value)
                    else
                        throw(ErrorException("Expected keyword argument, got: $kw"))
                    end
                end
            elseif value_expr.head == :block
                # Handle Julia's block syntax: ("value"; access = ...)
                # This is how Julia parses (value; kwargs...) - as a block with parameters
                block_args = value_expr.args
                value_found = false
                
                for arg in block_args
                    if arg isa LineNumberNode
                        continue  # Skip line number nodes
                    elseif arg isa Expr && arg.head == :(=)
                        # This is a keyword argument: access = value
                        key = arg.args[1]
                        value = arg.args[2]
                        process_attribute!(result, key, value)
                    elseif !value_found
                        # This should be the value part
                        result[:value] = arg
                        value_found = true
                    else
                        throw(ErrorException("Unexpected expression in block: $arg"))
                    end
                end
                
                if !value_found
                    result[:value] = nothing
                end
            else
                # Single value without parentheses: name::Type => value
                result[:value] = value_expr
            end
        else
            # Simple value: name::Type => value
            result[:value] = value_expr
        end

        return result
    end

    # If we reach here, the expression didn't match any of our expected patterns
    throw(ErrorException("Expected key definition (name::Type or name::Type => value), got expression with head: $(clean_expr.head)"))
end

"""
    @kvstore struct_name [clock_type=ClockType] [default_on_get=fn] [default_on_set=fn] begin
        key1::Type1
        key2::Type2 => default_value
        key3::Type3 => (default_value; access = AccessMode.READABLE)
        key4::Type4 => (; access = AccessMode.READABLE_ASSIGNABLE_MUTABLE, on_get = custom_get_fn)
    end

Create a struct with a static key-value store using direct field storage and compile-time metadata.

# Benefits
- **Concrete types**: No parametric complexity, easy to use as struct fields
- **Zero overhead**: Default callbacks optimized away completely
- **Type stable**: All metadata resolved at compile time
- **Memory efficient**: Direct field storage with minimal overhead

# Key definition formats
- `name::Type`: Simple key with type
- `name::Type => value`: Key with default value
- `name::Type => (value; kwargs...)`: Key with default value and keyword arguments
- `name::Type => (; kwargs...)`: Key with only keyword arguments

# Key keyword arguments
- `access`: Access control flags (e.g., `AccessMode.READABLE_ASSIGNABLE_MUTABLE`)
- `on_get`: Custom function called when getting: `(obj, key, value) -> transformed_value`
- `on_set`: Custom function called when setting: `(obj, key, value) -> transformed_value`

# Struct-level parameters
- `clock_type`: Concrete clock type to use (default: `Clocks.EpochClock`)
- `default_on_get`: Default get callback for all keys
- `default_on_set`: Default set callback for all keys

# Examples
```julia
# Basic usage with default EpochClock
@kvstore Person begin
    name::String
    age::Int => 25
    data::Vector{String} => (["initial"]; access = AccessMode.READABLE | AccessMode.MUTABLE)
end

# Using CachedEpochClock for better performance
@kvstore Person clock_type=Clocks.CachedEpochClock begin
    name::String
    age::Int => (18; access = AccessMode.READABLE_ASSIGNABLE_MUTABLE)
end

# With callbacks
@kvstore Person begin
    name::String => (""; on_set = (obj, key, val) -> titlecase(val))
    password::String => (; on_get = (obj, key, val) -> "***")
end
```
"""
macro kvstore(struct_name, args...)
    # The last argument should always be the key block
    if length(args) < 1
        error("@kvstore requires a begin...end block after the struct name")
    end

    block = args[end]
    if block.head != :block
        error("@kvstore requires a begin...end block for key definitions")
    end

    # Parse optional struct-level parameters
    default_on_get = nothing
    default_on_set = nothing
    clock_type = :(Clocks.EpochClock)  # Default to EpochClock

    # Handle struct-level parameters (everything except the last block)
    for i in 1:(length(args)-1)
        arg = args[i]
        if arg isa Expr && arg.head == :(=)
            param_name = arg.args[1]
            param_value = arg.args[2]

            if param_name == :default_on_get
                default_on_get = param_value
            elseif param_name == :default_on_set
                default_on_set = param_value
            elseif param_name == :clock_type
                clock_type = param_value
            else
                error("Unknown parameter: $param_name")
            end
        else
            error("Invalid parameter format: $arg")
        end
    end

    # Extract field definitions and expand any macros
    # This includes support for field generator macros like @generate_data_uri_fields
    key_defs = []

    # Process the block to handle macros and filter out non-expressions
    for expr in block.args
        if expr isa LineNumberNode
            continue  # Skip line number nodes
        elseif expr isa Expr
            if expr.head == :macrocall
                # Expand macros - try different module scopes for robust expansion
                local expanded
                success = false

                try
                    # First try to expand in caller's module
                    expanded = macroexpand(__module__, expr)
                    success = true
                catch e1
                    try
                        # Then try Main module
                        expanded = macroexpand(Main, expr)
                        success = true
                    catch e2
                        try
                            # Try current module
                            expanded = macroexpand(StaticKV, expr)
                            success = true
                        catch e3
                            # Nothing worked, report error
                            error("Failed to expand macro $(expr)")
                        end
                    end
                end

                if success
                    # Process the expanded result
                    if expanded isa Expr
                        if expanded.head == :block
                            # Handle block of expressions
                            for sub_expr in expanded.args
                                if !(sub_expr isa LineNumberNode) && sub_expr isa Expr
                                    # Strip module qualifications
                                    clean_expr = strip_module_qualifications(sub_expr)
                                    push!(key_defs, clean_expr)
                                end
                            end
                        else
                            # Single expression expansion
                            clean_expr = strip_module_qualifications(expanded)
                            push!(key_defs, clean_expr)
                        end
                    end
                end
            else
                # Regular key definition
                push!(key_defs, expr)
            end
        end
    end

    # Parse key definitions
    props = []
    for (index, def) in enumerate(key_defs)
        try
            # Check for module qualified names that need stripping
            if def isa Expr
                # Apply proper module qualification stripping
                def = strip_module_qualifications(def)
            end

            # Parse the key definition
            parsed_key = parse_key_def(def)

            push!(props, parsed_key)
        catch e
            # Simplify error messages
            if def isa Expr && def.head == :call && length(def.args) >= 3 && def.args[1] == :(=>)
                try
                    # Try to extract key components directly
                    type_expr = def.args[2]
                    attrs = def.args[3]

                    if type_expr isa Expr && type_expr.head == :(::)
                        name = strip_module_qualifications(type_expr.args[1])
                        type = strip_module_qualifications(type_expr.args[2])

                        # Create a clean definition and retry
                        clean_def = Expr(:(=>),
                            Expr(:(::), name isa Symbol ? name : :invalid_name,
                                 type isa Symbol || type isa Expr ? type : :Any),
                            strip_module_qualifications(attrs))

                        parsed_key = parse_key_def(clean_def)
                        push!(props, parsed_key)
                        continue
                    end
                catch
                    # If recovery fails, just report the original error
                    error("Failed to parse key definition: $(def)")
                end
            else
                error("Failed to parse key definition: $(def)")
            end
        end
    end

    # Extract key information
    key_names = [k[:name] for k in props]
    key_types = [k[:type] for k in props]
    key_values = [k[:value] for k in props]
    key_access = [k[:access] for k in props]
    key_get_cbs = [k[:on_get] for k in props]
    key_set_cbs = [k[:on_set] for k in props]

    # Use gensym for clock to avoid naming conflicts (from DirectFields)
    clock_field = gensym(:clock)

    # Generate the struct with direct field storage
    struct_fields = []

    # Add value fields
    for (name, type) in zip(key_names, key_types)
        push!(struct_fields, :($(name)::Union{Nothing,$(type)}))
    end

    # Add timestamp fields (with underscore prefix to avoid collisions)
    for name in key_names
        push!(struct_fields, :($(Symbol(:_, name, :_timestamp))::Int64))
    end

    # Add clock field (using gensym to avoid conflicts) - parametric for zero overhead
    push!(struct_fields, :($(clock_field)::C))

    # Create the struct definition (parametric on clock type for zero overhead)
    struct_def = quote
        mutable struct $(struct_name){C <: Clocks.AbstractClock}
            $(struct_fields...)

            # Constructor with proper default value handling (bypasses access control during construction)
            function $(struct_name)(clock::C = $(clock_type)()) where {C <: Clocks.AbstractClock}
                # Create instance with unset properties
                instance = new{C}(
                    # Value fields - all start as nothing
                    $([:(nothing) for i in 1:length(props)]...),

                    # Timestamp fields - all start as -1 (unset)
                    $([:(-1) for i in 1:length(props)]...),

                    # Clock
                    clock
                )

                # Set default values directly (bypassing access control during construction)
                $([if !isnothing(key_values[i])
                    quote
                        # Get the callback for this key
                        callback = _get_on_set($(struct_name), Val($(QuoteNode(key_names[i]))))

                        # Transform the default value through the callback
                        transformed_value = callback(instance, $(QuoteNode(key_names[i])), $(key_values[i]))

                        # Set the field directly (bypassing access checks since this is construction)
                        setfield!(instance, $(QuoteNode(key_names[i])), transformed_value)
                        setfield!(instance, $(QuoteNode(Symbol(:_, key_names[i], :_timestamp))), Clocks.time_nanos(clock))
                    end
                else
                    :()  # Empty expression for properties without defaults
                end for i in 1:length(props)]...)

                return instance
            end
        end
    end

    # Generate compile-time metadata functions for each key
    metadata_functions = []

    for (i, name) in enumerate(key_names)
        # Access control functions (using private naming to avoid conflicts)
        push!(metadata_functions, quote
            @inline _is_readable(::Type{<:$(struct_name)}, ::Val{$(QuoteNode(name))}) =
                StaticKV.AccessMode.is_readable($(key_access[i]))
            @inline _is_assignable(::Type{<:$(struct_name)}, ::Val{$(QuoteNode(name))}) =
                StaticKV.AccessMode.is_assignable($(key_access[i]))
            @inline _is_mutable(::Type{<:$(struct_name)}, ::Val{$(QuoteNode(name))}) =
                StaticKV.AccessMode.is_mutable($(key_access[i]))
            # Legacy function for backward compatibility
            @inline _is_writable(::Type{<:$(struct_name)}, ::Val{$(QuoteNode(name))}) =
                StaticKV.AccessMode.is_writable($(key_access[i]))
        end)

        # Callback functions (improved scoping)
        get_cb = if isnothing(key_get_cbs[i])
            isnothing(default_on_get) ? :(StaticKV._direct_default_callback) : default_on_get
        else
            key_get_cbs[i]
        end

        set_cb = if isnothing(key_set_cbs[i])
            isnothing(default_on_set) ? :(StaticKV._direct_default_callback) : default_on_set
        else
            key_set_cbs[i]
        end

        push!(metadata_functions, quote
            @inline _get_on_get(::Type{<:$(struct_name)}, ::Val{$(QuoteNode(name))}) = $(get_cb)
            @inline _get_on_set(::Type{<:$(struct_name)}, ::Val{$(QuoteNode(name))}) = $(set_cb)
        end)
    end

    # Generate key-specific accessor methods
    key_methods = []

    for (i, name) in enumerate(key_names)
        timestamp_field = Symbol(:_, name, :_timestamp)

        push!(key_methods, quote
            # Key-specific getkey method
            @inline function StaticKV.getkey(k::$(struct_name), ::Val{$(QuoteNode(name))})
                # Access check
                _is_readable($(struct_name), Val($(QuoteNode(name)))) ||
                    throw(ErrorException("Key not readable"))

                # Direct field access
                value = getfield(k, $(QuoteNode(name)))
                isnothing(value) && throw(ErrorException("Key not set"))

                # Compile-time callback (optimized away for defaults)
                callback = _get_on_get($(struct_name), Val($(QuoteNode(name))))
                return callback(k, $(QuoteNode(name)), value)
            end

            # Key-specific setkey! method
            @inline function StaticKV.setkey!(k::$(struct_name), ::Val{$(QuoteNode(name))}, v)
                # Access check
                _is_assignable($(struct_name), Val($(QuoteNode(name)))) ||
                    throw(ErrorException("Key not assignable"))

                # Compile-time callback (optimized away for defaults)
                callback = _get_on_set($(struct_name), Val($(QuoteNode(name))))
                transformed_value = callback(k, $(QuoteNode(name)), v)

                # Direct field updates (improved clock field access)
                setfield!(k, $(QuoteNode(name)), transformed_value)
                setfield!(k, $(QuoteNode(timestamp_field)), Clocks.time_nanos(getfield(k, $(QuoteNode(clock_field)))))

                return transformed_value
            end

            # Key-specific helper methods
            @inline function StaticKV.isset(k::$(struct_name), ::Val{$(QuoteNode(name))})
                !isnothing(getfield(k, $(QuoteNode(name))))
            end

            # Public access control methods (delegate to private ones)
            @inline function StaticKV.is_readable(k::$(struct_name), ::Val{$(QuoteNode(name))})
                _is_readable($(struct_name), Val($(QuoteNode(name))))
            end

            @inline function StaticKV.is_assignable(k::$(struct_name), ::Val{$(QuoteNode(name))})
                _is_assignable($(struct_name), Val($(QuoteNode(name))))
            end

            @inline function StaticKV.is_mutable(k::$(struct_name), ::Val{$(QuoteNode(name))})
                _is_mutable($(struct_name), Val($(QuoteNode(name))))
            end

            # Legacy function for backward compatibility
            @inline function StaticKV.is_writable(k::$(struct_name), ::Val{$(QuoteNode(name))})
                _is_writable($(struct_name), Val($(QuoteNode(name))))
            end

            @inline function StaticKV.last_update(k::$(struct_name), ::Val{$(QuoteNode(name))})
                getfield(k, $(QuoteNode(timestamp_field)))
            end

            @inline function StaticKV.resetindex!(k::$(struct_name), ::Val{$(QuoteNode(name))})
                _is_assignable($(struct_name), Val($(QuoteNode(name)))) ||
                    throw(ErrorException("Key not assignable"))
                setfield!(k, $(QuoteNode(name)), nothing)
                setfield!(k, $(QuoteNode(timestamp_field)), -1)
                return nothing
            end
        end)
    end

    # Generate utility functions
    utility_functions = quote
        # keynames function
        @inline function StaticKV.keynames(k::$(struct_name))
            $(Expr(:tuple, [QuoteNode(name) for name in key_names]...))
        end

        # Symbol-based dispatch functions (optimized if-else chains)
        @inline function StaticKV.getkey(k::$(struct_name), s::Symbol)
            $(if length(key_names) == 0
                :(throw(ErrorException("Key not found")))
            else
                result = :(throw(ErrorException("Key not found")))
                for name in reverse(key_names)
                    result = :(s === $(QuoteNode(name)) ? StaticKV.getkey(k, Val($(QuoteNode(name)))) : $result)
                end
                result
            end)
        end

        @inline function StaticKV.setindex!(k::$(struct_name), s::Symbol, v)
            $(if length(key_names) == 0
                :(throw(ErrorException("Key not found")))
            else
                result = :(throw(ErrorException("Key not found")))
                for name in reverse(key_names)
                    result = :(s === $(QuoteNode(name)) ? StaticKV.setindex!(k, Val($(QuoteNode(name))), v) : $result)
                end
                result
            end)
        end

        @inline function StaticKV.isset(k::$(struct_name), s::Symbol)
            $(if length(key_names) == 0
                :(false)
            else
                result = :(false)
                for name in reverse(key_names)
                    result = :(s === $(QuoteNode(name)) ? StaticKV.isset(k, Val($(QuoteNode(name)))) : $result)
                end
                result
            end)
        end

        @inline function StaticKV.is_readable(k::$(struct_name), s::Symbol)
            $(if length(key_names) == 0
                :(throw(ErrorException("Key not found")))
            else
                result = :(throw(ErrorException("Key not found")))
                for name in reverse(key_names)
                    result = :(s === $(QuoteNode(name)) ? _is_readable($(struct_name), Val($(QuoteNode(name)))) : $result)
                end
                result
            end)
        end

        @inline function StaticKV.is_writable(k::$(struct_name), s::Symbol)
            $(if length(key_names) == 0
                :(throw(ErrorException("Key not found")))
            else
                result = :(throw(ErrorException("Key not found")))
                for name in reverse(key_names)
                    result = :(s === $(QuoteNode(name)) ? _is_writable($(struct_name), Val($(QuoteNode(name)))) : $result)
                end
                result
            end)
        end

        @inline function StaticKV.is_assignable(k::$(struct_name), s::Symbol)
            $(if length(key_names) == 0
                :(throw(ErrorException("Key not found")))
            else
                result = :(throw(ErrorException("Key not found")))
                for name in reverse(key_names)
                    result = :(s === $(QuoteNode(name)) ? _is_assignable($(struct_name), Val($(QuoteNode(name)))) : $result)
                end
                result
            end)
        end

        @inline function StaticKV.is_mutable(k::$(struct_name), s::Symbol)
            $(if length(key_names) == 0
                :(throw(ErrorException("Key not found")))
            else
                result = :(throw(ErrorException("Key not found")))
                for name in reverse(key_names)
                    result = :(s === $(QuoteNode(name)) ? _is_mutable($(struct_name), Val($(QuoteNode(name)))) : $result)
                end
                result
            end)
        end

        @inline function StaticKV.last_update(k::$(struct_name), s::Symbol)
            $(if length(key_names) == 0
                :(throw(ErrorException("Key not found")))
            else
                result = :(throw(ErrorException("Key not found")))
                for name in reverse(key_names)
                    result = :(s === $(QuoteNode(name)) ? StaticKV.last_update(k, Val($(QuoteNode(name)))) : $result)
                end
                result
            end)
        end

        @inline function StaticKV.resetindex!(k::$(struct_name), s::Symbol)
            $(if length(key_names) == 0
                :(throw(ErrorException("Key not found")))
            else
                result = :(throw(ErrorException("Key not found")))
                for name in reverse(key_names)
                    result = :(s === $(QuoteNode(name)) ? StaticKV.resetindex!(k, Val($(QuoteNode(name)))) : $result)
                end
                result
            end)
        end

        # Additional utility functions
        @inline function StaticKV.keytype(::Type{<:$(struct_name)}, s::Symbol)
            $(if length(key_names) == 0
                :(nothing)
            else
                result = :(nothing)
                for (i, name) in enumerate(reverse(key_names))
                    key_type = key_types[end-i+1]
                    result = :(s === $(QuoteNode(name)) ? $(key_type) : $result)
                end
                result
            end)
        end

        @inline StaticKV.keytype(k::$(struct_name), s::Symbol) = StaticKV.keytype(typeof(k), s)

        @inline function StaticKV.allkeysset(k::$(struct_name))
            $(if length(key_names) == 0
                :(true)
            else
                and_expr = key_names[1] |> (name -> :(StaticKV.isset(k, $(QuoteNode(name)))))
                for name in key_names[2:end]
                    and_expr = :($(and_expr) && StaticKV.isset(k, $(QuoteNode(name))))
                end
                and_expr
            end)
        end

        # Improved pretty printing with better padding and formatting
        function Base.show(io::IO, ::MIME"text/plain", k::$(struct_name))
            println(io, "$($(QuoteNode(struct_name))) with keys:")

            names = StaticKV.keynames(k)
            if isempty(names)
                println(io, "  (no keys defined)")
                return
            end

            # Calculate padding widths for aligned columns
            max_name_len = maximum(length(string(name)) for name in names)
            max_type_len = 0
            max_value_len = 0
            max_access_len = 4  # "[RW]" is 4 characters

            # Pre-calculate all strings to determine max widths
            name_strs = String[]
            type_strs = String[]
            value_strs = String[]
            access_strs = String[]
            time_strs = String[]

            for name in names
                value = getfield(k, name)
                timestamp = getfield(k, Symbol(:_, name, :_timestamp))

                # Type info
                key_type = StaticKV.keytype(k, name)
                type_str = key_type === nothing ? "Any" : string(key_type)

                # Access info
                readable = StaticKV.is_readable(k, name)
                writable = StaticKV.is_writable(k, name)
                access_str = "[" * (readable ? "R" : "-") * (writable ? "W" : "-") * "]"

                # Value info
                value_str = isnothing(value) ? "nothing" : repr(value)
                time_str = timestamp == -1 ? "never" : "$(timestamp) ns"

                # Truncate very long values for better display
                if length(value_str) > 35
                    value_str = value_str[1:32] * "..."
                end

                push!(name_strs, string(name))
                push!(type_strs, type_str)
                push!(value_strs, value_str)
                push!(access_strs, access_str)
                push!(time_strs, time_str)

                max_type_len = max(max_type_len, length(type_str))
                max_value_len = max(max_value_len, length(value_str))
            end

            # Print each key with aligned columns
            for i in 1:length(names)
                name_padded = rpad(name_strs[i], max_name_len)
                type_padded = rpad("::$(type_strs[i])", max_type_len + 2)  # +2 for "::" prefix
                value_padded = rpad(value_strs[i], max_value_len)
                access_padded = rpad(access_strs[i], max_access_len)

                println(io, "  $(name_padded) $(type_padded) = $(value_padded) $(access_padded) (last update: $(time_strs[i]))")
            end
        end

        function Base.show(io::IO, k::$(struct_name))
            set_count = count(name -> StaticKV.isset(k, name), StaticKV.keynames(k))
            total = length(StaticKV.keynames(k))
            print(io, "$($(QuoteNode(struct_name))) $(set_count)/$(total) keys set")
        end

        # Safe key access functions (from old API)
        @inline function StaticKV.with_key(f::Function, k::$(struct_name), s::Symbol)
            if !StaticKV.isset(k, s)
                throw(ErrorException("Key :$s is not set"))
            end
            if !StaticKV.is_readable(k, s)
                throw(ErrorException("Key :$s is not readable"))
            end
            f(StaticKV.getkey(k, s))
        end

        @inline function StaticKV.with_key!(f::Function, k::$(struct_name), s::Symbol)
            if !StaticKV.isset(k, s)
                throw(ErrorException("Key :$s is not set"))
            end
            if !StaticKV.is_readable(k, s)
                throw(ErrorException("Key :$s is not readable"))
            end
            if !StaticKV.is_mutable(k, s)
                throw(ErrorException("Key :$s is not mutable"))
            end

            # Check if key type is isbits - if so, should throw error
            key_type = StaticKV.keytype(k, s)
            if key_type !== nothing && isbitstype(key_type)
                throw(ErrorException("Cannot mutate isbits key :$s in place"))
            end

            # Get the current value and call the function
            current_value = StaticKV.getkey(k, s)
            result = f(current_value)

            # For in-place mutations, we don't reassign the key value.
            # The function should modify the object directly and we just return the result.
            # If the user wants to set a new value, they should use setindex! explicitly.
            result
        end

        @inline function StaticKV.with_keys(f::Function, k::$(struct_name), keys::Symbol...)
            @inline function val_generator(i)
                prop = keys[i]
                if !StaticKV.isset(k, prop)
                    throw(ArgumentError("Key :\$prop is not set"))
                end
                if !StaticKV.is_readable(k, prop)
                    throw(ArgumentError("Key :\$prop is not readable"))
                end
                StaticKV.getkey(k, prop)
            end

            if length(keys) == 0
                return f()
            elseif length(keys) == 1
                return f(val_generator(1))
            elseif length(keys) == 2
                return f(val_generator(1), val_generator(2))
            elseif length(keys) == 3
                return f(val_generator(1), val_generator(2), val_generator(3))
            elseif length(keys) == 4
                return f(val_generator(1), val_generator(2), val_generator(3), val_generator(4))
            elseif length(keys) == 5
                return f(val_generator(1), val_generator(2), val_generator(3), val_generator(4), val_generator(5))
            else
                # For more than 5 keys, use splatting (less optimal but functional)
                values = [val_generator(i) for i in 1:length(keys)]
                return f(values...)
            end
        end

        # Base interface functions for backward compatibility
        @inline function Base.getindex(k::$(struct_name), key::Symbol)
            StaticKV.getkey(k, key)
        end

        @inline function Base.getindex(k::$(struct_name), keys::Symbol...)
            tuple((StaticKV.getkey(k, key) for key in keys)...)
        end

        @inline function Base.setindex!(k::$(struct_name), value, key::Symbol)
            StaticKV.setkey!(k, key, value)
        end

        @inline function Base.setindex!(k::$(struct_name), values, keys::Symbol...)
            if length(values) != length(keys)
                throw(ArgumentError("Number of values (\$(length(values))) must match number of keys (\$(length(keys)))"))
            end
            for (key, val) in zip(keys, values)
                StaticKV.setkey!(k, key, val)
            end
            values
        end

        @inline function Base.values(k::$(struct_name))
            # Note: This operation may allocate due to dynamic filtering
            # Key-value store interface operations are less performance-critical than direct key access
            readable_set_values = Any[]
            for name in StaticKV.keynames(k)
                if StaticKV.isset(k, name) && StaticKV.is_readable(k, name)
                    push!(readable_set_values, StaticKV.getkey(k, name))
                end
            end
            tuple(readable_set_values...)
        end

        @inline function Base.pairs(k::$(struct_name))
            # Only include pairs for keys that are set and readable
            # Use tuple comprehension to avoid allocations
            tuple(((name, StaticKV.getkey(k, name)) for name in StaticKV.keynames(k) if StaticKV.isset(k, name) && StaticKV.is_readable(k, name))...)
        end

        @inline function Base.iterate(k::$(struct_name))
            # Get all readable, set keys as a tuple to avoid allocations
            readable_set_keys = tuple(((name, StaticKV.getkey(k, name)) for name in StaticKV.keynames(k) if StaticKV.isset(k, name) && StaticKV.is_readable(k, name))...)

            if isempty(readable_set_keys)
                return nothing
            end
            return (readable_set_keys[1], (readable_set_keys, 2))
        end

        @inline function Base.iterate(k::$(struct_name), state)
            readable_set_keys, index = state
            if index > length(readable_set_keys)
                return nothing
            end
            return (readable_set_keys[index], (readable_set_keys, index + 1))
        end

        @inline function Base.length(k::$(struct_name))
            # Count only keys that are set
            count = 0
            for name in StaticKV.keynames(k)
                if StaticKV.isset(k, name)
                    count += 1
                end
            end
            count
        end

        @inline function Base.get(k::$(struct_name), key::Symbol, default)
            if StaticKV.isset(k, key) && StaticKV.is_readable(k, key)
                StaticKV.getkey(k, key)
            else
                default
            end
        end

        @inline function Base.isreadable(k::$(struct_name), key::Symbol)
            StaticKV.is_readable(k, key)
        end

        @inline function Base.iswritable(k::$(struct_name), key::Symbol)
            StaticKV.is_writable(k, key)
        end

        @inline function Base.ismutable(k::$(struct_name), key::Symbol)
            # Check if key exists and is mutable
            if haskey(k, key)
                StaticKV.is_mutable(k, key)
            else
                false
            end
        end

        @inline function Base.ismutable(k::$(struct_name))
            # The struct itself is always mutable (it's declared as mutable struct)
            true
        end

        @inline function Base.keys(k::$(struct_name))
            StaticKV.keynames(k)
        end

        @inline function Base.haskey(k::$(struct_name), key::Symbol)
            key in StaticKV.keynames(k)
        end

        # Override getproperty and setproperty! for natural dot syntax access
        @inline function Base.getproperty(k::$(struct_name), name::Symbol)
            # Check if it's a managed key first
            if name in StaticKV.keynames(k)
                return StaticKV.getkey(k, name)
            else
                # Fall back to default field access for internal fields (like clock)
                return getfield(k, name)
            end
        end

        @inline function Base.setproperty!(k::$(struct_name), name::Symbol, value)
            # Check if it's a managed key first
            if name in StaticKV.keynames(k)
                return StaticKV.setindex!(k, name, value)
            else
                # Fall back to default field access for internal fields (like clock)
                return setfield!(k, name, value)
            end
        end
    end

    # Combine everything
    result = quote
        $(struct_def)
        $(metadata_functions...)
        $(key_methods...)
        $(utility_functions)
    end

    return esc(result)
end

"""
    strip_module_qualifications(expr)

Remove module qualifications from symbols and expressions.
This is particularly useful for handling expressions generated by macros
where module qualifications are automatically inserted by Julia's macro system.

Uses MacroTools.postwalk for robust AST traversal and transformation.
"""
function strip_module_qualifications(expr)
    # Use MacroTools.postwalk which recursively walks the expression tree
    # and applies the transformation to each node
    MacroTools.postwalk(expr) do x
        # Handle GlobalRef (Main.:(=>))
        if x isa GlobalRef
            if x.mod == Main
                return x.name
            else
                # Keep module qualifications for non-Main modules
                # This is important for AccessMode constants
                return x
            end
        # Handle module qualification expressions (Main.Symbol)
        elseif x isa Expr && x.head == :(.)
            if length(x.args) == 2
                # Only strip Main module qualifications, preserve others like AccessMode
                if x.args[1] == :Main && x.args[2] isa QuoteNode
                    return x.args[2].value
                # Handle special cases involving operators and other symbols from Main
                elseif x.args[1] == :Main && x.args[2] isa Expr && x.args[2].head == :quote
                    return x.args[2].args[1]
                else
                    # Keep other module qualifications like AccessMode.READABLE
                    return x
                end
            end
        # Handle quoted expressions within module qualifications
        elseif x isa Expr && x.head == :quote
            # Don't transform the content of quoted expressions
            return x
        # Handle string literals specially
        elseif x isa Expr && x.head == :string
            # Don't transform string literals
            return x
        # Handle macro calls, only strip module from the macro name
        elseif x isa Expr && x.head == :macrocall
            if length(x.args) >= 1
                # Only strip from the macro name (first arg) but preserve the rest
                return Expr(:macrocall,
                           strip_module_qualifications(x.args[1]),
                           x.args[2:end]...)
            end
        end
        # Default: return node unchanged
        return x
    end
end


end # module
