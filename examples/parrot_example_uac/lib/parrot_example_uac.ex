defmodule ParrotExampleUac do
  @moduledoc """
  Example UAC (User Agent Client) application with PortAudio support.
  
  This application demonstrates:
  - Making outbound SIP calls
  - Using system microphone for outbound audio
  - Playing received audio through system speakers
  - Bidirectional G.711 audio streaming
  - Proper call lifecycle management
  
  ## Usage
  
      # Start the UAC
      ParrotExampleUac.start()
      
      # Make a call using default audio devices
      ParrotExampleUac.call("sip:service@127.0.0.1:5060")
      
      # Make a call with specific audio devices
      ParrotExampleUac.call("sip:service@127.0.0.1:5060", input_device: 1, output_device: 2)
      
      # List available audio devices
      ParrotExampleUac.list_audio_devices()
      
      # Hang up the current call
      ParrotExampleUac.hangup()
  """
  
  use GenServer
  require Logger
  
  alias Parrot.Sip.{UAC, Message}
  alias Parrot.Sip.Headers.{From, To, CSeq, CallId, Contact, Via}
  alias Parrot.Media.{MediaSession, MediaSessionManager, AudioDevices}
  
  @server_name {:via, Registry, {Parrot.Registry, __MODULE__}}
  
  defmodule State do
    @moduledoc false
    defstruct [
      :transport_ref,
      :current_call,
      :media_session,
      :dialog_id,
      :call_id,
      :local_tag,
      :remote_tag,
      :input_device_id,
      :output_device_id
    ]
  end
  
  # Client API
  
  @doc """
  Starts the UAC application.
  """
  def start(opts \\ []) do
    case GenServer.start_link(__MODULE__, opts, name: @server_name) do
      {:ok, pid} ->
        Logger.info("ParrotExampleUac started successfully")
        {:ok, pid}
      {:error, {:already_started, pid}} ->
        Logger.info("ParrotExampleUac already running")
        {:ok, pid}
      error ->
        error
    end
  end
  
  @doc """
  Lists available audio devices.
  """
  def list_audio_devices do
    IO.puts("\n")
    AudioDevices.print_devices()
    IO.puts("\nNote: Use the device IDs shown above when calling ParrotExampleUac.call/2")
    IO.puts("Example: ParrotExampleUac.call(\"sip:service@127.0.0.1:5060\", input_device: 1, output_device: 2)")
    :ok
  end
  
  @doc """
  Makes an outbound call.
  
  Options:
    - :input_device - Audio input device ID (defaults to system default)
    - :output_device - Audio output device ID (defaults to system default)
  """
  def call(uri, opts \\ []) do
    GenServer.call(@server_name, {:make_call, uri, opts})
  end
  
  @doc """
  Hangs up the current call.
  """
  def hangup do
    GenServer.call(@server_name, :hangup)
  end
  
  @doc """
  Gets the current call status.
  """
  def status do
    GenServer.call(@server_name, :status)
  end
  
  # Server Callbacks
  
  @impl true
  def init(opts) do
    Logger.info("Initializing ParrotExampleUac")
    
    # Get default audio devices
    input_device = case opts[:input_device] || AudioDevices.get_default_input() do
      {:ok, device_id} -> device_id
      _ -> nil
    end
    
    output_device = case opts[:output_device] || AudioDevices.get_default_output() do
      {:ok, device_id} -> device_id  
      _ -> nil
    end
    
    # Start transport
    transport_opts = Keyword.get(opts, :transport, %{})
    
    case start_transport(transport_opts) do
      {:ok, ref} ->
        state = %State{
          transport_ref: ref,
          input_device_id: input_device,
          output_device_id: output_device
        }
        
        {:ok, state}
        
      {:error, reason} ->
        {:stop, {:transport_error, reason}}
    end
  end
  
  @impl true
  def handle_call({:make_call, uri, opts}, _from, state) do
    if state.current_call do
      {:reply, {:error, :call_in_progress}, state}
    else
      # Override default devices if specified
      input_device = opts[:input_device] || state.input_device_id
      output_device = opts[:output_device] || state.output_device_id
      
      case do_make_call(uri, input_device, output_device, state) do
        {:ok, new_state} ->
          {:reply, :ok, new_state}
          
        {:error, reason} = error ->
          Logger.error("Failed to make call: #{inspect(reason)}")
          {:reply, error, state}
      end
    end
  end
  
  @impl true
  def handle_call(:hangup, _from, state) do
    if state.current_call do
      new_state = do_hangup(state)
      {:reply, :ok, new_state}
    else
      {:reply, {:error, :no_active_call}, state}
    end
  end
  
  @impl true
  def handle_call(:status, _from, state) do
    status = %{
      active_call: state.current_call != nil,
      call_id: state.call_id,
      dialog_id: state.dialog_id,
      media_active: state.media_session != nil
    }
    
    {:reply, status, state}
  end
  
  @impl true
  def handle_info({:uac_response, response}, state) do
    new_state = handle_uac_response(response, state)
    {:noreply, new_state}
  end
  
  @impl true
  def handle_info(msg, state) do
    Logger.debug("Unhandled message: #{inspect(msg)}")
    {:noreply, state}
  end
  
  # Private Functions
  
  defp start_transport(opts) do
    listen_port = opts[:listen_port] || 0  # Use ephemeral port
    
    # Create a simple handler for receiving responses
    handler = Parrot.Sip.Handler.new(
      __MODULE__.ResponseHandler,
      self(),
      log_level: :debug,
      sip_trace: true
    )
    
    case Parrot.Sip.Transport.StateMachine.start_udp(%{
      handler: handler,
      listen_port: listen_port
    }) do
      :ok ->
        {:ok, make_ref()}
      error ->
        error
    end
  end
  
  defp do_make_call(uri, input_device, output_device, state) do
    # Generate call parameters
    call_id = "uac-#{:rand.uniform(1000000)}@#{get_local_ip()}"
    local_tag = generate_tag()
    dialog_id = "#{call_id}-#{local_tag}"
    
    # Step 1: Prepare UAC session using MediaSessionManager
    Logger.debug("Preparing UAC media session...")
    case MediaSessionManager.prepare_uac_session(
      id: "uac-media-#{call_id}",
      dialog_id: dialog_id,
      audio_source: :device,
      audio_sink: :device,
      input_device_id: input_device,
      output_device_id: output_device,
      supported_codecs: [:pcma]  # G.711 A-law
    ) do
      {:ok, media_session, sdp_offer} ->
        Logger.debug("UAC session prepared with SDP offer")
        
        # Step 2: Create INVITE with the SDP from MediaSessionManager
        headers = %{
          "via" => [Via.new(get_local_ip(), "udp", 5060)],
          "from" => From.new("sip:parrot_uac@#{get_local_ip()}", "Parrot UAC", local_tag),
          "to" => To.new(uri),
          "call-id" => CallId.new(call_id),
          "cseq" => CSeq.new(1, :invite),
          "contact" => Contact.new("sip:parrot_uac@#{get_local_ip()}:5060"),
          "content-type" => "application/sdp",
          "allow" => "INVITE, ACK, BYE, CANCEL, OPTIONS, INFO",
          "supported" => "replaces, timer"
        }
        
        invite = Message.new_request(:invite, uri, headers)
        |> Message.set_body(sdp_offer)
        
        # Create UAC handler callback
        callback = create_uac_callback(self())
        
        # Step 3: Send INVITE
        {:uac_id, transaction} = UAC.request(invite, callback)
        Logger.info("INVITE sent, transaction: #{inspect(transaction)}")
        
        # Store session info for later
        new_state = %{state |
          current_call: uri,
          call_id: call_id,
          local_tag: local_tag,
          media_session: media_session
        }
        
        {:ok, new_state}
        
      {:error, reason} ->
        Logger.error("Failed to prepare UAC session: #{inspect(reason)}")
        {:error, reason}
    end
  end
  
  defp create_uac_callback(pid) do
    fn response ->
      send(pid, {:uac_response, response})
    end
  end
  
  defp handle_uac_response({:response, response}, state) do
    case response.status_code do
      code when code >= 100 and code < 200 ->
        # Provisional response
        Logger.info("Call progress: #{code} #{response.reason_phrase}")
        
        if code == 180 do
          IO.puts("\n🔔 Ringing...")
        end
        
        state
        
      200 ->
        # Success - check if this is for INVITE or other method
        case response.headers["cseq"] do
          %{method: :invite} ->
            # Success - call answered
            Logger.info("Call answered!")
            IO.puts("\n✅ Call connected! Audio devices active.")
            IO.puts("🎤 Speaking through microphone...")
            IO.puts("🔊 Listening through speakers...")
            IO.puts("\nPress Enter to hang up")
            
            # Extract remote tag and create dialog ID
            remote_tag = case response.headers["to"] do
              %{parameters: %{"tag" => tag}} -> tag
              _ -> nil
            end
            Logger.debug("Remote tag: #{inspect(remote_tag)}")
            
            dialog_id = %{
              call_id: state.call_id,
              local_tag: state.local_tag,
              remote_tag: remote_tag
            }
            
            # Send ACK immediately after receiving 200 OK for INVITE
            Logger.info("Sending ACK for 200 OK...")
            send_ack(state, response)
            
            # Extract SDP answer from response
            sdp_answer = response.body
            Logger.debug("Completing UAC setup with SDP answer...")
            
            # Complete UAC setup using MediaSessionManager
            case MediaSessionManager.complete_uac_setup(state.media_session, sdp_answer) do
              :ok ->
                Logger.info("UAC setup completed successfully, media is flowing")
                
                # Start a task to wait for Enter key
                Task.start(fn ->
                  IO.gets("")
                  GenServer.call(@server_name, :hangup)
                end)
                
                %{state |
                  dialog_id: dialog_id,
                  remote_tag: remote_tag
                }
                
              {:error, reason} ->
                Logger.error("Failed to complete UAC setup: #{inspect(reason)}")
                IO.puts("\n❌ Failed to establish media: #{inspect(reason)}")
                # TODO: Send BYE to terminate the call
                state
            end
          
          %{method: :bye} ->
            # Success response to BYE - no ACK needed
            Logger.info("BYE acknowledged")
            # Clean up already done in do_hangup
            state
            
          _ ->
            # Other successful response
            Logger.debug("Success response for #{inspect(response.headers["cseq"])}")
            state
        end
        
      code when code >= 300 and code < 400 ->
        # Redirect
        Logger.info("Call redirected: #{code} #{response.reason_phrase}")
        IO.puts("\n↪️  Call redirected: #{response.reason_phrase}")
        state
        
      code when code >= 400 ->
        # Error
        Logger.error("Call failed: #{code} #{response.reason_phrase}")
        IO.puts("\n❌ Call failed: #{response.reason_phrase}")
        
        # Clean up
        Process.delete({:call_context, state.call_id})
        
        %{state |
          current_call: nil,
          call_id: nil,
          local_tag: nil
        }
    end
  end
  
  defp handle_uac_response({:error, reason}, state) do
    Logger.error("UAC error: #{inspect(reason)}")
    IO.puts("\n❌ Call error: #{inspect(reason)}")
    
    # Clean up
    if state.media_session do
      MediaSession.terminate_session(state.media_session)
    end
    
    Process.delete({:call_context, state.call_id})
    
    %{state |
      current_call: nil,
      call_id: nil,
      local_tag: nil,
      media_session: nil,
      dialog_id: nil,
      remote_tag: nil
    }
  end
  
  defp send_ack(state, response) do
    # Extract remote tag from response
    remote_tag = case response.headers["to"] do
      %{parameters: %{"tag" => tag}} -> tag
      _ -> state.remote_tag
    end
    
    headers = %{
      "via" => [Via.new(get_local_ip(), "udp", 5060)],
      "from" => From.new("sip:parrot_uac@#{get_local_ip()}", "Parrot UAC", state.local_tag),
      "to" => To.new(state.current_call, nil, %{"tag" => remote_tag}),
      "call-id" => CallId.new(state.call_id),
      "cseq" => CSeq.new(1, :ack),
      "contact" => Contact.new("sip:parrot_uac@#{get_local_ip()}:5060")
    }
    
    ack = Message.new_request(:ack, state.current_call, headers)
    
    # ACK is sent without expecting a response
    UAC.ack_request(ack)
    Logger.info("ACK sent to #{state.current_call}")
  end
  
  defp do_hangup(state) do
    Logger.info("Hanging up call")
    
    # Send BYE
    headers = %{
      "via" => [Via.new(get_local_ip(), "udp", 5060)],
      "from" => From.new("sip:parrot_uac@#{get_local_ip()}", "Parrot UAC", state.local_tag),
      "to" => To.new(state.current_call, nil, %{"tag" => state.remote_tag}),
      "call-id" => CallId.new(state.call_id),
      "cseq" => CSeq.new(2, :bye),
      "contact" => Contact.new("sip:parrot_uac@#{get_local_ip()}:5060")
    }
    
    bye = Message.new_request(:bye, state.current_call, headers)
    
    callback = create_uac_callback(self())
    UAC.request(bye, callback)
    
    # Stop media session
    if state.media_session do
      MediaSession.terminate_session(state.media_session)
    end
    
    # Clean up
    Process.delete({:call_context, state.call_id})
    
    IO.puts("\n📞 Call ended")
    
    %{state |
      current_call: nil,
      call_id: nil,
      local_tag: nil,
      remote_tag: nil,
      media_session: nil,
      dialog_id: nil
    }
  end
  
  defp generate_tag do
    :crypto.strong_rand_bytes(8) |> Base.encode16(case: :lower)
  end
  
  defp get_local_ip do
    {:ok, addrs} = :inet.getifaddrs()
    
    addrs
    |> Enum.flat_map(fn {_iface, opts} ->
      opts
      |> Enum.filter(fn {:addr, addr} -> tuple_size(addr) == 4 and addr != {127, 0, 0, 1}
                       _ -> false end)
      |> Enum.map(fn {:addr, addr} -> addr end)
    end)
    |> List.first()
    |> case do
      nil -> {127, 0, 0, 1}
      addr -> addr
    end
    |> Tuple.to_list()
    |> Enum.join(".")
  end
  
  # Response Handler Module
  defmodule ResponseHandler do
    @moduledoc false
    require Logger
    
    # Simple handler that forwards responses to the parent process
    
    def transp_request(_msg, _owner_pid) do
      # We only handle responses in UAC
      :ignore
    end
    
    def transp_response(msg, owner_pid) do
      # Forward responses to the GenServer for logging/debugging
      send(owner_pid, {:uac_response, {:response, msg}})
      :consume
    end
    
    def transp_error(error, _reason, owner_pid) do
      send(owner_pid, {:uac_response, {:error, error}})
      :ok
    end
    
    # Required callbacks we don't use
    def process_ack(_msg, _state), do: :ignore
    def transaction(_event, _id, _state), do: :ignore
    def transaction_stop(_event, _id, _state), do: :ignore
    def uas_cancel(_msg, _state), do: :ignore
    def uas_request(_msg, _dialog_id, _state), do: :ignore
  end
end
