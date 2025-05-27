function test_performance()
    # Use the pre-defined TestPerformance type from basic_test_types.jl
    # Create a small benchmark measuring operations per second
    t = TestPerformance()
    set_property!(t, :name, "test")
    
    # Test property access overhead
    iterations = 10_000
    
    # Time direct field access (baseline)
    function time_direct_access(iterations)
        t = TestPerformance()
        start = time()
        for i in 1:iterations
            v = t.id.value
            t.id.value = i
        end
        return time() - start
    end
    
    # Time getter/setter overhead
    function time_managed_access(iterations)
        t = TestPerformance()
        start = time()
        for i in 1:iterations
            v = get_property(t, :id)
            set_property!(t, :id, i)
        end
        return time() - start
    end
    
    direct_time = time_direct_access(iterations)
    managed_time = time_managed_access(iterations)
    
    # We just verify that managed property access doesn't take excessively longer
    # than direct field access (factor depends on hardware, but 10x is reasonable)
    slowdown_factor = managed_time / direct_time
    @test slowdown_factor < 20.0
    
    # Test the with_property function overhead vs manual get/set
    function time_manual_modify(iterations)
        t = TestPerformance()
        start = time()
        for i in 1:iterations
            val = get_property(t, :id)
            val += 1
            set_property!(t, :id, val)
        end
        return time() - start
    end
    
    function time_with_property(iterations)
        t = TestPerformance()
        start = time()
        for i in 1:iterations
            with_property!(t, :id) do val
                val + 1
            end
        end
        return time() - start
    end
    
    manual_time = time_manual_modify(iterations)
    withprop_time = time_with_property(iterations)
    
    # We just verify that with_property isn't dramatically slower than manual
    withprop_factor = withprop_time / manual_time
    @test withprop_factor < 20.0
    
    # Test property lookup/type stability
    @test property_type(TestPerformance, :id) === Int
    @test is_set(t, :id) === true
    @test is_set(t, :missing) === false
end
