# Test allocation behavior of key accessors
using Test
using StaticKV

# Test struct with various key types
@kvstore AllocationTest begin
    bool_val::Bool => true
    char_val::Char => 'a'
    complex64_val::ComplexF32 => ComplexF32(1, 2)
    complex128_val::ComplexF64 => ComplexF64(3, 4)
    float16_val::Float16 => Float16(1.5)
    float32_val::Float32 => Float32(2.5)
    float_val::Float64 => 3.14
    int8_val::Int8 => Int8(1)
    int16_val::Int16 => Int16(3)
    int32_val::Int32 => Int32(5)
    int64_val::Int64 => Int64(7)
    int128_val::Int128 => Int128(9)
    int_val::Int => 42
    matrix_val::Matrix{Float64} => [1.0 2.0; 3.0 4.0]
    string_val::String => "test_string"
    symbol_val::Symbol => :test_symbol
    uint8_val::UInt8 => UInt8(2)
    uint16_val::UInt16 => UInt16(4)
    uint32_val::UInt32 => UInt32(6)
    uint64_val::UInt64 => UInt64(8)
    uint128_val::UInt128 => UInt128(10)
    vector_val::Vector{Int} => [1, 2, 3]
end

# Callback functions defined at module level
inc_callback(obj, key, val::T) where {T} = val + one(T)
stringify_callback(obj, key, val::T) where {T} = string(val)

# Test struct with custom callbacks
@kvstore CallbackTest begin
    int_val::Int => (42; on_get = inc_callback)
    any_val::Any => ("test"; on_get = stringify_callback)
end

function test_allocations()
    @info "Creating test objects for allocation tests..."
    t1 = AllocationTest()
    t2 = CallbackTest()

    # Function barriers for proper allocation testing
    function test_isbits_get_keyerty(obj, field, val)
        StaticKV.value!(obj, val, field)
        allocs = @allocated StaticKV.value(obj, field)
        @info "$(field) StaticKV.value allocations: $(allocs) bytes"
        allocs2 = @allocated isset(obj, field)
        @test allocs == 0
        @test allocs2 == 0
    end
    
    function test_isbits_set_keyerty(obj, field, val)
        allocs = @allocated StaticKV.value!(obj, val, field)
        @info "$(field) StaticKV.value! allocations: $(allocs) bytes"
        @test allocs == 0
    end

    # Warm up functions to ensure proper precompilation
    @info "Warming up functions..."
    StaticKV.value(t1, :int_val)
    StaticKV.value!(t1, 100, :int_val)
    isset(t1, :int_val)
    StaticKV.value(t2, :int_val)
    with_key(x -> x + 1, t1, :int_val)
    with_key!(v -> (v[1] = 1; v), t1, :vector_val)
    with_keys((i, f) -> i + f, t1, :int_val, :float_val)

    # Only keep one comprehensive isbits allocation testset (removes redundancy)
    @testset "StaticKV.value allocation - isbits (all)" begin
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
            test_isbits_get_keyerty(t1, field, val)
        end
    end

    @testset "StaticKV.value! allocation - isbits (all)" begin
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
            test_isbits_set_keyerty(t1, field, val)
        end
    end

    # Keep non-isbits and callback/mutable type allocation tests
    @testset "Symbol allocation" begin
        allocs1 = @allocated StaticKV.value(t1, :symbol_val)
        @info "Symbol StaticKV.value allocations: $(allocs1)"
        @test allocs1 == 0
        allocs2 = @allocated StaticKV.value!(t1, :new_symbol, :symbol_val)
        @info "Symbol StaticKV.value! allocations: $(allocs2)"
        @test allocs2 == 0
        allocs3 = @allocated isset(t1, :symbol_val)
        @info "Symbol isset allocations: $(allocs3)"
        @test allocs3 == 0
    end

    @testset "String allocation" begin
        allocs1 = @allocated StaticKV.value(t1, :string_val)
        @info "String StaticKV.value allocations: $allocs1"
        allocs2 = @allocated StaticKV.value!(t1, "new_string", :string_val)
        @info "String StaticKV.value! allocations: $allocs2"
        allocs3 = @allocated isset(t1, :string_val)
        @test allocs1 == 0
        @test allocs2 == 0
        @test allocs3 == 0
    end

    @testset "Vector allocation" begin
        allocs1 = @allocated StaticKV.value(t1, :vector_val)
        @info "Vector StaticKV.value allocations: $allocs1"
        allocs2 = @allocated StaticKV.value!(t1, [4, 5, 6], :vector_val)
        @info "Vector StaticKV.value! allocations: $allocs2"
        allocs3 = @allocated isset(t1, :vector_val)
        @test allocs1 == 0
        # Do not require allocs2 == 0: assigning a new array always allocates
        @test allocs3 == 0
    end

    @testset "Matrix allocation" begin
        allocs1 = @allocated StaticKV.value(t1, :matrix_val)
        @info "Matrix StaticKV.value allocations: $allocs1"
        allocs2 = @allocated StaticKV.value!(t1, [5.0 6.0; 7.0 8.0], :matrix_val)
        @info "Matrix StaticKV.value! allocations: $allocs2"
        allocs3 = @allocated isset(t1, :matrix_val)
        @test allocs1 == 0
        # Do not require allocs2 == 0: assigning a new array always allocates
        @test allocs3 == 0
    end

    @testset "with_key allocation - isbits" begin
        allocs = @allocated with_key(val -> val + 1, t1, :int_val)
        @test allocs == 0
        @info "with_key Int allocations: $allocs"
    end

    @testset "with_key allocation - Vector" begin
        allocs = @allocated with_key!(vec -> (push!(vec, 4); vec), t1, :vector_val)
        @info "with_key! Vector allocations (push!): $allocs"
        allocs = @allocated with_key!(vec -> (vec[1] = 99; vec), t1, :vector_val)
        @test allocs == 0
        @info "with_key! Vector allocations (index set): $allocs"
    end

    @testset "with_key allocation - Matrix" begin
        allocs = @allocated with_key!(mat -> (mat[1, 1] = 99.0; mat), t1, :matrix_val)
        @test allocs == 0
        @info "with_key! Matrix allocations (index set): $allocs"
        allocs = @allocated with_key!(mat -> (mat .= mat .* 2; mat), t1, :matrix_val)
        @test allocs == 0
        @info "with_key! Matrix allocations (broadcast): $allocs"
    end

    @testset "Custom callbacks allocation" begin
        allocs = @allocated StaticKV.value(t2, :int_val)
        @test allocs == 0
        @info "Custom int callback allocations: $allocs"
        allocs = @allocated StaticKV.value(t2, :any_val)
        # Note: stringify callback allocates because it creates a new string
        @info "Custom any->string callback allocations: $allocs"
        # Don't test allocs == 0 for string conversion as it inherently allocates
    end

    @testset "Multiple key operations" begin
        allocs = @allocated with_keys((i, f) -> i + f, t1, :int_val, :float_val)
        @test allocs == 0
        @info "with_keys allocations: $allocs"
    end

    @testset "with_keys allocation - vector and matrix" begin
        StaticKV.value!(t1, [1, 2, 3], :vector_val)
        StaticKV.value!(t1, [1.0 2.0; 3.0 4.0], :matrix_val)
        allocs = @allocated with_keys((v, m) -> (v .= v .* 2; m .= m .+ 10), t1, :vector_val, :matrix_val)
        @info "with_keys (vector, matrix) allocations: $allocs"
        @test allocs == 0
    end
end
