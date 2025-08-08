defmodule Parrot.Media.MediaSessionManager do
  @moduledoc """
  Manages media sessions and ensures proper port allocation.

  This module provides a better architecture where:
  1. MediaSession is created BEFORE sending INVITE
  2. MediaSession allocates and owns the RTP port
  3. The allocated port is used in the SDP
  """

  alias Parrot.Media.MediaSession
  require Logger

  @doc """
  Prepares a media session for an outgoing call (UAC).

  This should be called BEFORE creating the INVITE. It will:
  1. Create a MediaSession
  2. Allocate an RTP port
  3. Generate the SDP offer

  ## Options
  - `:id` - Unique session ID (required)
  - `:dialog_id` - SIP dialog ID (optional, can be set later)
  - `:audio_source` - Source of audio (:device, :file, :silence)
  - `:audio_sink` - Where to play audio (:device, :file, :none)
  - `:input_device_id` - Audio input device ID
  - `:output_device_id` - Audio output device ID

  ## Returns
  - `{:ok, session_pid, sdp_offer}` - Success
  - `{:error, reason}` - Failure
  """
  def prepare_uac_session(opts) do
    # Ensure we have required options
    _id = Keyword.fetch!(opts, :id)

    # Start MediaSession as UAC
    session_opts = Keyword.put(opts, :role, :uac)

    case MediaSession.start_link(session_opts) do
      {:ok, session_pid} ->
        # Generate SDP offer (this allocates the port)
        case MediaSession.generate_offer(session_pid) do
          {:ok, sdp_offer} ->
            {:ok, session_pid, sdp_offer}

          {:error, reason} ->
            # Clean up on failure
            GenServer.stop(session_pid)
            {:error, {:sdp_generation_failed, reason}}
        end

      {:error, reason} ->
        {:error, {:session_start_failed, reason}}
    end
  end

  @doc """
  Prepares a media session for an incoming call (UAS).

  This should be called when receiving an INVITE.

  ## Options
  Same as `prepare_uac_session/1` plus:
  - `:sdp_offer` - The SDP offer from the INVITE (required)

  ## Returns
  - `{:ok, session_pid, sdp_answer}` - Success with SDP answer
  - `{:error, reason}` - Failure
  """
  def prepare_uas_session(opts) do
    # Ensure we have required options
    _id = Keyword.fetch!(opts, :id)
    sdp_offer = Keyword.fetch!(opts, :sdp_offer)

    # Start MediaSession as UAS
    session_opts =
      opts
      |> Keyword.put(:role, :uas)
      |> Keyword.delete(:sdp_offer)

    case MediaSession.start_link(session_opts) do
      {:ok, session_pid} ->
        # Process offer and generate answer
        case MediaSession.process_offer(session_pid, sdp_offer) do
          {:ok, sdp_answer} ->
            {:ok, session_pid, sdp_answer}

          {:error, reason} ->
            # Clean up on failure
            GenServer.stop(session_pid)
            {:error, {:negotiation_failed, reason}}
        end

      {:error, reason} ->
        {:error, {:session_start_failed, reason}}
    end
  end

  @doc """
  Completes call setup for UAC after receiving 200 OK.

  ## Parameters
  - `session_pid` - The MediaSession process
  - `sdp_answer` - The SDP answer from 200 OK

  ## Returns
  - `:ok` - Success, media is now flowing
  - `{:error, reason}` - Failure
  """
  def complete_uac_setup(session_pid, sdp_answer) do
    case MediaSession.process_answer(session_pid, sdp_answer) do
      :ok ->
        # Start media flow
        MediaSession.start_media(session_pid)

      {:error, reason} ->
        {:error, {:answer_processing_failed, reason}}
    end
  end

  @doc """
  Completes call setup for UAS after sending 200 OK and receiving ACK.

  ## Parameters
  - `session_pid` - The MediaSession process

  ## Returns
  - `:ok` - Success, media is now flowing
  """
  def complete_uas_setup(session_pid) do
    MediaSession.start_media(session_pid)
  end

  # @doc """
  # Gets the allocated RTP port from a session.

  # Useful for debugging or if you need the port for other purposes.
  # """
  # def get_local_rtp_port(session_pid) do
  #   case MediaSession.get_state(session_pid) do
  #     {:ok, state} ->
  #       {:ok, state.local_rtp_port}

  #     error ->
  #       error
  #   end
  # end
end
