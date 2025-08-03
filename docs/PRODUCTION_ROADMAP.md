# Parrot Production Roadmap

This document outlines the remaining work needed to make Parrot a production-ready SIP/media library.

## Current State ✅

### Completed
- **SIP Protocol Stack**
  - Transport layer (UDP)
  - Transaction layer (RFC 3261 compliant state machines)
  - Dialog management with gen_statem
  - Basic message parsing and serialization
  - UAS (User Agent Server) support
  
- **Media Foundation**
  - MediaSession state management
  - SDP offer/answer negotiation
  - Basic Membrane pipeline integration
  - G.711 μ-law audio file playback
  - Raw audio streaming via UDP

- **Testing Infrastructure**
  - SIPp integration tests
  - Handler pattern for custom logic
  - Comprehensive logging

## Priority 1: Core Media Features 🚨

### 1. Proper RTP Implementation
**Status**: Currently sending raw audio without RTP headers
**Needed**:
```elixir
# Implement custom RTP payloader since Membrane.RTP.G711.Payloader doesn't exist
defmodule Parrot.Media.RTP.G711Payloader do
  use Membrane.Filter
  
  # Add RTP headers (RFC 3550)
  # - Version, Padding, Extension, CSRC count
  # - Marker bit, Payload type (0 for PCMU)
  # - Sequence number (increment)
  # - Timestamp (8kHz clock)
  # - SSRC (synchronization source)
end
```

### 2. RTCP Support
**Status**: Not implemented
**Needed**:
- Sender Reports (SR)
- Receiver Reports (RR)
- Source Description (SDES)
- Bye packets

### 3. Multiple Codec Support
**Status**: Only G.711 μ-law
**Needed**:
- G.711 A-law (PCMA)
- G.729
- G.722 (HD voice)
- Opus (modern codec)
- Codec negotiation in SDP

## Priority 2: Advanced Media Features 📞

### 1. Media Recording
```elixir
defmodule Parrot.Media.Recorder do
  # Record calls to files
  # Support for mixed/unmixed streams
  # Multiple formats (wav, mp3, etc.)
end
```

### 2. Media Playback Control
- Pause/Resume
- Seek
- Speed control
- Playlist support

### 3. DTMF Support
- RFC 2833 (RTP Events)
- SIP INFO method
- Inband DTMF detection

### 4. Echo Cancellation
- Acoustic echo cancellation
- Line echo cancellation

## Priority 3: SIP Protocol Completion 📡

### 1. UAC (User Agent Client) Support
```elixir
defmodule Parrot.Sip.UAC do
  # Initiate outbound calls
  # Handle authentication challenges
  # DNS resolution for SIP URIs
end
```

### 2. Authentication
- Digest authentication (RFC 2617)
- TLS/SRTP support
- Client certificates

### 3. Additional Transports
- TCP transport
- TLS transport
- WebSocket transport (for WebRTC)

### 4. Missing SIP Methods
- REGISTER (for SIP registration)
- REFER (call transfer)
- NOTIFY/SUBSCRIBE (presence, events)
- UPDATE
- PRACK (reliable provisional responses)

## Priority 4: Scalability & Reliability 🚀

### 1. Connection Pooling
```elixir
defmodule Parrot.Sip.Transport.Pool do
  # Reuse UDP/TCP connections
  # Load balancing
  # Failover support
end
```

### 2. High Availability
- Dialog replication
- State persistence
- Cluster support

### 3. Performance Optimizations
- Binary protocol optimizations
- ETS for fast lookups
- Flow control
- Back-pressure handling

## Priority 5: Advanced Features 🎯

### 1. Conference Bridge
```elixir
defmodule Parrot.Media.Conference do
  use Membrane.Pipeline
  
  # Multi-party audio mixing
  # Participant management
  # Recording support
end
```

### 2. IVR Support
- Menu systems
- Voice prompts
- Speech recognition integration
- Text-to-speech

### 3. WebRTC Gateway
- SIP to WebRTC bridging
- ICE/STUN/TURN support
- Media transcoding

### 4. Monitoring & Analytics
- Call quality metrics (MOS scores)
- Real-time dashboard
- OpenTelemetry integration
- SIP message tracing

## Implementation Plan

### Phase 1: RTP & Basic Codecs (4-6 weeks)
1. Implement RTP packetization
2. Add RTCP support
3. Add G.711 A-law support
4. Basic DTMF (RFC 2833)

### Phase 2: UAC & Authentication (4-6 weeks)
1. UAC implementation
2. Digest authentication
3. TCP transport
4. REGISTER support

### Phase 3: Production Features (6-8 weeks)
1. Media recording
2. Connection pooling
3. Basic HA support
4. Performance optimizations

### Phase 4: Advanced Features (8-12 weeks)
1. Conference bridge
2. Additional codecs
3. WebRTC gateway
4. Full monitoring

## Testing Requirements

### Unit Tests
- RTP packet generation/parsing
- Codec encoding/decoding
- Authentication calculations

### Integration Tests
- Multi-codec scenarios
- Call transfer scenarios
- Conference scenarios
- Load testing (1000+ concurrent calls)

### Compliance Tests
- RFC 3261 (SIP) compliance
- RFC 3550 (RTP) compliance
- RFC 4566 (SDP) compliance

## Documentation Needs

1. **API Documentation**
   - Public API reference
   - Handler implementation guide
   - Media pipeline customization

2. **Deployment Guide**
   - Production configuration
   - Security best practices
   - Performance tuning

3. **Examples**
   - PBX implementation
   - IVR system
   - Call center application
   - WebRTC gateway

## Recommended Next Steps

1. **Start with RTP**: This is the most critical missing piece
2. **Add UAC support**: Enable outbound calling
3. **Implement recording**: Common requirement for compliance
4. **Add more codecs**: G.729 and Opus are widely used
5. **Build conference bridge**: Key differentiator feature

## Code Quality Checklist

- [ ] Property-based testing for protocols
- [ ] Dialyzer specifications
- [ ] Performance benchmarks
- [ ] Security audit
- [ ] Documentation coverage
- [ ] CI/CD pipeline
- [ ] Release management