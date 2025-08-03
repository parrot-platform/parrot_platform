defmodule Parrot.Media.Handlers.WavPlayerHandler do
  @moduledoc """
  Example media handler that plays WAV files.

  This handler demonstrates how to:
  - Play a WAV file when media starts
  - Handle playback completion
  - Respond to DTMF input
  - Play different files based on events

  ## Example Usage

      # In your SIP handler
      def handle_invite(request, state) do
        # Create media session with WAV player handler
        {:ok, _pid} = MediaSession.start_link(
          id: session_id,
          dialog_id: dialog_id,
          role: :uas,
          media_handler: Parrot.Media.Handlers.WavPlayerHandler,
          handler_args: %{
            welcome_file: "/path/to/welcome.wav",
            menu_file: "/path/to/menu.wav",
            goodbye_file: "/path/to/goodbye.wav"
          }
        )
        
        # ... rest of INVITE handling
      end
  """

  @behaviour Parrot.MediaHandler

  require Logger

  @impl true
  def init(args) do
    # Set default files if not provided
    state =
      Map.merge(
        %{
          welcome_file: default_audio_file("welcome.wav"),
          menu_file: default_audio_file("menu.wav"),
          goodbye_file: default_audio_file("goodbye.wav"),
          music_file: default_audio_file("music.wav"),
          current_state: :init
        },
        args || %{}
      )

    {:ok, state}
  end

  @impl true
  def handle_session_start(session_id, _opts, state) do
    Logger.info("WavPlayerHandler: Session started #{session_id}")
    {:ok, state}
  end

  @impl true
  def handle_stream_start(session_id, :outbound, state) do
    Logger.info("WavPlayerHandler: Stream started for #{session_id}")

    # Play welcome message when stream starts
    if state.welcome_file && File.exists?(state.welcome_file) do
      Logger.info("WavPlayerHandler: Playing welcome file: #{state.welcome_file}")
      {{:play, state.welcome_file}, %{state | current_state: :welcome}}
    else
      # If no welcome file, play music
      Logger.info("WavPlayerHandler: No welcome file, playing music")
      {{:play, state.music_file || :default_audio}, %{state | current_state: :music}}
    end
  end

  @impl true
  def handle_play_complete(file_path, state) do
    Logger.info("WavPlayerHandler: Playback completed: #{file_path}")

    case state.current_state do
      :welcome ->
        # After welcome, play menu
        if state.menu_file && File.exists?(state.menu_file) do
          Logger.info("WavPlayerHandler: Playing menu file: #{state.menu_file}")
          {{:play, state.menu_file}, %{state | current_state: :menu}}
        else
          # No menu, just play music
          {{:play, state.music_file || :default_audio}, %{state | current_state: :music}}
        end

      :menu ->
        # After menu, stop playing
        Logger.info("WavPlayerHandler: Menu completed, stopping")
        {:stop, %{state | current_state: :done}}

      :music ->
        # Stop after music
        Logger.info("WavPlayerHandler: Music completed, stopping")
        {:stop, state}

      :goodbye ->
        # After goodbye, stop
        Logger.info("WavPlayerHandler: Goodbye completed, stopping")
        {:stop, state}

      _ ->
        # Default: play music
        {{:play, state.music_file || :default_audio}, state}
    end
  end

  # DTMF not implemented in initial version - will be added in Phase 2
  # def handle_dtmf(digit, _duration, state) do
  #   ...
  # end

  @impl true
  def handle_stream_error(session_id, error, state) do
    Logger.error("WavPlayerHandler: Stream error for #{session_id}, error: #{inspect(error)}")

    # On error, continue with default audio
    {:continue, state}
  end

  @impl true
  def handle_stream_stop(session_id, reason, state) do
    Logger.info("WavPlayerHandler: Stream stopped for #{session_id}, reason: #{inspect(reason)}")
    {:ok, state}
  end

  @impl true
  def handle_session_stop(session_id, reason, state) do
    Logger.info("WavPlayerHandler: Session stopped for #{session_id}, reason: #{inspect(reason)}")
    {:ok, state}
  end

  # Stubs for other callbacks - these are optional but let's implement minimal versions
  @impl true
  def handle_offer(_sdp, _direction, state), do: {:noreply, state}

  @impl true
  def handle_answer(_sdp, _direction, state), do: {:noreply, state}

  @impl true
  def handle_codec_negotiation(offered, supported, state) do
    # Simple codec selection - prefer opus, then pcmu, then pcma
    codec =
      cond do
        :opus in offered and :opus in supported ->
          :opus

        :pcmu in offered and :pcmu in supported ->
          :pcmu

        :pcma in offered and :pcma in supported ->
          :pcma

        true ->
          # Pick first common codec
          Enum.find(offered, fn c -> c in supported end)
      end

    if codec do
      {:ok, codec, state}
    else
      {:error, :no_common_codec, state}
    end
  end

  @impl true
  def handle_negotiation_complete(_local_sdp, _remote_sdp, _codec, state) do
    {:ok, state}
  end

  @impl true
  def handle_media_request(_request, state), do: {:error, :not_implemented, state}

  # Private functions

  defp default_audio_file(_filename) do
    # For now, use parrot-welcome.wav as the default for all audio files
    # In production, you would have different audio files for each purpose
    Path.join([
      :code.priv_dir(:parrot_platform),
      "audio",
      "parrot-welcome.wav"
    ])
  end
end
