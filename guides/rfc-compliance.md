# RFC Compliance Reference

This guide provides a comprehensive listing of all RFC standards referenced and implemented in the Parrot Framework codebase. The framework implements core SIP functionality according to these standards (or, at least, does its very best to).

## Core SIP RFCs

### RFC 3261 - SIP: Session Initiation Protocol
The fundamental SIP protocol specification. Parrot implements:
- Basic SIP message structure and parsing
- Transaction state machines (INVITE and non-INVITE)
- Dialog management
- Transport layer (UDP)
- Request and response handling

### RFC 3263 - Session Initiation Protocol (SIP): Locating SIP Servers
DNS resolution for SIP servers:
- SRV record lookups
- A/AAAA record fallback
- Transport selection

### RFC 3581 - An Extension to the Session Initiation Protocol (SIP) for Symmetric Response Routing
Symmetric response routing support:
- rport parameter handling
- NAT traversal improvements

### RFC 3986 - Uniform Resource Identifier (URI): Generic Syntax
URI parsing and validation for SIP URIs.

### RFC 4566 - SDP: Session Description Protocol
SDP parsing and generation for media negotiation:
- Media descriptions
- Codec negotiation
- Connection information

### RFC 5234 - Augmented BNF for Syntax Specifications: ABNF
Used for parsing SIP message syntax according to ABNF rules.

## SIP Extensions

### RFC 3262 - Reliability of Provisional Responses
Support for reliable provisional responses (100rel).

### RFC 3264 - An Offer/Answer Model with the Session Description Protocol (SDP)
SDP offer/answer negotiation model.

### RFC 3265 - Session Initiation Protocol (SIP)-Specific Event Notification
SUBSCRIBE/NOTIFY event framework.

### RFC 3311 - The Session Initiation Protocol (SIP) UPDATE Method
UPDATE method support for mid-dialog modifications.

### RFC 3428 - Session Initiation Protocol (SIP) Extension for Instant Messaging
MESSAGE method for instant messaging.

### RFC 3515 - The Session Initiation Protocol (SIP) REFER Method
REFER method for call transfer.

### RFC 3840 - Indicating User Agent Capabilities in SIP
Feature tags and capability negotiation.

### RFC 3903 - Session Initiation Protocol (SIP) Extension for Event State Publication
PUBLISH method for event state publication.

### RFC 4028 - Session Timers in the Session Initiation Protocol (SIP)
Session timer support for detecting failed sessions.

### RFC 6026 - Correct Transaction Handling for 2xx Responses to INVITE
Proper handling of multiple 2xx responses.

### RFC 6665 - SIP-Specific Event Notification (Updates RFC 3265)
Updated event notification framework.

## Media and RTP RFCs

### RFC 3550 - RTP: A Transport Protocol for Real-Time Applications
RTP packet handling and stream management.

### RFC 3551 - RTP Profile for Audio and Video Conferences
Standard audio/video payload types and formats.

### RFC 3711 - The Secure Real-time Transport Protocol (SRTP)
Secure RTP support (future implementation).

### RFC 4733 - RTP Payload for DTMF Digits, Telephony Tones, and Telephony Signals
DTMF over RTP (telephone-event).

### RFC 5109 - RTP Payload Format for Generic Forward Error Correction
FEC support for RTP streams.

### RFC 5389 - Session Traversal Utilities for NAT (STUN)
STUN support for NAT traversal.

### RFC 5766 - Traversal Using Relays around NAT (TURN)
TURN relay support.

### RFC 8445 - Interactive Connectivity Establishment (ICE)
ICE for NAT traversal.

## Codec Standards

### ITU-T G.711 - Pulse Code Modulation (PCM)
G.711 μ-law (PCMU) and A-law (PCMA) audio codecs.

### ITU-T G.729 - Coding of speech at 8 kbit/s
G.729 codec support (requires licensing).

### RFC 3952 - Real-time Transport Protocol (RTP) Payload Format for Internet Low Bit Rate Codec (iLBC)
iLBC codec support.

### RFC 5577 - RTP Payload Format for ITU-T Recommendation G.722.1
G.722.1 wideband codec.

## Implementation Status

The framework currently implements:
- ✅ Core SIP protocol (RFC 3261)
- ✅ Basic SDP support (RFC 4566)
- ✅ RTP handling (RFC 3550)
- ✅ G.711 codecs
- ✅ DNS resolution (RFC 3263)
- ✅ Symmetric response routing (RFC 3581)
- ⚠️  Partial SUBSCRIBE/NOTIFY (RFC 3265)
- ⚠️  Partial session timers (RFC 4028)
- ❌ SRTP (RFC 3711) - planned
- ❌ ICE (RFC 8445) - planned

## Usage in Code

References to these RFCs can be found throughout the codebase in comments explaining implementation decisions. For example:

```elixir
# As per RFC 3261 Section 17.2.1, server transactions are created
# when a request is received
```

When implementing new features or debugging issues, refer to the relevant RFC sections for authoritative guidance on correct behavior.
