<p align="center">
  <img src="../assets/logo.svg" alt="Parrot Logo" width="200">
</p>


We are putting the 'T' back in OTP.

## What is Parrot?

Parrot Platform is a real-time communication platform built the Elixir way. Parrot Platform provides Elixir libraries and OTP behaviours implementing the SIP (Session Initiation Protocol) stack and leveraging Membrane multimedia libraries for media streaming. 

It providers:
- **Complete SIP Stack**: Full implementation of SIP transactions, dialogs, and message handling
- **Media Handling**: Integration with Membrane multimedia libraries for RTP audio streaming via MediaHandler behaviour
- **OTP Design Principles**: Built following Erlang/OTP design principles using gen_statem and GenServer


## Quick Start

> Build a Parrot VoIP Server and Client

First, install the Parrot generators:

```bash
mix archive.install hex parrot_new
```

Now you can quickly create both a VoIP server (UAS) and VoIP client (UAC) applications.

#### Step 1: Create a VoIP Server (UAS)

In one terminal:

```bash
# Generate a UAS application
mix parrot.gen.uas voip_server

# Navigate to the generated app
cd voip_server

# Fetch dependencies
mix deps.get

# Start the server
iex -S mix
iex> VoipServer.start()
[info] Starting PhoneServer on port 5060
```

Your SIP server is now running and can receive calls!

#### Step 2: Create a VoIP Client (UAC)

In another terminal:

```bash
# Generate a UAC application
mix parrot.gen.uac voip_client

# Navigate to the generated app
cd voip_client

# Fetch dependencies
mix deps.get

# Start the client
iex -S mix
iex> VoipClient.start()

# List audio devices (optional)
iex> VoipClient.list_audio_devices()

# Make a call to your server
# You will need to verify the output of the above list and adjust your device ids
iex> VoipClient.call("sip:service@127.0.0.1:5060", input_device: 0, output_device: 1)
```

#### What Just Happened?

You've created a complete SIP/Communication communication system with:
- A **UAS** (server) that receives calls and plays audio
- A **UAC** (client) that makes calls using your microphone and speakers for audio
- Audio using PMCA codec
- Proper SIP protocol handling (INVITE, ACK, BYE)

## Parrot Platform Platitudes

Some ideas we believe in...

### Voice is Just Data
Signaling and audio are not snowflakes. They're just streams of data — ready to be piped, transformed, stored, and reasoned about like any other data using Elixir.

### Code Over Configuration
Write logic in Elixir. Use functions, not complex configuration files.

### Distribution by Default
Every node is a citizen. No need for extra infrastructure if you don't want it — scaling just works.

_Brandon's NOTE: Distribution has not been tested. But, should work and be fun to test once I get there._

### Concurrency Without Contortion
Handle thousands of calls and sessions naturally — not with hacks or workarounds, but with Elixir's runtime: processes, message passing, and supervision.

_Brandon's NOTE: No load testing as been done, so the above is more of a goal for now. But, I'm hopeful!_

### Don’t Fight the Beam
Lean into OTP. Supervise ruthlessly. Let things crash and restart. Resilience isn’t bolted on — it’s baked in.

## Key Features

### Pure Elixir Implementation
Unlike other Elixir SIP libraries that wrap C/Erlang implementations, Parrot is written entirely in Elixir, making it easier to understand, extend, and debug.

### State Machine Based
Parrot uses Erlang's `gen_statem` behavior extensively for proper protocol state management:
- Transaction state machines following ([RFC 3261 Section 17](https://www.rfc-editor.org/rfc/rfc3261.html#section-17))
- Dialog lifecycle management ([RFC 3261 Section 12](https://www.rfc-editor.org/rfc/rfc3261.html#section-12))
- Transport connection handling ([RFC 3261 Section 18](https://www.rfc-editor.org/rfc/rfc3261.html#section-18))

### Handler Pattern
Parrot provides two complementary handler behaviours for building communication applications:

#### SipHandler
Build SIP applications by implementing simple handler callbacks with powerful pattern matching:

```elixir
defmodule MyApp.SipHandler do
  @behaviour Parrot.SipHandler

  alias Parrot.Sip.Headers.{From, To}

  # Pattern match when Alice calls Bob
  def handle_invite(%Parrot.Sip.Message{
        headers: %{
          "from" => %From{uri: %{user: "alice"}},
          "to" => %To{uri: %{user: "bob"}}
        }
      } = message, state) do
    sdp = generate_sdp_answer(message.body)
    {:respond, 200, "OK", %{"content-type" => "application/sdp"}, sdp, state}
  end

  # Use Guards when Bob calls Alice
  def handle_invite(message, state)
      when message.headers["from"].uri.user == "bob" and
           message.headers["to"].uri.user == "alice" do
    sdp = generate_sdp_answer(message.body)
    {:respond, 486, "Busy Here", %{}, "", state}
  end

  # Default handler for other calls
  def handle_invite(message, state) do
    # Other calls get rejected
    {:respond, 403, "Forbidden", %{}, "", state}
  end

  def handle_bye(message, state) do
    # Clean up resources
    {:respond, 200, "OK", %{}, "", state}
  end
end
```

#### MediaHandler
Control media sessions with dedicated callbacks for audio streaming:

```elixir
defmodule MyApp.MediaHandler do
  @behaviour Parrot.MediaHandler
  
  @impl true
  def init(args) do
    {:ok, %{
      welcome_file: args[:welcome_file] || "/audio/welcome.wav",
      menu_file: args[:menu_file] || "/audio/menu.wav"
    }}
  end
  
  @impl true
  def handle_session_start(_session_id, _opts, state) do
    # Called when media session is created
    {:ok, state}
  end
  
  @impl true
  def handle_codec_negotiation(offered, supported, state) do
    # Choose preferred codec from offered/supported lists
    cond do
      :pcmu in offered and :pcmu in supported -> {:ok, :pcmu, state}
      :pcma in offered and :pcma in supported -> {:ok, :pcma, state}
      true -> {:error, :no_common_codec, state}
    end
  end
  
  @impl true
  def handle_stream_start(_session_id, :outbound, state) do
    # Play welcome message when call connects
    {{:play, state.welcome_file}, Map.put(state, :stage, :welcome)}
  end
  
  @impl true
  def handle_play_complete(_file, %{stage: :welcome} = state) do
    # After welcome, play menu
    {{:play, state.menu_file}, Map.put(state, :stage, :menu)}
  end
  
  @impl true
  def handle_play_complete(_file, state) do
    # After menu, stop playback
    {:stop, state}
  end
  
  # Required callbacks with default implementations
  @impl true
  def handle_session_stop(_id, _reason, state), do: {:ok, state}
  
  @impl true
  def handle_offer(_sdp, _direction, state), do: {:noreply, state}
  
  @impl true
  def handle_answer(_sdp, _direction, state), do: {:noreply, state}
  
  @impl true
  def handle_negotiation_complete(_local, _remote, _codec, state), do: {:ok, state}
  
  @impl true
  def handle_stream_stop(_id, _reason, state), do: {:ok, state}
  
  @impl true
  def handle_stream_error(_id, _error, state), do: {:continue, state}
  
  @impl true
  def handle_media_request(_request, state), do: {:error, :not_implemented, state}
end
```

### Layer Responsibilities

- **Transport Layer**: Handles network I/O, connection management, and protocol-specific transport (UDP/TCP/WebSocket)
- **Transaction Layer**: Implements RFC 3261 transaction state machines for reliable message delivery
- **Dialog Layer**: Manages SIP dialog lifecycle and state, maintains dialog-specific data
- **Handler Layer**: Provides the application interface through behavior callbacks
- **Media Layer**: Handles RTP streams, codec negotiation, and audio processing through Membrane

Each layer is independently supervised and communicates through well-defined interfaces, allowing for fault isolation and recovery.

