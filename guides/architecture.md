# Architecture

This guide provides a comprehensive overview of Parrot's architecture, including process supervision trees, state machines, and message flows.

The architecture follows the SIP protocol specification defined in [RFC 3261](https://www.rfc-editor.org/rfc/rfc3261.html) and related RFCs.

## System Architecture Overview

```mermaid
graph TB
    subgraph "Parrot Application"
        App[Parrot.Application]
        App --> MainSup[Parrot.Supervisor]
        
        MainSup --> TransSup[Transport.Supervisor]
        MainSup --> TxnSup[Transaction.Supervisor]
        MainSup --> DialogSup[Dialog.Supervisor]
        MainSup --> HandlerSup[HandlerAdapter.Supervisor]
        MainSup --> MediaSup[MediaSession.Supervisor]
        
        subgraph "Transport Layer"
            TransSup --> StateMachine[Transport.StateMachine<br/>gen_statem]
            StateMachine --> UDP[Transport.UDP<br/>GenServer]
            StateMachine --> TCP[Transport.TCP<br/>GenServer]
            StateMachine --> WS[Transport.WebSocket<br/>GenServer]
        end
        
        subgraph "Transaction Layer"
            TxnSup --> TxnStatem[Transaction.Statem<br/>gen_statem]
            TxnStatem --> ClientTxn[Client Transaction<br/>gen_statem]
            TxnStatem --> ServerTxn[Server Transaction<br/>gen_statem]
        end
        
        subgraph "Dialog Layer"
            DialogSup --> DialogStatem[Dialog.Statem<br/>gen_statem]
            DialogSup --> DialogReg[Dialog.Registry]
        end
        
        subgraph "Application Layer"
            HandlerSup --> HandlerCore[HandlerAdapter.Core<br/>gen_statem]
            HandlerCore --> UserHandler[User Handler<br/>Behaviour]
        end
        
        subgraph "Media Layer"
            MediaSup --> MediaSession[MediaSession<br/>gen_statem]
            MediaSession --> Pipeline[Membrane Pipeline<br/>GenServer]
        end
    end
    
    style App fill:#f9f,stroke:#333,stroke-width:4px
    style MainSup fill:#bbf,stroke:#333,stroke-width:2px
    style StateMachine fill:#fbb,stroke:#333,stroke-width:2px
    style TxnStatem fill:#fbb,stroke:#333,stroke-width:2px
    style DialogStatem fill:#fbb,stroke:#333,stroke-width:2px
    style HandlerCore fill:#fbb,stroke:#333,stroke-width:2px
    style MediaSession fill:#fbb,stroke:#333,stroke-width:2px
```

## Process Communication Flow

```mermaid
sequenceDiagram
    participant Net as Network
    participant UDP as UDP Transport
    participant Conn as Connection
    participant Parser as Parser
    participant TxnSrv as Transaction Statem
    participant Dialog as Dialog Server
    participant Handler as Handler Adapter
    participant App as User Application
    participant Media as Media Session
    
    Net->>UDP: UDP Packet
    UDP->>Conn: Raw Data
    Conn->>Parser: Parse SIP Message
    Parser->>UDP: Parsed Message
    UDP->>TxnSrv: Route to Transaction
    
    alt New Transaction
        TxnSrv->>Handler: Create Handler Instance
        Handler->>App: Call Handler Callback
        App->>Handler: Response Decision
    else Existing Transaction
        TxnSrv->>Dialog: Check Dialog State
        Dialog->>Handler: Route to Handler
    end
    
    Handler->>Media: Start Media Session
    Media->>Media: Create RTP Pipeline
    Handler->>TxnSrv: Send Response
    TxnSrv->>UDP: Send Message
    UDP->>Net: UDP Packet
```

## State Machine: Transaction Layer

The transaction state machines are implemented according to [RFC 3261 Section 17](https://www.rfc-editor.org/rfc/rfc3261.html#section-17):

```mermaid
graph LR
    subgraph "Client Transaction"
        CI[Init] --> CA[Calling]
        CA -->|1xx| CP[Proceeding]
        CA -->|final| CC[Completed]
        CP -->|final| CC
        CC -->|Timer D| CT[Terminated]
    end
    
    subgraph "Server Transaction"
        SI[Init] --> ST[Trying]
        ST -->|send 1xx| SP[Proceeding]
        ST -->|send final| SC[Completed]
        SP -->|send final| SC
        SC -->|ACK| SCF[Confirmed]
        SCF -->|Timer I| STM[Terminated]
    end
```

## State Machine: Dialog Layer

Dialog state management follows [RFC 3261 Section 12](https://www.rfc-editor.org/rfc/rfc3261.html#section-12):

```mermaid
stateDiagram-v2
    [*] --> Init: new_dialog
    Init --> Early: rcv_provisional
    Early --> Confirmed: rcv_2xx
    Early --> Terminated: rcv_final_error
    Confirmed --> Terminated: rcv_BYE
    Terminated --> [*]
    
    note right of Early: Dialog established<br/>with early media
    note right of Confirmed: Full dialog<br/>Media flowing
    note right of Terminated: Cleanup resources<br/>Stop media
```

## State Machine: Handler Adapter

```mermaid
stateDiagram-v2
    [*] --> Idle: init
    Idle --> TransactionTrying: rcv_INVITE
    TransactionTrying --> TransactionProceeding: send_provisional
    TransactionProceeding --> WaitingForAck: send_200_OK
    WaitingForAck --> InCall: rcv_ACK
    InCall --> Terminating: rcv_BYE
    Terminating --> Idle: send_200_OK
    
    note right of TransactionTrying: Notify app<br/>Start negotiation
    note right of InCall: Media flowing<br/>Call established
    note right of Terminating: Stop media<br/>Cleanup
```

## SIP Call Flow with Process Interaction

This flow demonstrates how Parrot implements the basic call flow from [RFC 3665 Section 3.1](https://www.rfc-editor.org/rfc/rfc3665.html#section-3.1):

```mermaid
sequenceDiagram
    participant Alice as Alice<br/>(UAC)
    participant Transport as Transport<br/>Layer
    participant TxnStatem as Transaction<br/>Statem
    participant Dialog as Dialog<br/>Server
    participant Handler as Handler<br/>Adapter
    participant App as Application<br/>Handler
    participant Media as Media<br/>Session
    participant Bob as Bob<br/>(UAS)
    
    Alice->>Transport: INVITE
    Transport->>TxnStatem: new_server_transaction
    TxnStatem->>TxnStatem: Start Timer C
    TxnStatem->>Handler: handle_invite
    Handler->>App: handle_invite callback
    App->>Media: start_session
    Media->>Media: Allocate RTP port
    App->>Handler: {respond, 180, "Ringing"}
    Handler->>TxnStatem: send_response
    TxnStatem->>Transport: 180 Ringing
    Transport->>Alice: 180 Ringing
    
    Note over App: User answers call
    
    App->>Handler: {respond, 200, "OK", SDP}
    Handler->>Dialog: create_dialog
    Dialog->>Dialog: Register dialog ID
    Handler->>TxnStatem: send_response
    TxnStatem->>Transport: 200 OK + SDP
    Transport->>Alice: 200 OK + SDP
    
    Alice->>Transport: ACK
    Transport->>TxnStatem: process_ACK
    TxnStatem->>Dialog: confirm_dialog
    Dialog->>Handler: handle_ack
    Handler->>Media: start_streaming
    
    Note over Alice,Bob: RTP Media Flow
    Media-->Alice: RTP Audio
    Alice-->Media: RTP Audio
    
    Alice->>Transport: BYE
    Transport->>Dialog: in_dialog_request
    Dialog->>Handler: handle_bye
    Handler->>Media: stop_session
    Media->>Media: Cleanup pipeline
    Handler->>Dialog: terminate_dialog
    Handler->>TxnStatem: send_response
    TxnStatem->>Transport: 200 OK
    Transport->>Alice: 200 OK
```

## Media Negotiation Flow

```mermaid
sequenceDiagram
    participant UAC as Alice UAC
    participant Handler as Parrot Handler
    participant Media as Media Session
    participant SDP as SDP Parser
    participant Pipeline as Membrane Pipeline
    participant RTP as RTP Endpoint
    
    UAC->>Handler: INVITE with SDP Offer
    Handler->>Media: process_offer(sdp)
    Media->>SDP: parse(offer)
    SDP->>Media: {codecs: [PCMU, PCMA], port: 30000}
    Media->>Media: Select compatible codec
    Media->>Pipeline: create_pipeline(codec: PCMU)
    Pipeline->>RTP: bind(local_port: 40000)
    RTP->>Pipeline: ready
    Pipeline->>Media: pipeline_ready
    Media->>SDP: generate_answer
    SDP->>Media: SDP Answer
    Media->>Handler: {ok, sdp_answer}
    Handler->>UAC: 200 OK with SDP Answer
    
    Note over UAC,RTP: Media Path Established
    
    UAC->>Handler: ACK
    Handler->>Media: start_media
    Media->>Pipeline: start_streaming
    
    loop RTP Stream
        UAC-->>RTP: RTP Packets (PCMU)
        RTP-->>Pipeline: Decode/Process
        Pipeline-->>RTP: Encode/Send
        RTP-->>UAC: RTP Packets (PCMU)
    end
```


## Process Registry and Discovery

```mermaid
graph LR
    subgraph "Process Registry"
        ViaReg[Via Registry<br/>Branch → Transaction PID]
        DialogReg[Dialog Registry<br/>Dialog ID → Dialog PID]
        MediaReg[Media Registry<br/>Call ID → Media PID]
    end
    
    subgraph "Message Routing"
        MSG[Incoming Message]
        MSG --> ViaCheck{Via Branch?}
        ViaCheck -->|Found| TxnPID[Transaction Process]
        ViaCheck -->|Not Found| DialogCheck{Dialog ID?}
        DialogCheck -->|Found| DialogPID[Dialog Process]
        DialogCheck -->|Not Found| NewTxn[Create Transaction]
    end
    
    subgraph "Resource Management"
        Supervisor[Supervisor]
        Supervisor --> Monitor[Monitor Processes]
        Monitor --> Cleanup[Cleanup on Exit]
        Cleanup --> Unregister[Unregister from Registry]
    end
```

## Fault Tolerance and Supervision

```mermaid
graph TB
    subgraph "Supervision Strategy"
        Root[Root Supervisor<br/>one_for_one]
        Root --> Transport[Transport Sup<br/>one_for_one]
        Root --> Transaction[Transaction Sup<br/>simple_one_for_one]
        Root --> Dialog[Dialog Sup<br/>simple_one_for_one]
        Root --> Media[Media Sup<br/>one_for_all]
        
        Transport --> UDP1[UDP:5060]
        Transport --> UDP2[UDP:5061]
        
        Transaction --> Txn1[Txn 1]
        Transaction --> Txn2[Txn 2]
        Transaction --> TxnN[Txn N]
        
        Dialog --> Dlg1[Dialog 1]
        Dialog --> Dlg2[Dialog 2]
        Dialog --> DlgN[Dialog N]
        
        Media --> Session1[Session 1]
        Media --> Session2[Session 2]
        Media --> SessionN[Session N]
    end
    
    subgraph "Failure Handling"
        Crash[Process Crash]
        Crash --> Restart[Supervisor Restart]
        Restart --> Recover[State Recovery]
        Recover --> Resume[Resume Operation]
    end
```

## Performance Characteristics

The architecture is designed for:

- **High Concurrency**: Each call/transaction in its own process
- **Fault Isolation**: Crashes don't affect other calls
- **Scalability**: Distribute across nodes
- **Low Latency**: Direct process messaging
- **Resource Efficiency**: Processes cleaned up after use

## Key Design Decisions

1. **gen_statem over GenServer**: For complex protocol state machines
2. **Process per Transaction**: Isolation and garbage collection
3. **Registry-based Discovery**: Fast process lookup
4. **Supervision Trees**: Automatic recovery from failures
5. **Layered Architecture**: Clear separation of concerns

## Integration Points

- **SIP Handler Behavior**: Implement `Parrot.SipHandler` callbacks for SIP protocol events
- **Media Handler Behavior**: Implement `Parrot.MediaHandler` callbacks for media session control
- **Transport Plugins**: Add new transport protocols beyond UDP
- **Codec Support**: Extend with additional audio/video codecs

## Handler Architecture

### UasHandler
The `Parrot.UasHandler` behaviour provides callbacks for SIP protocol events as a User Agent Server:
- `handle_invite/2` - Process incoming calls
- `handle_ack/2` - Handle call confirmation
- `handle_bye/2` - Handle call termination
- `handle_cancel/2` - Handle call cancellation
- Transaction state callbacks for fine-grained control

### MediaHandler
The `Parrot.MediaHandler` behaviour provides callbacks for media control:
- `init/1` - Initialize handler state
- `handle_session_start/3` - Media session lifecycle
- `handle_stream_start/3` - Begin media streaming
- `handle_play_complete/2` - Audio playback events
- `handle_codec_negotiation/3` - Influence codec selection
- `handle_rtp_stats/2` - Monitor call quality
- `handle_stream_error/3` - Error recovery

Both handlers work together to provide complete control over SIP calls and their associated media streams.