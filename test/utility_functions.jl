function test_utility_functions()
    # PART 1: Basic Utility Functions
    # Use the pre-defined TestUtility type from basic_test_types.jl
    t = TestUtility()
    StaticKV.setkey!(t, "Alice", :name)
    
    # Test resetkey!
    @test isset(t, :name) == true
    resetkey!(t, :name)
    @test isset(t, :name) == false
    @test last_update(t, :name) == -1
    @test_throws ErrorException StaticKV.getkey(t, :name)  # Should throw because key is not set
    StaticKV.setkey!(t, "Alice", :name)  # Set it again for the remaining tests
    
    # Test timestamp functionality
    old_timestamp = last_update(t, :name)
    sleep(0.001)  # Ensure timestamp changes
    StaticKV.setkey!(t, "Bob", :name)
    new_timestamp = last_update(t, :name)
    @test new_timestamp > old_timestamp
    
    # Test complex data structure handling
    addresses = StaticKV.getkey(t, :addresses)
    push!(addresses, "Vacation")
    StaticKV.setkey!(t, addresses, :addresses)
    @test StaticKV.getkey(t, :addresses) == ["Home", "Work", "Vacation"]
    
    # PART 2: with_key functions
    @testset "with_key and with_key! functions" begin
        # Test with_key (non-mutating)
        result = with_key(t, :name) do name
            return name * " Smith"
        end
        @test result == "Bob Smith"
        @test StaticKV.getkey(t, :name) == "Bob"  # Unchanged

        # Direct key manipulation instead of with_key!
        old_age = StaticKV.getkey(t, :age)
        result = old_age + 1
        StaticKV.setkey!(t, result, :age)
        @test result == 21
        @test StaticKV.getkey(t, :age) == 21  # Changed

        # Test using with_key! with non-mutable types (should throw)
        @test_throws ErrorException with_key!(t, :age) do val
            val + 5
        end
        @test StaticKV.getkey(t, :age) == 21  # Original value unchanged by with_key!

        # Now actually update the key with the result
        StaticKV.setkey!(t, 26, :age)
        @test StaticKV.getkey(t, :age) == 26

        # Test with anonymous functions that use more complex logic (should throw)
        @test_throws ErrorException with_key!(t, :age) do val
            if val > 20
                val * 2
            else
                0
            end
        end
        @test StaticKV.getkey(t, :age) == 26

        # Test with mutable types can modify in-place
        mutableContainer = MutableContainer()
        StaticKV.setkey!(mutableContainer, ["item1", "item2"], :items)

        with_key!(mutableContainer, :items) do items
            push!(items, "item3")
            items  # Return the modified array
        end

        @test StaticKV.getkey(mutableContainer, :items) == ["item1", "item2", "item3"]  # Should be modified

        # Test multiple key access
        height = StaticKV.getkey(t, :height)
        age = StaticKV.getkey(t, :age)
        result = height / age
        @test result ≈ 170.5 / 26
        @test StaticKV.getkey(t, :height) == 170.5  # Unchanged
        @test StaticKV.getkey(t, :age) == 26  # Unchanged

        # Test multiple key manipulation
        height = StaticKV.getkey(t, :height)
        age = StaticKV.getkey(t, :age)
        new_height = height + 1.0
        new_age = age + 1
        result = (new_height, new_age)
        StaticKV.setkey!(t, new_height, :height)
        StaticKV.setkey!(t, new_age, :age)
        @test result == (171.5, 27)
        @test StaticKV.getkey(t, :height) == 171.5  # Changed
        @test StaticKV.getkey(t, :age) == 27  # Changed

        # Test error conditions
        @test_throws ErrorException with_key(t, :nonexistent) do val
            return val
        end

        # Test with non-set key
        t2 = TestUtility()  # name is not set
        @test_throws ErrorException with_key(t2, :name) do val
            return val
        end

        # Test with complex key that has callbacks
        a = TestAnonymousCallbacks()
        StaticKV.setkey!(a, "John", :name)

        # Test with_key example
        result = with_key(a, :name) do name
            name * " Doe"  # Note: name is already uppercase due to get callback
        end
        @test result == "JOHN Doe"  # Only "JOHN" is uppercase
        @test StaticKV.getkey(a, :name) == "JOHN"  # Original value unchanged

        # Test with_key! with a numeric key (should throw)
        score_before = StaticKV.getkey(a, :score)
        @test_throws ErrorException with_key!(a, :score) do score
            score + 10
        end
        @test StaticKV.getkey(a, :score) == score_before  # Value unchanged by with_key!
    end
end
