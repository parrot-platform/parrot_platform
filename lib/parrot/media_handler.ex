defmodule Parrot.MediaHandler do
  @moduledoc """
  Behaviour for implementing media session handlers in Parrot.

  The `Parrot.MediaHandler` behaviour provides callbacks for handling media-specific
  events during SIP calls, including SDP negotiation, codec selection, media stream
  lifecycle, and real-time media events.

  ## Overview

  MediaHandler complements `Parrot.UasHandler` by providing fine-grained control over
  media sessions. While UasHandler manages SIP protocol events, MediaHandler focuses
  on the actual media streams (audio/video).

  Media handlers allow applications to:
  - Control audio playback with event-driven callbacks
  - Customize SDP offer/answer negotiation
  - Influence codec selection based on your preferences
  - React to media stream lifecycle events
  - Handle errors and recover gracefully
  - Build IVR systems, voicemail, music on hold, and more

  ## Basic Usage

  ```elixir
  defmodule MyApp.MediaHandler do
    @behaviour Parrot.MediaHandler

    @impl true
    def init(_args) do
      {:ok, %{preferred_codec: :opus}}
    end

    @impl true
    def handle_codec_negotiation(offered, supported, state) do
      # Prefer Opus over G.711
      cond do
        :opus in offered and :opus in supported ->
          {:ok, :opus, state}
        :pcmu in offered and :pcmu in supported ->
          {:ok, :pcmu, state}
        true ->
          {:error, :no_common_codec, state}
      end
    end

    @impl true
    def handle_stream_start(_session_id, :outbound, state) do
      # Play welcome message when call connects
      {{:play, "/audio/welcome.wav"}, state}
    end
    
    @impl true
    def handle_play_complete(file_path, state) do
      # After welcome, play menu or stop
      if file_path == "/audio/welcome.wav" do
        {{:play, "/audio/menu.wav"}, state}
      else
        {:stop, state}
      end
    end
  end
  ```

  ## Integration with UasHandler

  Typically, you'll implement both behaviours in your application:

  ```elixir
  defmodule MyApp do
    use Parrot.UasHandler
    @behaviour Parrot.MediaHandler
    
    # Handle incoming call
    @impl true
    def handle_invite(request, state) do
      # Create media session with this module as the handler
      {:ok, _pid} = Parrot.Media.MediaSession.start_link(
        id: "call_123",
        role: :uas,
        media_handler: __MODULE__,
        handler_args: %{welcome_file: "welcome.wav"}
      )
      
      # Process SDP and respond
      case Parrot.Media.MediaSession.process_offer("call_123", request.body) do
        {:ok, sdp_answer} ->
          {:respond, 200, "OK", %{}, sdp_answer}
        {:error, _} ->
          {:respond, 488, "Not Acceptable Here", %{}, ""}
      end
    end
    
    # MediaHandler callbacks...
  end
  ```

  ## Callback Flow

  The typical callback sequence for a call:

  1. `init/1` - Handler initialization
  2. `handle_session_start/3` - Media session created
  3. `handle_offer/3` - SDP offer received (optional)
  4. `handle_codec_negotiation/3` - Select codec
  5. `handle_negotiation_complete/4` - Negotiation done
  6. `handle_stream_start/3` - Media streaming begins
  7. `handle_play_complete/2` - Audio playback events (if playing)
  8. `handle_stream_stop/3` - Media streaming ends
  9. `handle_session_stop/3` - Cleanup

  ## Current Implementation

  The current implementation provides:
  - G.711 (PCMU/PCMA) codec support
  - Basic media control (play, stop, pause, resume)
  - Audio file playback with completion callbacks
  """

  @typedoc "Handler state - can be any term"
  @type state :: term()

  @typedoc "Media session ID"
  @type session_id :: String.t()

  @typedoc "SDP direction"
  @type direction :: :inbound | :outbound

  @typedoc "Codec atom"
  @type codec :: :pcmu | :pcma | :opus | atom()

  @typedoc """
  Media actions that can be returned from callbacks.

  - `{:play, file_path}` - Play an audio file
  - `{:play, file_path, opts}` - Play with options
  - `:stop` - Stop current media
  - `:pause` - Pause playback
  - `:resume` - Resume playback
  - `{:set_codec, codec}` - Switch codec
  - `:noreply` - No action
  """
  @type media_action ::
          {:play, file_path :: String.t()}
          | {:play, file_path :: String.t(), opts :: keyword()}
          | :stop
          | :pause
          | :resume
          | {:set_codec, codec()}
          | :noreply

  # Session Lifecycle Callbacks

  @doc """
  Initialize the media handler.

  Called when a new media session starts. This happens when MediaSession
  is started for a dialog.

  ## Parameters

  - `args` - Arguments passed when starting the handler

  ## Returns

  - `{:ok, state}` - Initialize with the given state
  - `{:stop, reason}` - Prevent the handler from starting

  ## Example

      @impl true
      def init(args) do
        {:ok, %{
          preferred_codec: :opus,
          quality_threshold: 5.0,
          play_queue: []
        }}
      end
  """
  @callback init(args :: term()) :: {:ok, state} | {:stop, reason :: term()}

  @doc """
  Handle media session start.

  Called when a media session is being established.

  ## Parameters

  - `session_id` - Unique session identifier
  - `opts` - Session options
  - `state` - Current handler state

  ## Returns

  - `{:ok, state}` - Session started successfully
  - `{:error, reason, state}` - Session start failed
  """
  @callback handle_session_start(session_id, opts :: keyword(), state) ::
              {:ok, state} | {:error, reason :: term(), state}

  @doc """
  Handle media session stop.

  Called when a media session is terminating.

  ## Parameters

  - `session_id` - Session identifier
  - `reason` - Termination reason
  - `state` - Current handler state

  ## Returns

  - `{:ok, state}` - Acknowledged
  """
  @callback handle_session_stop(session_id, reason :: term(), state) :: {:ok, state}

  # SDP Negotiation Callbacks

  @doc """
  Process an SDP offer.

  Called before the media session processes an SDP offer. The handler can
  modify the SDP or reject it.

  ## Parameters

  - `sdp` - The SDP offer as a string
  - `direction` - `:inbound` or `:outbound`
  - `state` - Current handler state

  ## Returns

  - `{:ok, modified_sdp, state}` - Use modified SDP
  - `{:reject, reason, state}` - Reject the offer
  - `{:noreply, state}` - Process SDP without modification
  """
  @callback handle_offer(sdp :: String.t(), direction, state) ::
              {:ok, modified_sdp :: String.t(), state}
              | {:reject, reason :: term(), state}
              | {:noreply, state}

  @doc """
  Process an SDP answer.

  Called before the media session finalizes an SDP answer.

  ## Parameters

  - `sdp` - The SDP answer as a string
  - `direction` - `:inbound` or `:outbound`
  - `state` - Current handler state

  ## Returns

  - `{:ok, modified_sdp, state}` - Use modified SDP
  - `{:reject, reason, state}` - Reject the answer
  - `{:noreply, state}` - Process SDP without modification
  """
  @callback handle_answer(sdp :: String.t(), direction, state) ::
              {:ok, modified_sdp :: String.t(), state}
              | {:reject, reason :: term(), state}
              | {:noreply, state}

  @doc """
  Customize codec selection.

  Called during SDP negotiation to select the best codec from offered
  and supported lists.

  ## Parameters

  - `offered_codecs` - Codecs offered by remote party
  - `supported_codecs` - Codecs supported locally
  - `state` - Current handler state

  ## Returns

  - `{:ok, codec, state}` - Select a single codec
  - `{:ok, codec_list, state}` - Return ordered preference list
  - `{:error, :no_common_codec, state}` - No acceptable codec

  ## Example

      @impl true
      def handle_codec_negotiation(offered, supported, state) do
        # Prefer Opus > G.711μ > G.711A
        cond do
          :opus in offered and :opus in supported ->
            {:ok, :opus, state}
          :pcmu in offered and :pcmu in supported ->
            {:ok, :pcmu, state}
          :pcma in offered and :pcma in supported ->
            {:ok, :pcma, state}
          true ->
            {:error, :no_common_codec, state}
        end
      end
  """
  @callback handle_codec_negotiation(
              offered_codecs :: [codec()],
              supported_codecs :: [codec()],
              state
            ) ::
              {:ok, codec(), state}
              | {:ok, [codec()], state}
              | {:error, :no_common_codec, state}

  @doc """
  Called after SDP negotiation completes.

  Provides the final negotiated parameters.

  ## Parameters

  - `local_sdp` - Final local SDP
  - `remote_sdp` - Final remote SDP
  - `selected_codec` - The negotiated codec
  - `state` - Current handler state

  ## Returns

  - `{:ok, state}` - Negotiation accepted
  - `{:error, reason, state}` - Reject the negotiation
  """
  @callback handle_negotiation_complete(
              local_sdp :: String.t(),
              remote_sdp :: String.t(),
              selected_codec :: codec(),
              state
            ) ::
              {:ok, state} | {:error, reason :: term(), state}

  # Media Stream Callbacks

  @doc """
  Handle media stream start.

  Called when media stream is about to start. Can return media actions
  to execute.

  ## Parameters

  - `session_id` - Session identifier
  - `direction` - `:inbound`, `:outbound`, or `:bidirectional`
  - `state` - Current handler state

  ## Returns

  - `media_action` - Single action to execute
  - `{media_action, state}` - Action with state update
  - `{[media_action], state}` - Multiple actions
  - `{:noreply, state}` - No action

  ## Example

      @impl true
      def handle_stream_start(_session_id, :inbound, state) do
        # Play welcome message
        {{:play, "/audio/welcome.wav"}, state}
      end
  """
  @callback handle_stream_start(
              session_id,
              direction :: :inbound | :outbound | :bidirectional,
              state
            ) ::
              media_action()
              | {media_action(), state}
              | {[media_action()], state}
              | {:noreply, state}

  @doc """
  Handle media stream stop.

  Called when media stream stops.

  ## Parameters

  - `session_id` - Session identifier
  - `reason` - Stop reason
  - `state` - Current handler state

  ## Returns

  - `{:ok, state}` - Acknowledged
  """
  @callback handle_stream_stop(session_id, reason :: term(), state) :: {:ok, state}

  @doc """
  Handle media stream errors.

  ## Parameters

  - `session_id` - Session identifier
  - `error` - Error details
  - `state` - Current handler state

  ## Returns

  - `{:retry, state}` - Retry the operation
  - `{:continue, state}` - Continue despite error
  - `{:stop, reason, state}` - Stop the stream
  """
  @callback handle_stream_error(session_id, error :: term(), state) ::
              {:retry, state} | {:continue, state} | {:stop, reason :: term(), state}

  # Media Control Callbacks

  @doc """
  Handle playback completion.

  Called when an audio file finishes playing.

  ## Parameters

  - `file_path` - Path of completed file
  - `state` - Current handler state

  ## Returns

  - `media_action` - Next action to execute
  - `{media_action, state}` - Action with state update
  - `{:noreply, state}` - No action
  """
  @callback handle_play_complete(file_path :: String.t(), state) ::
              media_action() | {media_action(), state} | {:noreply, state}

  @doc """
  Handle custom media requests.

  Allows for extensibility with custom requests.

  ## Parameters

  - `request` - Custom request
  - `state` - Current handler state

  ## Returns

  - `media_action` - Action to execute
  - `{media_action, state}` - Action with state update
  - `{:error, reason, state}` - Invalid request
  """
  @callback handle_media_request(request :: term(), state) ::
              media_action() | {media_action(), state} | {:error, reason :: term(), state}

  # Optional callbacks - all except init
  @optional_callbacks [
    handle_session_start: 3,
    handle_session_stop: 3,
    handle_offer: 3,
    handle_answer: 3,
    handle_codec_negotiation: 3,
    handle_negotiation_complete: 4,
    handle_stream_start: 3,
    handle_stream_stop: 3,
    handle_stream_error: 3,
    handle_play_complete: 2,
    handle_media_request: 2
  ]
end
