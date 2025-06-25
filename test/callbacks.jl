# Test callbacks functionality
function test_callbacks()
    # Use the pre-defined TestCallback type
    t1 = TestCallback()
    
    # Test set callbacks
    set_property!(t1, :uppercase, "hello")
    @test get_property(t1, :uppercase) == "HELLO"
    
    set_property!(t1, :lowercase, "HELLO")
    @test get_property(t1, :lowercase) == "hello"
    
    # Test get callbacks
    @test get_property(t1, :redacted) == "REDACTED"  # Original value is masked
    
    # Test combined read/set callbacks with default value processing
    @test get_property(t1, :transformed) == 10  # Default value 10 → multiply_cb(10) = 20 stored → divide_cb(20) = 10 returned
    set_property!(t1, :transformed, 5)
    @test get_property(t1, :transformed) == 5  # Set callback multiplies by 2 to 10, get callback divides by 2 to 5
    
    # Use the pre-defined TestCallbacks type for more complex scenarios
    t2 = TestCallbacks()
    
    # Test read/set callbacks
    @test get_property(t2, :name) == "ALICE"  # Uppercase get callback
    set_property!(t2, :name, "Bob")
    @test get_property(t2, :name) == "BOB"  # "bob" stored due to lowercase set callback, then uppercased
    
    # Test data validation via set callback
    set_property!(t2, :count, 10)
    @test get_property(t2, :count) == 10
    set_property!(t2, :count, -5)
    @test get_property(t2, :count) == 0  # Negative values are clamped to 0
    
    # Test read masking
    @test get_property(t2, :secret) == "REDACTED"  # Original value is masked
end
