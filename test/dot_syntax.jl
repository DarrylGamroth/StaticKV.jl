# Tests for dot syntax property access (getproperty/setproperty!)

using Test
using StaticKV

# Define test structs at module level
@kvstore TestDotSyntax begin
    name::String
    age::Int => 25
    readonly_key::String => ("readonly"; access = AccessMode.READABLE)
end

function test_dot_syntax()
    @testset "Dot Syntax Key Access" begin
        obj = TestDotSyntax()

        @testset "Basic Dot Syntax" begin
            # Test getting with dot syntax
            @test obj.age == 25
            @test obj.readonly_key == "readonly"
            
            # Test setting with dot syntax
            obj.name = "Alice"
            @test obj.name == "Alice"
            
            # Test consistency with function calls
            @test obj.name == getindex(obj, :name)
            setindex!(obj, :age, 30)
            @test obj.age == 30
        end

        @testset "Access Control" begin
            # Test readonly property cannot be written
            @test_throws Exception obj.readonly_key = "new value"
            
            # Test unset property throws error when read
            obj2 = TestDotSyntax()
            @test_throws Exception obj2.name
        end
    end
end
