# Test allocation behavior of property accessors
using Test
using ManagedProperties

# Test struct with various property types
@properties AllocationTest begin
    bool_val::Bool => (value => true)
    char_val::Char => (value => 'a')
    complex64_val::ComplexF32 => (value => ComplexF32(1, 2))
    complex128_val::ComplexF64 => (value => ComplexF64(3, 4))
    float16_val::Float16 => (value => Float16(1.5))
    float32_val::Float32 => (value => Float32(2.5))
    float_val::Float64 => (value => 3.14)
    int8_val::Int8 => (value => Int8(1))
    int16_val::Int16 => (value => Int16(3))
    int32_val::Int32 => (value => Int32(5))
    int64_val::Int64 => (value => Int64(7))
    int128_val::Int128 => (value => Int128(9))
    int_val::Int => (value => 42)
    matrix_val::Matrix{Float64} => (value => [1.0 2.0; 3.0 4.0])
    string_val::String => (value => "test_string")
    symbol_val::Symbol => (value => :test_symbol)
    uint8_val::UInt8 => (value => UInt8(2))
    uint16_val::UInt16 => (value => UInt16(4))
    uint32_val::UInt32 => (value => UInt32(6))
    uint64_val::UInt64 => (value => UInt64(8))
    uint128_val::UInt128 => (value => UInt128(10))
    vector_val::Vector{Int} => (value => [1, 2, 3])
end

# Callback functions defined at module level
inc_callback(obj, name, val::T) where {T} = val + one(T)
stringify_callback(obj, name, val::T) where {T} = string(val)

# Test struct with custom callbacks
@properties CallbackTest begin
    int_val::Int => (
        value => 42,
        on_get => inc_callback
    )
    any_val::Any => (
        value => "test",
        on_get => stringify_callback
    )
end

function test_allocations()
    @info "Creating test objects for allocation tests..."
    t1 = AllocationTest()
    t2 = CallbackTest()

    # Function barriers for proper allocation testing
    function test_isbits_get_property(obj, field, val)
        set_property!(obj, field, val)
        allocs = @allocated get_property(obj, field)
        @info "$(field) get_property allocations: $(allocs) bytes"
        allocs2 = @allocated is_set(obj, field)
        @test allocs == 0
        @test allocs2 == 0
    end
    
    function test_isbits_set_property(obj, field, val)
        allocs = @allocated set_property!(obj, field, val)
        @info "$(field) set_property! allocations: $(allocs) bytes"
        @test allocs == 0
    end

    # Warm up functions to ensure proper precompilation
    @info "Warming up functions..."
    get_property(t1, :int_val)
    set_property!(t1, :int_val, 100)
    is_set(t1, :int_val)
    get_property(t2, :int_val)
    with_property(x -> x + 1, t1, :int_val)
    with_property!(v -> (v[1] = 1; v), t1, :vector_val)
    with_properties((i, f) -> i + f, t1, :int_val, :float_val)

    # Only keep one comprehensive isbits allocation testset (removes redundancy)
    @testset "get_property allocation - isbits (all)" begin
        for (field, val) in (
            :bool_val => false,
            :char_val => 'z',
            :complex64_val => ComplexF32(2, 3),
            :complex128_val => ComplexF64(4, 5),
            :float16_val => Float16(2.5),
            :float32_val => Float32(3.5),
            :float_val => 6.28,
            :int8_val => Int8(2),
            :int16_val => Int16(4),
            :int32_val => Int32(6),
            :int64_val => Int64(8),
            :int128_val => Int128(10),
            :int_val => 84,
            :uint8_val => UInt8(3),
            :uint16_val => UInt16(5),
            :uint32_val => UInt32(7),
            :uint64_val => UInt64(9),
            :uint128_val => UInt128(11)
        )
            test_isbits_get_property(t1, field, val)
        end
    end

    @testset "set_property! allocation - isbits (all)" begin
        for (field, val) in (
            :bool_val => true,
            :char_val => 'y',
            :complex64_val => ComplexF32(5, 6),
            :complex128_val => ComplexF64(7, 8),
            :float16_val => Float16(3.5),
            :float32_val => Float32(4.5),
            :float_val => 9.42,
            :int8_val => Int8(3),
            :int16_val => Int16(5),
            :int32_val => Int32(7),
            :int64_val => Int64(9),
            :int128_val => Int128(11),
            :int_val => 168,
            :uint8_val => UInt8(4),
            :uint16_val => UInt16(6),
            :uint32_val => UInt32(8),
            :uint64_val => UInt64(10),
            :uint128_val => UInt128(12)
        )
            test_isbits_set_property(t1, field, val)
        end
    end

    # Keep non-isbits and callback/mutable type allocation tests
    @testset "Symbol allocation" begin
        allocs1 = @allocated get_property(t1, :symbol_val)
        @info "Symbol get_property allocations: $(allocs1)"
        @test allocs1 == 0
        allocs2 = @allocated set_property!(t1, :symbol_val, :new_symbol)
        @info "Symbol set_property! allocations: $(allocs2)"
        @test allocs2 == 0
        allocs3 = @allocated is_set(t1, :symbol_val)
        @info "Symbol is_set allocations: $(allocs3)"
        @test allocs3 == 0
    end

    @testset "String allocation" begin
        allocs1 = @allocated get_property(t1, :string_val)
        @info "String get_property allocations: $allocs1"
        allocs2 = @allocated set_property!(t1, :string_val, "new_string")
        @info "String set_property! allocations: $allocs2"
        allocs3 = @allocated is_set(t1, :string_val)
        @test allocs1 == 0
        @test allocs2 == 0
        @test allocs3 == 0
    end

    @testset "Vector allocation" begin
        allocs1 = @allocated get_property(t1, :vector_val)
        @info "Vector get_property allocations: $allocs1"
        allocs2 = @allocated set_property!(t1, :vector_val, [4, 5, 6])
        @info "Vector set_property! allocations: $allocs2"
        allocs3 = @allocated is_set(t1, :vector_val)
        @test allocs1 == 0
        # Do not require allocs2 == 0: assigning a new array always allocates
        @test allocs3 == 0
    end

    @testset "Matrix allocation" begin
        allocs1 = @allocated get_property(t1, :matrix_val)
        @info "Matrix get_property allocations: $allocs1"
        allocs2 = @allocated set_property!(t1, :matrix_val, [5.0 6.0; 7.0 8.0])
        @info "Matrix set_property! allocations: $allocs2"
        allocs3 = @allocated is_set(t1, :matrix_val)
        @test allocs1 == 0
        # Do not require allocs2 == 0: assigning a new array always allocates
        @test allocs3 == 0
    end

    @testset "with_property allocation - isbits" begin
        allocs = @allocated with_property(val -> val + 1, t1, :int_val)
        @test allocs == 0
        @info "with_property Int allocations: $allocs"
    end

    @testset "with_property allocation - Vector" begin
        allocs = @allocated with_property!(vec -> (push!(vec, 4); vec), t1, :vector_val)
        @info "with_property! Vector allocations (push!): $allocs"
        allocs = @allocated with_property!(vec -> (vec[1] = 99; vec), t1, :vector_val)
        @test allocs == 0
        @info "with_property! Vector allocations (index set): $allocs"
    end

    @testset "with_property allocation - Matrix" begin
        allocs = @allocated with_property!(mat -> (mat[1, 1] = 99.0; mat), t1, :matrix_val)
        @test allocs == 0
        @info "with_property! Matrix allocations (index set): $allocs"
        allocs = @allocated with_property!(mat -> (mat .= mat .* 2; mat), t1, :matrix_val)
        @test allocs == 0
        @info "with_property! Matrix allocations (broadcast): $allocs"
    end

    @testset "Custom callbacks allocation" begin
        allocs = @allocated get_property(t2, :int_val)
        @test allocs == 0
        @info "Custom int callback allocations: $allocs"
        allocs = @allocated get_property(t2, :any_val)
        # Note: stringify callback allocates because it creates a new string
        @info "Custom any->string callback allocations: $allocs"
        # Don't test allocs == 0 for string conversion as it inherently allocates
    end

    @testset "Multiple property operations" begin
        allocs = @allocated with_properties((i, f) -> i + f, t1, :int_val, :float_val)
        @test allocs == 0
        @info "with_properties allocations: $allocs"
    end

    @testset "with_properties allocation - vector and matrix" begin
        set_property!(t1, :vector_val, [1, 2, 3])
        set_property!(t1, :matrix_val, [1.0 2.0; 3.0 4.0])
        allocs = @allocated with_properties((v, m) -> (v .= v .* 2; m .= m .+ 10), t1, :vector_val, :matrix_val)
        @info "with_properties (vector, matrix) allocations: $allocs"
        @test allocs == 0
    end
end
