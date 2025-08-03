defmodule Parrot.Media.CodecSelectionTest do
  use ExUnit.Case, async: true

  alias Parrot.Media.MediaSession

  describe "codec selection" do
    test "SDP offer with PCMA and PCMU selects PCMA when preferred" do
      # Start a media session with PCMA preference
      session_opts = [
        id: "test-session-1",
        dialog_id: "test-dialog-1",
        role: :uas,
        supported_codecs: [:pcma, :pcmu]
      ]

      {:ok, session_pid} = MediaSession.start_link(session_opts)

      # SDP offer with both PCMU (0) and PCMA (8)
      sdp_offer = """
      v=0
      o=- 123456 123456 IN IP4 192.168.1.100
      s=Test Session
      c=IN IP4 192.168.1.100
      t=0 0
      m=audio 5004 RTP/AVP 0 8
      a=rtpmap:0 PCMU/8000
      a=rtpmap:8 PCMA/8000
      a=sendrecv
      """

      # Process offer should select PCMA (first in our preference list)
      {:ok, sdp_answer} = MediaSession.process_offer(session_pid, sdp_offer)

      # Verify answer contains PCMA (8)
      assert sdp_answer =~ "m=audio"
      assert sdp_answer =~ "RTP/AVP 8"
      assert sdp_answer =~ "a=rtpmap:8 PCMA/8000"

      # Clean up
      MediaSession.terminate_session(session_pid)
    end

    test "SDP offer with only PCMU selects PCMU even when not preferred" do
      # Start a media session with PCMA preference
      session_opts = [
        id: "test-session-2",
        dialog_id: "test-dialog-2",
        role: :uas,
        supported_codecs: [:pcma, :pcmu]
      ]

      {:ok, session_pid} = MediaSession.start_link(session_opts)

      # SDP offer with only PCMU (0)
      sdp_offer = """
      v=0
      o=- 123456 123456 IN IP4 192.168.1.100
      s=Test Session
      c=IN IP4 192.168.1.100
      t=0 0
      m=audio 5004 RTP/AVP 0
      a=rtpmap:0 PCMU/8000
      a=sendrecv
      """

      # Process offer should select PCMU (only available codec)
      {:ok, sdp_answer} = MediaSession.process_offer(session_pid, sdp_offer)

      # Verify answer contains PCMU (0)
      assert sdp_answer =~ "m=audio"
      assert sdp_answer =~ "RTP/AVP 0"
      assert sdp_answer =~ "a=rtpmap:0 PCMU/8000"

      # Clean up
      MediaSession.terminate_session(session_pid)
    end

    test "UAC generates offer with all supported codecs" do
      # Start a media session as UAC
      session_opts = [
        id: "test-session-3",
        dialog_id: "test-dialog-3",
        role: :uac,
        supported_codecs: [:pcma, :pcmu]
      ]

      {:ok, session_pid} = MediaSession.start_link(session_opts)

      # Generate offer
      {:ok, sdp_offer} = MediaSession.generate_offer(session_pid)

      # Verify offer contains both codecs
      assert sdp_offer =~ "m=audio"
      assert sdp_offer =~ "RTP/AVP 8 0" or sdp_offer =~ "RTP/AVP 0 8"
      assert sdp_offer =~ "a=rtpmap:0 PCMU/8000"
      assert sdp_offer =~ "a=rtpmap:8 PCMA/8000"

      # Clean up
      MediaSession.terminate_session(session_pid)
    end
  end
end
