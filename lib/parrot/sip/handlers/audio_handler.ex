defmodule Parrot.Sip.Handlers.AudioHandler do
  @moduledoc """
  SIP handler that plays audio files during calls.

  This handler responds to INVITE requests by:
  1. Parsing the SDP to get remote RTP endpoint
  2. Starting a media session
  3. Playing audio when the call is established
  """

  @behaviour Parrot.UasHandler

  require Logger

  alias Parrot.Media.MediaSession

  defstruct [
    :media_session,
    :call_state,
    :remote_sdp,
    :local_rtp_port
  ]

  @impl true
  def init(_args) do
    # Generate a random local RTP port
    local_rtp_port = 20000 + :rand.uniform(10000)

    {:ok,
     %__MODULE__{
       call_state: :idle,
       local_rtp_port: local_rtp_port
     }}
  end

  @impl true
  def handle_invite(msg, state) do
    Logger.info("AudioHandler: Received INVITE")

    # Parse SDP from request body
    if msg.body == "" do
      Logger.error("No SDP in INVITE request")
      {:respond, 400, "Bad Request", %{}, "", state}
    else
      # Start media session with a unique ID
      session_id = "audio_handler_#{:erlang.phash2({msg.headers["call-id"], :os.timestamp()})}"

      {:ok, session} =
        MediaSession.start_link(
          id: session_id,
          audio_file: get_audio_file()
        )

      # Process the SDP offer
      case MediaSession.process_offer(session, msg.body) do
        {:ok, sdp_answer} ->
          new_state = %{state | media_session: session, call_state: :ringing}

          # Send 200 OK with SDP answer
          headers = %{"content-type" => "application/sdp"}
          {:respond, 200, "OK", headers, sdp_answer, new_state}

        {:error, reason} ->
          Logger.error("Failed to process SDP offer: #{inspect(reason)}")
          {:respond, 488, "Not Acceptable Here", %{}, "", state}
      end
    end
  end

  @impl true
  def handle_ack(_msg, state) do
    Logger.info("AudioHandler: Received ACK")

    if state.media_session do
      # Start playing audio
      MediaSession.start_media(state.media_session)
    end

    {:ok, %{state | call_state: :active}}
  end

  @impl true
  def handle_bye(_msg, state) do
    Logger.info("AudioHandler: Received BYE")

    # Stop media session
    if state.media_session do
      MediaSession.terminate_session(state.media_session)
    end

    {:respond, 200, "OK", %{}, "", %{state | call_state: :terminated}}
  end

  @impl true
  def handle_info(_msg, state) do
    {:noreply, state}
  end

  # Private functions

  defp get_audio_file do
    # For now, use a default file
    # In production, this would be configurable
    Path.join(:code.priv_dir(:parrot_platform), "audio/music.pcmu")
  end
end
