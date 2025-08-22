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
  def handle_ack(nil, _state), do: :noreply
  
  def handle_ack(request, _state) do
    Logger.info("[ParrotExampleUas] ACK received")

    dialog_id = Parrot.Sip.Dialog.from_message(request)
    start_media_for_dialog(dialog_id)
    :noreply
  end
  
  defp start_media_for_dialog(dialog_id) do
    with [{_pid, media_session_id}] <- Registry.lookup(Parrot.Registry, {:my_app_media, dialog_id.call_id}) do
      Logger.info("[ParrotExampleUas] Starting media playback for session: #{media_session_id}")
      Task.start(fn ->
        Process.sleep(100)
        Parrot.Media.MediaSession.start_media(media_session_id)
      end)
    else
      [] -> Logger.warning("[ParrotExampleUas] No media session found for call: #{dialog_id.call_id}")
    end
  end

  @impl true
  def handle_bye(nil, _state), do: {:respond, 200, "OK", %{}, ""}
  
  def handle_bye(request, _state) do
    Logger.info("[ParrotExampleUas] BYE received, ending call")
    
    request
    |> Parrot.Sip.Dialog.from_message()
    |> cleanup_media_session()
    
    {:respond, 200, "OK", %{}, ""}
  end
  
  defp cleanup_media_session(dialog_id) do
    case Registry.lookup(Parrot.Registry, {:my_app_media, dialog_id.call_id}) do
      [{_pid, media_session_id}] ->
        terminate_media_session(media_session_id)
        Registry.unregister(Parrot.Registry, {:my_app_media, dialog_id.call_id})
      [] ->
        Logger.info("[ParrotExampleUas] No media session found for call: #{dialog_id.call_id}")
    end
  end
  
  defp terminate_media_session(media_session_id) do
    Logger.info("[ParrotExampleUas] Terminating media session: #{media_session_id}")
    
    try do
      Parrot.Media.MediaSession.terminate_session(media_session_id)
    rescue
      RuntimeError ->
        Logger.warning("[ParrotExampleUas] Media session #{media_session_id} already terminated")
    end
  end

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
    
    codec = select_best_codec(offered_codecs, supported_codecs)
    
    case codec do
      nil ->
        Logger.error("  No common codec found!")
        {:error, :no_common_codec, state}
      _ ->
        Logger.info("  Selected codec: #{codec}")
        {:ok, codec, state}
    end
  end
  
  defp select_best_codec(offered, supported) do
    # Codec preference order
    [:opus, :pcmu, :pcma]
    |> Enum.find(&(&1 in offered and &1 in supported))
    |> Kernel.||(find_any_common_codec(offered, supported))
  end
  
  defp find_any_common_codec(offered, supported) do
    Enum.find(offered, &(&1 in supported))
  end
  
  @impl Parrot.MediaHandler
  def handle_negotiation_complete(_local_sdp, _remote_sdp, codec, state) do
    Logger.info("[ParrotExampleUas MediaHandler] Negotiation complete with codec: #{codec}")
    {:ok, Map.put(state, :negotiated_codec, codec)}
  end
  
  @impl Parrot.MediaHandler
  def handle_stream_start(session_id, direction, %{welcome_file: nil} = state) do
    Logger.info("[ParrotExampleUas MediaHandler] Stream started for #{session_id} (#{direction})")
    Logger.warning("  No welcome file configured")
    {:ok, state}
  end
  
  def handle_stream_start(session_id, direction, %{welcome_file: file} = state) do
    Logger.info("[ParrotExampleUas MediaHandler] Stream started for #{session_id} (#{direction})")
    
    if File.exists?(file) do
      Logger.info("  Playing welcome file: #{file}")
      {{:play, file}, %{state | current_state: :welcome}}
    else
      Logger.warning("  Welcome file not found: #{file}")
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
  def handle_play_complete(audio_file, handler_state) do
    Logger.info("[ParrotExampleUas] Playback complete for file: #{audio_file}")
    # For demo: loop the welcome file continuously
    case handler_state.current_state do
      :welcome ->
        # Loop back to welcome file
        {{:play, handler_state.welcome_file}, %{handler_state | current_state: :welcome}}
      _ ->
        # Stop after other states
        {:stop, handler_state}
    end
  end
  
  
  
  @impl Parrot.MediaHandler
  def handle_media_request({:play_dtmf, digits}, state) do
    Logger.info("[ParrotExampleUas MediaHandler] Media request: play_dtmf")
    Logger.info("  Playing DTMF digits: #{digits}")
    {:ok, :dtmf_played, state}
  end
  
  def handle_media_request({:adjust_volume, level}, state) do
    Logger.info("[ParrotExampleUas MediaHandler] Media request: adjust_volume")
    Logger.info("  Adjusting volume to: #{level}")
    {:ok, :volume_adjusted, state}
  end
  
  def handle_media_request(request, state) do
    Logger.info("[ParrotExampleUas MediaHandler] Media request: #{inspect(request)}")
    Logger.warning("  Unknown media request")
    {:error, :unknown_request, state}
  end

  # Private functions

  defp process_invite(nil, _state) do
    Logger.error("[ParrotExampleUas] Cannot process nil INVITE")
    {:respond, 500, "Internal Server Error", %{}, ""}
  end

  defp process_invite(request, _state) do
    log_invite_from(request)
    
    dialog_id = Parrot.Sip.Dialog.from_message(request)
    dialog_id_str = Parrot.Sip.Dialog.to_string(dialog_id)
    media_session_id = "media_#{dialog_id_str}"
    audio_config = build_audio_config()

    with {:ok, _pid} <- start_media_session(media_session_id, dialog_id_str, audio_config),
         {:ok, sdp_answer} <- Parrot.Media.MediaSession.process_offer(media_session_id, request.body) do
      Logger.info("[ParrotExampleUas] Call accepted, SDP negotiated")
      Registry.register(Parrot.Registry, {:my_app_media, dialog_id.call_id}, media_session_id)
      {:respond, 200, "OK", %{}, sdp_answer}
    else
      {:error, :sdp_negotiation_failed = reason} ->
        Logger.error("[ParrotExampleUas] SDP negotiation failed: #{inspect(reason)}")
        {:respond, 488, "Not Acceptable Here", %{}, ""}
      {:error, reason} ->
        Logger.error("[ParrotExampleUas] Failed to create media session: #{inspect(reason)}")
        {:respond, 500, "Internal Server Error", %{}, ""}
    end
  end
  
  defp log_invite_from(%{headers: %{"from" => from}}) do
    caller = from.display_name || from.uri.user
    Logger.info("[ParrotExampleUas] Processing INVITE from: #{caller}")
  end
  
  defp build_audio_config do
    priv_dir = :code.priv_dir(:parrot_platform)
    audio_file = Path.join(priv_dir, "audio/parrot-welcome.wav")
    
    %{
      welcome_file: audio_file,
      menu_file: audio_file,  # Using same file for demo
      music_file: audio_file,
      goodbye_file: audio_file,
      current_state: :welcome
    }
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
      supported_codecs: [:opus, :pcma]  # Prefer OPUS, fallback to G.711 A-law
    )
  end

  # Media handler callbacks for Membrane pipeline
  def handle_playback_started(session_id, audio_file, handler_state) do
    Logger.info("[ParrotExampleUas] Playback started for session #{session_id}")
    Logger.info("  Playing file: #{audio_file}")
    handler_state
  end

end
