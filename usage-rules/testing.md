# Parrot Testing Rules

## Test-Driven Development

Parrot enforces TDD - write tests BEFORE implementation.

## Unit Testing Handlers

### Testing SipHandler

```elixir
defmodule MyApp.SipHandlerTest do
  use ExUnit.Case, async: true
  
  setup do
    {:ok, state} = MyApp.SipHandler.init(%{})
    {:ok, state: state}
  end
  
  test "accepts INVITE with valid codec", %{state: state} do
    request = %Parrot.Sip.Message{
      method: "INVITE",
      headers: %{
        "from" => %From{uri: %{user: "alice"}},
        "to" => %To{uri: %{user: "bob"}},
        "call-id" => "test-call-123"
      },
      body: valid_sdp_offer()
    }
    
    assert {:respond, 200, "OK", headers, sdp, _new_state} = 
      MyApp.SipHandler.handle_invite(request, state)
    
    assert headers["content-type"] == "application/sdp"
    assert sdp =~ "m=audio"
  end
  
  test "rejects INVITE with no common codec", %{state: state} do
    request = %{method: "INVITE", body: incompatible_sdp()}
    
    assert {:respond, 488, "Not Acceptable Here", _, _, _} = 
      MyApp.SipHandler.handle_invite(request, state)
  end
end
```

### Testing MediaHandler

```elixir
defmodule MyApp.MediaHandlerTest do
  use ExUnit.Case, async: true
  
  test "plays welcome message on stream start" do
    {:ok, state} = MyApp.MediaHandler.init(%{welcome: "welcome.wav"})
    
    assert {{:play, "welcome.wav"}, _state} = 
      MyApp.MediaHandler.handle_stream_start("session-1", :outbound, state)
  end
  
  test "handles high packet loss" do
    {:ok, state} = MyApp.MediaHandler.init(%{})
    
    stats = %{
      packet_loss_rate: 15.0,
      jitter: 50,
      packets_received: 1000,
      packets_lost: 150
    }
    
    # Should log warning but continue
    assert {:noreply, _state} = 
      MyApp.MediaHandler.handle_rtp_stats(stats, state)
  end
end
```

## Integration Testing

### Testing with real MediaSession

```elixir
test "full call flow with media" do
  # Start transport
  {:ok, _transport} = start_test_transport()
  
  # Simulate INVITE
  response = send_sip_request(invite_request())
  assert response.status == 200
  assert response.body =~ "m=audio"
  
  # Verify media session created
  assert {:ok, _pid} = Parrot.Media.MediaSession.get("test-call-123")
  
  # Send ACK
  send_sip_request(ack_request())
  
  # Wait for media to start
  :timer.sleep(100)
  
  # Send BYE
  response = send_sip_request(bye_request())
  assert response.status == 200
  
  # Verify cleanup
  :timer.sleep(100)
  assert {:error, :not_found} = Parrot.Media.MediaSession.get("test-call-123")
end
```

## SIPp Integration Tests

Parrot includes SIPp test scenarios:

```elixir
defmodule Parrot.SippTest do
  use ExUnit.Case
  
  @tag :sipp
  test "handles basic UAC scenario" do
    assert {:ok, _} = SippRunner.run_scenario("uac_invite.xml")
  end
  
  @tag :sipp
  test "handles CANCEL scenario" do
    assert {:ok, _} = SippRunner.run_scenario("uac_cancel.xml")
  end
end
```

Run SIPp tests:
```bash
mix test --only sipp
mix test test/sipp/test_scenarios.exs
```

## Test Helpers

Create helpers for common test data:

```elixir
defmodule Parrot.TestHelpers do
  def create_invite(opts \\ %{}) do
    %Parrot.Sip.Message{
      method: "INVITE",
      uri: opts[:uri] || "sip:bob@example.com",
      headers: build_headers(opts),
      body: opts[:sdp] || default_sdp_offer()
    }
  end
  
  def default_sdp_offer do
    """
    v=0
    o=alice 2890844526 IN IP4 10.0.0.1
    s=Session
    c=IN IP4 10.0.0.1
    t=0 0
    m=audio 49170 RTP/AVP 0 8
    a=rtpmap:0 PCMU/8000
    a=rtpmap:8 PCMA/8000
    """
  end
  
  def assert_valid_sdp_answer(sdp) do
    assert sdp =~ "v=0"
    assert sdp =~ "m=audio"
    assert sdp =~ "a=rtpmap:0 PCMU/8000"
  end
end
```

## Debugging Tests

Enable detailed logging:

```elixir
# In test
@moduletag capture_log: true

test "debug failing test" do
  # Logs will be captured and shown on failure
end

# From command line
LOG_LEVEL=debug mix test
SIP_TRACE=true mix test
```

## Testing State Machines

Test state transitions:

```elixir
test "transaction state transitions" do
  {:ok, pid} = start_test_transaction()
  
  # Verify initial state
  assert :trying = get_state(pid)
  
  # Send provisional response
  send_provisional(pid, 180)
  assert :proceeding = get_state(pid)
  
  # Send final response
  send_final(pid, 200)
  assert :completed = get_state(pid)
  
  # Send ACK
  send_ack(pid)
  assert :confirmed = get_state(pid)
end
```

## Performance Testing

```elixir
@tag :performance
test "handles concurrent calls" do
  tasks = for i <- 1..100 do
    Task.async(fn ->
      request = create_invite(call_id: "call-#{i}")
      assert {:respond, 200, _, _, _, _} = 
        MyApp.SipHandler.handle_invite(request, %{})
    end)
  end
  
  results = Task.await_many(tasks, 5000)
  assert length(results) == 100
end
```