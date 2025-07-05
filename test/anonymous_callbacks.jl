# Define test types with anonymous functions in key definitions
@kvstore TestAnonymousCallbacks begin
    # Anonymous function for get callback
    name::String => ("default"; on_get = (obj, key, val) -> uppercase(val))
    
    # Anonymous function for set callback
    email::String => (; on_set = (obj, key, val) -> lowercase(val))
    
    # Both read and set callbacks as anonymous functions
    score::Int => (10; 
        on_get = (obj, key, val) -> val * 2,
        on_set = (obj, key, val) -> max(0, val)  # Ensure non-negative
    )
    
    # Using anonymous functions with more complex logic
    status::Symbol => (:active; on_set = (obj, key, val) -> begin
            # Multi-line anonymous function with conditionals
            if val == :pending || val == :active || val == :inactive
                return val
            else
                return :invalid
            end
        end,
        on_get = (obj, key, val) -> begin
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
    items::Vector{String} => String[]
end

# Export the test function so it can be called from runtests.jl
function test_anonymous_callbacks()
    # Test focusing only on anonymous/inline callbacks in key definitions
    @testset "Anonymous functions in key definitions" begin
        t = TestAnonymousCallbacks()
        
        # Test get callback with anonymous function
        @test getindex(t, :name) == "DEFAULT"  # Should be uppercase
        setindex!(t, :name, "test")
        @test getindex(t, :name) == "TEST"  # Should be uppercase
        
        # Test set callback with anonymous function
        setindex!(t, :email, "USER@EXAMPLE.COM")
        @test getindex(t, :email) == "user@example.com"  # Should be lowercase
        
        # Test both read and set callbacks
        @test getindex(t, :score) == 20  # Default 10 * 2 from get callback
        setindex!(t, :score, -5)
        @test getindex(t, :score) == 0  # max(0, -5) = 0, then * 2 = 0
        setindex!(t, :score, 7)
        @test getindex(t, :score) == 14  # 7, then * 2 = 14
        
        # Test more complex anonymous function logic
        @test getindex(t, :status) == :ACTIVE  # Default :active transformed to :ACTIVE
        setindex!(t, :status, :pending)
        @test getindex(t, :status) == :PENDING
        setindex!(t, :status, :inactive)
        @test getindex(t, :status) == :inactive  # No special transformation
        setindex!(t, :status, :unknown)
        @test getindex(t, :status) == :invalid  # Converted by set callback
        
        # Test comparing anonymous callbacks vs. named callbacks
        tnamed = TestCallback()
        
        # Set identical values to compare behavior
        setindex!(tnamed, :uppercase, "hello")
        setindex!(t, :name, "hello")
        
        # Both should have the same result despite different implementation
        @test getindex(tnamed, :uppercase) == "HELLO"
        @test getindex(t, :name) == "HELLO"
        
        # Test with more complex scenario
        setindex!(tnamed, :transformed, 5)  # Will be multiplied by 2 on write, divided by 2 on read
        setindex!(t, :score, 5)  # Will be unchanged on write (>0), multiplied by 2 on read
        
        # Both should have similar behavior for positive values but through different mechanisms
        @test getindex(tnamed, :transformed) == 5
        @test getindex(t, :score) == 10
    end
end
