defmodule ParrotSupport.UasHandler do
  require Logger

  use Parrot.UasHandler

  alias Parrot.Media.MediaSessionSupervisor
  alias Parrot.Media.MediaSession
  alias Parrot.Sip.Dialog

  # Use process dictionary to store media session mappings
  # In production, consider using Registry or ETS

  @impl true
  def handle_transaction_invite_trying(_request, _trans, _state) do
    Logger.info("INVITE transaction in trying state")

    # Don't send anything here - let handle_invite handle the response
    :noreply
  end

  @impl true
  def handle_transaction_invite_proceeding(_request, _trans, _state) do
    Logger.info("INVITE transaction in proceeding state")

    # This will call transaction_proceeding({:call, from}, :complete, data) in the handler_adapter
    # {:ok, _response} = :gen_statem.call(trans, :complete)

    :noreply
  end

  @impl true
  def handle_invite(request, state) do
    Logger.info("[UasHandler] Received INVITE request")

    # Extract dialog ID from request
    dialog_id = Dialog.from_message(request)
    dialog_id_str = Dialog.to_string(dialog_id)

    Logger.info("[UasHandler] Dialog ID: #{dialog_id_str}")

    # Extract SDP offer from request body
    sdp_offer = request.body
    Logger.debug("[UasHandler] SDP offer received: #{String.trim(sdp_offer)}")

    # Create a media session for this dialog
    session_id = "media_#{dialog_id_str}"

    Logger.info("[UasHandler] Creating media session with ID: #{session_id}")

    case MediaSessionSupervisor.start_session(
           id: session_id,
           dialog_id: dialog_id_str,
           role: :uas,
           owner: self(),
           audio_file: Path.join(:code.priv_dir(:parrot_platform), "audio/parrot-welcome.wav"),
           media_handler: Parrot.Media.Handlers.WavPlayerHandler,
           handler_args: %{
             welcome_file:
               Path.join(:code.priv_dir(:parrot_platform), "audio/parrot-welcome.wav"),
             menu_file: Path.join(:code.priv_dir(:parrot_platform), "audio/parrot-welcome.wav")
           }
         ) do
      {:ok, pid} ->
        Logger.info("[UasHandler] Media session started with PID: #{inspect(pid)}")
        # Process the SDP offer and generate answer
        case MediaSession.process_offer(session_id, sdp_offer) do
          {:ok, sdp_answer} ->
            Logger.info("[UasHandler] Generated SDP answer for dialog #{dialog_id_str}")
            Logger.debug("[UasHandler] SDP answer: #{String.trim(sdp_answer)}")

            # Store media session ID in state for later use
            _updated_state = Map.put(state, :media_session_id, session_id)

            # Store media session ID in Registry for cross-process access
            # Store by call-id for simpler lookup
            Registry.register(Parrot.Registry, {:media_session, dialog_id.call_id}, session_id)

            Logger.info(
              "[UasHandler] Registered media session #{session_id} for call-id #{dialog_id.call_id}"
            )

            # Return 200 OK with SDP answer
            {:respond, 200, "OK", %{}, sdp_answer}

          {:error, reason} ->
            Logger.error("[UasHandler] Failed to process SDP offer: #{inspect(reason)}")
            # Return error response
            {:respond, 488, "Not Acceptable Here", %{}, ""}
        end

      {:error, reason} ->
        Logger.error("[UasHandler] Failed to start media session: #{inspect(reason)}")
        # Return error response
        {:respond, 500, "Internal Server Error", %{}, ""}
    end
  end

  @impl true
  def handle_options(_request, _state) do
    Logger.info("Received OPTIONS request")
    {:respond, 200, "OK", %{}, ""}
  end

  @impl true
  def handle_bye(request, _state) do
    Logger.info("[UasHandler] Received BYE request")

    # Get dialog ID from request
    dialog_id = Dialog.from_message(request)
    _dialog_id_str = Dialog.to_string(dialog_id)

    # Get media session ID from Registry
    case Registry.lookup(Parrot.Registry, {:media_session, dialog_id.call_id}) do
      [{_pid, session_id}] ->
        Logger.info("[UasHandler] Terminating media session #{session_id}")

        try do
          MediaSession.terminate_session(session_id)
        rescue
          RuntimeError ->
            Logger.warning("[UasHandler] Media session #{session_id} already terminated")
        end

        # Unregister from Registry
        Registry.unregister(Parrot.Registry, {:media_session, dialog_id.call_id})

      [] ->
        Logger.debug(
          "[UasHandler] No media session to terminate for call-id #{dialog_id.call_id}"
        )
    end

    {:respond, 200, "OK", %{}, ""}
  end

  @impl true
  def handle_ack(request, _state) do
    Logger.info("[UasHandler] Received ACK request")

    # Get dialog ID from request
    dialog_id = Dialog.from_message(request)
    _dialog_id_str = Dialog.to_string(dialog_id)

    # Get media session ID from Registry
    case Registry.lookup(Parrot.Registry, {:media_session, dialog_id.call_id}) do
      [{_pid, session_id}] ->
        Logger.info(
          "[UasHandler] Found media session #{session_id} for call-id #{dialog_id.call_id}"
        )

        Logger.info("[UasHandler] Starting media for session #{session_id}")

        case MediaSession.start_media(session_id) do
          :ok ->
            Logger.info("[UasHandler] Media started successfully")

          {:error, reason} ->
            Logger.error("[UasHandler] Failed to start media: #{inspect(reason)}")
        end

      [] ->
        Logger.warning("[UasHandler] No media session found for call-id #{dialog_id.call_id}")
    end

    :noreply
  end
end
