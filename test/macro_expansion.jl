# Tests for field generator macro expansion within @kvstore

using Test
using StaticKV

# Set up test environment variables
ENV["SUB_DATA_URI_1"] = "aeron:udp?endpoint=0.0.0.0:40123"
ENV["SUB_DATA_STREAM_1"] = "4"
ENV["SUB_DATA_URI_2"] = "aeron:udp?endpoint=0.0.0.0:40124" 
ENV["SUB_DATA_STREAM_2"] = "8"

# Field generator macros that can be used within @kvstore blocks
macro generate_data_uri_fields()
    fields = []
    
    # Scan environment variables at macro expansion time
    for (key, value) in ENV
        if startswith(key, "SUB_DATA_URI_")
            idx = parse(Int, replace(key, "SUB_DATA_URI_" => ""))
            uri_field = Symbol("DataURI$(idx)")
            stream_field = Symbol("DataStreamID$(idx)")

            # Create clean expressions directly
            uri_expr = :($(uri_field)::String => ($(value)))
            push!(fields, uri_expr)

            # Add corresponding stream ID field if it exists
            stream_key = "SUB_DATA_STREAM_$(idx)"
            if haskey(ENV, stream_key)
                stream_value = parse(Int, ENV[stream_key])
                stream_expr = :($(stream_field)::Int64 => ($(stream_value)))
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
        :($(Symbol("$(prefix_sym)version"))::UInt32 => (0x00000001))
    ]
    
    return Expr(:block, fields...)
end

macro generate_counter_fields(types...)
    fields = []
    
    for type_name in types
        counter_field = Symbol("$(type_name)_count")
        rate_field = Symbol("$(type_name)_rate")
        
        push!(fields, :($(counter_field)::UInt64 => (0x0000000000000000)))
        push!(fields, :($(rate_field)::Float64 => (0.0)))
    end
    
    return Expr(:block, fields...)
end

# Define a macro that generates fields with different access modes and callbacks
macro generate_secured_fields()
    # Build expressions manually using a completely explicit form without any quotes
    # to avoid Julia's expression transformations
    
    # Create the block expression that will contain all field definitions
    block = Expr(:block)
    
    # Create username field with default value and access mode
    # Create a call to => operator
    username_expr = Expr(:call, :(=>), 
        :(username::String), 
        # Create a call expression for the tuple with semicolon
        Expr(:tuple, 
            # Default value
            "default_user",
            # Semicolon 
            Expr(:parameters, 
                # Access keyword argument
                Expr(:kw, :access, :(AccessMode.READABLE))
            )
        )
    )
    push!(block.args, username_expr)
    
    # Create password field with only access mode and callback
    password_expr = Expr(:call, :(=>),
        :(password::String),
        # Empty value with keywords
        Expr(:tuple,
            Expr(:parameters,
                Expr(:kw, :access, :(AccessMode.READABLE_ASSIGNABLE_MUTABLE)),
                Expr(:kw, :on_get, :(function(obj, prop, val) "********" end))
            )
        )
    )
    push!(block.args, password_expr)
    
    # Create email field with access mode and callback
    email_expr = Expr(:call, :(=>),
        :(email::String),
        # Empty value with keywords
        Expr(:tuple,
            Expr(:parameters,
                Expr(:kw, :access, :(AccessMode.READABLE_ASSIGNABLE_MUTABLE)),
                Expr(:kw, :on_set, :(function(obj, prop, val) lowercase(val) end))
            )
        )
    )
    push!(block.args, email_expr)
    
    return block
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
@kvstore ConfigStruct begin
    name::String => ("config1")
    @generate_data_uri_fields
    @generate_timestamp_fields
    @generate_counter_fields message packet event
end

@kvstore ComplexStruct begin
    id::String => ("complex-1")
    
    # Use the combined fields macro
    @generate_combined_fields
    
    # Add one more directly
    extra::Bool => (true)
end

@kvstore SecuredUser begin
    id::String => ("user-1")
    @generate_secured_fields
end

function test_macro_expansion()
    # Test macro expansion
    @testset "Basic Macro Expansion" begin
        # Create a test instance
        config = ConfigStruct()
        
        # Test that all expected keys are present
        @test :name in keynames(config)
        @test :DataURI1 in keynames(config)
        @test :DataStreamID1 in keynames(config)
        @test :created_at in keynames(config)
        @test :updated_at in keynames(config)
        @test :version in keynames(config)
        @test :message_count in keynames(config)
        @test :message_rate in keynames(config)

        # Test key values (ensure the URI matches what's in the ENV)
        @test getindex(config, :DataURI1) == ENV["SUB_DATA_URI_1"]
        @test getindex(config, :DataStreamID1) == 4
        @test getindex(config, :message_count) == 0
        @test getindex(config, :version) == 0x00000001
    end
    
    # Test nested macro usage
    @testset "Nested Macro Composition" begin
        complex = ComplexStruct()
        
        # Test key generation
        @test length(keynames(complex)) > 10
        @test :audit_created_at in keynames(complex)
        @test :audit_updated_at in keynames(complex)
        @test :request_count in keynames(complex)
        @test :response_rate in keynames(complex)
        @test :error_count in keynames(complex)
        @test :extra in keynames(complex)
    end

    # Test advanced features like access control
    @testset "Access Control and Callbacks" begin
        user = SecuredUser()

        # Test read-only key
        @test_throws Exception setindex!(user, :username, "admin")
        
        # Test writable keys
        setindex!(user, :password, "secret123")
        setindex!(user, :email, "ADMIN@EXAMPLE.COM")
        
        # Test value transformation via callbacks
        @test getindex(user, :email) == "admin@example.com"
        @test getindex(user, :password) == "********"
    end
end
