# Testing Guide

This guide covers testing strategies for applications using the Parrot Framework, including unit tests, integration tests, and testing with real SIP clients.

## Prerequisites

- Elixir 1.15 or later
- SIPp (Session Initiation Protocol performance testing tool)
- ffmpeg (for audio file conversions)
- A SIP client for manual testing (e.g., Linphone, MicroSIP, Zoiper)

## Running Tests

### Unit Tests

Run all unit tests:
```bash
mix test
```

Run tests for a specific module:
```bash
mix test test/parrot/sip/transaction_test.exs
```

Run a specific test:
```bash
mix test test/parrot/sip/transaction_test.exs:42
```

Run tests with coverage:
```bash
mix test --cover
```

### Integration Tests with SIPp

The framework includes SIPp scenarios for testing SIP protocol compliance:

```bash
# Run all SIPp tests
mix test test/sipp/test_scenarios.exs

# Run specific scenario
mix test test/sipp/test_scenarios.exs --only uac_invite
```

#### Available SIPp Scenarios

1. **Basic INVITE** (`uac_invite.xml`)
   - Tests basic call setup and teardown
   - Validates SIP transaction handling

2. **Long INVITE** (`uac_invite_long.xml`)
   - Tests longer duration calls
   - Validates dialog state management

3. **INVITE with RTP** (`uac_invite_rtp.xml`)
   - Tests calls with RTP media
   - Validates SDP negotiation

4. **OPTIONS** (`uac_options.xml`)
   - Tests OPTIONS method handling
   - Validates capability queries

## Manual Testing with SIP Clients

### Starting the Test Server

```bash
# Start the server with IEx
iex -S mix

# In IEx, start a UAS (User Agent Server)
{:ok, _pid} = Parrot.Sip.UAS.start_link(
  port: 5060,
  handler: YourApp.SipHandler
)
```

### Configuring SIP Clients

Configure your SIP client with:
- **Server/Proxy**: Your machine's IP address
- **Port**: 5060 (or your configured port)
- **Username**: Any value (authentication not required for testing)
- **Transport**: UDP

### Testing Call Flows

1. **Basic Call**
   - Register your SIP client (if required)
   - Make a call to any number
   - Verify INVITE is received and processed
   - Verify RTP streams if media is enabled

2. **DTMF Testing**
   - During a call, press digits
   - Verify DTMF events are received

3. **Hold/Resume**
   - Place call on hold
   - Verify re-INVITE with appropriate SDP

## Testing Media Handlers

### Creating Test Media Handlers

```elixir
defmodule TestMediaHandler do
  use Parrot.MediaHandler

  @impl true
  def init(config) do
    {:ok, %{config: config, events: []}}
  end

  @impl true
  def handle_audio(audio_data, format, state) do
    # Store or process audio for testing
    {:ok, %{state | events: [{:audio, byte_size(audio_data)} | state.events]}}
  end

  @impl true
  def handle_dtmf(digit, state) do
    {:ok, %{state | events: [{:dtmf, digit} | state.events]}}
  end
end
```

### Testing RTP Streams

Use the provided test scripts:

```bash
# Generate test audio
./scripts/generate_test_audio.sh

# Test RTP streaming
mix run scripts/test_rtp_flow.exs

# Debug RTP packets
mix run scripts/debug_rtp_stream.exs
```

## Troubleshooting Test Failures

### Common Issues

1. **Port Already in Use**
   ```bash
   # Find process using port 5060
   lsof -i :5060
   # Kill the process if needed
   kill -9 <PID>
   ```

2. **SIPp Test Timeouts**
   - Check firewall settings
   - Verify localhost resolves correctly
   - Increase timeout in test configuration

3. **RTP Media Issues**
   - Verify audio files are in correct format (8kHz, mono)
   - Check RTP port range is available (10000-20000)
   - Enable RTP packet logging for debugging

### Debugging Tips

1. **Enable Verbose Logging**
   ```elixir
   # In config/test.exs
   config :logger, level: :debug
   ```

2. **Capture SIP Traffic**
   ```bash
   # Using tcpdump
   sudo tcpdump -i any -w sip_capture.pcap port 5060
   
   # Using ngrep
   sudo ngrep -d any -W byline port 5060
   ```

3. **Inspect State Machines**
   ```elixir
   # Get transaction state
   {:ok, state} = Parrot.Sip.Transaction.get_state(transaction_pid)
   
   # Get dialog state
   {:ok, dialog} = Parrot.Sip.Dialog.get_state(dialog_id)
   ```

## Performance Testing

For load testing, use SIPp with higher call rates:

```bash
# 10 calls per second, maximum 100 concurrent
sipp -sf scenarios/uac_invite.xml -r 10 -l 100 -m 1000 localhost:5060
```

Monitor performance metrics:
- Memory usage: `:erlang.memory()`
- Process count: `length(:erlang.processes())`
- Message queue lengths

## Writing Your Own Tests

### Testing SIP Handlers

```elixir
defmodule YourApp.SipHandlerTest do
  use ExUnit.Case
  alias Parrot.Sip.Message

  test "handles INVITE request" do
    handler = YourApp.SipHandler
    invite = Message.build_request("INVITE", "sip:user@example.com")
    
    assert {:ok, response} = handler.handle_request(invite, %{})
    assert response.status == 200
  end
end
```

### Testing Media Processing

```elixir
defmodule YourApp.MediaTest do
  use ExUnit.Case

  test "processes G.711 audio" do
    audio_data = File.read!("test/fixtures/sample.pcmu")
    format = %{encoding: :pcmu, sample_rate: 8000}
    
    {:ok, processed} = YourApp.MediaProcessor.process(audio_data, format)
    assert byte_size(processed) == byte_size(audio_data)
  end
end
```

## Continuous Integration

Example GitHub Actions workflow:

```yaml
name: Tests
on: [push, pull_request]

jobs:
  test:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v2
      - uses: erlef/setup-beam@v1
        with:
          elixir-version: '1.15'
          otp-version: '26.0'
      - run: mix deps.get
      - run: mix test
      - run: mix format --check-formatted
```