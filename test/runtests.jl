using ManagedProperties
using Test
using Clocks

# Include test type definitions first
include("basic_test_types.jl")

# Include all test files
include("property_basics.jl")
include("access_control.jl")
include("callbacks.jl")
include("utility_functions.jl")
include("edge_cases.jl")
include("performance.jl")
include("anonymous_callbacks.jl")

# Run all tests
@testset verbose=true "ManagedProperties.jl" begin
    @testset "Property Basics" begin
        test_property_basics()
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
    
    @testset "Performance" begin
        test_performance()
    end
    
    @testset "Anonymous Callbacks" begin
        test_anonymous_callbacks()
    end
end
