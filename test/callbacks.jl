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
    
    # Test combined read/set callbacks
    @test get_property(t1, :transformed) == 5  # Original value is 10, set callback doubles to 20, get callback divides by 2
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
