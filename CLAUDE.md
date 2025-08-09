# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

Parrot Platform provides Elixir libraries and OTP behaviours for building telecom applications, implementing the SIP (Session Initiation Protocol) stack. The tagline is "Putting the 'T' back in OTP."

## Current Development Priority

1. Add B2BUA state machine and handler capabilities
2. Adding more complex sipp scenario
     - retransmissions
     - re-invites
     - hold/unhold
     - UPDATE message to modify media mid-call
3. Add TCP and TLS transport support
4. Add registration client and server capabilities with authentication
     - Add sipp scenarios for testing
          - Basic REGISTER / 200 OK
          - REGISTER with authentication (401 Unauthorized challenge)
          - REGISTER with expiry 0 (unregister)
          - Multiple contacts in a single REGISTER
    - server registrar should make the storage of the registration handled by the user handlers so that the user can decide how they will store the registered contacts and look them up later to send messages
5. Authentication & Security
     - INVITE with Digest Authentication (401 / 407 challenge + re-INVITE)
     - Wrong password (should reject)
     - OPTIONS with authentication

## Coding Style Principles

### Pattern Matching Over Conditionals

**Use extensive pattern matching on data structures, especially the SIP message struct.** Prefer multiple function clauses with pattern matching over conditionals:

```elixir
# GOOD - Multiple function clauses with pattern matching
def handle_message(%Message{type: :request, method: "INVITE"} = msg), do: handle_invite(msg)
def handle_message(%Message{type: :request, method: "BYE"} = msg), do: handle_bye(msg)
def handle_message(%Message{type: :response, status: status} = msg) when status >= 200, do: handle_final_response(msg)

# BAD - Conditionals inside function
def handle_message(msg) do
  if msg.type == :request do
    case msg.method do
      "INVITE" -> handle_invite(msg)
      "BYE" -> handle_bye(msg)
    end
  else
    if msg.status >= 200 do
      handle_final_response(msg)
    end
  end
end
```

This approach:
- Makes code more readable and declarative
- Leverages Elixir's strengths
- Allows the compiler to optimize better
- Makes it easier to add new cases

## Test-Driven Development (TDD) Enforcement Policy

**IMPORTANT: All new features and bug fixes MUST follow TDD principles:**

1. **Write Tests First**: Before implementing any new functionality or fixing bugs, write failing tests that specify the expected behavior
2. **Red-Green-Refactor Cycle**: 
   - RED: Write a failing test
   - GREEN: Write the minimum code to make the test pass
   - REFACTOR: Improve the code while keeping tests green
3. **Test Coverage**: Aim for comprehensive test coverage, especially for:
   - SIP protocol handling (transactions, dialogs, messages)
   - State machine transitions
   - Error handling paths
   - Edge cases
4. **Integration Tests**: Always verify changes don't break SIPp integration tests by running:
   ```bash
   mix test test/sipp/test_scenarios.exs
   ```
5. **Unit Test Quality**: Tests should be:
   - Fast and isolated (use `async: true` where possible)
   - Descriptive in their naming
   - Testing behavior, not implementation details
   - Properly isolated with appropriate setup/teardown
6. sipp scenario functional testing
   - when new features are added, new sipp scenarios should be added to the sipp functional test sweet as well

## Common Development Commands

### Testing
- Run all tests: `mix test`
- Run SIPp integration tests: `mix test test/sipp/test_scenarios.exs`
- Run a specific test file: `mix test path/to/test_file.exs`
- Run a specific test: `mix test path/to/test_file.exs:LINE_NUMBER`

### Code Quality
- Format code: `mix format`
- Compile with warnings as errors: `mix compile --warnings-as-errors`

### Development
- Start interactive shell: `iex -S mix`
- Compile project: `mix compile`
- Get dependencies: `mix deps.get`

## Architecture Overview

### Critical: gen_statem Usage

**Parrot uses Erlang's gen_statem (state machine) behavior extensively, NOT just GenServer.** This is a key architectural decision that differs from most Elixir libraries:

- **Transaction State Machines**: `Parrot.Sip.Transaction` uses gen_statem to implement proper SIP transaction state machines (client and server transactions)
- **Dialog State Management**: Dialog lifecycle is managed through gen_statem states
- **Transport Layer**: Connection state management uses gen_statem

When working with these modules, understand gen_statem concepts:
- State functions (not just handle_* callbacks)
- State transitions with `{:next_state, new_state, data}`
- State enter calls
- Complex state data management

### Core Components

1. **SIP Stack Architecture**
   - **Transport Layer** (`lib/parrot/sip/transport/`): Handles UDP transport, connection management using gen_statem
   - **Transaction Layer** (`lib/parrot/sip/transaction.ex`, `transaction_server.ex`): Implements RFC 3261 transaction state machines using gen_statem
   - **Dialog Layer** (`lib/parrot/sip/dialog/`): Manages SIP dialog lifecycle with gen_statem
   - **Message Layer** (`lib/parrot/sip/message.ex`): Core SIP message representation and manipulation

2. **Handler Pattern**
   - Central to Parrot is the handler pattern defined in `lib/parrot/handler.ex`
   - Handlers implement callbacks for SIP events (requests, responses, errors)
   - Handler adapters convert between different handler implementations

3. **Supervision Tree**
   The application starts multiple supervisors under `Parrot.Application`:
   - `Parrot.Sip.Transport.Supervisor`: Manages transport processes
   - `Parrot.Sip.Transaction.Supervisor`: Manages transaction state machines
   - `Parrot.Sip.Dialog.Supervisor`: Manages dialog state machines
   - `Parrot.Sip.HandlerAdapter.Supervisor`: Manages handler adapters

4. **Header System**
   - All SIP headers are in `lib/parrot/sip/headers/`
   - Each header has parsing and serialization logic
   - Headers use `Parrot.Sip.Header` behavior

5. **Key Patterns**
   - **State Machines (gen_statem)**: Core pattern for transactions, dialogs, and transport
   - **GenServer**: Used for simpler components without complex state transitions
   - **Registry**: Used for process discovery (e.g., `Parrot.Sip.Dialog.Registry`)
   - **ETS**: Used for caching and fast lookups

### Testing Strategy

- Unit tests use ExUnit with async where possible
- Integration tests use SIPp (Session Initiation Protocol performance testing tool)
- SIPp scenarios are in `/test/sipp/scenarios/`
- Test helpers provide utilities for creating test messages and mocking

### Important Implementation Details

1. **Message Direction**: Recent refactoring introduced explicit message direction (inbound/outbound) and type structure
2. **Transaction Keys**: Transactions are identified by branch, method, and direction
3. **Branch Management**: Proper Via branch parameter handling is critical for transaction matching
4. **DNS Resolution**: Built-in DNS resolver for SIP URI resolution
5. **Connection Pooling**: Transport layer manages connection pools for efficiency
6. **State Machine Design**: Transaction and dialog modules implement proper SIP state machines as defined in RFC 3261

### Current Development Focus

Based on recent commits, the team is working on:
- Transaction handling improvements
- Response sending mechanisms (particularly initial 100 Trying responses)
- Dialog lifecycle management
- Message type and direction structure refinements
