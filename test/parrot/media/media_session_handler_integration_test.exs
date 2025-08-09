defmodule Parrot.Media.MediaSessionHandlerIntegrationTest do
  use ExUnit.Case

  alias Parrot.Media.MediaSession

  # Test handler that tracks callback invocations
  defmodule IntegrationTestHandler do
    @behaviour Parrot.MediaHandler

    @impl true
    def init(args) do
      {:ok,
       Map.merge(
         %{
           callbacks_invoked: [],
           test_pid: args[:test_pid]
         },
         args
       )}
    end

    @impl true
    def handle_session_start(session_id, _opts, state) do
      send(state.test_pid, {:callback, :session_start, session_id})
      {:ok, track_callback(state, :session_start)}
    end

    @impl true
    def handle_session_stop(session_id, reason, state) do
      send(state.test_pid, {:callback, :session_stop, {session_id, reason}})
      {:ok, track_callback(state, :session_stop)}
    end

    @impl true
    def handle_offer(sdp, direction, state) do
      send(state.test_pid, {:callback, :offer, {sdp, direction}})
      {:noreply, track_callback(state, :offer)}
    end

    @impl true
    def handle_answer(sdp, direction, state) do
      send(state.test_pid, {:callback, :answer, {sdp, direction}})
      {:noreply, track_callback(state, :answer)}
    end

    @impl true
    def handle_codec_negotiation(offered, supported, state) do
      send(state.test_pid, {:callback, :codec_negotiation, {offered, supported}})
      updated_state = track_callback(state, :codec_negotiation)

      # Prefer opus if available
      cond do
        :opus in offered and :opus in supported -> {:ok, :opus, updated_state}
        :pcmu in offered and :pcmu in supported -> {:ok, :pcmu, updated_state}
        :pcma in offered and :pcma in supported -> {:ok, :pcma, updated_state}
        true -> {:error, :no_common_codec, updated_state}
      end
    end

    @impl true
    def handle_negotiation_complete(local_sdp, remote_sdp, codec, state) do
      send(state.test_pid, {:callback, :negotiation_complete, {local_sdp, remote_sdp, codec}})
      {:ok, track_callback(state, :negotiation_complete)}
    end

    @impl true
    def handle_stream_start(session_id, direction, state) do
      send(state.test_pid, {:callback, :stream_start, {session_id, direction}})
      updated_state = track_callback(state, :stream_start)

      # Play welcome audio if configured
      if state[:play_welcome] do
        # Use :default_audio instead of a file path for testing
        {{:play, :default_audio}, updated_state}
      else
        {:noreply, updated_state}
      end
    end

    @impl true
    def handle_stream_stop(session_id, reason, state) do
      send(state.test_pid, {:callback, :stream_stop, {session_id, reason}})
      {:ok, track_callback(state, :stream_stop)}
    end

    @impl true
    def handle_stream_error(session_id, error, state) do
      send(state.test_pid, {:callback, :stream_error, {session_id, error}})
      {:continue, track_callback(state, :stream_error)}
    end

    @impl true
    def handle_play_complete(file_path, state) do
      send(state.test_pid, {:callback, :play_complete, file_path})
      {:noreply, track_callback(state, :play_complete)}
    end

    @impl true
    def handle_media_request(request, state) do
      send(state.test_pid, {:callback, :media_request, request})
      {:noreply, track_callback(state, :media_request)}
    end

    defp track_callback(state, callback) do
      Map.update(state, :callbacks_invoked, [callback], &(&1 ++ [callback]))
    end
  end

  setup do
    # Ensure test process is registered if needed
    {:ok, %{}}
  end

  describe "MediaSession with handler" do
    test "initializes handler on session start" do
      {:ok, session} =
        MediaSession.start_link(
          id: "test_session_#{:rand.uniform(1000)}",
          dialog_id: "dialog_1",
          role: :uas,
          media_handler: IntegrationTestHandler,
          handler_args: %{test_pid: self()}
        )

      # Handler init should have been called
      assert Process.alive?(session)

      MediaSession.terminate_session(session)
    end

    test "calls handler during SDP offer processing" do
      session_id = "test_session_#{:rand.uniform(1000)}"

      {:ok, session} =
        MediaSession.start_link(
          id: session_id,
          dialog_id: "dialog_1",
          role: :uas,
          media_handler: IntegrationTestHandler,
          handler_args: %{test_pid: self()},
          supported_codecs: [:opus, :pcma],
          audio_file: Path.join(:code.priv_dir(:parrot_platform), "audio/parrot-welcome.wav")
        )

      # Create a simple SDP offer
      sdp_offer = """
      v=0
      o=- 123456 123456 IN IP4 192.168.1.100
      s=Test Session
      c=IN IP4 192.168.1.100
      t=0 0
      m=audio 5004 RTP/AVP 0 8 96
      a=rtpmap:0 PCMU/8000
      a=rtpmap:8 PCMA/8000
      a=rtpmap:96 opus/48000/2
      a=sendrecv
      """

      # Process offer
      {:ok, _answer} = MediaSession.process_offer(session, sdp_offer)

      # Verify callbacks were invoked
      assert_receive {:callback, :offer, {_sdp, :inbound}}, 1000
      assert_receive {:callback, :codec_negotiation, {offered, supported}}, 1000
      # We receive PCMU in the offer but don't support it
      assert :pcma in offered
      assert :opus in offered
      assert :opus in supported
      assert :pcma in supported

      MediaSession.terminate_session(session)
    end

    test "calls handler when starting media" do
      session_id = "test_session_#{:rand.uniform(1000)}"

      {:ok, session} =
        MediaSession.start_link(
          id: session_id,
          dialog_id: "dialog_1",
          role: :uas,
          media_handler: IntegrationTestHandler,
          handler_args: %{test_pid: self(), play_welcome: true}
        )

      # Create SDP for negotiation
      sdp_offer = """
      v=0
      o=- 123456 123456 IN IP4 127.0.0.1
      s=Test
      c=IN IP4 127.0.0.1
      t=0 0
      m=audio 5004 RTP/AVP 8
      a=rtpmap:8 PCMA/8000
      """

      {:ok, _answer} = MediaSession.process_offer(session, sdp_offer)

      # Start media
      :ok = MediaSession.start_media(session)

      # Handler should receive stream_start callback
      assert_receive {:callback, :stream_start, {^session_id, _direction}}, 1000

      MediaSession.terminate_session(session)
    end

    test "handler receives RTP statistics" do
      session_id = "test_session_#{:rand.uniform(1000)}"

      {:ok, session} =
        MediaSession.start_link(
          id: session_id,
          dialog_id: "dialog_1",
          role: :uas,
          media_handler: IntegrationTestHandler,
          handler_args: %{test_pid: self()},
          # Report stats every 100ms for testing
          rtp_stats_interval: 100
        )

      # TODO: This test would need MediaSession to actually generate RTP stats
      # For now, we can simulate by sending a message to the session

      MediaSession.terminate_session(session)
    end

    test "handler codec preference affects negotiation" do
      session_id = "test_session_#{:rand.uniform(1000)}"

      {:ok, session} =
        MediaSession.start_link(
          id: session_id,
          dialog_id: "dialog_1",
          role: :uas,
          media_handler: IntegrationTestHandler,
          handler_args: %{test_pid: self()},
          supported_codecs: [:opus, :pcma],
          audio_file: Path.join(:code.priv_dir(:parrot_platform), "audio/parrot-welcome.wav")
        )

      # Offer with multiple codecs including opus
      sdp_offer = """
      v=0
      o=- 123456 123456 IN IP4 127.0.0.1
      s=Test
      c=IN IP4 127.0.0.1
      t=0 0
      m=audio 5004 RTP/AVP 111 0 8
      a=rtpmap:111 opus/48000/2
      a=rtpmap:0 PCMU/8000
      a=rtpmap:8 PCMA/8000
      """

      {:ok, answer} = MediaSession.process_offer(session, sdp_offer)

      # Handler should have been called for codec negotiation
      assert_receive {:callback, :codec_negotiation, {offered, _supported}}, 1000
      assert :opus in offered

      # Answer should prefer opus (based on handler logic)
      assert answer =~ "opus"

      MediaSession.terminate_session(session)
    end

    test "media actions from handler are processed" do
      session_id = "test_session_#{:rand.uniform(1000)}"

      {:ok, session} =
        MediaSession.start_link(
          id: session_id,
          dialog_id: "dialog_1",
          role: :uas,
          media_handler: IntegrationTestHandler,
          handler_args: %{test_pid: self(), play_welcome: true},
          # Provide audio file for pipeline
          audio_file: Path.join(:code.priv_dir(:parrot_platform), "audio/parrot-welcome.wav")
        )

      # Setup media session
      sdp_offer = """
      v=0
      o=- 123456 123456 IN IP4 127.0.0.1
      s=Test
      c=IN IP4 127.0.0.1
      t=0 0
      m=audio 5004 RTP/AVP 8
      a=rtpmap:8 PCMA/8000
      """

      {:ok, _answer} = MediaSession.process_offer(session, sdp_offer)
      :ok = MediaSession.start_media(session)

      # Handler should return play action
      assert_receive {:callback, :stream_start, {^session_id, _direction}}, 1000

      # TODO: Verify that MediaSession actually processes the {:play, "/audio/welcome.wav"} action
      # This would require MediaSession to send notifications about media actions

      MediaSession.terminate_session(session)
    end
  end

  describe "backward compatibility" do
    test "MediaSession works without handler" do
      session_id = "test_session_#{:rand.uniform(1000)}"

      # Start session without handler
      {:ok, session} =
        MediaSession.start_link(
          id: session_id,
          dialog_id: "dialog_1",
          role: :uas,
          audio_file: Path.join(:code.priv_dir(:parrot_platform), "audio/parrot-welcome.wav")
        )

      # Should work normally
      sdp_offer = """
      v=0
      o=- 123456 123456 IN IP4 127.0.0.1
      s=Test
      c=IN IP4 127.0.0.1
      t=0 0
      m=audio 5004 RTP/AVP 0
      a=rtpmap:0 PCMU/8000
      """

      {:ok, answer} = MediaSession.process_offer(session, sdp_offer)
      # We don't support PCMU, so should answer with PCMA
      assert answer =~ "PCMA"

      :ok = MediaSession.start_media(session)

      MediaSession.terminate_session(session)
    end
  end
end
