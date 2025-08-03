# Parrot Framework Project Status

## Overview

The Parrot Framework is an Elixir-based telecom framework implementing the SIP (Session Initiation Protocol) stack with media handling capabilities. This document summarizes the current state of the project, testing procedures, and what remains to be built for production use.

## Current Implementation Status

### ✅ Completed Features

#### SIP Protocol Stack
- **Transport Layer**: UDP transport with connection management using gen_statem
- **Transaction Layer**: RFC 3261 compliant transaction state machines
- **Dialog Management**: Full dialog lifecycle management with gen_statem
- **Message Processing**: Complete SIP message parsing and serialization
- **UAS Support**: Can receive and handle incoming calls
- **Handler Pattern**: Flexible handler system for custom business logic

#### Media Foundation
- **MediaSession Management**: State machine for media session lifecycle
- **SDP Negotiation**: Offer/answer model implementation
- **Membrane Integration**: Basic audio pipeline using Membrane framework
- **Audio Playback**: G.711 μ-law audio file streaming
- **UDP Streaming**: Raw audio transmission (without RTP headers)

#### Testing Infrastructure
- **SIPp Integration**: Automated testing with industry-standard SIP testing tool
- **Multiple Test Scenarios**: Basic and extended call flow tests
- **Comprehensive Logging**: Detailed logging throughout the stack
- **Handler Examples**: Reference implementation for common use cases

### 🚧 Current Limitations

1. **No RTP Headers**: Audio is streamed as raw UDP packets without proper RTP encapsulation
2. **Single Codec**: Only G.711 μ-law is supported
3. **UAS Only**: Cannot initiate outbound calls (no UAC implementation)
4. **No Authentication**: SIP digest authentication not implemented
5. **UDP Transport Only**: No TCP or TLS support

## Testing the Framework

### Prerequisites

```bash
# Install Elixir/Erlang
brew install elixir  # macOS

# Install SIPp
brew install sipp    # macOS
# or
sudo apt-get install sipp  # Ubuntu/Debian

# Get dependencies
mix deps.get
```

### Running Tests

#### Option 1: Automated Tests
```bash
# Run all tests
mix test

# Run only SIP tests
mix test --only sipp

# Run specific test
mix test test/sipp/test_scenarios.exs:54
```

#### Option 2: Manual Testing

**Terminal 1 - Start Parrot Server:**
```elixir
iex -S mix

# Start SIP transport
Parrot.Sip.Transport.Supervisor.start_transport(:udp, %{
  listen_port: 5060,
  handler: %Parrot.Sip.Handler{
    module: Parrot.Sip.HandlerAdapter.Core,
    args: {ParrotSupport.SipHandler, %{}}
  }
})
```

**Terminal 2 - Run SIPp Client:**
```bash
# Basic 5-second call
sipp -sf test/sipp/scenarios/basic/uac_invite.xml -m 1 -l 1 127.0.0.1:5060

# 10-second call
sipp -sf test/sipp/scenarios/basic/uac_invite_long.xml -m 1 -l 1 127.0.0.1:5060

# Load test with 10 concurrent calls
sipp -sf test/sipp/scenarios/basic/uac_invite.xml -m 10 -l 10 -r 2 127.0.0.1:5060
```

### Verifying Media Streaming

#### Using the RTP Capture Tool
```bash
# Terminal 1: Start RTP capture
elixir scripts/test_rtp_capture.exs 6000

# Terminal 2: Run test
mix test test/sipp/test_scenarios.exs

# You'll see packet info in Terminal 1 (though without RTP headers currently)
```

#### Using tcpdump
```bash
# Capture UDP traffic
sudo tcpdump -i lo0 -w rtp_capture.pcap 'udp port 6000'

# Run test in another terminal
mix test test/sipp/test_scenarios.exs

# Analyze capture
tcpdump -r rtp_capture.pcap -nn
```

### Expected Test Results

When running tests, you should see:

1. **SIP Signaling**: 
   - INVITE → 100 Trying → 200 OK → ACK → BYE → 200 OK

2. **Log Messages**:
   ```
   [SipHandler] Generated SDP answer for dialog
   MediaSession: Starting media pipeline in ready state
   RtpPipeline: Pipeline is now PLAYING - audio streaming started
   ```

3. **Call Duration**:
   - Basic test: ~5 seconds
   - Long test: ~10 seconds

## Production Requirements

### Priority 1: Core Media Features

#### 1. RTP Implementation
The most critical missing piece. Currently sending raw audio without RTP headers.

**What's Needed:**
- RTP header generation (RFC 3550)
- Sequence number management
- Timestamp generation
- SSRC handling

**Example Implementation Started:**
See `lib/parrot/media/rtp/g711_payloader.ex` for a template

#### 2. RTCP Support
- Sender/Receiver Reports
- Quality metrics
- Synchronization

#### 3. Additional Codecs
- G.711 A-law (PCMA)
- G.729 (common in telecom)
- Opus (modern, high-quality)

### Priority 2: SIP Protocol Completion

#### 1. UAC Implementation
Enable outbound calling:
```elixir
Parrot.Sip.UAC.call("sip:user@example.com", %{
  media: true,
  codecs: [:pcmu, :pcma]
})
```

#### 2. Authentication
- Digest authentication (RFC 2617)
- Challenge/response handling
- Credential management

#### 3. Additional Transports
- TCP for reliability
- TLS for security
- WebSocket for WebRTC

### Priority 3: Advanced Features

#### 1. Media Recording
```elixir
MediaSession.start_recording(session_id, "/path/to/recording.wav")
```

#### 2. DTMF Support
- RFC 2833 (RTP events)
- SIP INFO method
- Inband detection

#### 3. Conference Bridge
```elixir
Conference.create("room-123")
Conference.add_participant("room-123", session_id)
```

## Architecture Highlights

### State Management
The framework makes extensive use of gen_statem for complex state machines:
- Transaction state machines (client/server)
- Dialog lifecycle management
- Transport connection states
- Media session states

### Supervision Tree
```
Parrot.Application
├── Parrot.Sip.Transport.Supervisor
├── Parrot.Sip.Transaction.Supervisor
├── Parrot.Sip.Dialog.Supervisor
├── Parrot.Media.MediaSessionSupervisor
└── Parrot.Sip.HandlerAdapter.Supervisor
```

### Handler Pattern
Flexible handler system allows custom business logic:
```elixir
defmodule MyHandler do
  use Parrot.Handler
  
  def handle_invite(request, state) do
    # Custom INVITE handling
    {:respond, 200, "OK", %{}, sdp_answer}
  end
end
```

## Development Roadmap

### Phase 1: RTP & Core Media (4-6 weeks)
- [ ] Implement RTP packetization
- [ ] Add RTCP support
- [ ] Support G.711 A-law
- [ ] Basic DTMF (RFC 2833)

### Phase 2: Protocol Completion (4-6 weeks)
- [ ] UAC implementation
- [ ] Digest authentication
- [ ] TCP transport
- [ ] REGISTER support

### Phase 3: Production Features (6-8 weeks)
- [ ] Media recording
- [ ] Connection pooling
- [ ] High availability
- [ ] Performance optimization

### Phase 4: Advanced Features (8-12 weeks)
- [ ] Conference bridge
- [ ] WebRTC gateway
- [ ] Advanced codecs
- [ ] Full monitoring

## Quick Start Example

```elixir
# Start a simple SIP server
{:ok, _pid} = Parrot.start_link(
  port: 5060,
  handler: MyApp.CallHandler
)

# In MyApp.CallHandler
defmodule MyApp.CallHandler do
  use Parrot.Handler
  
  def handle_invite(request, state) do
    # Auto-answer with music
    {:respond, 200, "OK", %{}, generate_sdp_answer(request)}
  end
  
  def handle_ack(_request, state) do
    # Start streaming audio
    :noreply
  end
  
  def handle_bye(_request, state) do
    # Clean up
    {:respond, 200, "OK", %{}, ""}
  end
end
```

## Getting Help

- **Documentation**: See `/docs` directory
- **Examples**: Check `/test/support/sip_handler.ex`
- **Tests**: Review `/test/sipp/scenarios/`
- **Issues**: Report at GitHub (when repository is public)

## Conclusion

The Parrot Framework provides a solid foundation for SIP-based applications in Elixir. While not yet production-ready due to missing RTP implementation and other features, the architecture is sound and the basic functionality works well. The use of gen_statem for state management and Membrane for media processing provides a robust and scalable foundation for future development.

For production use, focus on implementing RTP packetization first, then add authentication and additional codecs based on your specific requirements.