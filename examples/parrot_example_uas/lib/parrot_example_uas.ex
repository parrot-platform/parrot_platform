defmodule ParrotExampleUas do
  @moduledoc """
  Example SIP application built using Parrot Framework.
  This demonstrates how to build a simple UAS (User Agent Server) that answers calls and plays audio.
  """

  use Parrot.UasHandler
  @behaviour Parrot.MediaHandler
  require Logger

  def start(opts \\ []) do
    port = Keyword.get(opts, :port, 5060)

    Logger.info("Starting ParrotExampleUas on port #{port}")
    Logger.info("Connect your SIP client to sip:service@<your-ip>:#{port}")

    # Start the SIP transport with our handler
    # Handler controls logging configuration:
    # - log_level: Controls the log level for transport messages (:debug, :info, :warning, :error)
    # - sip_trace: When true, logs full SIP messages regardless of log level
    handler = Parrot.Sip.Handler.new(
      Parrot.Sip.HandlerAdapter.Core,
      {__MODULE__, %{calls: %{}}},
      log_level: :info,      # Only show info and above from transport
      sip_trace: true        # But always show full SIP messages for debugging
    )

    case Parrot.Sip.Transport.StateMachine.start_udp(%{
      handler: handler,
      listen_port: port
    }) do
      :ok ->
        Logger.info("ParrotExampleUas started successfully!")
        :ok
      {:error, {:already_started, _pid}} = error ->
        Logger.info("ParrotExampleUas already running on port #{port}")
        error
    end
  end

  # Transaction callbacks for INVITE state machine
  @impl true
  def handle_transaction_invite_trying(_request, _transaction, _state) do
    Logger.info("[ParrotExampleUas] INVITE transaction: trying")
    :noreply
  end

  @impl true
  def handle_transaction_invite_proceeding(request, _transaction, state) do
    Logger.info("[ParrotExampleUas] INVITE transaction: proceeding")
    # Process the INVITE in the proceeding state
    process_invite(request, state)
  end

  @impl true
  def handle_transaction_invite_completed(_request, _transaction, _state) do
    Logger.info("[ParrotExampleUas] INVITE transaction: completed")
    :noreply
  end

  # Main SIP method handlers
  @impl true
  def handle_invite(request, state) do
    Logger.info("[ParrotExampleUas] Direct INVITE handler called")
    process_invite(request, state)
  end

  @impl true
  def handle_ack(request, _state) when not is_nil(request) do
    Logger.info("[ParrotExampleUas] ACK received")

    dialog_id = Parrot.Sip.DialogId.from_message(request)

    # Find and start the media session
    case Registry.lookup(Parrot.Registry, {:my_app_media, dialog_id.call_id}) do
      [{_pid, media_session_id}] ->
        Logger.info("[ParrotExampleUas] Starting media playback for session: #{media_session_id}")
        Task.start(fn ->
          Process.sleep(100)
          Parrot.Media.MediaSession.start_media(media_session_id)
        end)
      [] ->
        Logger.warning("[ParrotExampleUas] No media session found for call: #{dialog_id.call_id}")
    end

    :noreply
  end

  def handle_ack(nil, _state), do: :noreply

  @impl true
  def handle_bye(request, _state) when not is_nil(request) do
    Logger.info("[ParrotExampleUas] BYE received, ending call")

    dialog_id = Parrot.Sip.DialogId.from_message(request)

    # Clean up media session
    case Registry.lookup(Parrot.Registry, {:my_app_media, dialog_id.call_id}) do
      [{_pid, media_session_id}] ->
        Logger.info("[ParrotExampleUas] Terminating media session: #{media_session_id}")
        # Safely terminate the media session - it might already be gone
        try do
          Parrot.Media.MediaSession.terminate_session(media_session_id)
        rescue
          RuntimeError ->
            Logger.warning("[ParrotExampleUas] Media session #{media_session_id} already terminated")
        end
        Registry.unregister(Parrot.Registry, {:my_app_media, dialog_id.call_id})
      [] ->
        Logger.info("[ParrotExampleUas] No media session found for call: #{dialog_id.call_id}")
    end

    {:respond, 200, "OK", %{}, ""}
  end

  def handle_bye(nil, _state), do: {:respond, 200, "OK", %{}, ""}

  @impl true
  def handle_cancel(_request, _state) do
    Logger.info("[ParrotExampleUas] CANCEL received")
    {:respond, 200, "OK", %{}, ""}
  end

  @impl true
  def handle_options(_request, _state) do
    Logger.info("[ParrotExampleUas] OPTIONS received")
    allow_methods = "INVITE, ACK, BYE, CANCEL, OPTIONS, INFO"
    {:respond, 200, "OK", %{"Allow" => allow_methods}, ""}
  end

  @impl true
  def handle_register(_request, _state) do
    Logger.info("[ParrotExampleUas] REGISTER received")
    {:respond, 200, "OK", %{}, ""}
  end

  @impl true
  def handle_info(_request, _state) do
    Logger.info("[ParrotExampleUas] INFO received")
    {:respond, 200, "OK", %{}, ""}
  end

  # MediaHandler callbacks
  
  @impl Parrot.MediaHandler
  def init(args) do
    Logger.info("[ParrotExampleUas MediaHandler] Initializing with args: #{inspect(args)}")
    # Initialize with audio configuration
    state = Map.merge(%{
      welcome_file: nil,
      menu_file: nil,
      music_file: nil,
      goodbye_file: nil,
      current_state: :init,
      call_stats: %{
        packets_received: 0,
        packets_lost: 0,
        jitter: 0
      }
    }, args || %{})
    
    {:ok, state}
  end
  
  @impl Parrot.MediaHandler
  def handle_session_start(session_id, opts, state) do
    Logger.info("[ParrotExampleUas MediaHandler] Session started: #{session_id}")
    Logger.info("  Options: #{inspect(opts)}")
    {:ok, Map.put(state, :session_id, session_id)}
  end
  
  @impl Parrot.MediaHandler
  def handle_session_stop(session_id, reason, state) do
    Logger.info("[ParrotExampleUas MediaHandler] Session stopped: #{session_id}, reason: #{inspect(reason)}")
    # Log final call statistics
    Logger.info("  Final call stats: #{inspect(state.call_stats)}")
    {:ok, state}
  end
  
  @impl Parrot.MediaHandler
  def handle_offer(sdp, direction, state) do
    Logger.info("[ParrotExampleUas MediaHandler] Received SDP offer (#{direction})")
    Logger.debug("  SDP: #{String.trim(sdp)}")
    {:noreply, state}
  end
  
  @impl Parrot.MediaHandler
  def handle_answer(sdp, direction, state) do
    Logger.info("[ParrotExampleUas MediaHandler] Received SDP answer (#{direction})")
    Logger.debug("  SDP: #{String.trim(sdp)}")
    {:noreply, state}
  end
  
  @impl Parrot.MediaHandler
  def handle_codec_negotiation(offered_codecs, supported_codecs, state) do
    Logger.info("[ParrotExampleUas MediaHandler] Negotiating codecs")
    Logger.info("  Offered: #{inspect(offered_codecs)}")
    Logger.info("  Supported: #{inspect(supported_codecs)}")
    
    # Prefer opus, then pcmu, then pcma
    codec = cond do
      :opus in offered_codecs and :opus in supported_codecs -> :opus
      :pcmu in offered_codecs and :pcmu in supported_codecs -> :pcmu
      :pcma in offered_codecs and :pcma in supported_codecs -> :pcma
      true -> 
        # Pick first common codec
        Enum.find(offered_codecs, fn c -> c in supported_codecs end)
    end
    
    if codec do
      Logger.info("  Selected codec: #{codec}")
      {:ok, codec, state}
    else
      Logger.error("  No common codec found!")
      {:error, :no_common_codec, state}
    end
  end
  
  @impl Parrot.MediaHandler
  def handle_negotiation_complete(_local_sdp, _remote_sdp, codec, state) do
    Logger.info("[ParrotExampleUas MediaHandler] Negotiation complete with codec: #{codec}")
    {:ok, Map.put(state, :negotiated_codec, codec)}
  end
  
  @impl Parrot.MediaHandler
  def handle_stream_start(session_id, direction, state) do
    Logger.info("[ParrotExampleUas MediaHandler] Stream started for #{session_id} (#{direction})")
    
    # Start playing welcome message
    if state.welcome_file && File.exists?(state.welcome_file) do
      Logger.info("  Playing welcome file: #{state.welcome_file}")
      {{:play, state.welcome_file}, %{state | current_state: :welcome}}
    else
      Logger.warning("  No welcome file configured")
      {:ok, state}
    end
  end
  
  @impl Parrot.MediaHandler
  def handle_stream_stop(session_id, reason, state) do
    Logger.info("[ParrotExampleUas MediaHandler] Stream stopped for #{session_id}, reason: #{inspect(reason)}")
    {:ok, state}
  end
  
  @impl Parrot.MediaHandler
  def handle_stream_error(session_id, error, state) do
    Logger.error("[ParrotExampleUas MediaHandler] Stream error for #{session_id}: #{inspect(error)}")
    # Continue playing despite errors
    {:continue, state}
  end
  
  @impl Parrot.MediaHandler
  def handle_play_complete(file_path, state) do
    Logger.info("[ParrotExampleUas MediaHandler] Playback completed: #{file_path}")
    
    case state.current_state do
      :welcome ->
        # After welcome, play menu if available
        cond do
          state.menu_file && (state.menu_file == "menu.wav" || File.exists?(state.menu_file)) ->
            Logger.info("  Playing menu file: #{state.menu_file}")
            {{:play, state.menu_file}, %{state | current_state: :menu}}
          true ->
            # No menu, stop
            Logger.info("  No menu file, stopping playback")
            {:stop, %{state | current_state: :done}}
        end
        
      :menu ->
        # After menu, stop (in a real app, you might wait for DTMF)
        Logger.info("  Menu completed, stopping playback")
        {:stop, %{state | current_state: :done}}
        
      _ ->
        # Default: stop
        {:stop, state}
    end
  end
  
  
  
  @impl Parrot.MediaHandler
  def handle_media_request(request, state) do
    Logger.info("[ParrotExampleUas MediaHandler] Media request: #{inspect(request)}")
    
    case request do
      {:play_dtmf, digits} ->
        Logger.info("  Playing DTMF digits: #{digits}")
        {:ok, :dtmf_played, state}
        
      {:adjust_volume, level} ->
        Logger.info("  Adjusting volume to: #{level}")
        {:ok, :volume_adjusted, state}
        
      _ ->
        Logger.warning("  Unknown media request")
        {:error, :unknown_request, state}
    end
  end

  # Private functions

  defp process_invite(nil, _state) do
    Logger.error("[ParrotExampleUas] Cannot process nil INVITE")
    {:respond, 500, "Internal Server Error", %{}, ""}
  end

  defp process_invite(request, _state) do
    from = request.headers["from"]
    Logger.info("[ParrotExampleUas] Processing INVITE from: #{from.display_name || from.uri.user}")

    dialog_id = Parrot.Sip.DialogId.from_message(request)
    dialog_id_str = Parrot.Sip.DialogId.to_string(dialog_id)
    media_session_id = "media_#{dialog_id_str}"

    # Configure audio files for this call
    priv_dir = :code.priv_dir(:parrot_platform)
    audio_config = %{
      welcome_file: Path.join(priv_dir, "audio/parrot-welcome.wav"),
      menu_file: Path.join(priv_dir, "audio/parrot-welcome.wav"),  # Using same file for demo
      music_file: Path.join(priv_dir, "audio/parrot-welcome.wav"),
      goodbye_file: Path.join(priv_dir, "audio/parrot-welcome.wav"),
      current_state: :welcome
    }

    # Start media session
    case start_media_session(media_session_id, dialog_id_str, audio_config) do
      {:ok, _pid} ->
        # Process SDP offer and generate answer
        case Parrot.Media.MediaSession.process_offer(media_session_id, request.body) do
          {:ok, sdp_answer} ->
            Logger.info("[ParrotExampleUas] Call accepted, SDP negotiated")

            # Register media session for later lookup
            Registry.register(Parrot.Registry, {:my_app_media, dialog_id.call_id}, media_session_id)

            {:respond, 200, "OK", %{}, sdp_answer}

          {:error, reason} ->
            Logger.error("[ParrotExampleUas] SDP negotiation failed: #{inspect(reason)}")
            {:respond, 488, "Not Acceptable Here", %{}, ""}
        end

      {:error, reason} ->
        Logger.error("[ParrotExampleUas] Failed to create media session: #{inspect(reason)}")
        {:respond, 500, "Internal Server Error", %{}, ""}
    end
  end

  defp start_media_session(session_id, dialog_id, audio_config) do
    Parrot.Media.MediaSessionSupervisor.start_session(
      id: session_id,
      dialog_id: dialog_id,
      role: :uas,
      owner: self(),
      audio_file: audio_config.welcome_file,
      media_handler: __MODULE__,
      handler_args: audio_config,
      supported_codecs: [:pcma]  # Only G.711 A-law for now (Opus send not implemented)
    )
  end

end
