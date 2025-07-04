# Define test types with anonymous functions in key definitions
@kvstore TestAnonymousCallbacks begin
    # Anonymous function for get callback
    name::String => (
        value => "default",
        on_get => (obj, key, val) -> uppercase(val)
    )
    
    # Anonymous function for set callback
    email::String => (
        on_set => (obj, key, val) -> lowercase(val)
    )
    
    # Both read and set callbacks as anonymous functions
    score::Int => (
        value => 10,
        on_get => (obj, key, val) -> val * 2,
        on_set => (obj, key, val) -> max(0, val)  # Ensure non-negative
    )
    
    # Using anonymous functions with more complex logic
    status::Symbol => (
        value => :active,
        on_set => (obj, key, val) -> begin
            # Multi-line anonymous function with conditionals
            if val == :pending || val == :active || val == :inactive
                return val
            else
                return :invalid
            end
        end,
        on_get => (obj, key, val) -> begin
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
@kvstore MutableContainer begin
    items::Vector{String} => (value => String[])
end

# Export the test function so it can be called from runtests.jl
function test_anonymous_callbacks()
    # Test focusing only on anonymous/inline callbacks in key definitions
    @testset "Anonymous functions in key definitions" begin
        t = TestAnonymousCallbacks()
        
        # Test get callback with anonymous function
        @test getkey(t, :name) == "DEFAULT"  # Should be uppercase
        setkey!(t, :name, "test")
        @test getkey(t, :name) == "TEST"  # Should be uppercase
        
        # Test set callback with anonymous function
        setkey!(t, :email, "USER@EXAMPLE.COM")
        @test getkey(t, :email) == "user@example.com"  # Should be lowercase
        
        # Test both read and set callbacks
        @test getkey(t, :score) == 20  # Default 10 * 2 from get callback
        setkey!(t, :score, -5)
        @test getkey(t, :score) == 0  # max(0, -5) = 0, then * 2 = 0
        setkey!(t, :score, 7)
        @test getkey(t, :score) == 14  # 7, then * 2 = 14
        
        # Test more complex anonymous function logic
        @test getkey(t, :status) == :ACTIVE  # Default :active transformed to :ACTIVE
        setkey!(t, :status, :pending)
        @test getkey(t, :status) == :PENDING
        setkey!(t, :status, :inactive)
        @test getkey(t, :status) == :inactive  # No special transformation
        setkey!(t, :status, :unknown)
        @test getkey(t, :status) == :invalid  # Converted by set callback
        
        # Test comparing anonymous callbacks vs. named callbacks
        tnamed = TestCallback()
        
        # Set identical values to compare behavior
        setkey!(tnamed, :uppercase, "hello")
        setkey!(t, :name, "hello")
        
        # Both should have the same result despite different implementation
        @test getkey(tnamed, :uppercase) == "HELLO"
        @test getkey(t, :name) == "HELLO"
        
        # Test with more complex scenario
        setkey!(tnamed, :transformed, 5)  # Will be multiplied by 2 on write, divided by 2 on read
        setkey!(t, :score, 5)  # Will be unchanged on write (>0), multiplied by 2 on read
        
        # Both should have similar behavior for positive values but through different mechanisms
        @test getkey(tnamed, :transformed) == 5
        @test getkey(t, :score) == 10
    end
end
