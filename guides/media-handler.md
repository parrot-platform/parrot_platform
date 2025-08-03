# MediaHandler Behaviour Guide

The `Parrot.MediaHandler` behaviour provides a comprehensive callback system for handling media session events in your VoIP applications. This guide explains how to implement and use the MediaHandler to control audio playback, handle codec negotiation, and more.

## Overview

MediaHandler complements the SipHandler behaviour by providing callbacks specifically for media-related events. While SipHandler manages SIP protocol events, MediaHandler focuses on the media streams themselves.

## Implementation Pattern

The typical pattern is to implement both behaviours in your application module:

```elixir
defmodule MyVoIPApp do
  use Parrot.SipHandler
  @behaviour Parrot.MediaHandler
  
  # Your implementation...
end
```

## Core Callbacks

### Session Lifecycle

#### `init/1`

Called when the media handler is initialized. Use this to set up your initial state.

```elixir
@impl Parrot.MediaHandler
def init(args) do
  state = %{
    welcome_file: args[:welcome_file] || "default_welcome.wav",
    music_files: args[:music_files] || [],
    current_track: 0
  }
  {:ok, state}
end
```

#### `handle_session_start/3`

Called when a media session starts. This is your opportunity to prepare for media streaming.

```elixir
@impl Parrot.MediaHandler
def handle_session_start(session_id, opts, state) do
  Logger.info("Media session #{session_id} started")
  {:ok, Map.put(state, :session_id, session_id)}
end
```

#### `handle_session_stop/3`

Called when a media session ends. Clean up any resources here.

```elixir
@impl Parrot.MediaHandler
def handle_session_stop(session_id, reason, state) do
  Logger.info("Media session #{session_id} stopped: #{inspect(reason)}")
  {:ok, state}
end
```

### SDP Negotiation

#### `handle_offer/3`

Called when an SDP offer is received. You can inspect or log the offer.

```elixir
@impl Parrot.MediaHandler
def handle_offer(sdp, direction, state) do
  Logger.info("Received SDP offer (#{direction})")
  Logger.debug("SDP: #{sdp}")
  {:noreply, state}
end
```

#### `handle_codec_negotiation/3`

This is where you can influence codec selection. Return your preferred codec from the available options.

```elixir
@impl Parrot.MediaHandler
def handle_codec_negotiation(offered_codecs, supported_codecs, state) do
  # Prefer Opus, then PCMU, then PCMA
  codec = cond do
    :opus in offered_codecs and :opus in supported_codecs -> :opus
    :pcmu in offered_codecs and :pcmu in supported_codecs -> :pcmu
    :pcma in offered_codecs and :pcma in supported_codecs -> :pcma
    true -> hd(offered_codecs) # Fallback to first offered
  end
  
  {:ok, codec, state}
end
```

### Media Streaming

#### `handle_stream_start/3`

Called when media streaming begins. This is typically where you start playing audio.

```elixir
@impl Parrot.MediaHandler
def handle_stream_start(session_id, :outbound, state) do
  # Start playing welcome message
  {{:play, state.welcome_file}, state}
end
```

Return values:
- `{{:play, file_path}, new_state}` - Play an audio file
- `{{:play, file_path, opts}, new_state}` - Play with options
- `{:ok, new_state}` - Continue without playing
- `{:stop, new_state}` - Stop the stream

#### `handle_play_complete/2`

Called when audio playback finishes. Perfect for implementing IVR flows or playlists.

```elixir
@impl Parrot.MediaHandler
def handle_play_complete(file_path, state) do
  case state.current_state do
    :welcome ->
      # After welcome, play menu
      {{:play, "menu.wav"}, %{state | current_state: :menu}}
      
    :menu ->
      # After menu, wait for input
      {:ok, %{state | current_state: :waiting}}
      
    :music ->
      # Play next track in playlist
      next_track = rem(state.current_track + 1, length(state.music_files))
      file = Enum.at(state.music_files, next_track)
      {{:play, file}, %{state | current_track: next_track}}
      
    _ ->
      {:stop, state}
  end
end
```

### Error Handling

#### `handle_stream_error/3`

Called when stream errors occur. Decide whether to retry, continue, or stop.

```elixir
@impl Parrot.MediaHandler
def handle_stream_error(session_id, error, state) do
  Logger.error("Stream error in #{session_id}: #{inspect(error)}")
  
  case error do
    {:file_not_found, _} ->
      # Play fallback audio
      {{:play, "error_message.wav"}, state}
      
    {:network_error, _} ->
      # Retry
      {:retry, state}
      
    _ ->
      # Continue despite error
      {:continue, state}
  end
end
```

## Complete Example: IVR System

Here's a complete example implementing a simple IVR (Interactive Voice Response) system:

```elixir
defmodule IVRApp do
  use Parrot.SipHandler
  @behaviour Parrot.MediaHandler
  require Logger
  
  # SIP Handler - Accept incoming calls
  @impl true
  def handle_invite(request, state) do
    dialog_id = Parrot.Sip.DialogId.from_message(request)
    media_session_id = "media_#{dialog_id}"
    
    # Start media session with IVR handler
    {:ok, _pid} = Parrot.Media.MediaSession.start_link(
      id: media_session_id,
      dialog_id: dialog_id,
      role: :uas,
      media_handler: __MODULE__,
      handler_args: %{
        menu_options: %{
          "1" => "sales.wav",
          "2" => "support.wav",
          "3" => "hours.wav"
        }
      }
    )
    
    # Process SDP and accept call
    case Parrot.Media.MediaSession.process_offer(media_session_id, request.body) do
      {:ok, sdp_answer} ->
        {:respond, 200, "OK", %{}, sdp_answer}
      {:error, _reason} ->
        {:respond, 488, "Not Acceptable Here", %{}, ""}
    end
  end
  
  # MediaHandler - IVR Logic
  @impl Parrot.MediaHandler
  def init(args) do
    state = %{
      menu_options: args[:menu_options] || %{},
      current_state: :init
    }
    {:ok, state}
  end
  
  @impl Parrot.MediaHandler
  def handle_stream_start(_session_id, :outbound, state) do
    # Play welcome and menu
    {{:play, "welcome_menu.wav"}, %{state | current_state: :menu}}
  end
  
  @impl Parrot.MediaHandler
  def handle_play_complete(_file_path, state) do
    case state.current_state do
      :menu ->
        # After menu, could implement more options here
        {:ok, %{state | current_state: :done}}
        
      :playing_option ->
        # Return to menu after option
        {{:play, "welcome_menu.wav"}, %{state | current_state: :menu}}
        
      _ ->
        {:ok, state}
    end
  end
end
```

## Best Practices

1. **State Management**: Keep your handler state lightweight and focused on media control.

2. **Error Handling**: Always implement `handle_stream_error/3` to gracefully handle failures.

3. **Resource Cleanup**: Use `handle_session_stop/3` to clean up any resources.

4. **Codec Preferences**: Implement `handle_codec_negotiation/3` to ensure optimal codec selection.

5. **Logging**: Log important events in your callbacks.

6. **File Paths**: Use absolute paths or paths relative to `:code.priv_dir/1` for audio files.

## Integration with SipHandler

The MediaHandler works seamlessly with SipHandler. Here's the typical flow:

1. SipHandler receives INVITE
2. Create MediaSession with your MediaHandler
3. MediaHandler callbacks manage the media stream
4. SipHandler handles BYE to end the call

```elixir
# In your SipHandler
def handle_invite(request, state) do
  # Create media session
  {:ok, _pid} = MediaSession.start_link(
    media_handler: __MODULE__,
    handler_args: %{} # Your handler args
  )
  # ... rest of INVITE handling
end

def handle_bye(request, state) do
  # MediaSession will call handle_session_stop/3
  MediaSession.terminate_session(session_id)
  {:respond, 200, "OK", %{}, ""}
end
```

## Future Features

The MediaHandler behaviour is designed to be extensible. Future releases will add:

- Video streaming support
- Advanced codec options (Opus support coming soon)
- Real-time transcription hooks

## Conclusion

The MediaHandler behaviour provides a powerful and flexible way to control media in your VoIP applications. By implementing these callbacks, you can create sophisticated IVR systems, music on hold, voicemail, and other media-rich features.

For a complete working example, see the `ParrotExampleApp` in the `examples/simple_uas_app/` directory.