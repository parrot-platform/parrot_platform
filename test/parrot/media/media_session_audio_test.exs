defmodule Parrot.Media.MediaSessionAudioTest do
  use ExUnit.Case, async: true
  alias Parrot.Media.MediaSession

  describe "audio configuration" do
    test "defaults audio_source to :file when audio_file is provided" do
      {:ok, pid} = MediaSession.start_link(
        id: "test-audio-1",
        dialog_id: "dialog-1",
        role: :uas,
        audio_file: "/path/to/audio.wav"
      )
      
      {_state_name, data} = :sys.get_state(pid)
      assert data.audio_source == :file
      assert data.audio_sink == :none
      
      MediaSession.terminate_session(pid)
    end

    test "defaults audio_source to :silence when no audio_file" do
      {:ok, pid} = MediaSession.start_link(
        id: "test-audio-2",
        dialog_id: "dialog-2",
        role: :uas
      )
      
      {_state_name, data} = :sys.get_state(pid)
      assert data.audio_source == :silence
      assert data.audio_sink == :none
      
      MediaSession.terminate_session(pid)
    end

    test "accepts explicit audio_source and audio_sink configuration" do
      {:ok, pid} = MediaSession.start_link(
        id: "test-audio-3",
        dialog_id: "dialog-3",
        role: :uas,
        audio_source: :device,
        audio_sink: :device,
        input_device_id: 0,
        output_device_id: 1
      )
      
      {_state_name, data} = :sys.get_state(pid)
      assert data.audio_source == :device
      assert data.audio_sink == :device
      assert data.input_device_id == 0
      assert data.output_device_id == 1
      
      MediaSession.terminate_session(pid)
    end

    test "configures recording to file" do
      {:ok, pid} = MediaSession.start_link(
        id: "test-audio-4",
        dialog_id: "dialog-4",
        role: :uas,
        audio_source: :silence,
        audio_sink: :file,
        output_file: "/tmp/recording.wav"
      )
      
      {_state_name, data} = :sys.get_state(pid)
      assert data.audio_source == :silence
      assert data.audio_sink == :file
      assert data.output_file == "/tmp/recording.wav"
      
      MediaSession.terminate_session(pid)
    end
  end

  describe "pipeline selection" do
    setup do
      # Create a simple SDP offer for testing
      sdp_offer = """
      v=0
      o=- 123456 123456 IN IP4 127.0.0.1
      s=Test Session
      c=IN IP4 127.0.0.1
      t=0 0
      m=audio 20000 RTP/AVP 8
      a=rtpmap:8 PCMA/8000
      a=sendrecv
      """
      
      {:ok, sdp_offer: sdp_offer}
    end

    test "selects PortAudioPipeline when using device audio", %{sdp_offer: sdp_offer} do
      {:ok, pid} = MediaSession.start_link(
        id: "test-pipeline-1",
        dialog_id: "dialog-5",
        role: :uas,
        audio_source: :device
      )
      
      # Process offer to trigger pipeline selection
      {:ok, _answer} = MediaSession.process_offer(pid, sdp_offer)
      
      {_state_name, data} = :sys.get_state(pid)
      assert data.pipeline_module == Parrot.Media.PortAudioPipeline
      
      MediaSession.terminate_session(pid)
    end

    test "selects codec-specific pipeline for file-only audio", %{sdp_offer: sdp_offer} do
      {:ok, pid} = MediaSession.start_link(
        id: "test-pipeline-2",
        dialog_id: "dialog-6",
        role: :uas,
        audio_source: :file,
        audio_sink: :none,
        audio_file: "/path/to/audio.wav"
      )
      
      # Process offer to trigger pipeline selection
      {:ok, _answer} = MediaSession.process_offer(pid, sdp_offer)
      
      {_state_name, data} = :sys.get_state(pid)
      # Should use the codec-specific pipeline (MembraneAlawPipeline for PCMA)
      assert data.pipeline_module == Parrot.Media.MembraneAlawPipeline
      
      MediaSession.terminate_session(pid)
    end
  end
end