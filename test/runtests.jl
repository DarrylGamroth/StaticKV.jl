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
include("abstract_type.jl")

# Include new comprehensive test files for improved coverage
include("base_show_tests.jl")
include("exception_tests.jl")
# TODO: Fix @kvstore syntax errors in these files
# include("extended_edge_cases.jl")
# include("macro_edge_cases.jl")
# include("utility_coverage.jl")

# Run all tests
@testset verbose=true "StaticKV.jl" begin
    @testset "Key-Value Store Basics" begin
        test_key_value_basics()
    end

    @testset "Access Control" begin
        test_access_control()
        test_new_access_control_modes()
        test_base_ismutable()
        test_legacy_compatibility()
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
    
    @testset "Abstract Type" begin
        test_abstract_type()
    end
    
    @testset "Base.show Methods" begin
        test_base_show()
    end
    
    @testset "Exception Paths" begin
        test_exception_paths()
    end
    
    # TODO: Re-enable after fixing @kvstore syntax errors
    # @testset "Extended Edge Cases" begin
    #     test_extended_edge_cases()
    # end
    # 
    # @testset "Macro Edge Cases" begin
    #     test_macro_edge_cases()
    # end
    # 
    # @testset "Utility Coverage" begin
    #     test_utility_coverage()
    # end
end
