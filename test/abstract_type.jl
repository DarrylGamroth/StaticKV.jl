# Test abstract type functionality
using Test
using StaticKV

# Test structs for abstract type testing
@kvstore AbstractTestPerson begin
    name::String
    age::Int => (25)
end

@kvstore AbstractTestProduct begin
    title::String => ("default")
    price::Float64
end

function test_abstract_type()
    @testset "Abstract Type Tests" begin
        # Create instances
        person = AbstractTestPerson()
        product = AbstractTestProduct()

        # Test that both inherit from AbstractStaticKV
        @test person isa StaticKV.AbstractStaticKV
        @test product isa StaticKV.AbstractStaticKV
        @test typeof(person) <: StaticKV.AbstractStaticKV
        @test typeof(product) <: StaticKV.AbstractStaticKV

        # Test that they have different concrete types
        @test typeof(person) != typeof(product)
        @test typeof(person) == AbstractTestPerson{typeof(person).parameters[1]}
        @test typeof(product) == AbstractTestProduct{typeof(product).parameters[1]}

        # Test generic function that works with any AbstractStaticKV
        function count_set_keys(kv::StaticKV.AbstractStaticKV)
            count = 0
            for key in StaticKV.keynames(kv)
                if StaticKV.isset(kv, key)
                    count += 1
                end
            end
            return count
        end

        # Test the generic function works with both types
        @test count_set_keys(person) == 1  # age has default value
        @test count_set_keys(product) == 1  # title has default value

        # Set some values and test again
        setindex!(person, "Alice", :name)
        setindex!(product, 29.99, :price)
        
        @test count_set_keys(person) == 2  # name and age are set
        @test count_set_keys(product) == 2  # title and price are set

        # Test type constraints work
        function process_same_type(kv1::T, kv2::T) where T <: StaticKV.AbstractStaticKV
            return typeof(kv1) == typeof(kv2)
        end

        person2 = AbstractTestPerson()
        @test process_same_type(person, person2) == true
        
        # This should work at runtime but would be a type error if uncommented:
        # @test process_same_type(person, product) == false  # Would be type error

        # Test that we can create arrays of AbstractStaticKV
        kvstores = StaticKV.AbstractStaticKV[person, product]
        @test length(kvstores) == 2
        @test all(kv -> kv isa StaticKV.AbstractStaticKV, kvstores)

        # Test generic operations on the array
        total_keys = sum(kv -> length(StaticKV.keynames(kv)), kvstores)
        @test total_keys == 4  # 2 keys per struct * 2 structs

        # Test that supertype relationships work
        @test StaticKV.AbstractStaticKV == supertype(typeof(person))
        @test StaticKV.AbstractStaticKV == supertype(typeof(product))

        # Test method dispatch
        function dispatch_test(kv::StaticKV.AbstractStaticKV)
            return "AbstractStaticKV method"
        end

        function dispatch_test(kv::AbstractTestPerson)
            return "AbstractTestPerson method"
        end

        @test dispatch_test(person) == "AbstractTestPerson method"  # More specific method
        @test dispatch_test(product) == "AbstractStaticKV method"   # Abstract method

        # Test that methods work on concrete types (which inherit from AbstractStaticKV)
        @test hasmethod(StaticKV.keynames, (typeof(person),))
        @test hasmethod(StaticKV.isset, (typeof(person), Symbol))
        @test hasmethod(Base.getindex, (typeof(person), Symbol))
        @test hasmethod(Base.setindex!, (typeof(person), Any, Symbol))
        
        # Same for the product type
        @test hasmethod(StaticKV.keynames, (typeof(product),))
        @test hasmethod(StaticKV.isset, (typeof(product), Symbol))
        @test hasmethod(Base.getindex, (typeof(product), Symbol))
        @test hasmethod(Base.setindex!, (typeof(product), Any, Symbol))
    end
end
