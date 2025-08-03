# Media Session Handler Requirements

## Overview

This document outlines the requirements for implementing a callback-based media session handler system in Parrot Platform, similar to the existing SIP handler pattern (`Parrot.SipHandler`). The media handler will provide a behavior for handling media-specific events during SIP calls, including SDP negotiation, codec selection, media stream lifecycle, and real-time media events.

## Goals

1. **Consistent API**: Follow the same patterns as `Parrot.SipHandler` for familiarity
2. **Extensibility**: Allow applications to handle media events without modifying core code
3. **State Management**: Maintain handler state across media session lifecycle
4. **Media Control**: Provide fine-grained control over media streams and processing
5. **Event-Driven**: React to media events as they occur

## Initial Implementation Scope

The first implementation will focus on core functionality:
- **Codec Support**: G.711 (PCMU/PCMA) and Opus only
- **RTP Statistics**: Packet loss, jitter, and quality monitoring
- **Basic Media Control**: Play, stop, pause, resume

Advanced features (DTMF, VAD, tone detection) will be addressed in future phases.

## Proposed Behavior: `Parrot.MediaHandler`

### Core Callbacks - Initial Implementation

The initial implementation will include only the essential callbacks needed for basic media handling with G.711/Opus codecs and RTP statistics.

#### 1. Session Lifecycle Callbacks

```elixir
@callback init(args :: term()) :: {:ok, state} | {:stop, reason :: term()}
```
Initialize the media handler when a new media session starts.

```elixir
@callback handle_session_start(session_id :: String.t(), opts :: keyword(), state) :: 
  {:ok, state} | {:error, reason :: term(), state}
```
Called when a media session is being established.

```elixir
@callback handle_session_stop(session_id :: String.t(), reason :: term(), state) :: 
  {:ok, state}
```
Called when a media session is terminating.

#### 2. SDP Negotiation Callbacks

```elixir
@callback handle_offer(sdp :: String.t(), direction :: :inbound | :outbound, state) :: 
  {:ok, modified_sdp :: String.t(), state} | 
  {:reject, reason :: term(), state} |
  {:noreply, state}
```
Process an SDP offer before it's handled by the media session. Can modify the SDP.

```elixir
@callback handle_answer(sdp :: String.t(), direction :: :inbound | :outbound, state) :: 
  {:ok, modified_sdp :: String.t(), state} | 
  {:reject, reason :: term(), state} |
  {:noreply, state}
```
Process an SDP answer before it's finalized.

```elixir
@callback handle_codec_negotiation(offered_codecs :: [atom()], supported_codecs :: [atom()], state) :: 
  {:ok, selected_codec :: atom(), state} | 
  {:ok, codec_list :: [atom()], state} |
  {:error, :no_common_codec, state}
```
Customize codec selection logic. Can return a single codec or ordered preference list.

```elixir
@callback handle_negotiation_complete(local_sdp :: String.t(), remote_sdp :: String.t(), selected_codec :: atom(), state) :: 
  {:ok, state} | 
  {:error, reason :: term(), state}
```
Called after SDP negotiation is complete with final parameters.

#### 3. Media Stream Callbacks

```elixir
@callback handle_stream_start(session_id :: String.t(), direction :: :inbound | :outbound | :bidirectional, state) :: 
  media_action() | {media_action(), state} | {[media_action()], state} | {:noreply, state}
```
Called when media stream is about to start. Can return media actions.

```elixir
@callback handle_stream_stop(session_id :: String.t(), reason :: term(), state) :: 
  {:ok, state}
```
Called when media stream stops.

```elixir
@callback handle_stream_error(session_id :: String.t(), error :: term(), state) :: 
  {:retry, state} | 
  {:continue, state} | 
  {:stop, reason :: term(), state}
```
Handle media stream errors.

#### 4. RTP Statistics Events (Initial Implementation)

```elixir
@callback handle_rtp_stats(stats :: map(), state) :: 
  {:noreply, state} | 
  {:adjust_quality, adjustment :: term(), state}
```
Called periodically with RTP statistics including packet loss, jitter, and round-trip time.

Stats map includes:
- `:packets_received` - Total packets received
- `:packets_lost` - Estimated packet loss count
- `:jitter` - Jitter buffer measurement in ms
- `:packet_loss_rate` - Loss percentage (0.0 to 100.0)

#### 5. Media Control Callbacks

```elixir
@callback handle_play_complete(file_path :: String.t(), state) :: 
  media_action() | {media_action(), state} | {:noreply, state}
```
Called when audio file playback completes.

```elixir
@callback handle_record_complete(file_path :: String.t(), duration :: non_neg_integer(), state) :: 
  {:ok, state} | {:error, reason :: term(), state}
```
Called when recording completes.

```elixir
@callback handle_media_request(request :: term(), state) :: 
  media_action() | {media_action(), state} | {:error, reason :: term(), state}
```
Handle custom media requests from the application.

### Media Actions - Initial Implementation

Media callbacks can return actions that the media session will execute:

```elixir
@type media_action ::
  {:play, file_path :: String.t()} |
  {:play, file_path :: String.t(), opts :: keyword()} |
  :stop |
  :pause |
  :resume |
  {:set_codec, codec :: :pcmu | :pcma | :opus} |
  :noreply
```

Note: Recording, audio injection, bridging, and tone detection will be added in future phases.

### Usage Example - Initial Implementation

```elixir
defmodule MyApp.MediaHandler do
  @behaviour Parrot.MediaHandler
  
  @impl true
  def init(_args) do
    {:ok, %{
      play_queue: [],
      preferred_codec: :opus,
      quality_threshold: 5.0  # 5% packet loss threshold
    }}
  end
  
  @impl true
  def handle_offer(sdp, :inbound, state) do
    # Initial implementation: pass through without modification
    {:noreply, state}
  end
  
  @impl true
  def handle_codec_negotiation(offered, supported, state) do
    # Prefer Opus > G.711μ > G.711A
    cond do
      :opus in offered and :opus in supported ->
        {:ok, :opus, state}
      :pcmu in offered and :pcmu in supported ->
        {:ok, :pcmu, state}
      :pcma in offered and :pcma in supported ->
        {:ok, :pcma, state}
      true ->
        # Pick first common codec
        codec = Enum.find(offered, fn c -> c in supported end)
        if codec do
          {:ok, codec, state}
        else
          {:error, :no_common_codec, state}
        end
    end
  end
  
  @impl true
  def handle_stream_start(_session_id, :inbound, state) do
    # Play welcome message when call starts
    {:play, "/audio/welcome.wav", state}
  end
  
  @impl true
  def handle_rtp_stats(stats, state) do
    # Monitor quality and potentially switch codecs
    if stats.packet_loss_rate > state.quality_threshold do
      Logger.warning("High packet loss detected: #{stats.packet_loss_rate}%")
      # Could switch to more resilient codec in future
      {:noreply, state}
    else
      {:noreply, state}
    end
  end
  
  @impl true
  def handle_play_complete(_file, state) do
    # Play next file in queue if any
    case state.play_queue do
      [next | rest] ->
        {:play, next, %{state | play_queue: rest}}
      [] ->
        {:noreply, state}
    end
  end
end
```

## Integration with Existing Code

### 1. MediaSession Module Changes

The `Parrot.Media.MediaSession` module (which uses gen_statem) will need to be updated to:

- Accept a media handler in its start options
- Call handler callbacks at appropriate points within state transitions
- Process media actions returned by callbacks
- Pass handler state through the session lifecycle

**Key integration points in MediaSession's gen_statem states:**
- `init/1` - Initialize handler in addition to state machine
- `idle` state - Handle initial setup with handler
- `negotiating` state - Call `handle_offer/3` and `handle_codec_negotiation/3`
- `ready` state - Call `handle_stream_start/3` when transitioning to active
- `active` state - Periodically call `handle_rtp_stats/2` with statistics
- All states - Forward media actions from handler callbacks

The gen_statem architecture remains unchanged - we're adding handler callbacks at key points in the existing state machine.

### 2. Initial Media Infrastructure

For the initial implementation, we'll add:

- **RTP Statistics Collection**: Use existing Membrane modules:
  - `Membrane.RTP.InboundTracker` for incoming packet statistics
  - `Membrane.RTP.OutboundTracker` for outgoing packet statistics
  - `Membrane.RTCP.Parser` for RTCP report processing
- **Codec Support**: 
  - G.711 (already supported via `membrane_g711_plugin`)
  - Opus (requires adding `membrane_opus_plugin` dependency)

### 3. Handler Adapter Pattern

Similar to SIP handler adapters, we may want:

```elixir
defmodule Parrot.Media.HandlerAdapter do
  @moduledoc """
  Adapts media handlers to work with the media session state machine.
  """
  
  def start_link(handler_module, handler_args, session_opts) do
    # Start a GenServer that wraps the handler
  end
end
```

### 4. Configuration

Media handlers would be configured at the application or call level:

```elixir
# In SIP handler
def handle_invite(msg, state) do
  # Start media session with custom handler
  {:ok, session} = MediaSession.start_link(
    id: generate_id(),
    media_handler: MyApp.MediaHandler,
    handler_args: %{mode: :ivr}
  )
  
  # Continue with normal INVITE processing
end
```

## Implementation Phases

### Phase 1: Initial Implementation (Current Focus)
- Define `Parrot.MediaHandler` behaviour with core callbacks
- Update `MediaSession` to support handlers
- Implement G.711 and Opus codec support
- Add RTP statistics collection and reporting
- Basic media actions (play, stop, pause, resume)
- Comprehensive unit and integration tests

### Phase 2: Future Enhancements
- **DTMF Support**: RFC 4733 implementation (~200-300 lines)
- **Voice Activity Detection**: Silero VAD integration
- **Recording**: Audio capture to files
- **Advanced Media Actions**: Volume control, audio injection
- **Tone Detection**: Fax, busy signals, etc.
- **Media Bridging**: Connect multiple sessions

## Membrane Plugin Support for Initial Implementation

### 1. G.711 Codec Support
**Status**: Fully Available
- `membrane_g711_plugin` - Encoding/decoding for both μ-law (PCMU) and A-law (PCMA)
- `membrane_rtp_g711_plugin` - RTP payloader/depayloader for G.711
- Already integrated in existing Parrot pipelines

### 2. Opus Codec Support
**Status**: Available (needs to be added)
- `membrane_opus_plugin` - Opus encoder/decoder
- `membrane_rtp_opus_plugin` - RTP payloader/depayloader for Opus
- High quality, low latency codec ideal for VoIP
- Requires adding to mix.exs dependencies

### 3. RTP Statistics & Quality Monitoring
**Status**: Partially available, sufficient for initial implementation
- **Available in membrane_rtp_plugin**:
  - `Membrane.RTP.InboundTracker` - Tracks incoming packet statistics
  - `Membrane.RTP.OutboundTracker` - Tracks outgoing packet statistics
  - `Membrane.RTCP.Parser` - Parses RTCP reports with quality metrics
  - `Membrane.RTP.JitterBuffer` - Provides jitter measurements
- **Custom implementation needed**: Calculate packet loss percentage from tracker data

## Future Feature Roadmap

### DTMF Detection (RFC 4733) - Phase 2
- Not available in Membrane, requires custom element (~200-300 lines)
- Parse RTP telephone-event payload (PT 101)

### Voice Activity Detection (VAD) - Phase 2
- Silero VAD integration (requires `ortex` and `nx`)
- Or Membrane RTC Engine's VAD extension

### Additional Features - Phase 3+
- Tone detection (custom DSP)
- Recording capabilities
- Audio mixing/bridging
- Echo cancellation

## Test-Driven Development (TDD) Requirements

Following Parrot Platform's TDD enforcement policy (as specified in CLAUDE.md), all media handler implementations MUST follow strict TDD principles:

### 1. Unit Tests First - Initial Implementation Focus

Before implementing any callback or feature, write comprehensive unit tests:

```elixir
# test/parrot/media/handler_test.exs
defmodule Parrot.Media.HandlerTest do
  use ExUnit.Case, async: true
  
  describe "handle_codec_negotiation/3" do
    test "selects opus when available in both lists" do
      # Write this test BEFORE implementing the callback
      handler_state = %{preferred_codec: :opus}
      offered = [:pcmu, :opus, :pcma]
      supported = [:opus, :pcmu, :pcma]
      
      assert {:ok, :opus, ^handler_state} = 
        TestHandler.handle_codec_negotiation(offered, supported, handler_state)
    end
    
    test "falls back to G.711 when opus not available" do
      handler_state = %{preferred_codec: :opus}
      offered = [:pcmu, :pcma]
      supported = [:opus, :pcmu, :pcma]
      
      assert {:ok, :pcmu, ^handler_state} = 
        TestHandler.handle_codec_negotiation(offered, supported, handler_state)
    end
  end
  
  describe "handle_rtp_stats/2" do
    test "monitors packet loss and jitter" do
      handler_state = %{quality_threshold: 5.0}
      stats = %{
        packets_received: 1000,
        packets_lost: 50,
        packet_loss_rate: 5.0,
        jitter: 20
      }
      
      assert {:noreply, ^handler_state} = 
        TestHandler.handle_rtp_stats(stats, handler_state)
    end
  end
end
```

### 2. Integration Tests with MediaSession

Test the handler with real MediaSession interactions:

```elixir
# test/parrot/media/media_session_handler_integration_test.exs
defmodule Parrot.Media.MediaSessionHandlerIntegrationTest do
  use ExUnit.Case
  
  test "media session calls handler callbacks in correct order" do
    # Test the full lifecycle
  end
end
```

### 3. Property-Based Tests

For codec negotiation and SDP manipulation:

```elixir
property "always selects a codec that exists in both offered and supported lists" do
  check all offered <- list_of(codec_generator()),
            supported <- list_of(codec_generator()) do
    # Property test implementation
  end
end
```

### 4. Mock Membrane Elements

Create test doubles for Membrane elements:

```elixir
defmodule Test.Membrane.MockRTPSource do
  # Mock RTP source for testing DTMF events
end
```

## Architecture Decision: gen_statem vs GenServer

### Why gen_statem for MediaSession

The existing `Parrot.Media.MediaSession` correctly uses `gen_statem` because:

1. **Complex State Transitions**: Media sessions have distinct states (idle → negotiating → ready → active → terminating)
2. **State-Specific Behavior**: Different callbacks are valid in different states
3. **RFC Compliance**: Media state machines align with telecom standards
4. **Consistency**: Matches the architecture pattern used in SIP components

### Why GenServer for MediaHandler

The MediaHandler should use GenServer (via the adapter pattern) because:

1. **Simple Request/Response**: Handlers primarily respond to events without complex state machines
2. **Stateless Callbacks**: Most callbacks don't depend on specific states
3. **Flexibility**: Applications can implement their own state management
4. **Performance**: Less overhead than gen_statem for simple event handling

### Implementation Pattern

```elixir
defmodule Parrot.Media.HandlerAdapter do
  use GenServer
  
  # Wraps the handler callbacks in a GenServer
  def init({handler_module, handler_args}) do
    case handler_module.init(handler_args) do
      {:ok, handler_state} ->
        {:ok, %{
          handler_module: handler_module,
          handler_state: handler_state
        }}
      {:stop, reason} ->
        {:stop, reason}
    end
  end
  
  # Forward events to handler callbacks
  def handle_call({:handle_dtmf, digit, duration}, _from, state) do
    case state.handler_module.handle_dtmf(digit, duration, state.handler_state) do
      {:noreply, new_handler_state} ->
        {:reply, :ok, %{state | handler_state: new_handler_state}}
      {action, new_handler_state} ->
        {:reply, {:action, action}, %{state | handler_state: new_handler_state}}
    end
  end
end
```

This architecture provides:
- Clean separation of concerns
- Predictable behavior
- Easy testing
- Flexibility for applications

## Testing Strategy - Initial Implementation

1. **Unit Tests**: 
   - Test codec negotiation logic with G.711 and Opus
   - Test RTP statistics handling
   - Test media action returns (play, stop, pause, resume)
   
2. **Integration Tests**: 
   - Test handler integration with MediaSession
   - Verify RTP statistics collection from Membrane
   - Test codec switching based on quality metrics
   
3. **Example Handlers**: 
   - Simple announcement server (G.711/Opus)
   - Quality monitoring handler
   - Adaptive codec selector based on network conditions

## Open Questions for Initial Implementation

1. **Opus Dependencies**: Should we add `membrane_opus_plugin` to mix.exs now or make it optional?
2. **Statistics Frequency**: How often should RTP statistics be reported to handlers (every second, 5 seconds)?
3. **Codec Switching**: Should the initial implementation support dynamic codec switching based on quality?

## Backward Compatibility

The media handler system will be optional. Existing code using MediaSession directly will continue to work. The handler system provides an additional layer of abstraction for applications that need it.

## Summary

The initial implementation focuses on:
- Core handler callbacks for session lifecycle and codec negotiation
- G.711 (PCMU/PCMA) and Opus codec support
- RTP statistics monitoring (packet loss, jitter)
- Basic media control (play, stop, pause, resume)
- Comprehensive TDD approach
- **MediaSession continues to use gen_statem** for complex state management
- MediaHandler callbacks are simplified but work within the existing gen_statem architecture

Future phases will add DTMF, VAD, recording, and other advanced features as outlined in the roadmap.