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
        @test StaticKV.value(t, :name) == "DEFAULT"  # Should be uppercase
        StaticKV.value!(t, "test", :name)
        @test StaticKV.value(t, :name) == "TEST"  # Should be uppercase
        
        # Test set callback with anonymous function
        StaticKV.value!(t, "USER@EXAMPLE.COM", :email)
        @test StaticKV.value(t, :email) == "user@example.com"  # Should be lowercase
        
        # Test both read and set callbacks
        @test StaticKV.value(t, :score) == 20  # Default 10 * 2 from get callback
        StaticKV.value!(t, -5, :score)
        @test StaticKV.value(t, :score) == 0  # max(0, -5) = 0, then * 2 = 0
        StaticKV.value!(t, 7, :score)
        @test StaticKV.value(t, :score) == 14  # 7, then * 2 = 14
        
        # Test more complex anonymous function logic
        @test StaticKV.value(t, :status) == :ACTIVE  # Default :active transformed to :ACTIVE
        StaticKV.value!(t, :pending, :status)
        @test StaticKV.value(t, :status) == :PENDING
        StaticKV.value!(t, :inactive, :status)
        @test StaticKV.value(t, :status) == :inactive  # No special transformation
        StaticKV.value!(t, :unknown, :status)
        @test StaticKV.value(t, :status) == :invalid  # Converted by set callback
        
        # Test comparing anonymous callbacks vs. named callbacks
        tnamed = TestCallback()
        
        # Set identical values to compare behavior
        StaticKV.value!(tnamed, "hello", :uppercase)
        StaticKV.value!(t, "hello", :name)
        
        # Both should have the same result despite different implementation
        @test StaticKV.value(tnamed, :uppercase) == "HELLO"
        @test StaticKV.value(t, :name) == "HELLO"
        
        # Test with more complex scenario
        StaticKV.value!(tnamed, 5, :transformed)  # Will be multiplied by 2 on write, divided by 2 on read
        StaticKV.value!(t, 5, :score)  # Will be unchanged on write (>0), multiplied by 2 on read
        
        # Both should have similar behavior for positive values but through different mechanisms
        @test StaticKV.value(tnamed, :transformed) == 5
        @test StaticKV.value(t, :score) == 10
    end
end
