# SIP Basics

This guide provides an introduction to the Session Initiation Protocol (SIP) as implemented in Parrot, following [RFC 3261](https://www.rfc-editor.org/rfc/rfc3261.html), with detailed flow diagrams showing how SIP works in practice.

## What is SIP?

SIP (Session Initiation Protocol) is a signaling protocol used for initiating, maintaining, and terminating real-time sessions that include voice, video and messaging applications. It is defined in [RFC 3261](https://www.rfc-editor.org/rfc/rfc3261.html).

## Basic SIP Call Flow

This flow demonstrates a basic SIP session establishment as described in [RFC 3665 Section 3.1](https://www.rfc-editor.org/rfc/rfc3665.html#section-3.1):

```mermaid
sequenceDiagram
    participant Alice as Alice 192.168.1.100
    participant Proxy as SIP Proxy sip.example.com
    participant Location as Location Service
    participant Bob as Bob 10.0.0.50
    
    Note over Alice: Wants to call bob@example.com
    
    Alice->>Proxy: INVITE sip:bob@example.com
    Note right of Alice: Via: SIP/2.0/UDP 192.168.1.100:5060\nFrom: alice@example.com\nTo: bob@example.com\nCall-ID: 12345@192.168.1.100
    
    Proxy->>Location: Query bob@example.com
    Location->>Proxy: Contact: sip:bob@10.0.0.50
    
    Proxy->>Bob: INVITE sip:bob@10.0.0.50
    Note right of Proxy: Via: SIP/2.0/UDP proxy.example.com\nVia: SIP/2.0/UDP 192.168.1.100:5060\nRecord-Route: sip:proxy.example.com
    
    Bob->>Proxy: 180 Ringing
    Proxy->>Alice: 180 Ringing
    
    Note over Bob: User answers
    
    Bob->>Proxy: 200 OK (+ SDP)
    Note left of Bob: Contact: sip:bob@10.0.0.50\nContent-Type: application/sdp
    
    Proxy->>Alice: 200 OK (+ SDP)
    
    Alice->>Proxy: ACK
    Proxy->>Bob: ACK
    
    Note over Alice,Bob: RTP Media Flow (Direct)
    Alice<->Bob: Voice/Video (RTP)
    
    Note over Alice: Hangs up
    
    Alice->>Proxy: BYE
    Proxy->>Bob: BYE
    Bob->>Proxy: 200 OK
    Proxy->>Alice: 200 OK
```

## SIP Registration Flow

SIP registration is specified in [RFC 3261 Section 10](https://www.rfc-editor.org/rfc/rfc3261.html#section-10):

```mermaid
sequenceDiagram
    participant UA as User Agent (Alice's Phone)
    participant Registrar as Registrar Server
    participant Auth as Authentication Service
    participant Location as Location Database
    
    UA->>Registrar: REGISTER sip:example.com
    Note right of UA: From: alice@example.com\nTo: alice@example.com\nContact: sip:alice@192.168.1.100\nExpires: 3600
    
    Registrar->>UA: 401 Unauthorized
    Note left of Registrar: WWW-Authenticate: Digest\nrealm=example.com\nnonce=84a4cc6f3082121f
    
    UA->>UA: Calculate Digest Response
    
    UA->>Registrar: REGISTER sip:example.com
    Note right of UA: Authorization: Digest\nusername=alice\nrealm=example.com\nnonce=84a4cc6f3082121f\nresponse=7587245234b3434cc3412
    
    Registrar->>Auth: Verify Credentials
    Auth->>Registrar: OK
    
    Registrar->>Location: Store Binding
    Note right of Registrar: AOR: alice@example.com\nContact: sip:alice@192.168.1.100\nExpires: 3600
    
    Location->>Registrar: Stored
    
    Registrar->>UA: 200 OK
    Note left of Registrar: Contact: sip:alice@192.168.1.100 expires=3600
```

## SDP Negotiation in Detail

Session Description Protocol (SDP) negotiation follows [RFC 4566](https://www.rfc-editor.org/rfc/rfc4566.html) for SDP format and [RFC 3264](https://www.rfc-editor.org/rfc/rfc3264.html) for offer/answer model:

```mermaid
sequenceDiagram
    participant Alice as Alice
    participant Handler as Parrot Handler
    participant Bob as Bob
    
    Note over Alice: SDP Offer
    Alice->>Handler: INVITE with SDP
    Note right of Alice: v=0\no=alice 2890844526 IN IP4 192.168.1.100\ns=Session\nc=IN IP4 192.168.1.100\nt=0 0\nm=audio 49170 RTP/AVP 0 8 97\na=rtpmap:0 PCMU/8000\na=rtpmap:8 PCMA/8000\na=rtpmap:97 opus/48000
    
    Handler->>Handler: Parse Offer\nSelect Codecs
    
    Handler->>Bob: 200 OK with SDP Answer
    Note right of Handler: v=0\no=bob 2890844527 IN IP4 10.0.0.50\ns=Session\nc=IN IP4 10.0.0.50\nt=0 0\nm=audio 49172 RTP/AVP 0\na=rtpmap:0 PCMU/8000
    
    Note over Alice,Bob: Negotiated: PCMU codec\nAlice sends to 10.0.0.50:49172\nBob sends to 192.168.1.100:49170
    
    Alice->>Bob: RTP PCMU @49172
    Bob->>Alice: RTP PCMU @49170
```

## SIP Transaction State Machines

These state machines are precisely defined in [RFC 3261 Section 17](https://www.rfc-editor.org/rfc/rfc3261.html#section-17):

### Server Transaction (INVITE)

As specified in [RFC 3261 Section 17.2.1](https://www.rfc-editor.org/rfc/rfc3261.html#section-17.2.1):

```mermaid
stateDiagram-v2
    [*] --> Trying: INVITE received
    
    Trying --> Proceeding: Send 1xx response
    Trying --> Completed: Send final response (300-699)
    
    Proceeding --> Proceeding: Send 1xx response
    Proceeding --> Completed: Send final response (300-699)
    
    Completed --> Confirmed: ACK received
    Completed --> Terminated: Timer H expires (no ACK)
    
    Confirmed --> Terminated: Timer I expires
    
    note right of Trying: Initial state\nStart Timer H
    note right of Proceeding: Provisional responses sent\nCan send multiple 1xx
    note right of Completed: Final response sent\nWaiting for ACK
    note right of Confirmed: ACK received\nStart Timer I (5s)
    note right of Terminated: Transaction ends\nCleanup resources
```

### Client Transaction (INVITE)

As specified in [RFC 3261 Section 17.1.1](https://www.rfc-editor.org/rfc/rfc3261.html#section-17.1.1):

```mermaid
stateDiagram-v2
    [*] --> Calling: Send INVITE
    
    Calling --> Proceeding: Receive 1xx response
    Calling --> Completed: Receive 300-699 response
    Calling --> Terminated: Receive 2xx response
    
    Proceeding --> Proceeding: Receive 1xx response
    Proceeding --> Completed: Receive 300-699 response
    Proceeding --> Terminated: Receive 2xx response
    
    Completed --> Terminated: Timer D expires
    
    note right of Calling: INVITE sent\nStart Timer A & B
    note right of Proceeding: Provisional received\nCancel Timer A & B
    note right of Completed: Error response\nSend ACK, start Timer D
    note right of Terminated: Success (2xx) or timeout\nTransaction ends
```

### Server Transaction (Non-INVITE)

As specified in [RFC 3261 Section 17.2.2](https://www.rfc-editor.org/rfc/rfc3261.html#section-17.2.2):

```mermaid
stateDiagram-v2
    [*] --> Trying: Request received
    
    Trying --> Proceeding: Send 1xx response
    Trying --> Completed: Send final response
    
    Proceeding --> Proceeding: Send 1xx response
    Proceeding --> Completed: Send final response
    
    Completed --> Terminated: Timer J expires
    
    note right of Trying: BYE, OPTIONS, etc.\nNo special timers
    note right of Proceeding: Provisional sent\nRarely used
    note right of Completed: Final response sent\nStart Timer J (32s)
    note right of Terminated: Transaction ends
```

### Client Transaction (Non-INVITE)

As specified in [RFC 3261 Section 17.1.2](https://www.rfc-editor.org/rfc/rfc3261.html#section-17.1.2):

```mermaid
stateDiagram-v2
    [*] --> Trying: Send request
    
    Trying --> Proceeding: Receive 1xx response
    Trying --> Completed: Receive final response
    
    Proceeding --> Proceeding: Receive 1xx response
    Proceeding --> Completed: Receive final response
    
    Completed --> Terminated: Timer K expires
    
    note right of Trying: Request sent\nStart Timer E & F
    note right of Proceeding: Provisional received\nTimer E continues
    note right of Completed: Final response\nStart Timer K (5s)
    note right of Terminated: Transaction ends
```

## CANCEL Flow

The CANCEL method is defined in [RFC 3261 Section 9](https://www.rfc-editor.org/rfc/rfc3261.html#section-9):

```mermaid
sequenceDiagram
    participant Alice as Alice
    participant Proxy as Proxy
    participant Bob as Bob
    
    Alice->>Proxy: INVITE
    Proxy->>Bob: INVITE
    Bob->>Proxy: 180 Ringing
    Proxy->>Alice: 180 Ringing
    
    Note over Alice: User cancels call
    
    Alice->>Proxy: CANCEL
    Note right of Alice: Same Call-ID\nSame From tag\nSame Request-URI
    
    Proxy->>Alice: 200 OK (CANCEL)
    
    Proxy->>Bob: CANCEL
    Bob->>Proxy: 200 OK (CANCEL)
    Bob->>Proxy: 487 Request Terminated
    Proxy->>Alice: 487 Request Terminated
    
    Alice->>Proxy: ACK
    Proxy->>Bob: ACK
```

## Forking Proxy Flow

Forking proxy behavior is specified in [RFC 3261 Section 16.7](https://www.rfc-editor.org/rfc/rfc3261.html#section-16.7):

```mermaid
sequenceDiagram
    participant Alice as Alice
    participant Proxy as Forking Proxy
    participant Bob1 as Bob (Office)
    participant Bob2 as Bob (Mobile)
    participant Bob3 as Bob (Home)
    
    Alice->>Proxy: INVITE bob@example.com
    
    par Parallel Forking
        Proxy->>Bob1: INVITE (branch-1)
    and
        Proxy->>Bob2: INVITE (branch-2)
    and
        Proxy->>Bob3: INVITE (branch-3)
    end
    
    Bob1->>Proxy: 180 Ringing
    Proxy->>Alice: 180 Ringing
    
    Bob2->>Proxy: 180 Ringing
    Note over Proxy: Suppressed (already sent 180)
    
    Bob3->>Proxy: 486 Busy Here
    
    Bob2->>Proxy: 200 OK
    
    Note over Proxy: Cancel other branches
    
    Proxy->>Bob1: CANCEL
    Bob1->>Proxy: 200 OK (CANCEL)
    Bob1->>Proxy: 487 Request Terminated
    
    Proxy->>Alice: 200 OK (from Bob2)
    
    Alice->>Proxy: ACK
    Proxy->>Bob2: ACK
    
    Note over Alice,Bob2: Call established with Mobile
```

## Early Media Flow

Early media is discussed in [RFC 3960](https://www.rfc-editor.org/rfc/rfc3960.html):

```mermaid
sequenceDiagram
    participant Caller as Caller
    participant PBX as PBX/IVR
    participant Callee as Callee
    
    Caller->>PBX: INVITE
    PBX->>PBX: Start IVR
    
    PBX->>Caller: 183 Session Progress
    Note right of PBX: SDP with media info\na=sendonly
    
    Note over Caller,PBX: Early Media (One-way)
    PBX-->>Caller: RTP (Announcement)
    Note left of PBX: Please wait while\nwe connect your call...
    
    PBX->>Callee: INVITE
    Callee->>PBX: 180 Ringing
    
    Note over Caller,PBX: Early Media continues
    PBX-->>Caller: RTP (Ring tone)
    
    Callee->>PBX: 200 OK
    PBX->>Caller: 200 OK
    
    Caller->>PBX: ACK
    PBX->>Callee: ACK
    
    Note over Caller,Callee: Regular Media (Two-way)
    Caller<->PBX: RTP
    PBX<->Callee: RTP
```

## REFER (Call Transfer) Flow

The REFER method is specified in [RFC 3515](https://www.rfc-editor.org/rfc/rfc3515.html):

```mermaid
sequenceDiagram
    participant A as Alice
    participant B as Bob
    participant C as Carol
    
    Note over A,B: Existing call
    A<->B: RTP Media
    
    Note over B: Bob transfers to Carol
    
    B->>A: REFER sip:carol@example.com
    Note right of B: Refer-To: sip:carol@example.com
    
    A->>B: 202 Accepted
    
    A->>B: NOTIFY
    Note right of A: Event: refer\nSubscription-State: active\nContent-Type: message/sipfrag\nSIP/2.0 100 Trying
    
    B->>A: 200 OK
    
    A->>C: INVITE
    Note right of A: Referred-By: sip:bob@example.com
    
    C->>A: 200 OK
    A->>C: ACK
    
    A->>B: NOTIFY
    Note right of A: Event: refer\nSubscription-State: terminated\nContent-Type: message/sipfrag\nSIP/2.0 200 OK
    
    B->>A: 200 OK
    
    A->>B: BYE
    B->>A: 200 OK
    
    Note over A,C: New call established
    A<->C: RTP Media
```

## SIP Headers Explained

SIP header fields are defined in [RFC 3261 Section 20](https://www.rfc-editor.org/rfc/rfc3261.html#section-20):

### Via Header Path

Via header processing is specified in [RFC 3261 Section 8.1.1.7](https://www.rfc-editor.org/rfc/rfc3261.html#section-8.1.1.7):

```mermaid
graph LR
    subgraph "Request Path"
        A[Alice] -->|Via: A| P1[Proxy 1]
        P1 -->|Via: P1 Via: A| P2[Proxy 2]
        P2 -->|Via: P2 Via: P1 Via: A| B[Bob]
    end
    
    subgraph "Response Path"
        B2[Bob] -->|Remove Via: P2| P22[Proxy 2]
        P22 -->|Remove Via: P1| P12[Proxy 1]
        P12 -->|Remove Via: A| A2[Alice]
    end
```

### Record-Route and Route Headers

Record-Route mechanism is defined in [RFC 3261 Section 16.6](https://www.rfc-editor.org/rfc/rfc3261.html#section-16.6):

```mermaid
sequenceDiagram
    participant A as Alice
    participant P1 as Proxy 1
    participant P2 as Proxy 2
    participant B as Bob
    
    A->>P1: INVITE
    Note right of A: No Route headers
    
    P1->>P2: INVITE
    Note right of P1: Record-Route: sip:p1.com lr
    
    P2->>B: INVITE
    Note right of P2: Record-Route: sip:p2.com lr\nRecord-Route: sip:p1.com lr
    
    B->>P2: 200 OK
    Note left of B: Record-Route: sip:p2.com lr\nRecord-Route: sip:p1.com lr
    
    P2->>P1: 200 OK
    P1->>A: 200 OK
    
    Note over A: Stores Route Set:\n1. sip:p1.com lr\n2. sip:p2.com lr
    
    A->>P1: ACK
    Note right of A: Route: sip:p1.com lr\nRoute: sip:p2.com lr
    
    P1->>P2: ACK
    Note right of P1: Route: sip:p2.com lr
    
    P2->>B: ACK
    Note right of P2: No Route headers
```

## Using Parrot for SIP

Parrot handles all these complex flows automatically. You simply implement the Handler behavior:

```elixir
defmodule MyHandler do
  @behaviour Parrot.SipHandler
  
  def handle_invite(message, state) do
    # Parrot handles:
    # - Transaction state machines
    # - Retransmissions
    # - Timer management
    # - Response routing
    # - Dialog state
    
    # You handle:
    # - Business logic
    # - Media decisions
    # - User interaction
    
    {:respond, 200, "OK", headers, sdp, state}
  end
end
```

Parrot abstracts the protocol complexity while giving you full control over application behavior.