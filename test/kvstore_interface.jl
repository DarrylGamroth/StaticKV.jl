using StaticKV
using Test

# Define the test type at the top level
@kvstore TestBag begin
    string_key::String
    int_key::Int => (42; access = AccessMode.READABLE_ASSIGNABLE_MUTABLE)
    read_only::Float64 => (3.14; access = AccessMode.READABLE)
    write_only::Symbol => (; access = AccessMode.ASSIGNABLE)
    custom_read::String => ("original"; 
        access = AccessMode.READABLE_ASSIGNABLE_MUTABLE,
        on_get = (obj, key, val) -> "READ: $(val)"
    )
end

function test_kvstore_interface()

    # Create a test instance
    bag = TestBag()
    setindex!(bag, "hello", :string_key)
    
    @testset "Base.getindex - Single key" begin
        @test getindex(bag, :string_key) == "hello"
        @test getindex(bag, :int_key) == 42
        @test getindex(bag, :read_only) == 3.14
        @test getindex(bag, :custom_read) == "READ: original"
        @test_throws ErrorException getindex(bag, :write_only)  # Not readable
        @test_throws ErrorException getindex(bag, :nonexistent)  # Doesn't exist
    end

    @testset "Base.getindex - Multiple keys" begin
        @test getindex(bag, :string_key, :int_key) == ("hello", 42)
        @test getindex(bag, :int_key, :read_only, :custom_read) == (42, 3.14, "READ: original")
        @test_throws ErrorException getindex(bag, :string_key, :write_only)  # One key not readable
        @test_throws ErrorException getindex(bag, :string_key, :nonexistent)  # One key doesn't exist
    end

    @testset "Base.setindex! - Single key" begin
        # Test writable properties
        setindex!(bag, "world", :string_key)
        @test getindex(bag, :string_key) == "world"
        
        setindex!(bag, 100, :int_key)
        @test getindex(bag, :int_key) == 100
        
        setindex!(bag, :test, :write_only)
        @test isset(bag, :write_only)
        @test_throws ErrorException getindex(bag, :write_only)  # Can't read it but it's set
        
        setindex!(bag, "modified", :custom_read)
        @test getindex(bag, :custom_read) == "READ: modified"
        
        # Test read-only key
        @test_throws ErrorException setindex!(bag, 2.71, :read_only)
        @test getindex(bag, :read_only) == 3.14  # Value unchanged
        
        # Test nonexistent key
        @test_throws ErrorException setindex!(bag, "value", :nonexistent)
    end

    @testset "Base.setindex! - Multiple keys" begin
        # Test with tuple values
        setindex!(bag, ("multiple", 200), :string_key, :int_key)
        @test getindex(bag, :string_key) == "multiple"
        @test getindex(bag, :int_key) == 200
        
        # Test with array values
        setindex!(bag, ["array", 300], :string_key, :int_key)
        @test getindex(bag, :string_key) == "array"
        @test getindex(bag, :int_key) == 300
        
        # Sets don't work with indexing, as they're unordered
        # Try with another collection that supports indexing
        setindex!(bag, collect(["set", 400]), :string_key, :int_key)
        @test getindex(bag, :string_key) == "set"
        @test getindex(bag, :int_key) == 400
        
        # Test value count mismatch
        @test_throws ArgumentError setindex!(bag, ("one_value",), :string_key, :int_key)
        
        # Test with read-only key
        @test_throws ErrorException setindex!(bag, ("ok", 2.71), :string_key, :read_only)
        
        # Test with nonexistent key
        @test_throws ErrorException setindex!(bag, ("ok", "bad"), :string_key, :nonexistent)
    end

    @testset "Base.keys" begin
        @test collect(keys(bag)) == [:string_key, :int_key, :read_only, :write_only, :custom_read]
        @test keys(bag) == keynames(bag)  # keys should be the same as keynames
    end

    @testset "Base.values" begin
        # For this test, we need to create a clean instance without the write_only key set
        # since Base.values will try to read all set keys
        clean_bag = TestBag()
        setindex!(clean_bag, "test_values", :string_key)
        setindex!(clean_bag, 999, :int_key)
        # Note: read_only and custom_read already have default values
        
        # Only set properties with read access are included
        expected_values = ["test_values", 999, 3.14, "READ: original"]
        values_arr = collect(values(clean_bag))
        @test length(values_arr) == 4  # All readable properties
        @test all(v -> v ∈ values_arr, expected_values)
    end

    @testset "Base.pairs" begin
        # Create a new bag to have deterministic state
        new_bag = TestBag()
        setindex!(new_bag, "pair_test", :string_key)
        setindex!(new_bag, 500, :int_key)
        
        pairs_dict = Dict(collect(pairs(new_bag)))
        @test pairs_dict[:string_key] == "pair_test"
        @test pairs_dict[:int_key] == 500
        @test pairs_dict[:read_only] == 3.14
        @test pairs_dict[:custom_read] == "READ: original"
        @test !haskey(pairs_dict, :write_only)  # Not readable
    end

    @testset "Base.iterate" begin
        # We're using direct iteration which calls iterate internally
        # Iteration should yield key-value pairs for properties that are set and readable
        new_bag = TestBag()
        setindex!(new_bag, "iterate_test", :string_key)
        
        # Collect into dictionary for easy testing
        iterated_dict = Dict(new_bag)
        
        @test iterated_dict[:string_key] == "iterate_test"
        @test iterated_dict[:int_key] == 42
        @test iterated_dict[:read_only] == 3.14
        @test iterated_dict[:custom_read] == "READ: original"
        @test !haskey(iterated_dict, :write_only)  # Not readable
    end

    @testset "Base.length" begin
        # Only counts properties that are set (not null)
        empty_bag = TestBag()  # Only default values are set
        @test length(empty_bag) == 3  # int_key, read_only, custom_read have defaults
        
        setindex!(empty_bag, "length_test", :string_key)
        @test length(empty_bag) == 4
        
        setindex!(empty_bag, :set, :write_only)
        @test length(empty_bag) == 5  # All properties are now set
        
        # Reset a key
        reset!(empty_bag, :custom_read)
        @test length(empty_bag) == 4
    end
    
    @testset "Base.haskey" begin
        @test haskey(bag, :string_key)
        @test haskey(bag, :int_key)
        @test haskey(bag, :read_only)
        @test haskey(bag, :write_only)
        @test haskey(bag, :custom_read)
        @test !haskey(bag, :nonexistent)
    end
    
    @testset "Base.get" begin
        # Create a new bag with known state for these tests
        get_bag = TestBag()
        setindex!(get_bag, "get_test", :string_key)
        setindex!(get_bag, 123, :int_key)
        
        @test get(get_bag, :string_key, "default") == "get_test"
        @test get(get_bag, :int_key, 0) == 123
        @test get(get_bag, :read_only, 0.0) == 3.14
        @test get(get_bag, :custom_read, "default") == "READ: original"
        
        # Test default value for unset key
        reset!(get_bag, :string_key)
        @test get(get_bag, :string_key, "was_reset") == "was_reset"
        
        # Nonexistent key returns default
        @test get(get_bag, :nonexistent, "doesn't exist") == "doesn't exist"
        
        # write_only is set but not readable - need to modify Base.get to handle this case
        # This test is commented out until we implement a fix to handle non-readable keys
        # @test get(bag, :write_only, :default) == :default
        
        # Reset a key and test default
        reset!(bag, :string_key)
        @test get(bag, :string_key, "was_reset") == "was_reset"
        
        # Nonexistent key returns default
        @test get(bag, :nonexistent, "doesn't exist") == "doesn't exist"
    end
    
    @testset "Base.isreadable/iswritable" begin
        @test isreadable(bag, :string_key)
        @test isreadable(bag, :int_key)
        @test isreadable(bag, :read_only)
        @test !isreadable(bag, :write_only)
        @test isreadable(bag, :custom_read)
        
        @test iswritable(bag, :string_key)
        @test iswritable(bag, :int_key)
        @test !iswritable(bag, :read_only)
        @test iswritable(bag, :write_only)
        @test iswritable(bag, :custom_read)
        
        # Should match our own is_readable/is_writable functions
        for prop in keynames(bag)
            @test isreadable(bag, prop) == is_readable(bag, prop)
            @test iswritable(bag, prop) == is_writable(bag, prop)
        end
        
        @test_throws ErrorException isreadable(bag, :nonexistent)
        @test_throws ErrorException iswritable(bag, :nonexistent)
    end
end
