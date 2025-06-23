# Tests for field generator macro expansion within @properties

using Test
using ManagedProperties

# Set up test environment variables
ENV["SUB_DATA_URI_1"] = "aeron:udp?endpoint=0.0.0.0:40123"
ENV["SUB_DATA_STREAM_1"] = "4"
ENV["SUB_DATA_URI_2"] = "aeron:udp?endpoint=0.0.0.0:40124" 
ENV["SUB_DATA_STREAM_2"] = "8"

# Field generator macros that can be used within @properties blocks
macro generate_data_uri_fields()
    fields = []
    
    # Scan environment variables at macro expansion time
    for (key, value) in ENV
        if startswith(key, "SUB_DATA_URI_")
            idx = parse(Int, replace(key, "SUB_DATA_URI_" => ""))
            uri_field = Symbol("DataURI$(idx)")
            stream_field = Symbol("DataStreamID$(idx)")

            # Create clean expressions directly
            uri_expr = :($(uri_field)::String => (value => $(value)))
            push!(fields, uri_expr)

            # Add corresponding stream ID field if it exists
            stream_key = "SUB_DATA_STREAM_$(idx)"
            if haskey(ENV, stream_key)
                stream_value = parse(Int, ENV[stream_key])
                stream_expr = :($(stream_field)::Int64 => (value => $(stream_value)))
                push!(fields, stream_expr)
            end
        end
    end
    
    return Expr(:block, fields...)
end

macro generate_timestamp_fields(prefix="")
    prefix_str = string(prefix)
    prefix_sym = prefix_str == "" ? "" : "$(prefix_str)_"
    
    fields = [
        :($(Symbol("$(prefix_sym)created_at"))::Int64),
        :($(Symbol("$(prefix_sym)updated_at"))::Int64),
        :($(Symbol("$(prefix_sym)version"))::UInt32 => (value => 0x00000001))
    ]
    
    return Expr(:block, fields...)
end

macro generate_counter_fields(types...)
    fields = []
    
    for type_name in types
        counter_field = Symbol("$(type_name)_count")
        rate_field = Symbol("$(type_name)_rate")
        
        push!(fields, :($(counter_field)::UInt64 => (value => 0x0000000000000000)))
        push!(fields, :($(rate_field)::Float64 => (value => 0.0)))
    end
    
    return Expr(:block, fields...)
end

# Define a macro that generates fields with different access modes and callbacks
macro generate_secured_fields()
    quote
        username::String => (
            value => "default_user",
            access => AccessMode.READABLE
        )
        
        password::String => (
            access => AccessMode.READABLE_WRITABLE,
            read_callback => (obj, prop, val) -> "********"
        )
        
        email::String => (
            access => AccessMode.READABLE_WRITABLE,
            write_callback => (obj, prop, val) -> lowercase(val)
        )
    end
end

# Define a macro that composes several field generator macros
macro generate_combined_fields()
    # Instead of using quote directly, expand the macros at definition time
    # and return their combined results
    
    # Expand each macro separately to get their block expressions
    data_uri_fields = macroexpand(@__MODULE__, :(@generate_data_uri_fields))
    timestamp_fields = macroexpand(@__MODULE__, :(@generate_timestamp_fields audit))
    counter_fields = macroexpand(@__MODULE__, :(@generate_counter_fields request response error))
    
    # Combine all the expanded fields into a single block
    combined_fields = Expr(:block)
    
    # Extract contents from each block and append to combined_fields
    for expr in [data_uri_fields, timestamp_fields, counter_fields]
        if expr.head == :block
            for field in expr.args
                if !(field isa LineNumberNode)
                    push!(combined_fields.args, field)
                end
            end
        end
    end
    
    return combined_fields
end

# Define structs at module level
@properties ConfigStruct begin
    name::String => (value => "config1")
    @generate_data_uri_fields
    @generate_timestamp_fields
    @generate_counter_fields message packet event
end

@properties ComplexStruct begin
    id::String => (value => "complex-1")
    
    # Use the combined fields macro
    @generate_combined_fields
    
    # Add one more directly
    extra::Bool => (value => true)
end

@properties SecuredUser begin
    id::String => (value => "user-1")
    @generate_secured_fields
end

function test_macro_expansion()
    # Test macro expansion
    @testset "Basic Macro Expansion" begin
        # Create a test instance
        config = ConfigStruct()
        
        # Test that all expected properties are present
        @test :name in property_names(config)
        @test :DataURI1 in property_names(config)
        @test :DataStreamID1 in property_names(config)
        @test :created_at in property_names(config)
        @test :updated_at in property_names(config)
        @test :version in property_names(config)
        @test :message_count in property_names(config)
        @test :message_rate in property_names(config)

        # Test property values (ensure the URI matches what's in the ENV)
        @test get_property(config, :DataURI1) == ENV["SUB_DATA_URI_1"]
        @test get_property(config, :DataStreamID1) == 4
        @test get_property(config, :message_count) == 0
        @test get_property(config, :version) == 0x00000001
    end
    
    # Test nested macro usage
    @testset "Nested Macro Composition" begin
        complex = ComplexStruct()
        
        # Test property generation
        @test length(property_names(complex)) > 10
        @test :audit_created_at in property_names(complex)
        @test :audit_updated_at in property_names(complex)
        @test :request_count in property_names(complex)
        @test :response_rate in property_names(complex)
        @test :error_count in property_names(complex)
        @test :extra in property_names(complex)
    end

    # Test advanced features like access control
    @testset "Access Control and Callbacks" begin
        user = SecuredUser()

        # Test read-only property
        @test_throws Exception set_property!(user, :username, "admin")
        
        # Test writable properties
        set_property!(user, :password, "secret123")
        set_property!(user, :email, "ADMIN@EXAMPLE.COM")
        
        # Test value transformation via callbacks
        @test get_property(user, :email) == "admin@example.com"
        @test get_property(user, :password) == "********"
    end
end
