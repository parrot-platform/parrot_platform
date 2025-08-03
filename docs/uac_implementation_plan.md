# UAC Implementation Plan

## Status: Partially Complete ✅

### Completed Items
- ✅ `Parrot.UacHandler` behavior module
- ✅ `Parrot.Sip.UacHandlerAdapter` for bridging low-level and high-level APIs
- ✅ Comprehensive tests for UacHandler
- ✅ Renamed `Parrot.SipHandler` to `Parrot.UasHandler` for consistency
- ✅ Audio device support via PortAudio plugin
- ✅ `Parrot.Media.AudioDevices` for device discovery
- ✅ `Parrot.Media.PortAudioPipeline` for bidirectional audio
- ✅ MediaSession updated with audio_source/audio_sink configuration

### Remaining Work
- 🔲 Mix task generator (`mix parrot.gen.uac`)
- 🔲 Example UAC application
- 🔲 Integration tests with UAS
- 🔲 Mix task `pa_devices` for listing audio devices
- 🔲 DTMF support for audio device pipelines
- 🔲 Audio level monitoring

## Overview
This document outlines the work needed to implement a proper UAC (User Agent Client) system in Parrot that mirrors the existing UAS (User Agent Server) architecture. Currently, Parrot has a well-developed UAS handler system but lacks an equivalent high-level interface for UAC operations.

## Current State

### What Exists
1. **`Parrot.Sip.UAS`** - Low-level UAS protocol handling
2. **`Parrot.Sip.UAC`** - Low-level UAC protocol handling (uses callbacks)
3. **`Parrot.SipHandler`** - High-level behavior for implementing UAS handlers
4. **`ParrotExampleUas`** - Example UAS implementation using `Parrot.SipHandler`

### What's Missing
1. ~~**`Parrot.UacHandler`** - High-level behavior for implementing UAC handlers~~ ✅ DONE
2. ~~**`Parrot.Sip.UacHandlerAdapter`** - Adapter to bridge low-level UAC with high-level handler~~ ✅ DONE
3. **Mix task for UAC** - Similar to `mix parrot.gen.uas`
4. **Example UAC implementation** - Using the handler pattern

## Implementation Tasks

### 1. ✅ Create `Parrot.UacHandler` Behavior
Location: `lib/parrot/uac_handler.ex`

**COMPLETED** - The UacHandler behavior has been implemented with:
- Full callback definitions for all response types
- Default implementations via `use Parrot.UacHandler`
- Comprehensive documentation with examples
- Support for ACK sending and redirect following

### 2. ✅ Create UAC Handler Adapter
Location: `lib/parrot/sip/uac_handler_adapter.ex`

**COMPLETED** - The adapter successfully bridges the low-level UAC callback mechanism with the high-level handler pattern:
- Routes responses to appropriate handler callbacks based on status code
- Handles automatic ACK sending for INVITE 200 OK
- Supports redirect following
- Manages handler state across callbacks
- Includes test mode support

### 3. Create Mix Task Generator
Location: `lib/mix/tasks/parrot.gen.uac.ex`

Similar to `parrot.gen.uas`, this should generate a new UAC application:

```elixir
defmodule Mix.Tasks.Parrot.Gen.Uac do
  @shortdoc "Generates a new Parrot UAC application"
  
  def run(args) do
    # Generate:
    # - UAC handler module
    # - Supervisor
    # - Application module
    # - Example configuration
  end
end
```

### 4. Create Example UAC Application
Location: `examples/parrot_example_uac/`

A complete example showing:
- Making outbound calls
- Handling responses
- Media session integration with ex_sdp
- Proper cleanup

### 5. Create Simple UAC Mix Task
Location: `lib/mix/tasks/parrot.uac.ex`

A runnable UAC client for testing:

```bash
mix parrot.uac --to sip:service@127.0.0.1:5060 --duration 10
```

Features:
- Use the UacHandler pattern
- Support media with ex_sdp
- Configurable options (port, audio file, duration)
- Proper state management

### 6. Integration Points

#### With Media Sessions
- UAC should create media sessions with `role: :uac`
- Use `MediaSession.generate_offer/1` for SDP offer
- Use `MediaSession.process_answer/2` for SDP answer
- Start media after ACK is sent

#### With Transport Layer
- Reuse existing transport infrastructure
- Start transport with handler configuration
- Let transport handle retransmissions

## Testing Plan

### 1. Unit Tests
Location: `test/parrot/uac_handler_test.exs`

Test:
- Callback routing based on response codes
- State management across callbacks
- Error handling

### 2. Integration Tests
Location: `test/integration/uac_uas_test.exs`

Test complete call flow:
1. Start UAS example on port 5060
2. Start UAC to call the UAS
3. Verify INVITE -> 200 OK -> ACK flow
4. Verify media session establishment
5. Send BYE and verify cleanup

### 3. SIPp Tests
Add UAC scenarios to `test/sipp/scenarios/`:
- `uac_basic_call.xml` - Basic outbound call
- `uac_call_failure.xml` - Handle various error responses
- `uac_cancel.xml` - CANCEL handling

## Code Refactoring Notes

### Future: Rename for Consistency
1. `Parrot.SipHandler` → `Parrot.UasHandler`
2. Update all references in documentation
3. Update example applications
4. Add deprecation warnings

### Handler State Management
Consider creating a GenServer-based UAC client that:
- Maintains handler state
- Manages multiple concurrent calls
- Provides a cleaner API

## Example Usage

```elixir
defmodule MyApp.CallClient do
  use Parrot.UacHandler
  
  @impl true
  def init(args) do
    {:ok, %{calls: %{}}}
  end
  
  @impl true
  def handle_provisional(%{status: 180} = response, state) do
    IO.puts("Phone is ringing...")
    {:ok, state}
  end
  
  @impl true
  def handle_success(%{status: 200} = response, state) do
    IO.puts("Call answered!")
    # Process SDP answer, send ACK
    {:ok, state}
  end
end

# Making a call:
{:ok, _pid} = MyApp.CallClient.start_link()
MyApp.CallClient.call("sip:alice@example.com")
```

## Dependencies
- Existing Parrot.Sip.UAC module
- Media.MediaSession for SDP handling
- ex_sdp for SDP generation/parsing
- Transport layer for SIP messaging

## Success Criteria
1. UAC can make calls to the existing UAS example
2. Media sessions work bidirectionally
3. Clean handler-based API similar to UAS
4. All SIPp tests pass
5. Mix tasks work reliably
6. Documentation is complete