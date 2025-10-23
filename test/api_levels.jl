# Test the distinction between internal and external API levels
using Test
using StaticKV

# Define a message type with read-only external access
@kvstore TestMessage begin
    payload::String => (; access = AccessMode.READABLE)
    timestamp::Int => (; access = AccessMode.READABLE)
    internal_state::Vector{String} => (String[]; access = AccessMode.READABLE_ASSIGNABLE_MUTABLE)
end

function test_api_levels()
    @testset "API Levels: Internal vs External" begin
        msg = TestMessage()
        
        # Test internal API (value/value!) can write to read-only fields (bypasses access control)
        @test StaticKV.value!(msg, "internal data", :payload) == "internal data"
        @test StaticKV.value!(msg, 12345, :timestamp) == 12345
        @test StaticKV.value(msg, :payload) == "internal data"
        @test StaticKV.value(msg, :timestamp) == 12345
        
        # Test external API can read but not write to read-only fields
        @test getindex(msg, :payload) == "internal data"
        @test getindex(msg, :timestamp) == 12345
        @test_throws ErrorException setindex!(msg, "hacked", :payload)
        @test_throws ErrorException setindex!(msg, 99999, :timestamp)
        
        # Verify values didn't change after failed external write
        @test getindex(msg, :payload) == "internal data"
        @test getindex(msg, :timestamp) == 12345
        
        # Test external API works normally for fully accessible fields
        @test setindex!(msg, ["external"], :internal_state) == ["external"]
        @test getindex(msg, :internal_state) == ["external"]
        
        # Test internal API also works for fully accessible fields
        @test StaticKV.value!(msg, ["internal"], :internal_state) == ["internal"]
        @test StaticKV.value(msg, :internal_state) == ["internal"]
    end
    
    @testset "Use Case: Messaging System" begin
        # Simulate a messaging system scenario
        
        # Internal function - processes incoming messages (uses unchecked value/value!)
        function process_incoming!(msg::TestMessage, data::String)
            StaticKV.value!(msg, data, :payload)
            StaticKV.value!(msg, Int(time_ns()), :timestamp)
        end
        
        # External function - user tries to modify message
        function user_modify!(msg::TestMessage, data::String)
            setindex!(msg, data, :payload)  # Should fail
        end
        
        # External function - user reads message
        function user_read(msg::TestMessage)
            return getindex(msg, :payload)
        end
        
        msg = TestMessage()
        
        # Internal processing works
        process_incoming!(msg, "system message")
        @test StaticKV.value(msg, :payload) == "system message"
        @test isset(msg, :timestamp)
        
        # External read works
        @test user_read(msg) == "system message"
        
        # External write fails
        @test_throws ErrorException user_modify!(msg, "hacked message")
        
        # Verify message wasn't tampered with
        @test user_read(msg) == "system message"
    end
end
