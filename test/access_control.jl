function test_access_control()
    # Use the pre-defined TestAccess type
    t = TestAccess()
    
    # Test readable key
    @test is_readable(t, :readable) == true
    @test is_writable(t, :readable) == false
    @test getkey(t, :readable) == "read-only"
    @test_throws ErrorException setkey!(t, :readable, "new value")
    @test_throws ErrorException resetkey!(t, :readable)  # Can't reset read-only key
    
    # Test writable key
    @test is_readable(t, :writable) == false
    @test is_writable(t, :writable) == true
    @test_throws ErrorException getkey(t, :writable)
    @test setkey!(t, :writable, "new value") == "new value"
    @test resetkey!(t, :writable) === nothing  # Can reset writable key
    @test isset(t, :writable) == false  # Now it should be unset
    setkey!(t, :writable, "restored")  # Restore for later tests
    
    # Test read-write key
    @test is_readable(t, :readwrite) == true
    @test is_writable(t, :readwrite) == true
    @test getkey(t, :readwrite) == "both"
    @test setkey!(t, :readwrite, "new value") == "new value"
    @test getkey(t, :readwrite) == "new value"
    @test resetkey!(t, :readwrite) === nothing  # Can reset read-write key
    @test isset(t, :readwrite) == false  # Now it should be unset
    @test_throws ErrorException getkey(t, :readwrite)  # Can't get unset key
    setkey!(t, :readwrite, "restored")  # Restore for later tests
    
    # Test no-access key
    @test is_readable(t, :none) == false
    @test is_writable(t, :none) == false
    @test_throws ErrorException getkey(t, :none)
    @test_throws ErrorException setkey!(t, :none, "new value")
    @test_throws ErrorException resetkey!(t, :none)  # Can't reset no-access key
    
    # Test isset still works for non-readable keys
    @test isset(t, :writable) == true
    @test isset(t, :none) == true
end
