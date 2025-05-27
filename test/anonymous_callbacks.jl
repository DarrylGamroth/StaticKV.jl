# Define test types with anonymous functions in property definitions
@properties TestAnonymousCallbacks begin
    # Anonymous function for read callback
    name::String => (
        value => "default",
        read_callback => (obj, name, val) -> uppercase(val)
    )
    
    # Anonymous function for write callback
    email::String => (
        write_callback => (obj, name, val) -> lowercase(val)
    )
    
    # Both read and write callbacks as anonymous functions
    score::Int => (
        value => 10,
        read_callback => (obj, name, val) -> val * 2,
        write_callback => (obj, name, val) -> max(0, val)  # Ensure non-negative
    )
    
    # Using anonymous functions with more complex logic
    status::Symbol => (
        value => :active,
        write_callback => (obj, name, val) -> begin
            # Multi-line anonymous function with conditionals
            if val == :pending || val == :active || val == :inactive
                return val
            else
                return :invalid
            end
        end,
        read_callback => (obj, name, val) -> begin
            # Multi-line anonymous function for formatting
            if val == :active
                return :ACTIVE
            elseif val == :pending
                return :PENDING
            else
                return val
            end
        end
    )
end

# Container for testing mutable properties with anonymous functions
@properties MutableContainer begin
    items::Vector{String} => (value => String[])
end

# Export the test function so it can be called from runtests.jl
function test_anonymous_callbacks()
    # Test focusing only on anonymous/inline callbacks in property definitions
    @testset "Anonymous functions in property definitions" begin
        t = TestAnonymousCallbacks()
        
        # Test read callback with anonymous function
        @test get_property(t, :name) == "DEFAULT"  # Should be uppercase
        set_property!(t, :name, "test")
        @test get_property(t, :name) == "TEST"  # Should be uppercase
        
        # Test write callback with anonymous function
        set_property!(t, :email, "USER@EXAMPLE.COM")
        @test get_property(t, :email) == "user@example.com"  # Should be lowercase
        
        # Test both read and write callbacks
        @test get_property(t, :score) == 20  # Default 10 * 2 from read callback
        set_property!(t, :score, -5)
        @test get_property(t, :score) == 0  # max(0, -5) = 0, then * 2 = 0
        set_property!(t, :score, 7)
        @test get_property(t, :score) == 14  # 7, then * 2 = 14
        
        # Test more complex anonymous function logic
        @test get_property(t, :status) == :ACTIVE  # Default :active transformed to :ACTIVE
        set_property!(t, :status, :pending)
        @test get_property(t, :status) == :PENDING
        set_property!(t, :status, :inactive)
        @test get_property(t, :status) == :inactive  # No special transformation
        set_property!(t, :status, :unknown)
        @test get_property(t, :status) == :invalid  # Converted by write callback
        
        # Test comparing anonymous callbacks vs. named callbacks
        tnamed = TestCallback()
        
        # Set identical values to compare behavior
        set_property!(tnamed, :uppercase, "hello")
        set_property!(t, :name, "hello")
        
        # Both should have the same result despite different implementation
        @test get_property(tnamed, :uppercase) == "HELLO"
        @test get_property(t, :name) == "HELLO"
        
        # Test with more complex scenario
        set_property!(tnamed, :transformed, 5)  # Will be multiplied by 2 on write, divided by 2 on read
        set_property!(t, :score, 5)  # Will be unchanged on write (>0), multiplied by 2 on read
        
        # Both should have similar behavior for positive values but through different mechanisms
        @test get_property(tnamed, :transformed) == 5
        @test get_property(t, :score) == 10
    end
end
