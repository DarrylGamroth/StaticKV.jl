module ManagedProperties

"""
    ManagedProperties

A high-performance implementation of managed properties with direct field storage and compile-time metadata.
This version creates concrete, non-parametric structs that are easy to use as fields in other structs.

# Key Features
- **Direct field storage**: `Union{Nothing,T}` for values, `Int64` for timestamps
- **Compile-time metadata**: Access control and callbacks stored at type level
- **Zero overhead**: Default callbacks optimized away completely
- **Type-stable**: All operations fully optimized by Julia compiler
- **Macro expansion**: Support for field generator macros in property blocks

# Example
```julia
using ManagedProperties

@properties Person begin
    name::String
    age::Int => (access => AccessMode.READABLE)
    email::String => (
        read_callback => (obj, prop, val) -> "***@***.com",
        write_callback => (obj, prop, val) -> lowercase(val)
    )
end

person = Person()
set_property!(person, :name, "Alice")
println(get_property(person, :name))  # "Alice"

# Can be used as concrete field types
struct Company
    ceo::Person{Clocks.EpochClock}
    employees::Vector{Person{Clocks.EpochClock}}
end
```
"""

using Clocks
using MacroTools

# Export public API
export @properties, AccessMode
export get_property, set_property!, reset_property!, property_type, is_set, all_properties_set
export with_property, with_property!
export with_properties
export is_readable, is_writable, last_update
export property_names
export Clocks

"""
    AccessMode

Module containing access control constants for property access.

# Constants
- `NONE`: No access (0x00)
- `READABLE`: Property can be read (0x01)
- `WRITABLE`: Property can be written (0x02)
- `READABLE_WRITABLE`: Property can be both read and written (0x03)
"""
module AccessMode
const AccessModeType = UInt8

const NONE::AccessModeType = 0x00
const READABLE::AccessModeType = 0x01
const WRITABLE::AccessModeType = 0x02
const READABLE_WRITABLE::AccessModeType = READABLE | WRITABLE

"""
    is_readable(flags)

Check if the property has readable access based on its access flags.
"""
@inline is_readable(flags) = !iszero(flags & READABLE)

"""
    is_writable(flags)

Check if the property has writable access based on its access flags.
"""
@inline is_writable(flags) = !iszero(flags & WRITABLE)

end # AccessMode module

# Default callback functions (zero overhead when inlined)
@inline _direct_default_callback(obj, prop, value) = value

# Helper function to process property attributes
function process_attribute!(result, key, value)
    if key === :value
        result[:value] = value
    elseif key === :access
        result[:access] = value
    elseif key === :read_callback
        result[:read_callback] = value
    elseif key === :write_callback
        result[:write_callback] = value
    else
        throw(ErrorException("Unknown property attribute: $key"))
    end
end

"""
    parse_property_def(expr)

Parse a property definition expression into a dictionary containing the property's
name, type, default value, access mode, and callbacks.

Uses MacroTools for AST manipulation and simple pattern analysis.
"""
function parse_property_def(expr)
    # Property definition parser

    result = Dict{Symbol,Any}()

    # Initialize with defaults
    result[:value] = nothing
    result[:access] = :(ManagedProperties.AccessMode.READABLE_WRITABLE)
    result[:read_callback] = nothing
    result[:write_callback] = nothing

    # Helper function to check if type expression is a Union
    function is_union_type(type_expr)
        if type_expr isa Expr && type_expr.head == :curly && type_expr.args[1] == :Union
            return true
        end
        return false
    end

    # Make sure expr is an Expr
    if !(expr isa Expr)
        throw(ErrorException("Expected property definition, got: $(typeof(expr))"))
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
            throw(ErrorException("Property name must be a symbol, got: $(typeof(name_expr))"))
        end

        # Extract the type
        result[:type] = type_expr

        # Check for Union types
        if is_union_type(result[:type])
            throw(ErrorException("Union types are not allowed in property definitions as they conflict with the internal representation of unset properties"))
        end

        return result
    end

    # Handle pair syntax: name::Type => (attributes...)
    if clean_expr.head == :call && length(clean_expr.args) >= 3 && clean_expr.args[1] == :(=>)
        type_expr = clean_expr.args[2]
        attrs_expr = clean_expr.args[3]

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
            throw(ErrorException("Property name must be a symbol, got: $(typeof(name_expr))"))
        end

        # Extract the type
        result[:type] = type_value

        # Check for Union types
        if is_union_type(result[:type])
            throw(ErrorException("Union types are not allowed in property definitions as they conflict with the internal representation of unset properties"))
        end

        # Parse attributes
        if attrs_expr isa Expr
            if attrs_expr.head == :call && length(attrs_expr.args) >= 3 && attrs_expr.args[1] == :(=>)
                # Single key-value attribute
                key = attrs_expr.args[2]
                value = attrs_expr.args[3]

                # Key must be a symbol or convertible to one
                if key isa Symbol
                    process_attribute!(result, key, value)
                else
                    throw(ErrorException("Attribute key must be a symbol, got: $(typeof(key))"))
                end
            elseif attrs_expr.head == :tuple
                # Multiple attributes in a tuple
                for attr in attrs_expr.args
                    if attr isa LineNumberNode
                        continue
                    end

                    if attr isa Expr && attr.head == :call && length(attr.args) >= 3 && attr.args[1] == :(=>)
                        key = attr.args[2]
                        value = attr.args[3]

                        # Key must be a symbol or convertible to one
                        if key isa Symbol
                            process_attribute!(result, key, value)
                        else
                            throw(ErrorException("Attribute key must be a symbol, got: $(typeof(key))"))
                        end
                    else
                        throw(ErrorException("Expected key => value pair in attributes, got: $attr"))
                    end
                end
            else
                throw(ErrorException("Expected attributes as tuple or pair, got: $attrs_expr"))
            end
        else
            throw(ErrorException("Expected attributes expression, got: $(typeof(attrs_expr))"))
        end

        return result
    end

    # If we reach here, the expression didn't match any of our expected patterns
    throw(ErrorException("Expected property definition (name::Type or name::Type => attrs), got expression with head: $(clean_expr.head)"))
end

"""
    @properties struct_name [clock_type=ClockType] [default_read_callback=fn] [default_write_callback=fn] begin
        prop1::Type1
        prop2::Type2 => (access => AccessMode.READABLE)
        prop3::Type3 => (
            value => default_value,
            access => AccessMode.READABLE_WRITABLE,
            read_callback => custom_read_fn,
            write_callback => custom_write_fn
        )
    end

Create a struct with managed properties using direct field storage and compile-time metadata.

# Benefits
- **Concrete types**: No parametric complexity, easy to use as struct fields
- **Zero overhead**: Default callbacks optimized away completely
- **Type stable**: All metadata resolved at compile time
- **Memory efficient**: Direct field storage with minimal overhead

# Property definition formats
- `name::Type`: Simple property with type
- `name::Type => (key => value, ...)`: Property with custom attributes

# Property attributes
- `value`: Default value for the property
- `access`: Access control flags (e.g., `AccessMode.READABLE_WRITABLE`)
- `read_callback`: Custom function called when reading: `(obj, name, value) -> transformed_value`
- `write_callback`: Custom function called when writing: `(obj, name, value) -> transformed_value`

# Struct-level parameters
- `clock_type`: Concrete clock type to use (default: `Clocks.EpochClock`)
- `default_read_callback`: Default read callback for all properties
- `default_write_callback`: Default write callback for all properties

# Examples
```julia
# Basic usage with default EpochClock
@properties Person begin
    name::String
end

# Using CachedEpochClock for better performance
@properties Person clock_type=Clocks.CachedEpochClock begin
    name::String
    age::Int
end

# With default callbacks
@properties Person default_read_callback=my_read_fn default_write_callback=my_write_fn begin
    name::String
end

# Using field generator macros
@properties Config begin
    name::String

    # Field generator macros are expanded during compilation
    @generate_timestamp_fields
    @generate_counter_fields request response
end
```
"""
macro properties(struct_name, args...)
    # The last argument should always be the property block
    if length(args) < 1
        error("@properties requires a begin...end block after the struct name")
    end

    block = args[end]
    if block.head != :block
        error("@properties requires a begin...end block for property definitions")
    end

    # Parse optional struct-level parameters
    default_read_callback = nothing
    default_write_callback = nothing
    clock_type = :(Clocks.EpochClock)  # Default to EpochClock

    # Handle struct-level parameters (everything except the last block)
    for i in 1:(length(args)-1)
        arg = args[i]
        if arg isa Expr && arg.head == :(=)
            param_name = arg.args[1]
            param_value = arg.args[2]

            if param_name == :default_read_callback
                default_read_callback = param_value
            elseif param_name == :default_write_callback
                default_write_callback = param_value
            elseif param_name == :clock_type
                clock_type = param_value
            else
                error("Unknown parameter: $param_name")
            end
        else
            error("Invalid parameter format: $arg")
        end
    end

    # Extract property definitions and expand any macros
    # This includes support for field generator macros like @generate_data_uri_fields
    property_defs = []

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
                            expanded = macroexpand(ManagedProperties, expr)
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
                                    push!(property_defs, clean_expr)
                                end
                            end
                        else
                            # Single expression expansion
                            clean_expr = strip_module_qualifications(expanded)
                            push!(property_defs, clean_expr)
                        end
                    end
                end
            else
                # Regular property definition
                push!(property_defs, expr)
            end
        end
    end

    # Parse property definitions
    props = []
    for (index, def) in enumerate(property_defs)
        try
            # Check for module qualified names that need stripping
            if def isa Expr
                # Apply proper module qualification stripping
                def = strip_module_qualifications(def)
            end

            # Parse the property definition
            parsed_prop = parse_property_def(def)

            push!(props, parsed_prop)
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

                        parsed_prop = parse_property_def(clean_def)
                        push!(props, parsed_prop)
                        continue
                    end
                catch
                    # If recovery fails, just report the original error
                    error("Failed to parse property definition: $(def)")
                end
            else
                error("Failed to parse property definition: $(def)")
            end
        end
    end

    # Extract property information
    prop_names = [p[:name] for p in props]
    prop_types = [p[:type] for p in props]
    prop_values = [p[:value] for p in props]
    prop_access = [p[:access] for p in props]
    prop_read_cbs = [p[:read_callback] for p in props]
    prop_write_cbs = [p[:write_callback] for p in props]

    # Use gensym for clock to avoid naming conflicts (from DirectFields)
    clock_field = gensym(:clock)

    # Generate the struct with direct field storage
    struct_fields = []

    # Add value fields
    for (name, type) in zip(prop_names, prop_types)
        push!(struct_fields, :($(name)::Union{Nothing,$(type)}))
    end

    # Add timestamp fields (with underscore prefix to avoid collisions)
    for name in prop_names
        push!(struct_fields, :($(Symbol(:_, name, :_timestamp))::Int64))
    end

    # Add clock field (using gensym to avoid conflicts) - parametric for zero overhead
    push!(struct_fields, :($(clock_field)::C))

    # Create the struct definition (parametric on clock type for zero overhead)
    struct_def = quote
        mutable struct $(struct_name){C <: Clocks.AbstractClock}
            $(struct_fields...)

            # Constructor with better default value handling
            function $(struct_name)(clock::C = $(clock_type)()) where {C <: Clocks.AbstractClock}
                # Initialize values (use defaults if provided, nothing otherwise)
                # Initialize timestamps (current time if default value, -1 otherwise)
                new{C}(
                    # Value fields
                    $([:($(isnothing(prop_values[i]) ? :(nothing) : prop_values[i])) for i in 1:length(props)]...),

                    # Timestamp fields
                    $([:($(isnothing(prop_values[i]) ? :(-1) : :(Clocks.time_nanos(clock)))) for i in 1:length(props)]...),

                    # Clock
                    clock
                )
            end

            # Convenience constructor with default clock type
            function $(struct_name)()
                $(struct_name)($(clock_type)())
            end
        end
    end

    # Generate compile-time metadata functions for each property
    metadata_functions = []

    for (i, name) in enumerate(prop_names)
        # Access control functions (using private naming to avoid conflicts)
        push!(metadata_functions, quote
            @inline _is_readable(::Type{<:$(struct_name)}, ::Val{$(QuoteNode(name))}) =
                ManagedProperties.AccessMode.is_readable($(prop_access[i]))
            @inline _is_writable(::Type{<:$(struct_name)}, ::Val{$(QuoteNode(name))}) =
                ManagedProperties.AccessMode.is_writable($(prop_access[i]))
        end)

        # Callback functions (improved scoping)
        read_cb = if isnothing(prop_read_cbs[i])
            isnothing(default_read_callback) ? :(ManagedProperties._direct_default_callback) : default_read_callback
        else
            prop_read_cbs[i]
        end

        write_cb = if isnothing(prop_write_cbs[i])
            isnothing(default_write_callback) ? :(ManagedProperties._direct_default_callback) : default_write_callback
        else
            prop_write_cbs[i]
        end

        push!(metadata_functions, quote
            @inline _get_read_callback(::Type{<:$(struct_name)}, ::Val{$(QuoteNode(name))}) = $(read_cb)
            @inline _get_write_callback(::Type{<:$(struct_name)}, ::Val{$(QuoteNode(name))}) = $(write_cb)
        end)
    end

    # Generate property-specific accessor methods
    property_methods = []

    for (i, name) in enumerate(prop_names)
        timestamp_field = Symbol(:_, name, :_timestamp)

        push!(property_methods, quote
            # Property-specific get_property method (improved from DirectFields)
            @inline function get_property(p::$(struct_name), ::Val{$(QuoteNode(name))})
                # Compile-time access check
                _is_readable($(struct_name), Val($(QuoteNode(name)))) ||
                    throw(ErrorException("Property not readable"))

                # Direct field access
                value = getfield(p, $(QuoteNode(name)))
                isnothing(value) && throw(ErrorException("Property not set"))

                # Compile-time callback (optimized away for defaults)
                callback = _get_read_callback($(struct_name), Val($(QuoteNode(name))))
                return callback(p, $(QuoteNode(name)), value)
            end

            # Property-specific set_property! method (improved clock access)
            @inline function set_property!(p::$(struct_name), ::Val{$(QuoteNode(name))}, v)
                # Compile-time access check
                _is_writable($(struct_name), Val($(QuoteNode(name)))) ||
                    throw(ErrorException("Property not writable"))

                # Compile-time callback (optimized away for defaults)
                callback = _get_write_callback($(struct_name), Val($(QuoteNode(name))))
                transformed_value = callback(p, $(QuoteNode(name)), v)

                # Direct field updates (improved clock field access)
                setfield!(p, $(QuoteNode(name)), transformed_value)
                setfield!(p, $(QuoteNode(timestamp_field)), Clocks.time_nanos(getfield(p, $(QuoteNode(clock_field)))))

                return transformed_value
            end

            # Property-specific helper methods
            @inline function is_set(p::$(struct_name), ::Val{$(QuoteNode(name))})
                !isnothing(getfield(p, $(QuoteNode(name))))
            end

            # Public access control methods (delegate to private ones)
            @inline function is_readable(p::$(struct_name), ::Val{$(QuoteNode(name))})
                _is_readable($(struct_name), Val($(QuoteNode(name))))
            end

            @inline function is_writable(p::$(struct_name), ::Val{$(QuoteNode(name))})
                _is_writable($(struct_name), Val($(QuoteNode(name))))
            end

            @inline function last_update(p::$(struct_name), ::Val{$(QuoteNode(name))})
                getfield(p, $(QuoteNode(timestamp_field)))
            end

            @inline function reset_property!(p::$(struct_name), ::Val{$(QuoteNode(name))})
                _is_writable($(struct_name), Val($(QuoteNode(name)))) ||
                    throw(ErrorException("Property not writable"))
                setfield!(p, $(QuoteNode(name)), nothing)
                setfield!(p, $(QuoteNode(timestamp_field)), -1)
                return nothing
            end
        end)
    end

    # Generate utility functions
    utility_functions = quote
        # property_names function
        @inline function property_names(p::$(struct_name))
            $(Expr(:tuple, [QuoteNode(name) for name in prop_names]...))
        end

        # Symbol-based dispatch functions (optimized if-else chains)
        @inline function get_property(p::$(struct_name), s::Symbol)
            $(if length(prop_names) == 0
                :(throw(ErrorException("Property not found")))
            else
                result = :(throw(ErrorException("Property not found")))
                for name in reverse(prop_names)
                    result = :(s === $(QuoteNode(name)) ? get_property(p, Val($(QuoteNode(name)))) : $result)
                end
                result
            end)
        end

        @inline function set_property!(p::$(struct_name), s::Symbol, v)
            $(if length(prop_names) == 0
                :(throw(ErrorException("Property not found")))
            else
                result = :(throw(ErrorException("Property not found")))
                for name in reverse(prop_names)
                    result = :(s === $(QuoteNode(name)) ? set_property!(p, Val($(QuoteNode(name))), v) : $result)
                end
                result
            end)
        end

        @inline function is_set(p::$(struct_name), s::Symbol)
            $(if length(prop_names) == 0
                :(false)
            else
                result = :(false)
                for name in reverse(prop_names)
                    result = :(s === $(QuoteNode(name)) ? is_set(p, Val($(QuoteNode(name)))) : $result)
                end
                result
            end)
        end

        @inline function is_readable(p::$(struct_name), s::Symbol)
            $(if length(prop_names) == 0
                :(throw(ErrorException("Property not found")))
            else
                result = :(throw(ErrorException("Property not found")))
                for name in reverse(prop_names)
                    result = :(s === $(QuoteNode(name)) ? _is_readable($(struct_name), Val($(QuoteNode(name)))) : $result)
                end
                result
            end)
        end

        @inline function is_writable(p::$(struct_name), s::Symbol)
            $(if length(prop_names) == 0
                :(throw(ErrorException("Property not found")))
            else
                result = :(throw(ErrorException("Property not found")))
                for name in reverse(prop_names)
                    result = :(s === $(QuoteNode(name)) ? _is_writable($(struct_name), Val($(QuoteNode(name)))) : $result)
                end
                result
            end)
        end

        @inline function last_update(p::$(struct_name), s::Symbol)
            $(if length(prop_names) == 0
                :(throw(ErrorException("Property not found")))
            else
                result = :(throw(ErrorException("Property not found")))
                for name in reverse(prop_names)
                    result = :(s === $(QuoteNode(name)) ? last_update(p, Val($(QuoteNode(name)))) : $result)
                end
                result
            end)
        end

        @inline function reset_property!(p::$(struct_name), s::Symbol)
            $(if length(prop_names) == 0
                :(throw(ErrorException("Property not found")))
            else
                result = :(throw(ErrorException("Property not found")))
                for name in reverse(prop_names)
                    result = :(s === $(QuoteNode(name)) ? reset_property!(p, Val($(QuoteNode(name)))) : $result)
                end
                result
            end)
        end

        # Additional utility functions (from DirectFields version)
        @inline function property_type(::Type{<:$(struct_name)}, s::Symbol)
            $(if length(prop_names) == 0
                :(nothing)
            else
                result = :(nothing)
                for (i, name) in enumerate(reverse(prop_names))
                    prop_type = prop_types[end-i+1]
                    result = :(s === $(QuoteNode(name)) ? $(prop_type) : $result)
                end
                result
            end)
        end

        @inline property_type(p::$(struct_name), s::Symbol) = property_type(typeof(p), s)

        @inline function all_properties_set(p::$(struct_name))
            $(if length(prop_names) == 0
                :(true)
            else
                and_expr = prop_names[1] |> (name -> :(is_set(p, $(QuoteNode(name)))))
                for name in prop_names[2:end]
                    and_expr = :($(and_expr) && is_set(p, $(QuoteNode(name))))
                end
                and_expr
            end)
        end

        # Improved pretty printing with better padding and formatting
        function Base.show(io::IO, ::MIME"text/plain", p::$(struct_name))
            println(io, "$($(QuoteNode(struct_name))) with properties:")

            names = property_names(p)
            if isempty(names)
                println(io, "  (no properties defined)")
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
                value = getfield(p, name)
                timestamp = getfield(p, Symbol(:_, name, :_timestamp))

                # Type info
                prop_type = property_type(p, name)
                type_str = prop_type === nothing ? "Any" : string(prop_type)

                # Access info
                readable = is_readable(p, name)
                writable = is_writable(p, name)
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

            # Print each property with aligned columns
            for i in 1:length(names)
                name_padded = rpad(name_strs[i], max_name_len)
                type_padded = rpad("::$(type_strs[i])", max_type_len + 2)  # +2 for "::" prefix
                value_padded = rpad(value_strs[i], max_value_len)
                access_padded = rpad(access_strs[i], max_access_len)

                println(io, "  $(name_padded) $(type_padded) = $(value_padded) $(access_padded) (last update: $(time_strs[i]))")
            end
        end

        function Base.show(io::IO, p::$(struct_name))
            set_count = count(name -> is_set(p, name), property_names(p))
            total = length(property_names(p))
            print(io, "$($(QuoteNode(struct_name))) $(set_count)/$(total) properties set")
        end

        # Safe property access functions (from old API)
        @inline function with_property(f::Function, p::$(struct_name), s::Symbol)
            if !is_set(p, s)
                throw(ErrorException("Property :$s is not set"))
            end
            if !is_readable(p, s)
                throw(ErrorException("Property :$s is not readable"))
            end
            f(get_property(p, s))
        end

        @inline function with_property!(f::Function, p::$(struct_name), s::Symbol)
            if !is_set(p, s)
                throw(ErrorException("Property :$s is not set"))
            end
            if !is_readable(p, s)
                throw(ErrorException("Property :$s is not readable"))
            end
            if !is_writable(p, s)
                throw(ErrorException("Property :$s is not writable"))
            end

            # Check if property type is isbits - if so, should throw error
            prop_type = property_type(p, s)
            if prop_type !== nothing && isbitstype(prop_type)
                throw(ErrorException("Cannot mutate isbits property :$s in place"))
            end

            # Get the current value and call the function
            current_value = get_property(p, s)
            result = f(current_value)

            # For in-place mutations, we don't reassign the property value.
            # The function should modify the object directly and we just return the result.
            # If the user wants to set a new value, they should use set_property! explicitly.
            result
        end

        @inline function with_properties(f::Function, p::$(struct_name), properties::Symbol...)
            @inline function val_generator(i)
                prop = properties[i]
                if !is_set(p, prop)
                    throw(ArgumentError("Property :\$prop is not set"))
                end
                if !is_readable(p, prop)
                    throw(ArgumentError("Property :\$prop is not readable"))
                end
                get_property(p, prop)
            end

            if length(properties) == 0
                return f()
            elseif length(properties) == 1
                return f(val_generator(1))
            elseif length(properties) == 2
                return f(val_generator(1), val_generator(2))
            elseif length(properties) == 3
                return f(val_generator(1), val_generator(2), val_generator(3))
            elseif length(properties) == 4
                return f(val_generator(1), val_generator(2), val_generator(3), val_generator(4))
            elseif length(properties) == 5
                return f(val_generator(1), val_generator(2), val_generator(3), val_generator(4), val_generator(5))
            else
                # For more than 5 properties, use splatting (less optimal but functional)
                values = [val_generator(i) for i in 1:length(properties)]
                return f(values...)
            end
        end

        # Base interface functions for backward compatibility
        @inline function Base.getindex(p::$(struct_name), key::Symbol)
            get_property(p, key)
        end

        @inline function Base.getindex(p::$(struct_name), keys::Symbol...)
            tuple((get_property(p, key) for key in keys)...)
        end

        @inline function Base.setindex!(p::$(struct_name), value, key::Symbol)
            set_property!(p, key, value)
        end

        @inline function Base.setindex!(p::$(struct_name), values, keys::Symbol...)
            if length(values) != length(keys)
                throw(ArgumentError("Number of values (\$(length(values))) must match number of keys (\$(length(keys)))"))
            end
            for (key, val) in zip(keys, values)
                set_property!(p, key, val)
            end
            values
        end

        @inline function Base.values(p::$(struct_name))
            # Note: This operation may allocate due to dynamic filtering
            # Property bag interface operations are less performance-critical than direct property access
            readable_set_values = Any[]
            for name in property_names(p)
                if is_set(p, name) && is_readable(p, name)
                    push!(readable_set_values, get_property(p, name))
                end
            end
            tuple(readable_set_values...)
        end

        @inline function Base.pairs(p::$(struct_name))
            # Only include pairs for properties that are set and readable
            # Use tuple comprehension to avoid allocations
            tuple(((name, get_property(p, name)) for name in property_names(p) if is_set(p, name) && is_readable(p, name))...)
        end

        @inline function Base.iterate(p::$(struct_name))
            # Get all readable, set properties as a tuple to avoid allocations
            readable_set_props = tuple(((name, get_property(p, name)) for name in property_names(p) if is_set(p, name) && is_readable(p, name))...)

            if isempty(readable_set_props)
                return nothing
            end
            return (readable_set_props[1], (readable_set_props, 2))
        end

        @inline function Base.iterate(p::$(struct_name), state)
            readable_set_props, index = state
            if index > length(readable_set_props)
                return nothing
            end
            return (readable_set_props[index], (readable_set_props, index + 1))
        end

        @inline function Base.length(p::$(struct_name))
            # Count only properties that are set
            count = 0
            for name in property_names(p)
                if is_set(p, name)
                    count += 1
                end
            end
            count
        end

        @inline function Base.get(p::$(struct_name), key::Symbol, default)
            if is_set(p, key) && is_readable(p, key)
                get_property(p, key)
            else
                default
            end
        end

        @inline function Base.isreadable(p::$(struct_name), key::Symbol)
            is_readable(p, key)
        end

        @inline function Base.iswritable(p::$(struct_name), key::Symbol)
            is_writable(p, key)
        end

        @inline function Base.keys(p::$(struct_name))
            property_names(p)
        end

        @inline function Base.haskey(p::$(struct_name), key::Symbol)
            key in property_names(p)
        end

        # Override getproperty and setproperty! for natural dot syntax access
        @inline function Base.getproperty(p::$(struct_name), name::Symbol)
            # Check if it's a managed property first
            if name in property_names(p)
                return get_property(p, name)
            else
                # Fall back to default field access for internal fields (like clock)
                return getfield(p, name)
            end
        end

        @inline function Base.setproperty!(p::$(struct_name), name::Symbol, value)
            # Check if it's a managed property first
            if name in property_names(p)
                return set_property!(p, name, value)
            else
                # Fall back to default field access for internal fields (like clock)
                return setfield!(p, name, value)
            end
        end
    end

    # Combine everything
    result = quote
        $(struct_def)
        $(metadata_functions...)
        $(property_methods...)
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
