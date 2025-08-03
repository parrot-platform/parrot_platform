defmodule AudioDeviceExample do
  @moduledoc """
  Example demonstrating how to use PortAudio devices with Parrot Platform.
  
  This example shows different configurations for audio handling:
  1. Playing audio from file to remote party
  2. Recording remote party audio to file
  3. Full duplex communication with system audio devices
  4. Using specific audio devices by ID
  """
  
  alias Parrot.Media.{MediaSession, AudioDevices}
  
  @doc """
  Example 1: Play audio file to remote party (UAS scenario)
  """
  def play_file_to_caller do
    {:ok, session} = MediaSession.start_link(
      id: "example-session-1",
      dialog_id: "dialog-123",
      role: :uas,
      audio_source: :file,
      audio_file: "/path/to/welcome.wav",
      audio_sink: :none  # Don't save remote audio
    )
    
    # Process SDP offer and start media
    # ... SIP handling code ...
    
    session
  end
  
  @doc """
  Example 2: Record remote party audio to file (UAS scenario)
  """
  def record_caller_audio do
    {:ok, session} = MediaSession.start_link(
      id: "example-session-2",
      dialog_id: "dialog-456",
      role: :uas,
      audio_source: :silence,  # Don't send audio
      audio_sink: :file,
      output_file: "/tmp/recording.wav"
    )
    
    # Process SDP offer and start media
    # ... SIP handling code ...
    
    session
  end
  
  @doc """
  Example 3: Full duplex with system audio devices (UAC/UAS scenario)
  """
  def full_duplex_audio do
    # First, list available devices
    {:ok, devices} = AudioDevices.list_devices()
    
    IO.puts("Available audio devices:")
    Enum.each(devices, fn device ->
      IO.puts("  #{device.type}: #{device.name} (ID: #{device.id})")
    end)
    
    # Get default devices
    {:ok, input_id} = AudioDevices.get_default_input()
    {:ok, output_id} = AudioDevices.get_default_output()
    
    {:ok, session} = MediaSession.start_link(
      id: "example-session-3",
      dialog_id: "dialog-789",
      role: :uac,
      audio_source: :device,
      audio_sink: :device,
      input_device_id: input_id,
      output_device_id: output_id
    )
    
    # Generate SDP offer or process answer
    # ... SIP handling code ...
    
    session
  end
  
  @doc """
  Example 4: Using specific audio devices
  """
  def use_specific_devices do
    # Validate devices exist
    case AudioDevices.validate_device(2, :input) do
      :ok ->
        case AudioDevices.validate_device(3, :output) do
          :ok ->
            {:ok, session} = MediaSession.start_link(
              id: "example-session-4",
              dialog_id: "dialog-999",
              role: :uas,
              audio_source: :device,
              audio_sink: :device,
              input_device_id: 2,  # Specific microphone
              output_device_id: 3  # Specific speaker
            )
            
            {:ok, session}
            
          {:error, reason} ->
            {:error, {:invalid_output_device, reason}}
        end
        
      {:error, reason} ->
        {:error, {:invalid_input_device, reason}}
    end
  end
  
  @doc """
  Example 5: UAS handler with audio device support
  """
  defmodule AudioDeviceUasHandler do
    use Parrot.UasHandler
    alias Parrot.Media.MediaSession
    
    @impl true
    def init(_args) do
      {:ok, %{calls: %{}}}
    end
    
    @impl true
    def handle_invite(request, state) do
      # Extract call ID and create media session with audio devices
      call_id = request.headers["call-id"]
      
      {:ok, session} = MediaSession.start_link(
        id: "media-#{call_id}",
        dialog_id: call_id,
        role: :uas,
        audio_source: :device,  # Use microphone
        audio_sink: :device     # Use speaker
      )
      
      # Process SDP offer
      sdp_offer = request.body
      {:ok, sdp_answer} = MediaSession.process_offer(session, sdp_offer)
      
      # Send 200 OK with SDP answer
      response = %{
        status_code: 200,
        headers: %{
          "content-type" => "application/sdp"
        },
        body: sdp_answer
      }
      
      new_state = put_in(state.calls[call_id], %{session: session})
      {:reply, response, new_state}
    end
    
    @impl true
    def handle_ack(request, state) do
      call_id = request.headers["call-id"]
      
      if call_info = state.calls[call_id] do
        # Start media flow
        :ok = MediaSession.start_media(call_info.session)
      end
      
      {:noreply, state}
    end
    
    @impl true
    def handle_bye(request, state) do
      call_id = request.headers["call-id"]
      
      if call_info = state.calls[call_id] do
        # Stop media session
        MediaSession.terminate_session(call_info.session)
      end
      
      new_state = update_in(state.calls, &Map.delete(&1, call_id))
      {:reply, %{status_code: 200}, new_state}
    end
  end
  
  @doc """
  Example 6: UAC with audio device support
  """
  def make_call_with_audio(target_uri) do
    alias Parrot.Sip.UAC
    alias Parrot.UacHandlerAdapter
    
    # Create UAC handler that manages audio
    handler_module = __MODULE__.AudioDeviceUacHandler
    
    # Create callback for UAC
    callback = UacHandlerAdapter.create_callback(handler_module, %{})
    
    # Make the call
    {:ok, dialog_id} = UAC.send_request(
      method: :invite,
      uri: target_uri,
      headers: %{
        "from" => %{uri: "sip:user@example.com", parameters: %{"tag" => "12345"}},
        "to" => %{uri: target_uri},
        "call-id" => "call-#{:rand.uniform(1000000)}",
        "cseq" => %{number: 1, method: :invite}
      },
      body: generate_sdp_offer(),
      callback: callback
    )
    
    {:ok, dialog_id}
  end
  
  defp generate_sdp_offer do
    # Generate SDP with audio media line
    # This would use MediaSession.generate_offer/1 in practice
    """
    v=0
    o=- 123456 123456 IN IP4 192.168.1.100
    s=Parrot Audio Call
    c=IN IP4 192.168.1.100
    t=0 0
    m=audio 16384 RTP/AVP 0 8
    a=rtpmap:0 PCMU/8000
    a=rtpmap:8 PCMA/8000
    a=sendrecv
    """
  end
  
  # UAC Handler for outbound calls with audio
  defmodule AudioDeviceUacHandler do
    use Parrot.UacHandler
    alias Parrot.Media.MediaSession
    
    @impl true
    def init(_args) do
      {:ok, %{session: nil}}
    end
    
    @impl true
    def handle_provisional(response, state) do
      if response.status_code == 180 do
        IO.puts("Ringing...")
      end
      {:ok, state}
    end
    
    @impl true
    def handle_success(response, state) do
      if response.status_code == 200 and response.headers["cseq"].method == :invite do
        # Create media session for the call
        {:ok, session} = MediaSession.start_link(
          id: "uac-media-#{:rand.uniform(1000)}",
          dialog_id: "uac-dialog",
          role: :uac,
          audio_source: :device,
          audio_sink: :device
        )
        
        # Process SDP answer
        sdp_answer = response.body
        :ok = MediaSession.process_answer(session, sdp_answer)
        
        # Start media
        :ok = MediaSession.start_media(session)
        
        IO.puts("Call connected! Audio devices active.")
        
        {:ok, %{state | session: session}}
      else
        {:ok, state}
      end
    end
    
    @impl true
    def handle_call_ended(_dialog_id, _reason, state) do
      if state.session do
        MediaSession.terminate_session(state.session)
      end
      
      IO.puts("Call ended.")
      {:ok, %{state | session: nil}}
    end
  end
end