# Parrot Platform Usage Rules

Parrot Platform provides Elixir libraries and OTP behaviours for building telecom applications with SIP protocol and media handling.

## Core Concepts

### Always use OTP behaviours
- Implement `Parrot.SipHandler` for SIP protocol events
- Implement `Parrot.MediaHandler` for media session events
- Both behaviours can be implemented in the same module

### Pattern matching is critical
Always use pattern matching on SIP messages instead of conditionals:

```elixir
# GOOD
def handle_invite(%{headers: %{"from" => %From{uri: %{user: "alice"}}}} = msg, state)
def handle_invite(%{method: "INVITE"} = msg, state)

# BAD
def handle_invite(msg, state) do
  if msg.headers["from"].uri.user == "alice" do
```

## Quick Start Pattern

```elixir
defmodule MyApp do
  use Parrot.SipHandler
  @behaviour Parrot.MediaHandler
  
  # SIP handler - handles protocol events
  def handle_invite(request, state) do
    {:ok, _pid} = Parrot.Media.MediaSession.start_link(
      id: generate_call_id(),
      role: :uas,
      media_handler: __MODULE__,
      handler_args: %{}
    )
    
    case Parrot.Media.MediaSession.process_offer(call_id, request.body) do
      {:ok, sdp_answer} -> {:respond, 200, "OK", %{}, sdp_answer}
      {:error, _} -> {:respond, 488, "Not Acceptable Here", %{}, ""}
    end
  end
  
  # MediaHandler - handles media events
  def handle_stream_start(_id, :outbound, state) do
    {{:play, "welcome.wav"}, state}
  end
end
```

## Key Modules

- `Parrot.Sip.Transport.StateMachine` - Start UDP/TCP transports
- `Parrot.Media.MediaSession` - Manage media sessions
- `Parrot.Sip.Message` - SIP message structure
- `Parrot.Sip.Dialog` - Dialog management

## Common Patterns

### Starting a UAS (server)
```elixir
handler = Parrot.Sip.Handler.new(MyApp.SipHandler, %{}, log_level: :info)
Parrot.Sip.Transport.StateMachine.start_udp(%{
  listen_port: 5060,
  handler: handler
})
```

### SipHandler callbacks
- `handle_invite/2` - Incoming calls
- `handle_ack/2` - Call confirmation  
- `handle_bye/2` - Call termination
- `handle_cancel/2` - Call cancellation
- `handle_response/2` - SIP responses
- `handle_request/2` - Other SIP methods

### MediaHandler callbacks
- `handle_stream_start/3` - Media begins, return `{:play, file}` to play audio
- `handle_play_complete/2` - Audio finished, return next action
- `handle_codec_negotiation/3` - Select codec preference

## Important Notes

- Uses gen_statem extensively (NOT just GenServer)
- SIP transactions and dialogs are state machines
- Media sessions integrate with Membrane multimedia libraries
- Pattern match on message structs for clean code
- Let it crash - supervisors handle failures

## Testing

```bash
# Run all tests
mix test

# Run SIPp integration tests
mix test test/sipp/test_scenarios.exs

# Enable SIP tracing
SIP_TRACE=true mix test
```

## Common Mistakes

1. **Not pattern matching** - Always pattern match SIP messages
2. **Fighting gen_statem** - Embrace state machines for transactions/dialogs
3. **Ignoring media callbacks** - Implement MediaHandler for audio
4. **Not handling all SIP methods** - Implement handle_request/2 fallback

## Example: Simple IVR

```elixir
defmodule MyIVR do
  use Parrot.SipHandler
  @behaviour Parrot.MediaHandler
  
  def init(_), do: {:ok, %{menu_files: ["welcome.wav", "menu.wav"]}}
  
  def handle_stream_start(_, :outbound, state) do
    {{:play, hd(state.menu_files)}, state}
  end
  
  def handle_play_complete(file, state) do
    remaining = tl(state.menu_files)
    if remaining == [] do
      {:stop, state}
    else
      {{:play, hd(remaining)}, %{state | menu_files: remaining}}
    end
  end
end
```