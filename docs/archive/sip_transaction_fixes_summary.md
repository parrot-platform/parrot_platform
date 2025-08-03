# SIP Transaction Fixes and Architecture Summary

## Overview

This document summarizes the fixes made to the Parrot SIP framework to pass all SIPp integration tests, architectural insights gained during debugging, and future development plans for removing ersip dependencies and integrating Elixir Membrane for audio streaming.

## Key Fixes Made

### 1. ACK Handling in Server Transactions

**Problem**: ACK messages were not properly transitioning INVITE server transactions from `completed` to `confirmed` state.

**Solution**: Added proper pattern matching in `transaction_server.ex` to handle ACK messages in the completed state:

```elixir
def completed(:cast, {:received, msg}, %{type: :server, data: data} = state) do
  case handle_common_event({:received, msg}, data) do
    {:next_state, new_state_name, new_data} ->
      {:next_state, new_state_name, %{state | data: new_data}}
    {:keep_state, new_data} ->
      {:keep_state, %{state | data: new_data}}
    {:stop, reason, new_data} ->
      {:stop, reason, %{state | data: new_data}}
  end
end
```

### 2. BYE Response Handling

**Problem**: BYE requests were not receiving 200 OK responses because `handle_in_dialog_request/1` was not implemented.

**Solution**: Implemented the missing function to create non-INVITE server transactions for in-dialog requests:

```elixir
defp handle_in_dialog_request(sip_msg) do
  Logger.info("📋 Creating new non-INVITE server transaction for in-dialog #{sip_msg.method}")
  
  case Parrot.Sip.TransactionStore.find_or_create_server_transaction(sip_msg) do
    {:ok, transaction} ->
      Logger.info("✅ Created transaction #{transaction.id} for in-dialog #{sip_msg.method}")
      :ok
    {:error, reason} ->
      Logger.error("❌ Failed to create transaction for in-dialog request: #{inspect(reason)}")
      :ok
  end
end
```

### 3. RFC 3261 Compliance: 100 Trying

**Problem**: 100 Trying was being sent for all transactions, including BYE requests.

**RFC Violation**: Per RFC 3261, 100 Trying should only be sent for INVITE transactions, not for non-INVITE transactions.

**Solution**: Added conditional check to only send 100 Trying for INVITE methods:

```elixir
# Only send 100 Trying for INVITE transactions
if sip_msg.method == :invite do
  trying_resp =
    Parrot.Sip.Message.reply(sip_msg, 100, "Trying")
    |> Map.put(:body, "")
  UAS.response(trying_resp, transaction)
end
```

### 4. Non-INVITE Transaction Initial State

**Problem**: Non-INVITE server transactions were starting in `:init` state instead of `:trying`.

**RFC Requirement**: RFC 3261 section 17.2.2 specifies that non-INVITE server transactions should start in the trying state.

**Solution**: Fixed transaction creation in `transaction.ex`:

```elixir
transaction = %__MODULE__{
  id: id,
  type: :non_invite_server,
  state: :trying,  # Changed from :init
  request: request,
  # ...
}
```

### 5. State Machine Pattern Matching

**Problem**: State handling was using conditionals instead of idiomatic Elixir pattern matching.

**Solution**: Refactored to use multiple function clauses with pattern matching on transaction type:

```elixir
# Pattern match on server transactions
def completed(:cast, {:received, msg}, %{type: :server, data: data} = state) do
  # Handle server transaction events
end

# Pattern match on client transactions  
def completed(:cast, {:received, msg}, %{type: :client, data: data} = state) do
  # Handle client transaction events
end
```

## Architecture Insights

### 1. Hybrid Implementation

The codebase currently uses a hybrid approach:
- **ersip**: Erlang SIP library for message parsing and some transaction handling
- **Pure Elixir**: Custom implementation using gen_statem for state machines

This creates complexity as there are two parallel implementations that need to be synchronized.

### 2. gen_statem Usage

The framework uses Erlang's gen_statem (not just GenServer) for:
- **Transaction state machines**: Managing SIP transaction states (trying, proceeding, completed, confirmed, terminated)
- **Dialog state machines**: Managing SIP dialog states (early, confirmed, terminated)

This is a critical architectural difference from typical Elixir applications.

### 3. Message Flow

1. UDP messages received by `Parrot.Sip.Transport.UdpListener`
2. Parsed by both ersip and pure Elixir parsers
3. Routed through transaction layer
4. Handled by user-defined handlers via `Parrot.Handler` behavior
5. Responses sent back through transaction layer

## Best Practices and Coding Style

### 1. Pattern Matching Over Conditionals

Always prefer multiple function clauses with pattern matching:

```elixir
# Good - Pattern matching
def handle_message(%{method: :invite} = msg), do: handle_invite(msg)
def handle_message(%{method: :bye} = msg), do: handle_bye(msg)
def handle_message(%{method: :ack} = msg), do: handle_ack(msg)

# Avoid - Conditionals
def handle_message(msg) do
  case msg.method do
    :invite -> handle_invite(msg)
    :bye -> handle_bye(msg)
    :ack -> handle_ack(msg)
  end
end
```

### 2. State Machine Design

- Use gen_statem for complex state management
- Define clear state transitions
- Handle all events in all states (even if just to log and ignore)
- Use pattern matching on state names and data

### 3. RFC Compliance

- Always refer to RFC 3261 for SIP protocol requirements
- Pay special attention to:
  - Transaction state diagrams (sections 17.1 and 17.2)
  - Message format requirements
  - Required vs optional headers
  - Method-specific behaviors

## Future Development Path

### 1. Remove ersip Dependencies

**Goal**: Eliminate all ersip dependencies and use only the pure Elixir SIP implementation.

**Steps**:
1. Identify all ersip usage points in the codebase
2. Implement missing functionality in pure Elixir
3. Update message parsing to use only Elixir parser
4. Remove ersip from mix.exs dependencies
5. **Ensure all SIPp integration tests continue to pass** using `mix test test/sipp/test_scenarios.exs`

**Key Areas to Address**:
- Message parsing (currently using both ersip and custom parser)
- Transaction management (hybrid implementation)
- Header manipulation utilities
- SDP parsing

### 2. Elixir Membrane Integration

**Goal**: After SIP protocol is fully working, integrate Elixir Membrane for audio streaming.

**Implementation Plan**:
1. Add Membrane as a dependency
2. Create audio pipeline for RTP handling
3. Implement audio file playback to SIPp
4. Adapt SIPp test scenarios to:
   - Send audio files during calls
   - Verify audio reception
   - Test various codecs (starting with PCMU/8000)

**Test Scenarios**:
- Modify `test/sipp/test_scenarios.exs` to include audio verification
- Create new scenarios that test:
  - Audio playback during established calls
  - Codec negotiation
  - RTP stream handling
  - DTMF detection (future)

### 3. Testing Strategy

1. **Current**: All SIPp tests must pass with pure Elixir implementation
2. **After ersip removal**: Same tests must continue to pass
3. **After Membrane integration**: Enhanced tests with audio verification

## Debugging Tips

### 1. Logging

Add strategic logging to understand state transitions:

```elixir
Logger.debug("🔄 State transition: #{old_state} -> #{new_state}")
Logger.info("📨 Received #{msg.method} in #{state_name} state")
Logger.error("❌ Unexpected event #{inspect(event)} in #{state_name}")
```

### 2. State Machine Debugging

- Log all state transitions
- Log unhandled events
- Use consistent logging prefixes for different components
- Check both gen_statem state AND transaction data state

### 3. SIPp Integration

- Check SIPp logs in `test/sipp/logs/`
- Look for both sent and received messages
- Verify message format matches RFC requirements
- Use `-trace_msg` flag for detailed SIPp output

## Common Pitfalls

1. **State Synchronization**: Ensure gen_statem state matches transaction data state
2. **ACK Handling**: ACK is special - it completes INVITE transactions but doesn't create new ones
3. **Dialog vs Transaction**: Understand the difference and when each applies
4. **100 Trying**: Only for INVITE, not for other methods
5. **Initial States**: Non-INVITE server transactions start in trying, not init

## Next Session Checklist

1. ✅ All SIPp tests passing with current hybrid implementation
2. ⏳ Remove all ersip dependencies while maintaining test success
3. ⏳ Integrate Elixir Membrane for audio playback
4. ⏳ Enhance SIPp scenarios to test audio streaming
5. ⏳ Implement bi-directional audio flow

## Resources

- RFC 3261: SIP Protocol Specification
- Erlang gen_statem documentation
- Elixir Membrane Framework guides
- SIPp documentation for scenario creation

## Conclusion

The Parrot SIP framework now successfully passes all SIPp integration tests. The key to success was:
1. Proper understanding of RFC 3261 requirements
2. Correct gen_statem state machine implementation
3. Idiomatic Elixir patterns with extensive pattern matching
4. Strategic logging for debugging complex state transitions

The next phase involves completing the transition to pure Elixir and adding real-time audio capabilities with Membrane.