# Tests for dot syntax property access (getproperty/setproperty!)

using Test
using ManagedProperties

# Define test structs at module level
@properties TestDotSyntax begin
    name::String
    age::Int => (value => 25)
    readonly_prop::String => (
        value => "readonly", 
        access => AccessMode.READABLE
    )
end

function test_dot_syntax()
    @testset "Dot Syntax Property Access" begin
        obj = TestDotSyntax()

        @testset "Basic Dot Syntax" begin
            # Test getting with dot syntax
            @test obj.age == 25
            @test obj.readonly_prop == "readonly"
            
            # Test setting with dot syntax
            obj.name = "Alice"
            @test obj.name == "Alice"
            
            # Test consistency with function calls
            @test obj.name == get_property(obj, :name)
            set_property!(obj, :age, 30)
            @test obj.age == 30
        end

        @testset "Access Control" begin
            # Test readonly property cannot be written
            @test_throws Exception obj.readonly_prop = "new value"
            
            # Test unset property throws error when read
            obj2 = TestDotSyntax()
            @test_throws Exception obj2.name
        end
    end
end
