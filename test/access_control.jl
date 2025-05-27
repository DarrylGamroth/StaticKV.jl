function test_access_control()
    # Use the pre-defined TestAccess type
    t = TestAccess()
    
    # Test readable property
    @test is_readable(t, :readable) == true
    @test is_writable(t, :readable) == false
    @test get_property(t, :readable) == "read-only"
    @test_throws ErrorException set_property!(t, :readable, "new value")
    @test_throws ErrorException reset_property!(t, :readable)  # Can't reset read-only property
    
    # Test writable property
    @test is_readable(t, :writable) == false
    @test is_writable(t, :writable) == true
    @test_throws ErrorException get_property(t, :writable)
    @test set_property!(t, :writable, "new value") == "new value"
    @test reset_property!(t, :writable) === nothing  # Can reset writable property
    @test is_set(t, :writable) == false  # Now it should be unset
    set_property!(t, :writable, "restored")  # Restore for later tests
    
    # Test read-write property
    @test is_readable(t, :readwrite) == true
    @test is_writable(t, :readwrite) == true
    @test get_property(t, :readwrite) == "both"
    @test set_property!(t, :readwrite, "new value") == "new value"
    @test get_property(t, :readwrite) == "new value"
    @test reset_property!(t, :readwrite) === nothing  # Can reset read-write property
    @test is_set(t, :readwrite) == false  # Now it should be unset
    @test_throws ErrorException get_property(t, :readwrite)  # Can't get unset property
    set_property!(t, :readwrite, "restored")  # Restore for later tests
    
    # Test no-access property
    @test is_readable(t, :none) == false
    @test is_writable(t, :none) == false
    @test_throws ErrorException get_property(t, :none)
    @test_throws ErrorException set_property!(t, :none, "new value")
    @test_throws ErrorException reset_property!(t, :none)  # Can't reset no-access property
    
    # Test is_set still works for non-readable properties
    @test is_set(t, :writable) == true
    @test is_set(t, :none) == true
end
