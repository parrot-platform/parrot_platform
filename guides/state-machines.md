# Parrot Platform State Machines

This guide shows the simplified state machines used in Parrot Platform for handling SIP transactions, dialogs, and media sessions.

## Transaction State Machine

The transaction state machine handles reliable SIP message delivery:

```mermaid
stateDiagram-v2
    [*] --> Trying: New Transaction
    
    Trying --> Proceeding: 1xx Response
    Trying --> Completed: Final Response
    
    Proceeding --> Completed: Final Response
    
    Completed --> Confirmed: ACK Received
    Completed --> Terminated: Timer Expires
    
    Confirmed --> Terminated: Timer Expires
    
    Terminated --> [*]
    
    note right of Trying: Initial state
    note right of Proceeding: Provisional responses
    note right of Completed: Final response sent/received
    note right of Confirmed: INVITE only
    note right of Terminated: Cleanup
```

## Dialog State Machine

The dialog state machine manages SIP dialog lifecycle:

```mermaid
stateDiagram-v2
    [*] --> Early: INVITE Sent/Received
    
    Early --> Confirmed: 2xx Response
    Early --> Terminated: Error/Cancel
    
    Confirmed --> Terminated: BYE Request
    
    Terminated --> [*]
    
    note right of Early: Dialog establishing
    note right of Confirmed: Active dialog
    note right of Terminated: Dialog ended
```

## Media Session State Machine

The media session state machine handles audio streaming:

```mermaid
stateDiagram-v2
    [*] --> Idle: Session Created
    
    Idle --> Negotiating: SDP Offer
    
    Negotiating --> Ready: SDP Answer
    Negotiating --> Failed: Error
    
    Ready --> Active: Start RTP
    
    Active --> Stopping: End Call
    
    Stopping --> [*]
    Failed --> [*]
    
    note right of Idle: No media yet
    note right of Negotiating: Exchange SDP
    note right of Ready: Ports allocated
    note right of Active: Audio flowing
    note right of Stopping: Cleanup
```

## How They Work Together

1. **Transaction** ensures reliable message delivery
2. **Dialog** maintains the call context
3. **Media** handles the actual audio stream

All three use Erlang's `gen_statem` behavior for robust state management.