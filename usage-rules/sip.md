# Parrot SIP Protocol Rules

## SipHandler Behaviour

The `Parrot.SipHandler` behaviour manages SIP protocol events.

### Core callbacks

```elixir
# Required initialization
def init(args), do: {:ok, initial_state}

# Main SIP methods
def handle_invite(request, state)  # Incoming call
def handle_ack(request, state)     # Call confirmation
def handle_bye(request, state)     # Call termination
def handle_cancel(request, state)  # Call cancellation

# Catch-all for other methods
def handle_request(request, state) # OPTIONS, REGISTER, etc.

# Response handling
def handle_response(response, state)

# State change notifications
def handle_transaction_state(old_state, new_state, direction, state)
def handle_dialog_state(old_state, new_state, state)
```

### Response formats

```elixir
# Send response
{:respond, status_code, reason, headers, body, new_state}
{:respond, 200, "OK", %{"content-type" => "application/sdp"}, sdp, state}

# No response needed
{:ok, new_state}

# Error
{:error, reason, new_state}
```

## Message Structure

Always pattern match on message fields:

```elixir
def handle_invite(%{
  method: "INVITE",
  headers: headers,
  body: sdp_offer,
  source: source
} = request, state) do
  # Access headers with pattern matching
  %{"from" => from, "to" => to, "call-id" => call_id} = headers
  
  # Process the request
end
```

### Important headers
- `"from"` - Caller identity (From header)
- `"to"` - Called party (To header)
- `"call-id"` - Unique call identifier
- `"cseq"` - Command sequence
- `"via"` - Request path
- `"contact"` - Direct contact address

## Transaction Management

Transactions are managed automatically by Parrot:

```elixir
# Monitor transaction states
def handle_transaction_state(:trying, :proceeding, :server, state) do
  # Server transaction received provisional response
  {:ok, state}
end

def handle_transaction_state(:proceeding, :completed, :server, state) do
  # Server transaction sent final response
  {:ok, state}
end
```

Transaction states:
- `:trying` - Initial state
- `:proceeding` - Provisional response sent/received
- `:completed` - Final response sent/received
- `:confirmed` - ACK received (INVITE only)
- `:terminated` - Transaction ended

## Dialog Management

Dialogs track established calls:

```elixir
def handle_dialog_state(:init, :early, state) do
  # Dialog established with provisional response
  {:ok, state}
end

def handle_dialog_state(:early, :confirmed, state) do
  # Dialog confirmed with 2xx response
  # Media can now flow
  {:ok, state}
end

def handle_dialog_state(_, :terminated, state) do
  # Dialog ended - cleanup resources
  {:ok, state}
end
```

## Common SIP Patterns

### Accept call with media
```elixir
def handle_invite(request, state) do
  # Start media session
  {:ok, _} = Parrot.Media.MediaSession.start_link(
    id: request.headers["call-id"],
    role: :uas,
    media_handler: MyMediaHandler
  )
  
  # Send 180 Ringing first
  send_response(request, 180, "Ringing")
  
  # Then 200 OK with SDP
  {:respond, 200, "OK", %{"content-type" => "application/sdp"}, sdp_answer, state}
end
```

### Reject call
```elixir
def handle_invite(request, state) do
  # Various rejection codes
  {:respond, 486, "Busy Here", %{}, "", state}      # Busy
  {:respond, 603, "Decline", %{}, "", state}        # Rejected
  {:respond, 404, "Not Found", %{}, "", state}      # Unknown user
  {:respond, 488, "Not Acceptable Here", %{}, "", state}  # Codec mismatch
end
```

### Handle OPTIONS (keepalive)
```elixir
def handle_request(%{method: "OPTIONS"} = request, state) do
  headers = %{
    "accept" => "application/sdp",
    "allow" => "INVITE, ACK, BYE, CANCEL, OPTIONS"
  }
  {:respond, 200, "OK", headers, "", state}
end
```

### Early media (183 Session Progress)
```elixir
def handle_invite(request, state) do
  # Start media before answering
  {:ok, _} = start_media_session(request)
  
  # Send 183 with SDP for early media
  {:respond, 183, "Session Progress", 
   %{"content-type" => "application/sdp"}, 
   sdp_answer, state}
end
```

## Error Handling

Always handle errors gracefully:

```elixir
def handle_invite(request, state) do
  case process_invite(request) do
    {:ok, sdp} ->
      {:respond, 200, "OK", %{"content-type" => "application/sdp"}, sdp, state}
    
    {:error, :no_codec} ->
      {:respond, 488, "Not Acceptable Here", %{}, "", state}
    
    {:error, :busy} ->
      {:respond, 486, "Busy Here", %{}, "", state}
    
    {:error, _} ->
      {:respond, 500, "Internal Server Error", %{}, "", state}
  end
end
```