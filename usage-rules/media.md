# Parrot Media Handling Rules

## MediaHandler Behaviour

The `Parrot.MediaHandler` behaviour provides callbacks for media session events.

### Required callback
```elixir
@impl true
def init(args), do: {:ok, initial_state}
```

### Key callbacks for audio playback
```elixir
# Called when media stream starts
def handle_stream_start(session_id, direction, state) do
  # Return media action
  {{:play, "audio.wav"}, state}
end

# Called when audio playback completes
def handle_play_complete(file_path, state) do
  # Return next action or :stop
  {:stop, state}
end
```

### Media actions
- `{:play, file_path}` - Play audio file
- `{:play, file_path, opts}` - Play with options
- `:stop` - Stop media
- `:pause` - Pause playback
- `:resume` - Resume playback
- `:noreply` - No action


### Codec negotiation
```elixir
def handle_codec_negotiation(offered, supported, state) do
  # Select preferred codec
  cond do
    :pcmu in offered and :pcmu in supported -> {:ok, :pcmu, state}
    :pcma in offered and :pcma in supported -> {:ok, :pcma, state}
    true -> {:error, :no_common_codec, state}
  end
end
```

## MediaSession Integration

Always create MediaSession in your SipHandler:

```elixir
def handle_invite(request, state) do
  {:ok, _pid} = Parrot.Media.MediaSession.start_link(
    id: "call_#{System.unique_integer()}",
    role: :uas,  # or :uac for outbound
    media_handler: __MODULE__,
    handler_args: %{welcome: "welcome.wav"}
  )
  
  # Process SDP and respond
  case Parrot.Media.MediaSession.process_offer(id, request.body) do
    {:ok, sdp_answer} -> {:respond, 200, "OK", %{}, sdp_answer}
    {:error, _} -> {:respond, 488, "Not Acceptable Here", %{}, ""}
  end
end
```
```
```
```
```

## Common Media Patterns

### Playlist
```elixir
def init(args) do
  {:ok, %{playlist: ["welcome.wav", "menu.wav", "goodbye.wav"], index: 0}}
end

def handle_stream_start(_, :outbound, state) do
  {{:play, Enum.at(state.playlist, 0)}, state}
end

def handle_play_complete(_, state) do
  next_index = state.index + 1
  if next_index < length(state.playlist) do
    {{:play, Enum.at(state.playlist, next_index)}, %{state | index: next_index}}
  else
    {:stop, state}
  end
end
```

