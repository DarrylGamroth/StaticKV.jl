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

# Mutable struct with concrete type parameters
mutable struct PropertySpecs{T,RCB<:Function,WCB<:Function}
    value::Union{Nothing,T}
    access_flags::AccessMode.AccessModeType
    read_callback::RCB
    write_callback::WCB
    last_update::Int64
end

function PropertySpecs{T}(
    value::Union{Nothing,T},
    access_flags::AccessMode.AccessModeType,
    read_callback::Function,
    write_callback::Function,
    last_update::Int64
) where {T}
    return PropertySpecs{T,typeof(read_callback),typeof(write_callback)}(
        value,
        access_flags,
        read_callback,
        write_callback,
        last_update
    )
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

# Parse property definition
function parse_property_def(expr)
    result = Dict{Symbol,Any}()

    # Initialize with defaults
    result[:value] = nothing
    result[:access] = :(AccessMode.READABLE_WRITABLE)
    result[:read_callback] = :(ManagedProperties._default_read_callback)
    result[:write_callback] = :(ManagedProperties._default_write_callback)

    # Handle simple type annotation
    if expr.head == :(::)
        result[:name] = expr.args[1]
        result[:type] = expr.args[2]
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
    @properties struct_name begin
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
macro properties(struct_name, block)
    if block.head != :block
        error("@properties requires a begin...end block after the struct name")
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
    prop_read_cbs = [p[:read_callback] for p in props]
    prop_write_cbs = [p[:write_callback] for p in props]

    # Add these lines after extracting property information
    prop_read_cb_types = []
    prop_write_cb_types = []

    # Create struct body
    struct_body = Expr(:block)

    # Add property fields
    for i in 1:length(props)
        # Determine the exact read callback type
        read_cb_type = :(typeof($(prop_read_cbs[i])))
        push!(prop_read_cb_types, read_cb_type)  # Store for later use

        # Determine the exact write callback type
        write_cb_type = :(typeof($(prop_write_cbs[i])))
        push!(prop_write_cb_types, write_cb_type)  # Store for later use

        # Use the specific callback types in the field definition
        push!(struct_body.args, Expr(:(::), prop_names[i],
            :(ManagedProperties.PropertySpecs{$(prop_types[i]),$read_cb_type,$write_cb_type})))
    end

    # Add clock field
    push!(struct_body.args, :(clock::C))

    # Create the parameterized constructor
    param_constructor = quote
        function $(struct_name)(clock::C=Clocks.EpochClock();
            default_read_callback=ManagedProperties._default_read_callback,
            default_write_callback=ManagedProperties._default_write_callback) where {C<:AbstractClock}

            # Create PropertySpecs instances with stored type information
            $([:($(prop_names[i]) = ManagedProperties.PropertySpecs{$(prop_types[i])}(
                $(prop_values[i] === nothing ? :(nothing) : prop_values[i]),
                convert(AccessMode.AccessModeType, $(prop_access[i])),
                $(prop_read_cbs[i] === :default_read_callback ?
                  :(default_read_callback) : prop_read_cbs[i]),
                $(prop_write_cbs[i] === :default_write_callback ?
                  :(default_write_callback) : prop_write_cbs[i]),
                $(prop_values[i] === nothing ? :(-1) : :(Clocks.time_nanos(clock)))
            )) for i in 1:length(props)]...)

            # Use new function to create the instance
            return new{C}($(prop_names...), clock)
        end
    end

    # Add both constructors to the struct body
    push!(struct_body.args, param_constructor.args[2])  # Add the parameterized constructor

    # Create the complete struct definition
    struct_def = Expr(:struct, true, Expr(:curly, struct_name, Expr(:<:, :C, :AbstractClock)), struct_body)

    # Generate property information
    prop_info = :(const $(Symbol("$(struct_name)_PROPS")) = (
        names=$(Expr(:tuple, [QuoteNode(name) for name in prop_names]...)),
        types=$(Expr(:tuple, [type for type in prop_types]...))
    ))

    # Generate accessor functions
    result = quote
        # Define the struct
        $(struct_def)

        # Store property metadata
        $(prop_info)

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
            # Manual lookup with index-based iteration
            names = $(Symbol("$(struct_name)_PROPS")).names
            if s in names
                return !isnothing(getfield(p, s).value)
            end
            return false
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
            names = $(Symbol("$(struct_name)_PROPS")).names
            for name in names
                if isnothing(getfield(p, name).value)
                    return false
                end
            end
            return true
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
            names = $(Symbol("$(struct_name)_PROPS")).names
            if s in names
                prop_meta = getfield(p, s)

                if !AccessMode.is_readable(prop_meta.access_flags)
                    throw(ErrorException("Property not readable"))
                end

                if isnothing(prop_meta.value)
                    throw(ErrorException("Property not set"))
                end

                return prop_meta.read_callback(p, s, prop_meta.value)
            end
            throw(ErrorException("Property not found"))
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
            # Manual lookup with index-based iteration
            names = $(Symbol("$(struct_name)_PROPS")).names
            if s in names
                # Get property metadata
                prop_meta = getfield(p, s)

                if !AccessMode.is_writable(prop_meta.access_flags)
                    throw(ErrorException("Property not writable"))
                end

                val = prop_meta.write_callback(p, s, v)

                # Update the existing metadata with the transformed value
                prop_meta.value = val
                prop_meta.last_update = Clocks.time_nanos(p.clock)

                return val
            end
            throw(ErrorException("Property not found"))
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
        @inline function property_type(::Type{$(struct_name)}, s::Symbol)
            # Manual lookup with index-based iteration
            names = $(Symbol("$(struct_name)_PROPS")).names
            types = $(Symbol("$(struct_name)_PROPS")).types
            for i in 1:length(names)
                if names[i] === s
                    return types[i]
                end
            end
            return nothing
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
        @inline function property_type(p::$(struct_name), s::Symbol)
            return property_type($(struct_name), s)
        end

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
            # Manual lookup with index-based iteration
            names = $(Symbol("$(struct_name)_PROPS")).names
            if s in names
                prop_meta = getfield(p, s)
                return AccessMode.is_readable(prop_meta.access_flags)
            end
            throw(ErrorException("Property not found"))
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
            # Manual lookup with index-based iteration
            names = $(Symbol("$(struct_name)_PROPS")).names
            if s in names
                prop_meta = getfield(p, s)
                return AccessMode.is_writable(prop_meta.access_flags)
            end
            throw(ErrorException("Property not found"))
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
            # Manual lookup with index-based iteration
            names = $(Symbol("$(struct_name)_PROPS")).names
            if s in names
                return getfield(p, s).last_update
            end
            throw(ErrorException("Property not found"))
        end

        # Add pretty printing support
        function Base.show(io::IO, ::MIME"text/plain", p::$(struct_name){C}) where {C}
            println(io, "$($(QuoteNode(struct_name))){$C} with properties:")

            # Get property information
            names = $(Symbol("$(struct_name)_PROPS")).names
            types = $(Symbol("$(struct_name)_PROPS")).types

            # Maximum name length for alignment
            max_name_len = maximum(length(string(name)) for name in names)

            # Print each property
            for i in 1:length(names)
                name = names[i]
                prop_meta = getfield(p, name)

                # Access flags string representation
                access_str = ""
                if AccessMode.is_readable(prop_meta.access_flags)
                    access_str *= "R"
                else
                    access_str *= "-"
                end
                if AccessMode.is_writable(prop_meta.access_flags)
                    access_str *= "W"
                else
                    access_str *= "-"
                end

                # Value representation
                value_str = if isnothing(prop_meta.value)
                    "nothing"
                elseif prop_meta.value isa AbstractArray
                    type_str = string(typeof(prop_meta.value).parameters[1])
                    dims_str = join(size(prop_meta.value), "×")
                    "$(type_str)[$dims_str]"
                else
                    repr(prop_meta.value)
                end

                # Callbacks info
                read_cb = prop_meta.read_callback === ManagedProperties._default_read_callback ? "" : " (custom read)"
                write_cb = prop_meta.write_callback === ManagedProperties._default_write_callback ? "" : " (custom write)"
                cb_str = read_cb * write_cb

                # Last update time
                time_str = if prop_meta.last_update == -1
                    "never"
                else
                    "$(prop_meta.last_update) ns"
                end

                name_padded = lpad(string(name), max_name_len)
                type_str = rpad(string(types[i]), 20)
                value_padded = rpad(value_str, 15)
                println(io, "  $(name_padded) :: $(type_str) = $(value_padded) [$(access_str)]$(cb_str) (last update: $(time_str))")
            end
        end

        # Add a compact version for regular show
        function Base.show(io::IO, p::$(struct_name){C}) where {C}
            print(io, "$($(QuoteNode(struct_name))){$C}(")
            names = $(Symbol("$(struct_name)_PROPS")).names
            set_count = 0
            total = length(names)

            for name in names
                if !isnothing(getfield(p, name).value)
                    set_count += 1
                end
            end

            print(io, "$(set_count)/$(total) properties set)")
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
            # Manual lookup with index-based iteration
            names = $(Symbol("$(struct_name)_PROPS")).names
            if s in names
                prop_meta = getfield(p, s)

                if isnothing(prop_meta.value)
                    throw(ErrorException("Property not set"))
                end

                # Check if property is readable
                if !AccessMode.is_readable(prop_meta.access_flags)
                    throw(ErrorException("Property not readable"))
                end

                # Get value through read callback first
                value = prop_meta.read_callback(p, s, prop_meta.value)

                # Apply the function to the value
                return f(value)
            end
            throw(ErrorException("Property not found"))
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
            # Manual lookup with index-based iteration
            names = $(Symbol("$(struct_name)_PROPS")).names
            if s in names
                prop_meta = getfield(p, s)

                if isnothing(prop_meta.value)
                    throw(ErrorException("Property not set"))
                end

                # Check if property is both readable and writable
                if !AccessMode.is_readable(prop_meta.access_flags)
                    throw(ErrorException("Property not readable"))
                end

                if !AccessMode.is_writable(prop_meta.access_flags)
                    throw(ErrorException("Property not writable"))
                end

                # Get value through read callback
                value = prop_meta.read_callback(p, s, prop_meta.value)

                # Apply the function to the value
                result = f(value)

                # Always write back the value through the write callback
                prop_meta.value = prop_meta.write_callback(p, s, value)

                # Update the timestamp
                prop_meta.last_update = Clocks.time_nanos(p.clock)

                return result
            end
            throw(ErrorException("Property not found"))
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
            # Get all property values
            values = ntuple(length(properties)) do i
                s = properties[i]
                names = $(Symbol("$(struct_name)_PROPS")).names

                if s in names
                    prop_meta = getfield(p, s)

                    if isnothing(prop_meta.value)
                        throw(ErrorException("Property $s not set"))
                    end

                    if !AccessMode.is_readable(prop_meta.access_flags)
                        throw(ErrorException("Property $s not readable"))
                    end

                    prop_meta.read_callback(p, s, prop_meta.value)
                else
                    throw(ErrorException("Property $s not found"))
                end
            end

            # Call the function with all values
            return f(values...)
        end

        """
            with_properties!(f::Function, p, properties::Symbol...)

        Apply a function to multiple property values and update the properties with modified values.

        # Arguments
        - `f::Function`: The function to apply to the property values
        - `p`: An object created with `@properties`
        - `properties::Symbol...`: The property names

        # Returns
        - The result of applying `f` to the property values

        # Throws
        - `ErrorException` if any property is not readable, not writable, not set, or not found

        # Example
        ```julia
        with_properties!(person, :x, :y) do x, y
            x += 10
            y += 5
            return nothing
        end
        ```
        """
        # Multiple property access - mutating version
        @inline function with_properties!(f::Function, p::$(struct_name), properties::Symbol...)
            # Get all property values
            values = ntuple(length(properties)) do i
                s = properties[i]
                names = $(Symbol("$(struct_name)_PROPS")).names

                if s in names
                    prop_meta = getfield(p, s)

                    if isnothing(prop_meta.value)
                        throw(ErrorException("Property $s not set"))
                    end

                    if !AccessMode.is_readable(prop_meta.access_flags)
                        throw(ErrorException("Property $s not readable"))
                    end

                    if !AccessMode.is_writable(prop_meta.access_flags)
                        throw(ErrorException("Property $s not writable"))
                    end

                    prop_meta.read_callback(p, s, prop_meta.value)
                else
                    throw(ErrorException("Property $s not found"))
                end
            end

            # Call the function with all values (in-place modifications happen here)
            result = f(values...)

            # Update timestamps for all properties
            for s in properties
                prop_meta = getfield(p, s)
                prop_meta.last_update = Clocks.time_nanos(p.clock)
            end

            return result
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
            # Manual lookup with index-based iteration
            names = $(Symbol("$(struct_name)_PROPS")).names
            if s in names
                # Get property metadata
                prop_meta = getfield(p, s)

                if !AccessMode.is_writable(prop_meta.access_flags)
                    throw(ErrorException("Property not writable"))
                end

                # Reset value to nothing and last_update to -1
                prop_meta.value = nothing
                prop_meta.last_update = -1

                return nothing
            end
            throw(ErrorException("Property not found"))
        end

        # Precompilation directives for general property operations
        Base.precompile(Tuple{typeof(get_property), $(struct_name), Symbol})
        Base.precompile(Tuple{typeof(set_property!), $(struct_name), Symbol, Any})
        Base.precompile(Tuple{typeof(reset_property!), $(struct_name), Symbol})
        Base.precompile(Tuple{typeof(is_set), $(struct_name), Symbol})
        Base.precompile(Tuple{typeof(all_properties_set), $(struct_name)})
        Base.precompile(Tuple{typeof(is_readable), $(struct_name), Symbol})
        Base.precompile(Tuple{typeof(is_writable), $(struct_name), Symbol})
        Base.precompile(Tuple{typeof(last_update), $(struct_name), Symbol})
        Base.precompile(Tuple{typeof(property_type), $(struct_name), Symbol})

        # Precompile with_property variants
        Base.precompile(Tuple{typeof(with_property), Function, $(struct_name), Symbol})
        Base.precompile(Tuple{typeof(with_property!), Function, $(struct_name), Symbol})

        # Property-specific precompilation
        $([:( 
            # Type-specific property operations
            Base.precompile(Tuple{typeof(get_property), $(struct_name), typeof($(QuoteNode(name)))});
            Base.precompile(Tuple{typeof(set_property!), $(struct_name), typeof($(QuoteNode(name))), $(prop_types[i])});
            Base.precompile(Tuple{typeof(reset_property!), $(struct_name), typeof($(QuoteNode(name)))});
            Base.precompile(Tuple{typeof(is_set), $(struct_name), typeof($(QuoteNode(name)))});
            Base.precompile(Tuple{typeof(is_readable), $(struct_name), typeof($(QuoteNode(name)))});
            Base.precompile(Tuple{typeof(is_writable), $(struct_name), typeof($(QuoteNode(name)))});
        ) for (i, name) in enumerate(prop_names)]...)
    end

    return esc(result)
end

# Export public API
export @properties, AccessMode
export get_property, set_property!, reset_property!, property_type, is_set, all_properties_set
export with_property, with_property!
export with_properties, with_properties!
export is_readable, is_writable, last_update

end # module