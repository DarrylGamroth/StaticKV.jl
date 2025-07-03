using StaticKV
using Test

# Include test type definitions first
include("basic_test_types.jl")

# Include all test files
include("key_value_basics.jl")
include("access_control.jl")
include("callbacks.jl")
include("utility_functions.jl")
include("edge_cases.jl")
include("anonymous_callbacks.jl")
include("allocation_tests.jl")
include("default_callbacks.jl")
include("kvstore_interface.jl")
include("macro_expansion.jl")
include("dot_syntax.jl")

# Run all tests
@testset verbose=true "StaticKV.jl" begin
    @testset "Key-Value Store Basics" begin
        test_key_value_basics()
    end

    @testset "Access Control" begin
        test_access_control()
    end

    @testset "Custom Callbacks" begin
        test_callbacks()
    end

    @testset "Utility Functions" begin
        test_utility_functions()
    end

    @testset "Edge Cases" begin
        test_edge_cases()
    end
    
    @testset "Default Callbacks" begin
        test_default_callbacks()
    end
    
    @testset "Anonymous Callbacks" begin
        test_anonymous_callbacks()
    end
    
    @testset "Key-Value Store Interface" begin
        test_kvstore_interface()
    end
    
    @testset "Allocation Tests" begin
        test_allocations()
    end
    
    @testset "Macro Expansion" begin
        test_macro_expansion()
    end
    
    @testset "Dot Syntax" begin
        test_dot_syntax()
    end
end
