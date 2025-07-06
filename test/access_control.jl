function test_access_control()
    # Use the pre-defined TestAccess type
    t = TestAccess()
    
    # Test readable key
    @test is_readable(t, :readable) == true
    @test is_writable(t, :readable) == false
    @test StaticKV.value(t, :readable) == "read-only"
    @test_throws ErrorException StaticKV.value!(t, "new value", :readable)
    @test_throws ErrorException reset!(t, :readable)  # Can't reset read-only key
    
    # Test writable key
    @test is_readable(t, :writable) == false
    @test is_writable(t, :writable) == true
    @test_throws ErrorException StaticKV.value(t, :writable)
    @test StaticKV.value!(t, "new value", :writable) == "new value"
    @test reset!(t, :writable) === nothing  # Can reset writable key
    @test isset(t, :writable) == false  # Now it should be unset
    StaticKV.value!(t, "restored", :writable)  # Restore for later tests
    
    # Test read-write key
    @test is_readable(t, :readwrite) == true
    @test is_writable(t, :readwrite) == true
    @test StaticKV.value(t, :readwrite) == "both"
    @test StaticKV.value!(t, "new value", :readwrite) == "new value"
    @test StaticKV.value(t, :readwrite) == "new value"
    @test reset!(t, :readwrite) === nothing  # Can reset read-write key
    @test isset(t, :readwrite) == false  # Now it should be unset
    @test_throws ErrorException StaticKV.value(t, :readwrite)  # Can't get unset key
    StaticKV.value!(t, "restored", :readwrite)  # Restore for later tests
    
    # Test no-access key
    @test is_readable(t, :none) == false
    @test is_writable(t, :none) == false
    @test_throws ErrorException StaticKV.value(t, :none)
    @test_throws ErrorException StaticKV.value!(t, "new value", :none)
    @test_throws ErrorException reset!(t, :none)  # Can't reset no-access key
    
    # Test isset still works for non-readable keys
    @test isset(t, :writable) == true
    @test isset(t, :none) == true
end

# Define test structs with new access modes (at top level)
@kvstore TestNewAccess begin
    readonly::String => ("read-only"; access = AccessMode.READABLE)
    assignable_only::String => ("initial"; access = AccessMode.ASSIGNABLE)
    mutable_only::Vector{String} => (["item1"]; access = AccessMode.MUTABLE)
    read_assignable::String => ("both"; access = AccessMode.READABLE | AccessMode.ASSIGNABLE)
    read_mutable::Vector{String} => (["initial"]; access = AccessMode.READABLE | AccessMode.MUTABLE)
    assign_mutable::Vector{String} => (["initial"]; access = AccessMode.ASSIGNABLE | AccessMode.MUTABLE)
    full_access::Vector{String} => (["initial"]; access = AccessMode.READABLE_ASSIGNABLE_MUTABLE)
    default_access::String => "default"  # Should use READABLE_ASSIGNABLE_MUTABLE as default
    legacy_writable::String => ("legacy"; access = AccessMode.ASSIGNABLE)
    legacy_readable_writable::String => ("legacy2"; access = AccessMode.READABLE_ASSIGNABLE_MUTABLE)
end

@kvstore TestDefaultAccess begin
    default_key::String
    another_key::Int
end

@kvstore TestMutable begin
    readonly::String => ("read-only"; access = AccessMode.READABLE)
    mutable_key::Vector{String} => (["initial"]; access = AccessMode.MUTABLE)
    full_access::Vector{String} => (["initial"]; access = AccessMode.READABLE_ASSIGNABLE_MUTABLE)
    isbits_key::Int => (42; access = AccessMode.READABLE_ASSIGNABLE_MUTABLE)
end

@kvstore TestLegacy begin
    old_writable::String => ("test"; access = AccessMode.ASSIGNABLE)
    old_readable_writable::String => ("test"; access = AccessMode.READABLE_ASSIGNABLE_MUTABLE)
end

# Test the new access control modes
function test_new_access_control_modes()
    # Use the test structs defined above
    t = TestNewAccess()

    # Test READABLE only
    @test is_readable(t, :readonly) == true
    @test is_assignable(t, :readonly) == false
    @test is_mutable(t, :readonly) == false
    @test is_writable(t, :readonly) == false  # Legacy function should map to assignable
    @test StaticKV.value(t, :readonly) == "read-only"
    @test_throws ErrorException StaticKV.value!(t, "new", :readonly)
    @test_throws ErrorException reset!(t, :readonly)

    # Test ASSIGNABLE only
    @test is_readable(t, :assignable_only) == false
    @test is_assignable(t, :assignable_only) == true
    @test is_mutable(t, :assignable_only) == false
    @test is_writable(t, :assignable_only) == true  # Legacy function should work
    @test_throws ErrorException StaticKV.value(t, :assignable_only)
    @test StaticKV.value!(t, "new value", :assignable_only) == "new value"
    @test reset!(t, :assignable_only) === nothing

    # Test MUTABLE only
    @test is_readable(t, :mutable_only) == false
    @test is_assignable(t, :mutable_only) == false
    @test is_mutable(t, :mutable_only) == true
    @test is_writable(t, :mutable_only) == false  # Should be false for mutable-only
    @test_throws ErrorException StaticKV.value(t, :mutable_only)
    @test_throws ErrorException StaticKV.value!(t, ["new"], :mutable_only)
    @test_throws ErrorException with_key!(v -> push!(v, "new"), t, :mutable_only)  # Can't read to mutate

    # Test READABLE | ASSIGNABLE
    @test is_readable(t, :read_assignable) == true
    @test is_assignable(t, :read_assignable) == true
    @test is_mutable(t, :read_assignable) == false
    @test is_writable(t, :read_assignable) == true
    @test StaticKV.value(t, :read_assignable) == "both"
    @test StaticKV.value!(t, "new", :read_assignable) == "new"
    @test StaticKV.value(t, :read_assignable) == "new"
    @test reset!(t, :read_assignable) === nothing

    # Test READABLE | MUTABLE
    @test is_readable(t, :read_mutable) == true
    @test is_assignable(t, :read_mutable) == false
    @test is_mutable(t, :read_mutable) == true
    @test is_writable(t, :read_mutable) == false
    @test StaticKV.value(t, :read_mutable) == ["initial"]
    @test_throws ErrorException StaticKV.value!(t, ["new"], :read_mutable)
    result = with_key!(v -> push!(v, "mutated"), t, :read_mutable)  # Should work for in-place mutation
    @test length(result) == 2  # push! returns the array, which now has 2 elements
    @test StaticKV.value(t, :read_mutable) == ["initial", "mutated"]

    # Test ASSIGNABLE | MUTABLE
    @test is_readable(t, :assign_mutable) == false
    @test is_assignable(t, :assign_mutable) == true
    @test is_mutable(t, :assign_mutable) == true
    @test is_writable(t, :assign_mutable) == true
    @test_throws ErrorException StaticKV.value(t, :assign_mutable)
    @test StaticKV.value!(t, ["replaced"], :assign_mutable) == ["replaced"]
    @test_throws ErrorException with_key!(v -> push!(v, "mutated"), t, :assign_mutable)  # Can't read

    # Test full access (READABLE_ASSIGNABLE_MUTABLE)
    @test is_readable(t, :full_access) == true
    @test is_assignable(t, :full_access) == true
    @test is_mutable(t, :full_access) == true
    @test is_writable(t, :full_access) == true
    @test StaticKV.value(t, :full_access) == ["initial"]
    @test StaticKV.value!(t, ["replaced"], :full_access) == ["replaced"]
    @test StaticKV.value(t, :full_access) == ["replaced"]
    result = with_key!(v -> push!(v, "mutated"), t, :full_access)
    @test length(result) == 2  # push! returns the array, which now has 2 elements
    @test StaticKV.value(t, :full_access) == ["replaced", "mutated"]

    # Test default access mode (should be READABLE_ASSIGNABLE_MUTABLE)
    @test is_readable(t, :default_access) == true
    @test is_assignable(t, :default_access) == true
    @test is_mutable(t, :default_access) == true
    @test is_writable(t, :default_access) == true
    @test StaticKV.value(t, :default_access) == "default"
    @test StaticKV.value!(t, "new", :default_access) == "new"
    @test StaticKV.value(t, :default_access) == "new"
end

# Test Base.ismutable functionality
function test_base_ismutable()
    t = TestMutable()

    # Test Base.ismutable for specific keys
    @test Base.ismutable(t, :readonly) == false
    @test Base.ismutable(t, :mutable_key) == true
    @test Base.ismutable(t, :full_access) == true
    @test Base.ismutable(t, :isbits_key) == true  # Access-wise it's mutable
    @test Base.ismutable(t, :nonexistent) == false

    # Test Base.ismutable for the struct itself
    @test Base.ismutable(t) == true  # The struct itself is mutable

    # Test with_key! respects isbits restrictions
    @test_throws ErrorException with_key!(x -> x + 1, t, :isbits_key)  # Can't mutate isbits in place

    # Test with_key! works for non-isbits mutable keys
    result = with_key!(v -> push!(v, "new"), t, :full_access)
    @test length(result) == 2  # push! returns the array, which now has 2 elements
    @test StaticKV.value(t, :full_access) == ["initial", "new"]
end

# Test legacy compatibility
function test_legacy_compatibility()
    # Old-style access mode definitions should still work
    t = TestLegacy()

    # WRITABLE should map to ASSIGNABLE
    @test is_assignable(t, :old_writable) == true
    @test is_mutable(t, :old_writable) == false
    @test is_writable(t, :old_writable) == true

    # READABLE_WRITABLE should map to READABLE_ASSIGNABLE_MUTABLE
    @test is_readable(t, :old_readable_writable) == true
    @test is_assignable(t, :old_readable_writable) == true
    @test is_mutable(t, :old_readable_writable) == true
    @test is_writable(t, :old_readable_writable) == true
end
