using ManagedProperties
using Test

# Include test type definitions first
include("basic_test_types.jl")

# Include all test files
include("property_basics.jl")
include("access_control.jl")
include("callbacks.jl")
include("utility_functions.jl")
include("edge_cases.jl")
include("anonymous_callbacks.jl")
include("allocation_tests.jl")
include("default_callbacks.jl")
include("property_bag_interface.jl")

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
    
    @testset "Default Callbacks" begin
        test_default_callbacks()
    end
    
    @testset "Anonymous Callbacks" begin
        test_anonymous_callbacks()
    end
    
    @testset "Property Bag Interface" begin
        test_property_bag_interface()
    end
    
    @testset "Allocation Tests" begin
        test_allocations()
    end
end
