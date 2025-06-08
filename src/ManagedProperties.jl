"""
    ManagedProperties

A Julia package that provides a macro-based system for creating objects with managed properties.
Properties can have access control, custom read/write callbacks, and automatic timestamp tracking.

# Example
```julia
using ManagedProperties
using Clocks

@properties Person begin
    name::String
    age::Int => (value => 0, access => AccessMode.READABLE_WRITABLE)
    ssn::String => (access => AccessMode.READABLE)
    address::String => (
        read_callback => (obj, name, val) -> "REDACTED",
        write_callback => (obj, name, val) -> uppercase(val)
    )
end

person = Person()
set_property!(person, :name, "Alice")
println(get_property(person, :name))  # "Alice"
```
"""
module ManagedProperties

# Export public API
export @properties, AccessMode
export get_property, set_property!, reset_property!, property_type, is_set, all_properties_set
export with_property, with_property!
export with_properties
export is_readable, is_writable, last_update
export property_names

# Access mode flags
"""
    AccessMode

Module containing access control flags and utility functions for property access.

# Constants
- `NONE`: No access (0x00)
- `READABLE`: Property can be read (0x01)
- `WRITABLE`: Property can be written (0x02)
- `READABLE_WRITABLE`: Property can be both read and written (READABLE | WRITABLE)

# Functions
- `is_readable(flags)`: Check if property is readable
- `is_writable(flags)`: Check if property is writable
"""
module AccessMode
const AccessModeType = UInt

const NONE::AccessModeType = 0x00
const READABLE::AccessModeType = 0x01
const WRITABLE::AccessModeType = 0x02
const READABLE_WRITABLE::AccessModeType = READABLE | WRITABLE

"""
    is_readable(flags)

Check if the property has readable access based on its access flags.

# Arguments
- `flags::AccessModeType`: The access flags to check

# Returns
- `true` if the property is readable, `false` otherwise
"""
@inline is_readable(flags) = !iszero(flags & READABLE)

"""
    is_writable(flags)

Check if the property has writable access based on its access flags.

# Arguments
- `flags::AccessModeType`: The access flags to check

# Returns
- `true` if the property is writable, `false` otherwise
"""
@inline is_writable(flags) = !iszero(flags & WRITABLE)

end # module

@inline function _default_read_callback(props, name, value::T)::T where {T}
    return value
end

@inline function _default_write_callback(props, name, value::T)::T where {T}
    return value
end

"""
    PropertySpecs{T,R,W}

A struct that holds all the information for a managed property.
This includes the current value, access flags, read/write callbacks and last update timestamp.

The struct is parameterized on the value type `T` and the callback types `R` and `W`,
allowing it to remain concrete even with anonymous functions.

- `T`: The type of the property value
- `R`: The type of the read callback function
- `W`: The type of the write callback function
"""
mutable struct PropertySpecs{T,R<:Function,W<:Function}
    value::Union{Nothing,T}
    const access_flags::AccessMode.AccessModeType
    const read_callback::R
    const write_callback::W
    last_update::Int64
end

function PropertySpecs{T}(
    value::Union{Nothing,T},
    access_flags::AccessMode.AccessModeType,
    read_callback::R,
    write_callback::W,
    last_update::Int64
) where {T,R<:Function,W<:Function}
    PropertySpecs{T,R,W}(value, access_flags, read_callback, write_callback, last_update)
end

# Helper function to process attributes
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
        throw(ErrorException("Unknown property configuration"))
    end
end

# Parse property definition - checks and validates property definitions, including rejecting Union types
# which are incompatible with the internal representation of unset properties (using `nothing`)
function parse_property_def(expr)
    result = Dict{Symbol,Any}()

    # Initialize with defaults
    result[:value] = nothing
    result[:access] = :(AccessMode.READABLE_WRITABLE)
    result[:read_callback] = nothing
    result[:write_callback] = nothing

    # Helper function to check if type expression is a Union
    function is_union_type(type_expr)
        # Check direct Union expressions like Union{Nothing, String}
        if type_expr isa Expr && type_expr.head == :curly && type_expr.args[1] == :Union
            return true
        end
        return false
    end

    # Handle simple type annotation
    if expr.head == :(::)
        result[:name] = expr.args[1]
        result[:type] = expr.args[2]

        # Check if the type is a Union
        if is_union_type(result[:type])
            throw(ErrorException("Union types are not allowed in property definitions as they conflict with the internal representation of unset properties"))
        end

        return result
    end

    # Handle pair syntax
    if expr.head == :call && expr.args[1] == :(=>)
        type_expr = expr.args[2]
        if type_expr.head != :(::)
            throw(ErrorException("Expected name::type on left side of =>"))
        end

        result[:name] = type_expr.args[1]
        result[:type] = type_expr.args[2]

        # Check if the type is a Union
        if is_union_type(result[:type])
            throw(ErrorException("Union types are not allowed in property definitions as they conflict with the internal representation of unset properties"))
        end

        attrs = expr.args[3]

        # Handle single attribute
        if attrs.head == :call && attrs.args[1] == :(=>)
            key = attrs.args[2]
            value = attrs.args[3]
            process_attribute!(result, key, value)
            # Handle multiple attributes
        elseif attrs.head == :tuple
            for attr in attrs.args
                if attr.head == :call && attr.args[1] == :(=>)
                    key = attr.args[2]
                    value = attr.args[3]
                    process_attribute!(result, key, value)
                else
                    throw(ErrorException("Expected key => value pair in attributes"))
                end
            end
        else
            throw(ErrorException("Expected attributes as tuple or pair"))
        end

        return result
    end

    throw(ErrorException("Expected property definition"))
end

"""
    @properties struct_name [default_read_callback=custom_reader] [default_write_callback=custom_writer] begin
        prop1::Type1
        prop2::Type2 => (access => AccessMode.READABLE_WRITABLE)
        prop3::Type3 => (
            value => default_value,
            access => AccessMode.READABLE,
            read_callback => custom_read_fn,
            write_callback => custom_write_fn
        )
    end

Create a struct with managed properties that include access control, custom callbacks, and timestamp tracking.

# Arguments
- `struct_name`: The name of the struct to create
- `default_read_callback`: Optional global read callback to use as default for all properties
- `default_write_callback`: Optional global write callback to use as default for all properties
- `block`: A block containing property definitions

# Property definition formats
- `name::Type`: Simple property with type
- `name::Type => (key => value, ...)`: Property with custom attributes

# Property attributes
- `value`: Default value for the property
- `access`: Access control flags (e.g., `AccessMode.READABLE_WRITABLE`)
- `read_callback`: Custom function called when reading the property: `(obj, name, value) -> transformed_value`
- `write_callback`: Custom function called when writing the property: `(obj, name, value) -> transformed_value`

# Returns
- Creates a new type with the specified properties and generates accessor functions
"""
# Main properties macro
macro properties(struct_name, args...)
    # Check for keyword arguments before the block
    default_read_callback = nothing
    default_write_callback = nothing

    clock_field = gensym(:clock)

    # The last argument should always be the property block
    if length(args) < 1
        error("@properties requires a begin...end block after the struct name")
    end

    # Handle keyword arguments passed directly to the macro
    block = args[end]
    if length(args) > 1
        # Process keyword arguments (default callbacks)
        for i in 1:length(args)-1
            arg = args[i]
            if arg isa Expr && arg.head == :(=)
                key, value = arg.args
                if key == :default_read_callback
                    default_read_callback = value isa Symbol ? :(Main.$value) : value
                elseif key == :default_write_callback
                    default_write_callback = value isa Symbol ? :(Main.$value) : value
                else
                    error("Unknown keyword argument: $key")
                end
            else
                error("Expected keyword arguments before the property block")
            end
        end
    end

    if block.head != :block
        error("@properties requires a begin...end block for property definitions")
    end

    # Extract property definitions
    property_defs = filter(x -> x isa Expr && !(x isa LineNumberNode), block.args)

    # Parse property definitions
    props = []
    for def in property_defs
        push!(props, parse_property_def(def))
    end

    # Extract property information
    prop_names = [p[:name] for p in props]
    prop_types = [p[:type] for p in props]
    prop_values = [p[:value] for p in props]
    prop_access = [p[:access] for p in props]
    prop_read_cbs = Any[p[:read_callback] for p in props]
    prop_write_cbs = Any[p[:write_callback] for p in props]

    # Build type parameter list for all PropertySpecs and clock
    ps_type_syms = [Symbol(:PS, i) for i in 1:length(props)]
    all_type_syms = [ps_type_syms..., :C]
    struct_type_params = Expr(:curly, struct_name, [Expr(:<:, ps, :(ManagedProperties.PropertySpecs{$(prop_types[i])})) for (i, ps) in enumerate(ps_type_syms)]..., Expr(:<:, :C, :(Clocks.AbstractClock)))

    # Build the struct body with parametric PropertySpecs types
    struct_body = Expr(:block)
    for i in 1:length(props)
        push!(struct_body.args, Expr(:(::), prop_names[i], Symbol(:PS, i)))
    end
    push!(struct_body.args, Expr(:(::), clock_field, :C))

    # Build the parametric constructor (infers PropertySpecs types)
    param_constructor = quote
        function $(struct_name)(clock::C=Clocks.EpochClock()) where {C<:Clocks.AbstractClock}
            $([:($(prop_names[i]) = let
                value = $(isnothing(prop_values[i]) ? :(nothing) : prop_values[i])
                access = convert(AccessMode.AccessModeType, $(prop_access[i]))
                read_cb = $(isnothing(prop_read_cbs[i]) ? (isnothing(default_read_callback) ? :(ManagedProperties._default_read_callback) : default_read_callback) : prop_read_cbs[i])
                write_cb = $(isnothing(prop_write_cbs[i]) ? (isnothing(default_write_callback) ? :(ManagedProperties._default_write_callback) : default_write_callback) : prop_write_cbs[i])
                timestamp = $(isnothing(prop_values[i]) ? :(-1) : :(Clocks.time_nanos(clock)))
                ManagedProperties.PropertySpecs{$(prop_types[i])}(value, access, read_cb, write_cb, timestamp)
            end) for i in 1:length(props)]...)
            return new{$([:(typeof($(prop_names[i]))) for i in 1:length(props)]...),C}($(prop_names...), clock)
        end
    end

    # Add the constructor to the struct body
    push!(struct_body.args, param_constructor.args[2])
    struct_def = Expr(:struct, true, struct_type_params, struct_body)

    # Helper for clock field access in generated code
    clock_access = Expr(:call, :getfield, :p, QuoteNode(clock_field))

    # Generate accessor functions
    result = quote
        # Define the struct
        $(struct_def)

        """
            property_names(p)

        Return a tuple of property names (as Symbols) for a managed properties object.

        # Arguments
        - `p`: An object created with `@properties`

        # Returns
        - A tuple of property names (Symbols) representing the user-defined properties

        # Example
        ```julia
        names = property_names(person)  # (:name, :age, :address, ...)
        for name in property_names(person)
            println(name, " = ", get_property(person, name))
        end
        ```
        """
        @inline function property_names(p::$(struct_name))
            # Exclude the last field (which is always the clock field)
            # This returns only the user-defined property names
            propertynames(p)[1:end-1]
        end

        # OPTIMIZATION: Generate property-specific methods for compile-time dispatch
        # These methods eliminate the need for runtime property name validation
        $(Expr(:block, [quote
            @inline function get_property(p::$(struct_name), ::Val{$(QuoteNode(name))})
                specs = getfield(p, $(QuoteNode(name)))
                !AccessMode.is_readable(specs.access_flags) && throw(ErrorException("Property not readable"))
                isnothing(specs.value) && throw(ErrorException("Property not set"))
                specs.read_callback(p, $(QuoteNode(name)), specs.value)
            end
            
            @inline function set_property!(p::$(struct_name), ::Val{$(QuoteNode(name))}, v)
                specs = getfield(p, $(QuoteNode(name)))
                !AccessMode.is_writable(specs.access_flags) && throw(ErrorException("Property not writable"))
                specs.value = specs.write_callback(p, $(QuoteNode(name)), v)
                specs.last_update = Clocks.time_nanos($(clock_access))
                return specs.value
            end
            
            @inline function is_set(p::$(struct_name), ::Val{$(QuoteNode(name))})
                !isnothing(getfield(p, $(QuoteNode(name))).value)
            end
            
            @inline function is_readable(p::$(struct_name), ::Val{$(QuoteNode(name))})
                specs = getfield(p, $(QuoteNode(name)))
                AccessMode.is_readable(specs.access_flags)
            end
            
            @inline function is_writable(p::$(struct_name), ::Val{$(QuoteNode(name))})
                specs = getfield(p, $(QuoteNode(name)))
                AccessMode.is_writable(specs.access_flags)
            end
            
            @inline function last_update(p::$(struct_name), ::Val{$(QuoteNode(name))})
                getfield(p, $(QuoteNode(name))).last_update
            end
            
            @inline function reset_property!(p::$(struct_name), ::Val{$(QuoteNode(name))})
                specs = getfield(p, $(QuoteNode(name)))
                !AccessMode.is_writable(specs.access_flags) && throw(ErrorException("Property not writable"))
                specs.value = nothing
                specs.last_update = -1
                return nothing
            end
        end for name in prop_names]...))

        # Property access functions (allocation-free)
        """
            is_set(p, s::Symbol)

        Check if a property is set (not `nothing`).

        # Arguments
        - `p`: An object created with `@properties`
        - `s::Symbol`: The property name

        # Returns
        - `true` if the property is set, `false` otherwise
        """
        @inline function is_set(p::$(struct_name), s::Symbol)
            # Optimized compile-time dispatch - no tuple allocation
            $(if length(prop_names) == 0
                :(false)
            else
                # Generate optimized if-else chain for property dispatch
                result = :(false)
                for name in reverse(prop_names)
                    result = :(s === $(QuoteNode(name)) ? is_set(p, Val($(QuoteNode(name)))) : $result)
                end
                result
            end)
        end

        """
            all_properties_set(p)

        Check if all properties of an object are set (not `nothing`).

        # Arguments
        - `p`: An object created with `@properties`

        # Returns
        - `true` if all properties are set, `false` otherwise
        """
        @inline function all_properties_set(p::$(struct_name))
            all(!isnothing(getfield(p, n).value) for n in property_names(p))
        end

        """
            get_property(p, s::Symbol)

        Get the value of a property.

        # Arguments
        - `p`: An object created with `@properties`
        - `s::Symbol`: The property name

        # Returns
        - The property value, transformed by the read callback

        # Throws
        - `ErrorException` if the property is not readable, not set, or not found
        """
        @inline function get_property(p::$(struct_name), s::Symbol)
            # Optimized compile-time dispatch - no tuple allocation
            $(if length(prop_names) == 0
                :(throw(ErrorException("Property not found")))
            else
                # Generate optimized if-else chain for property dispatch
                result = :(throw(ErrorException("Property not found")))
                for name in reverse(prop_names)
                    result = :(s === $(QuoteNode(name)) ? get_property(p, Val($(QuoteNode(name)))) : $result)
                end
                result
            end)
        end

        """
            set_property!(p, s::Symbol, v)

        Set the value of a property.

        # Arguments
        - `p`: An object created with `@properties`
        - `s::Symbol`: The property name
        - `v`: The value to set

        # Returns
        - The transformed value that was set (after applying the write callback)

        # Throws
        - `ErrorException` if the property is not writable or not found
        """
        @inline function set_property!(p::$(struct_name), s::Symbol, v)
            # Optimized compile-time dispatch - no tuple allocation
            $(if length(prop_names) == 0
                :(throw(ErrorException("Property not found")))
            else
                # Generate optimized if-else chain for property dispatch
                result = :(throw(ErrorException("Property not found")))
                for name in reverse(prop_names)
                    result = :(s === $(QuoteNode(name)) ? set_property!(p, Val($(QuoteNode(name))), v) : $result)
                end
                result
            end)
        end

        """
            property_type(::Type{T}, s::Symbol) where T

        Get the type of a property from a type.

        # Arguments
        - `T`: The type created with `@properties`
        - `s::Symbol`: The property name

        # Returns
        - The type of the property, or `nothing` if the property is not found
        """
        @inline function property_type(::Type{T}, s::Symbol) where {T<:$(struct_name)}
            s in fieldnames(T)[1:end-1] || return nothing
            FT = fieldtype(T, s)
            get_valtype(::Type{ManagedProperties.PropertySpecs{T,R,W}}) where {T,R,W} = T
            get_valtype(::Type{ManagedProperties.PropertySpecs{T}}) where {T} = T
            get_valtype(FT)
        end

        """
            property_type(p, s::Symbol)

        Get the type of a property from an instance.

        # Arguments
        - `p`: An object created with `@properties`
        - `s::Symbol`: The property name

        # Returns
        - The type of the property, or `nothing` if the property is not found
        """
        @inline property_type(p::$(struct_name), s::Symbol) = property_type(typeof(p), s)

        """
            is_readable(p, s::Symbol)

        Check if a property is readable.

        # Arguments
        - `p`: An object created with `@properties`
        - `s::Symbol`: The property name

        # Returns
        - `true` if the property is readable, `false` otherwise

        # Throws
        - `ErrorException` if the property is not found
        """
        @inline function is_readable(p::$(struct_name), s::Symbol)
            # Optimized compile-time dispatch - no tuple allocation
            $(if length(prop_names) == 0
                :(throw(ErrorException("Property not found")))
            else
                # Generate optimized if-else chain for property dispatch
                result = :(throw(ErrorException("Property not found")))
                for name in reverse(prop_names)
                    result = :(s === $(QuoteNode(name)) ? is_readable(p, Val($(QuoteNode(name)))) : $result)
                end
                result
            end)
        end

        """
            is_writable(p, s::Symbol)

        Check if a property is writable.

        # Arguments
        - `p`: An object created with `@properties`
        - `s::Symbol`: The property name

        # Returns
        - `true` if the property is writable, `false` otherwise

        # Throws
        - `ErrorException` if the property is not found
        """
        @inline function is_writable(p::$(struct_name), s::Symbol)
            # Optimized compile-time dispatch - no tuple allocation
            $(if length(prop_names) == 0
                :(throw(ErrorException("Property not found")))
            else
                # Generate optimized if-else chain for property dispatch
                result = :(throw(ErrorException("Property not found")))
                for name in reverse(prop_names)
                    result = :(s === $(QuoteNode(name)) ? is_writable(p, Val($(QuoteNode(name)))) : $result)
                end
                result
            end)
        end

        """
            last_update(p, s::Symbol)

        Get the timestamp of the last update to a property.

        # Arguments
        - `p`: An object created with `@properties`
        - `s::Symbol`: The property name

        # Returns
        - The timestamp (in nanoseconds) of the last update, or -1 if never updated

        # Throws
        - `ErrorException` if the property is not found
        """
        @inline function last_update(p::$(struct_name), s::Symbol)
            # Optimized compile-time dispatch - no tuple allocation
            $(if length(prop_names) == 0
                :(throw(ErrorException("Property not found")))
            else
                # Generate optimized if-else chain for property dispatch
                result = :(throw(ErrorException("Property not found")))
                for name in reverse(prop_names)
                    result = :(s === $(QuoteNode(name)) ? last_update(p, Val($(QuoteNode(name)))) : $result)
                end
                result
            end)
        end

        """
            with_property(f::Function, p, s::Symbol)

        Apply a function to a property value without modifying it.

        # Arguments
        - `f::Function`: The function to apply to the property value
        - `p`: An object created with `@properties`
        - `s::Symbol`: The property name

        # Returns
        - The result of applying `f` to the property value

        # Throws
        - `ErrorException` if the property is not readable, not set, or not found

        # Example
        ```julia
        area = with_property(person, :dimensions) do dims
            dims.width * dims.height
        end
        ```
        """
        # Non-mutating version for read-only operations
        @inline function with_property(f::Function, p::$(struct_name), s::Symbol)
            s in property_names(p) || throw(ErrorException("Property not found"))
            specs = getfield(p, s)
            isnothing(specs.value) && throw(ErrorException("Property not set"))
            !AccessMode.is_readable(specs.access_flags) && throw(ErrorException("Property not readable"))
            value = specs.read_callback(p, s, specs.value)
            f(value)
        end

        """
            with_property!(f::Function, p, s::Symbol)

        Apply a function to a property value. Note that this function DOES NOT update the property with
        the function result. It returns the result of applying the function to the property value, but
        the property value itself will only be updated if the function modifies it in-place (only possible
        for mutable types).

        # Arguments
        - `f::Function`: The function to apply to the property value
        - `p`: An object created with `@properties`
        - `s::Symbol`: The property name

        # Returns
        - The result of applying `f` to the property value

        # Throws
        - `ErrorException` if the property is not readable, not writable, not set, or not found

        # Notes
        - For **mutable** property types (e.g., arrays, custom mutable structs), you can mutate the value in-place inside the do-block.
        - For **isbits/immutable** property types (e.g., `Int`, `Float64`, `Char`, tuples, or immutable structs), you **cannot** mutate the value in-place. To update an isbits property, return the new value from the do-block and assign it using `set_property!`.

        # Example
        ```julia
        # For mutable types, in-place modification works:
        with_property!(person, :addresses) do addresses
            push!(addresses, "123 Main St")
            addresses  # Return the modified value
        end

        # For immutable types like numbers, you need to set the property with the result:
        result = with_property!(person, :age) do age
            age + 1  # This returns the new value but doesn't change the property
        end
        set_property!(person, :age, result)  # Now update the property with the result
        ```
        """
        # Mutating version for in-place operations (non-isbits types only)
        @inline function with_property!(f::Function, p::$(struct_name), s::Symbol)
            s in property_names(p) || throw(ErrorException("Property not found"))
            specs = getfield(p, s)
            isbits(specs.value) && throw(ErrorException("Property is isbits cannot mutate in-place"))
            isnothing(specs.value) && throw(ErrorException("Property not set"))
            !AccessMode.is_readable(specs.access_flags) && throw(ErrorException("Property not readable"))
            !AccessMode.is_writable(specs.access_flags) && throw(ErrorException("Property not writable"))
            value = specs.read_callback(p, s, specs.value)
            result = f(value)
            specs.write_callback(p, s, value)
            specs.last_update = Clocks.time_nanos($(clock_access))
            return result
        end

        """
            with_properties(f::Function, p, properties::Symbol...)

        Apply a function to multiple property values without modifying them.

        # Arguments
        - `f::Function`: The function to apply to the property values
        - `p`: An object created with `@properties`
        - `properties::Symbol...`: The property names

        # Returns
        - The result of applying `f` to the property values

        # Throws
        - `ErrorException` if any property is not readable, not set, or not found

        # Example
        ```julia
        area = with_properties(person, :width, :height) do width, height
            width * height
        end
        ```
        """
        # Multiple property access - read-only version
        @inline function with_properties(f::Function, p::$(struct_name), properties::Symbol...)
            @inline function val_generator(i)
                s = properties[i]
                s in property_names(p) || throw(ErrorException("Property $s not found"))
                specs = getfield(p, s)
                isnothing(specs.value) && throw(ErrorException("Property $s not set"))
                !AccessMode.is_readable(specs.access_flags) && throw(ErrorException("Property $s not readable"))
                specs.read_callback(p, s, specs.value)
            end
            values = ntuple(val_generator, length(properties))
            f(values...)
        end

        """
            reset_property!(p, s::Symbol)

        Reset a property to an unset state by setting its value to `nothing` and
        its last update timestamp to -1.

        # Arguments
        - `p`: An object created with `@properties`
        - `s::Symbol`: The property name

        # Returns
        - `nothing`

        # Throws
        - `ErrorException` if the property is not writable or not found

        # Example
        ```julia
        reset_property!(person, :address)  # Clears the address property
        ```
        """
        @inline function reset_property!(p::$(struct_name), s::Symbol)
            # Optimized compile-time dispatch - no tuple allocation
            $(if length(prop_names) == 0
                :(throw(ErrorException("Property not found")))
            else
                # Generate optimized if-else chain for property dispatch
                result = :(throw(ErrorException("Property not found")))
                for name in reverse(prop_names)
                    result = :(s === $(QuoteNode(name)) ? reset_property!(p, Val($(QuoteNode(name)))) : $result)
                end
                result
            end)
        end

        # Add pretty printing support
        function Base.show(io::IO, ::MIME"text/plain", p::$(struct_name){C}) where {C}
            println(io, "$($(QuoteNode(struct_name))){$C} with properties:")

            # Get property information
            names = property_names(p)
            types = [property_type(p, name) for name in names]

            # Maximum name length for alignment
            max_name_len = maximum(length(string(name)) for name in names)

            # Print each property
            for i in 1:length(names)
                name = names[i]
                specs = getfield(p, name)

                # Access flags string representation
                access_str = ""
                if AccessMode.is_readable(specs.access_flags)
                    access_str *= "R"
                else
                    access_str *= "-"
                end
                if AccessMode.is_writable(specs.access_flags)
                    access_str *= "W"
                else
                    access_str *= "-"
                end

                # Value representation
                value_str = if isnothing(specs.value)
                    "nothing"
                elseif specs.value isa AbstractArray
                    type_str = string(typeof(specs.value).parameters[1])
                    dims_str = join(size(specs.value), "×")
                    "$(type_str)[$dims_str]"
                else
                    repr(specs.value)
                end

                # Callbacks info
                read_cb = specs.read_callback === ManagedProperties._default_read_callback ? "" : " (custom read)"
                write_cb = specs.write_callback === ManagedProperties._default_write_callback ? "" : " (custom write)"
                cb_str = read_cb * write_cb

                # Last update time
                time_str = if specs.last_update == -1
                    "never"
                else
                    "$(specs.last_update) ns"
                end

                name_padded = rpad(string(name), max_name_len)
                type_str = rpad(string(types[i]), 20)
                value_padded = rpad(value_str, 20)
                println(io, "  $(name_padded) :: $(type_str) = $(value_padded) [$(access_str)]$(cb_str) (last update: $(time_str))")
            end
        end

        # Add a compact version for regular show
        function Base.show(io::IO, p::$(struct_name))
            print(io, "$($(QuoteNode(struct_name)))")
            names = property_names(p)
            set_count = 0
            total = length(names)

            for name in names
                if !isnothing(getfield(p, name).value)
                    set_count += 1
                end
            end

            print(io, " $(set_count)/$(total) properties set")
        end

                """
            obj[key::Symbol]

        Get a property value using indexing syntax. Equivalent to `get_property(obj, key)`.

        # Example
        ```julia
        name = person[:name]  # Same as get_property(person, :name)
        ```
        """
        @inline function Base.getindex(p::$(struct_name), key::Symbol)
            get_property(p, key)
        end

        """
            obj[key1::Symbol, key2::Symbol, ...]

        Get multiple property values using indexing syntax. Returns a tuple of values.

        # Example
        ```julia
        name, age = person[:name, :age]  # Destructure into variables
        values = person[:name, :age, :email]  # Get tuple of values
        ```
        """
        @inline function Base.getindex(p::$(struct_name), keys::Symbol...)
            ntuple(i -> get_property(p, keys[i]), length(keys))
        end

        """
            obj[key::Symbol] = value

        Set a property value using indexing syntax. Equivalent to `set_property!(obj, key, value)`.

        # Example
        ```julia
        person[:name] = "Alice"  # Same as set_property!(person, :name, "Alice")
        ```
        """
        @inline function Base.setindex!(p::$(struct_name), value, key::Symbol)
            set_property!(p, key, value)
        end

        """
            obj[key1::Symbol, key2::Symbol, ...] = values

        Set multiple property values using indexing syntax. Values can be provided as:
        - A tuple: `obj[:name, :age] = ("Alice", 30)`
        - An array/vector: `obj[:name, :age] = ["Alice", 30]`
        - Any iterable collection: `obj[:name, :age] = ("Alice", 30)`

        The number of values must match the number of property keys.

        # Example
        ```julia
        person[:name, :age] = ("Alice", 30)        # Tuple assignment
        person[:name, :age] = ["Alice", 30]        # Array assignment  
        person[:name, :age, :email] = ("Bob", 25, "bob@example.com")  # Multiple properties
        ```
        """
        @inline function Base.setindex!(p::$(struct_name), values, keys::Symbol...)
            length(values) == length(keys) || throw(ArgumentError("Number of values (\$(length(values))) must match number of keys (\$(length(keys)))"))
            for (i, key) in enumerate(keys)
                set_property!(p, key, values[i])
            end
            return values
        end

        """
            keys(obj)

        Return an iterator over the property names of a managed properties object.

        # Example
        ```julia
        for prop_name in keys(person)
            println(prop_name)
        end
        ```
        """
        @inline Base.keys(p::$(struct_name)) = property_names(p)

        """
            values(obj)

        Return an iterator over the property values of a managed properties object.
        Only returns values for properties that are set (not `nothing`).

        # Example
        ```julia
        for prop_value in values(person)
            println(prop_value)
        end
        ```
        """
        @inline function Base.values(p::$(struct_name))
            (get_property(p, k) for k in property_names(p) if is_set(p, k))
        end

        """
            pairs(obj)

        Return an iterator over (name, value) pairs for all set properties.

        # Example
        ```julia
        for (name, value) in pairs(person)
            println("\$name = \$value")
        end
        ```
        """
        @inline function Base.pairs(p::$(struct_name))
            ((k, get_property(p, k)) for k in property_names(p) if is_set(p, k))
        end

        """
            iterate(obj)
            iterate(obj, state)

        Allow iteration over (name, value) pairs of set properties.

        # Example
        ```julia
        for (name, value) in person
            println("\$name = \$value")
        end
        ```
        """
        @inline function Base.iterate(p::$(struct_name))
            set_props = filter(k -> is_set(p, k), property_names(p))
            isempty(set_props) && return nothing
            first_key = first(set_props)
            (first_key, get_property(p, first_key)), (set_props, 2)
        end

        @inline function Base.iterate(p::$(struct_name), state)
            set_props, index = state
            index > length(set_props) && return nothing
            key = set_props[index]
            (key, get_property(p, key)), (set_props, index + 1)
        end

        """
            length(obj)

        Return the number of set properties (not the total number of defined properties).

        # Example
        ```julia
        println("Number of set properties: \$(length(person))")
        ```
        """
        @inline function Base.length(p::$(struct_name))
            count = 0
            $([:(is_set(p, $(QuoteNode(name))) && (count += 1)) for name in prop_names]...)
            count
        end

        """
            haskey(obj, key::Symbol)

        Check if a property name exists (regardless of whether it's set).

        # Example
        ```julia
        if haskey(person, :name)
            println("Person has a name property")
        end
        ```
        """
        @inline Base.haskey(p::$(struct_name), key::Symbol) = key in property_names(p)

        """
            get(obj, key::Symbol, default)

        Get a property value, returning `default` if the property is not set or doesn't exist.

        # Example
        ```julia
        age = get(person, :age, 0)  # Returns 0 if age is not set
        ```
        """
        @inline function Base.get(p::$(struct_name), key::Symbol, default)
            haskey(p, key) && is_set(p, key) ? get_property(p, key) : default
        end

        """
            isreadable(obj, key::Symbol)

        Check if a property is readable (has read access permissions).

        # Example
        ```julia
        if isreadable(person, :name)
            println("Name property can be read")
        end
        ```
        """
        @inline function Base.isreadable(p::$(struct_name), key::Symbol)
            is_readable(p, key)
        end

        """
            iswritable(obj, key::Symbol)

        Check if a property is writable (has write access permissions).

        # Example
        ```julia
        if iswritable(person, :name)
            println("Name property can be modified")
        end
        ```
        """
        @inline function Base.iswritable(p::$(struct_name), key::Symbol)
            is_writable(p, key)
        end        

        # Precompilation directives for general property operations
        Base.precompile(Tuple{typeof(get_property),$(struct_name),Symbol})
        Base.precompile(Tuple{typeof(set_property!),$(struct_name),Symbol,Any})
        Base.precompile(Tuple{typeof(reset_property!),$(struct_name),Symbol})
        Base.precompile(Tuple{typeof(is_set),$(struct_name),Symbol})
        Base.precompile(Tuple{typeof(all_properties_set),$(struct_name)})
        Base.precompile(Tuple{typeof(is_readable),$(struct_name),Symbol})
        Base.precompile(Tuple{typeof(is_writable),$(struct_name),Symbol})
        Base.precompile(Tuple{typeof(last_update),$(struct_name),Symbol})
        Base.precompile(Tuple{typeof(property_type),$(struct_name),Symbol})

        # Precompilation for Base interface methods
        Base.precompile(Tuple{typeof(Base.getindex),$(struct_name),Symbol})
        Base.precompile(Tuple{typeof(Base.setindex!),$(struct_name),Any,Symbol})
        Base.precompile(Tuple{typeof(Base.setindex!),$(struct_name),Any,Vararg{Symbol}})
        Base.precompile(Tuple{typeof(Base.keys),$(struct_name)})
        Base.precompile(Tuple{typeof(Base.values),$(struct_name)})
        Base.precompile(Tuple{typeof(Base.pairs),$(struct_name)})
        Base.precompile(Tuple{typeof(Base.iterate),$(struct_name)})
        Base.precompile(Tuple{typeof(Base.length),$(struct_name)})
        Base.precompile(Tuple{typeof(Base.haskey),$(struct_name),Symbol})
        Base.precompile(Tuple{typeof(Base.get),$(struct_name),Symbol,Any})
        Base.precompile(Tuple{typeof(Base.isreadable),$(struct_name),Symbol})
        Base.precompile(Tuple{typeof(Base.iswritable),$(struct_name),Symbol})

        # Precompile with_property variants
        Base.precompile(Tuple{typeof(with_property),Function,$(struct_name),Symbol})
        Base.precompile(Tuple{typeof(with_property!),Function,$(struct_name),Symbol})

        # Property-specific precompilation
        $([:(
            # Type-specific property operations
            Base.precompile(Tuple{typeof(get_property),$(struct_name),typeof($(QuoteNode(name)))});
            Base.precompile(Tuple{typeof(set_property!),$(struct_name),typeof($(QuoteNode(name))),$(prop_types[i])});
            Base.precompile(Tuple{typeof(reset_property!),$(struct_name),typeof($(QuoteNode(name)))});
            Base.precompile(Tuple{typeof(is_set),$(struct_name),typeof($(QuoteNode(name)))});
            Base.precompile(Tuple{typeof(is_readable),$(struct_name),typeof($(QuoteNode(name)))});
            Base.precompile(Tuple{typeof(is_writable),$(struct_name),typeof($(QuoteNode(name)))})
        ) for (i, name) in enumerate(prop_names)]...)
    end
    return esc(result)
end

end # module