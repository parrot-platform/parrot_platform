defmodule Mix.Tasks.Parrot.Gen.Uac do
  @shortdoc "Generates a new Parrot UAC (User Agent Client) application"
  @moduledoc """
  Generates a new Parrot UAC application from a template.

  ## Usage

      mix parrot.gen.uac APP_NAME [OPTIONS]

  ## Examples

      mix parrot.gen.uac my_uac_app
      mix parrot.gen.uac my_uac_app --module MyCompany.UacApp
      mix parrot.gen.uac my_uac_app --no-audio

  ## Options

    * `--module` - The module name to use (default: derived from app name)
    * `--no-audio` - Skip audio device support (SIP signaling only)

  The generator creates:

    * A complete UAC application module using GenServer
    * Integration with system audio devices via PortAudio
    * SIP outbound calling functionality
    * Response handler for processing SIP responses
    * README with usage instructions
    * Basic test file

  The generated application will:

    * Make outbound SIP calls
    * Use system microphone for outbound audio
    * Play received audio through system speakers
    * Support G.711 A-law (PCMA) codec
    * Provide interactive call control
  """

  use Mix.Task
  import Mix.Generator

  @switches [
    module: :string,
    no_audio: :boolean
  ]

  @impl Mix.Task
  def run(args) do
    case OptionParser.parse(args, switches: @switches) do
      {opts, [app_name], _} ->
        generate(app_name, opts)
        
      _ ->
        Mix.raise """
        Invalid arguments. Usage: mix parrot.gen.uac APP_NAME [OPTIONS]
        
        Example: mix parrot.gen.uac my_uac_app --module MyCompany.UacApp
        """
    end
  end

  defp generate(app_name, opts) do
    # Clean up app name using same logic as UAS generator
    app = to_app_name(app_name)
    module_name = opts[:module] || to_module_name(app_name)
    include_audio = !opts[:no_audio]
    
    assigns = [
      app_name: app,
      module: module_name,
      include_audio: include_audio
    ]
    
    create_directory(app_name)
    create_directory(Path.join(app_name, "lib"))
    create_directory(Path.join(app_name, "test"))
    
    create_file(
      Path.join([app_name, "mix.exs"]),
      mix_exs_template(assigns)
    )
    
    create_file(
      Path.join([app_name, "lib", "#{app}.ex"]),
      app_template(assigns)
    )
    
    create_file(
      Path.join([app_name, "README.md"]),
      readme_template(assigns)
    )
    
    create_file(
      Path.join([app_name, "test", "#{app}_test.exs"]),
      test_template(assigns)
    )
    
    create_file(
      Path.join([app_name, ".formatter.exs"]),
      formatter_template()
    )
    
    create_file(
      Path.join([app_name, ".gitignore"]),
      gitignore_template()
    )
    
    Mix.shell().info("""
    
    Your Parrot UAC application has been generated!
    
    To get started:
    
        cd #{app_name}
        mix deps.get
        mix compile
        
    To make a test call:
    
        # Start your UAC in one terminal
        iex -S mix
        iex> #{module_name}.start()
        #{if include_audio do
          "iex> #{module_name}.list_audio_devices()  # Optional: see available devices"
        else
          ""
        end}
        iex> #{module_name}.call("sip:service@127.0.0.1:5060")
        
        # Press Enter to hang up
        
    """)
  end
  
  defp mix_exs_template(assigns) do
    """
    defmodule <%= @module %>.MixProject do
      use Mix.Project

      def project do
        [
          app: :<%= @app_name %>,
          version: "0.1.0",
          elixir: "~> 1.14",
          start_permanent: Mix.env() == :prod,
          deps: deps()
        ]
      end

      def application do
        [
          extra_applications: [:logger],
          mod: {<%= @module %>.Application, []}
        ]
      end

      defp deps do
        [
          {:parrot_platform, github: "byoungdale/parrot"}
          # {:parrot_platform, "~> 0.0.1-alpha.1"}
        ]
      end
    end
    """
    |> EEx.eval_string(assigns: assigns)
  end
  
  defp app_template(assigns) do
    """
    defmodule <%= @module %> do
      @moduledoc \"\"\"
      <%= @module %> - A Parrot UAC (User Agent Client) application.
      
      This application demonstrates:
      - Making outbound SIP calls
      <%= if @include_audio do %>- Using system microphone for outbound audio
      - Playing received audio through system speakers
      - Bidirectional G.711 A-law audio streaming<% else %>- SIP signaling without media<% end %>
      - Proper call lifecycle management
      
      ## Usage
      
          # Start the UAC
          <%= @module %>.start()
          <%= if @include_audio do %>
          # List available audio devices
          <%= @module %>.list_audio_devices()
          
          # Make a call using default audio devices
          <%= @module %>.call("sip:service@127.0.0.1:5060")
          
          # Make a call with specific audio devices
          <%= @module %>.call("sip:service@127.0.0.1:5060", input_device: 1, output_device: 2)
          <% else %>
          # Make a call
          <%= @module %>.call("sip:service@127.0.0.1:5060")
          <% end %>
          # Hang up the current call
          <%= @module %>.hangup()
      \"\"\"
      
      use GenServer
      require Logger
      
      alias Parrot.Sip.{UAC, Message}
      alias Parrot.Sip.Headers.{From, To, CSeq, CallId, Contact, Via}<%= if @include_audio do %>
      alias Parrot.Media.{MediaSession, MediaSessionManager, AudioDevices}<% end %>
      
      @server_name {:via, Registry, {Parrot.Registry, __MODULE__}}
      
      defmodule State do
        @moduledoc false
        defstruct [
          :transport_ref,
          :current_call,<%= if @include_audio do %>
          :media_session,<% end %>
          :dialog_id,
          :call_id,
          :local_tag,
          :remote_tag<%= if @include_audio do %>,
          :input_device_id,
          :output_device_id<% end %>
        ]
      end
      
      # Client API
      
      @doc \"\"\"
      Starts the UAC application.
      \"\"\"
      def start(opts \\\\ []) do
        case GenServer.start_link(__MODULE__, opts, name: @server_name) do
          {:ok, pid} ->
            Logger.info("<%= @module %> started successfully")
            {:ok, pid}
          {:error, {:already_started, pid}} ->
            Logger.info("<%= @module %> already running")
            {:ok, pid}
          error ->
            error
        end
      end
      <%= if @include_audio do %>
      @doc \"\"\"
      Lists available audio devices.
      \"\"\"
      def list_audio_devices do
        IO.puts("\\n")
        AudioDevices.print_devices()
        IO.puts("\\nNote: Use the device IDs shown above when calling <%= @module %>.call/2")
        IO.puts("Example: <%= @module %>.call(\\"sip:service@127.0.0.1:5060\\", input_device: 1, output_device: 2)")
        :ok
      end
      <% end %>
      @doc \"\"\"
      Makes an outbound call.
      <%= if @include_audio do %>
      Options:
        - :input_device - Audio input device ID (defaults to system default)
        - :output_device - Audio output device ID (defaults to system default)
      <% end %>\"\"\"
      def call(uri, opts \\\\ []) do
        GenServer.call(@server_name, {:make_call, uri, opts})
      end
      
      @doc \"\"\"
      Hangs up the current call.
      \"\"\"
      def hangup do
        GenServer.call(@server_name, :hangup)
      end
      
      @doc \"\"\"
      Gets the current call status.
      \"\"\"
      def status do
        GenServer.call(@server_name, :status)
      end
      
      # Server Callbacks
      
      @impl true
      def init(opts) do
        Logger.info("Initializing <%= @module %>")
        <%= if @include_audio do %>
        # Get default audio devices
        input_device = case opts[:input_device] || AudioDevices.get_default_input() do
          {:ok, device_id} -> device_id
          _ -> nil
        end
        
        output_device = case opts[:output_device] || AudioDevices.get_default_output() do
          {:ok, device_id} -> device_id  
          _ -> nil
        end
        <% end %>
        # Start transport
        transport_opts = Keyword.get(opts, :transport, %{})
        
        case start_transport(transport_opts) do
          {:ok, ref} ->
            state = %State{
              transport_ref: ref<%= if @include_audio do %>,
              input_device_id: input_device,
              output_device_id: output_device<% end %>
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
        else<%= if @include_audio do %>
          # Override default devices if specified
          input_device = opts[:input_device] || state.input_device_id
          output_device = opts[:output_device] || state.output_device_id
          
          case do_make_call(uri, input_device, output_device, state) do<% else %>
          case do_make_call(uri, state) do<% end %>
            {:ok, new_state} ->
              {:reply, :ok, new_state}
              
            {:error, reason} = error ->
              Logger.error("Failed to make call: \#{inspect(reason)}")
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
          dialog_id: state.dialog_id<%= if @include_audio do %>,
          media_active: state.media_session != nil<% end %>
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
        Logger.debug("Unhandled message: \#{inspect(msg)}")
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
      
      defp do_make_call(uri, <%= if @include_audio do %>input_device, output_device, <% end %>state) do
        # Generate call parameters
        call_id = "uac-\#{:rand.uniform(1000000)}@\#{get_local_ip()}"
        local_tag = generate_tag()
        dialog_id = "\#{call_id}-\#{local_tag}"
        <%= if @include_audio do %>
        # Step 1: Prepare UAC session using MediaSessionManager
        Logger.debug("Preparing UAC media session...")
        case MediaSessionManager.prepare_uac_session(
          id: "uac-media-\#{call_id}",
          dialog_id: dialog_id,
          audio_source: :device,
          audio_sink: :device,
          input_device_id: input_device,
          output_device_id: output_device,
          supported_codecs: [:pcma]  # G.711 A-law
        ) do
          {:ok, media_session, sdp_offer} ->
            Logger.debug("UAC session prepared with SDP offer")
            
            # Step 2: Create INVITE with the SDP from MediaSessionManager<% else %>
        # Create INVITE without SDP<% end %>
            headers = %{
              "via" => [Via.new(get_local_ip(), "udp", 5060)],
              "from" => From.new("sip:uac@\#{get_local_ip()}", "<%= @module %>", local_tag),
              "to" => To.new(uri),
              "call-id" => CallId.new(call_id),
              "cseq" => CSeq.new(1, :invite),
              "contact" => Contact.new("sip:uac@\#{get_local_ip()}:5060"),<%= if @include_audio do %>
              "content-type" => "application/sdp",<% end %>
              "allow" => "INVITE, ACK, BYE, CANCEL, OPTIONS, INFO",
              "supported" => "replaces, timer"
            }
            
            invite = Message.new_request(:invite, uri, headers)<%= if @include_audio do %>
            |> Message.set_body(sdp_offer)<% end %>
            
            # Create UAC handler callback
            callback = create_uac_callback(self())
            
            # Step 3: Send INVITE
            {:uac_id, transaction} = UAC.request(invite, callback)
            Logger.info("INVITE sent, transaction: \#{inspect(transaction)}")
            
            # Store session info for later
            new_state = %{state |
              current_call: uri,
              call_id: call_id,
              local_tag: local_tag<%= if @include_audio do %>,
              media_session: media_session<% end %>
            }
            
            {:ok, new_state}<%= if @include_audio do %>
            
          {:error, reason} ->
            Logger.error("Failed to prepare UAC session: \#{inspect(reason)}")
            {:error, reason}
        end<% end %>
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
            Logger.info("Call progress: \#{code} \#{response.reason_phrase}")
            
            if code == 180 do
              IO.puts("\\n🔔 Ringing...")
            end
            
            state
            
          200 ->
            # Success - check if this is for INVITE or other method
            case response.headers["cseq"] do
              %{method: :invite} ->
                # Success - call answered
                Logger.info("Call answered!")
                IO.puts("\\n✅ Call connected!<%= if @include_audio do %> Audio devices active.<% end %>")
                <%= if @include_audio do %>IO.puts("🎤 Speaking through microphone...")
                IO.puts("🔊 Listening through speakers...")
                <% end %>IO.puts("\\nPress Enter to hang up")
                
                # Extract remote tag and create dialog ID
                remote_tag = case response.headers["to"] do
                  %{parameters: %{"tag" => tag}} -> tag
                  _ -> nil
                end
                Logger.debug("Remote tag: \#{inspect(remote_tag)}")
                
                dialog_id = %{
                  call_id: state.call_id,
                  local_tag: state.local_tag,
                  remote_tag: remote_tag
                }
                
                # Send ACK immediately after receiving 200 OK for INVITE
                Logger.info("Sending ACK for 200 OK...")
                send_ack(state, response)
                <%= if @include_audio do %>
                # Extract SDP answer from response
                sdp_answer = response.body
                Logger.debug("Completing UAC setup with SDP answer...")
                
                # Complete UAC setup using MediaSessionManager
                case MediaSessionManager.complete_uac_setup(state.media_session, sdp_answer) do
                  :ok ->
                    Logger.info("UAC setup completed successfully, media is flowing")
                    <% else %>
                Logger.info("Call connected (signaling only)")
                <% end %>
                    # Start a task to wait for Enter key
                    Task.start(fn ->
                      IO.gets("")
                      GenServer.call(@server_name, :hangup)
                    end)
                    
                    %{state |
                      dialog_id: dialog_id,
                      remote_tag: remote_tag
                    }<%= if @include_audio do %>
                    
                  {:error, reason} ->
                    Logger.error("Failed to complete UAC setup: \#{inspect(reason)}")
                    IO.puts("\\n❌ Failed to establish media: \#{inspect(reason)}")
                    # TODO: Send BYE to terminate the call
                    state
                end<% end %>
              
              %{method: :bye} ->
                # Success response to BYE - no ACK needed
                Logger.info("BYE acknowledged")
                # Clean up already done in do_hangup
                state
                
              _ ->
                # Other successful response
                Logger.debug("Success response for \#{inspect(response.headers["cseq"])}")
                state
            end
            
          code when code >= 300 and code < 400 ->
            # Redirect
            Logger.info("Call redirected: \#{code} \#{response.reason_phrase}")
            IO.puts("\\n↪️  Call redirected: \#{response.reason_phrase}")
            state
            
          code when code >= 400 ->
            # Error
            Logger.error("Call failed: \#{code} \#{response.reason_phrase}")
            IO.puts("\\n❌ Call failed: \#{response.reason_phrase}")
            
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
        Logger.error("UAC error: \#{inspect(reason)}")
        IO.puts("\\n❌ Call error: \#{inspect(reason)}")
        <%= if @include_audio do %>
        # Clean up
        if state.media_session do
          MediaSession.terminate_session(state.media_session)
        end
        <% end %>
        Process.delete({:call_context, state.call_id})
        
        %{state |
          current_call: nil,
          call_id: nil,
          local_tag: nil<%= if @include_audio do %>,
          media_session: nil<% end %>,
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
          "from" => From.new("sip:uac@\#{get_local_ip()}", "<%= @module %>", state.local_tag),
          "to" => To.new(state.current_call, nil, %{"tag" => remote_tag}),
          "call-id" => CallId.new(state.call_id),
          "cseq" => CSeq.new(1, :ack),
          "contact" => Contact.new("sip:uac@\#{get_local_ip()}:5060")
        }
        
        ack = Message.new_request(:ack, state.current_call, headers)
        
        # ACK is sent without expecting a response
        UAC.ack_request(ack)
        Logger.info("ACK sent to \#{state.current_call}")
      end
      
      defp do_hangup(state) do
        Logger.info("Hanging up call")
        
        # Send BYE
        headers = %{
          "via" => [Via.new(get_local_ip(), "udp", 5060)],
          "from" => From.new("sip:uac@\#{get_local_ip()}", "<%= @module %>", state.local_tag),
          "to" => To.new(state.current_call, nil, %{"tag" => state.remote_tag}),
          "call-id" => CallId.new(state.call_id),
          "cseq" => CSeq.new(2, :bye),
          "contact" => Contact.new("sip:uac@\#{get_local_ip()}:5060")
        }
        
        bye = Message.new_request(:bye, state.current_call, headers)
        
        callback = create_uac_callback(self())
        UAC.request(bye, callback)
        <%= if @include_audio do %>
        # Stop media session
        if state.media_session do
          MediaSession.terminate_session(state.media_session)
        end
        <% end %>
        # Clean up
        Process.delete({:call_context, state.call_id})
        
        IO.puts("\\n📞 Call ended")
        
        %{state |
          current_call: nil,
          call_id: nil,
          local_tag: nil,
          remote_tag: nil<%= if @include_audio do %>,
          media_session: nil<% end %>,
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
    
    defmodule <%= @module %>.Application do
      @moduledoc false
      
      use Application
      
      @impl true
      def start(_type, _args) do
        children = [
          # Add any application-specific children here
        ]
        
        opts = [strategy: :one_for_one, name: <%= @module %>.Supervisor]
        Supervisor.start_link(children, opts)
      end
    end
    """
    |> EEx.eval_string(assigns: assigns)
  end
  
  defp readme_template(assigns) do
    """
    # <%= @module %>

    A Parrot UAC (User Agent Client) application for making outbound SIP calls.

    ## Features

    - Make outbound SIP calls to any SIP endpoint
    <%= if @include_audio do %>- System audio integration (microphone and speakers)
    - G.711 A-law (PCMA) audio codec support
    - Audio device selection and listing<% else %>- SIP signaling (no media)<% end %>
    - Interactive call control

    ## Usage

    ### Starting the Application

    ```elixir
    iex> <%= @module %>.start()
    {:ok, #PID<0.123.0>}
    ```
    <%= if @include_audio do %>
    ### Listing Audio Devices

    ```elixir
    iex> <%= @module %>.list_audio_devices()

    Input Devices:
    0: Built-in Microphone (2 channels, 48000 Hz)
    
    Output Devices:
    1: Built-in Output (2 channels, 48000 Hz)

    :ok
    ```
    <% end %>
    ### Making a Call

    ```elixir
    # Call using default audio devices
    iex> <%= @module %>.call("sip:service@192.168.1.100:5060")
    :ok

    🔔 Ringing...
    ✅ Call connected!<%= if @include_audio do %> Audio devices active.
    🎤 Speaking through microphone...
    🔊 Listening through speakers...<% end %>

    Press Enter to hang up
    ```
    <%= if @include_audio do %>
    ### Making a Call with Specific Audio Devices

    ```elixir
    iex> <%= @module %>.call("sip:service@192.168.1.100:5060", input_device: 0, output_device: 1)
    :ok
    ```
    <% end %>
    ### Checking Call Status

    ```elixir
    iex> <%= @module %>.status()
    %{
      active_call: true,
      call_id: "uac-123456@192.168.1.50",
      dialog_id: %{...}<%= if @include_audio do %>,
      media_active: true<% end %>
    }
    ```

    ### Hanging Up

    ```elixir
    iex> <%= @module %>.hangup()
    :ok

    📞 Call ended
    ```

    ## Configuration

    The UAC can be configured when starting:

    ```elixir
    <%= @module %>.start(transport: %{listen_port: 5070})
    ```

    ## Testing with a UAS

    To test your UAC, you need a UAS (User Agent Server) to receive calls:

    1. Generate a UAS application:
       ```bash
       mix parrot.gen.uas my_uas_app
       cd my_uas_app
       mix deps.get
       iex -S mix
       ```

    2. In another terminal, start your UAC and make a call:
       ```bash
       cd <%= @app_name %>
       iex -S mix
       iex> <%= @module %>.start()
       iex> <%= @module %>.call("sip:service@127.0.0.1:5060")
       ```

    ## Troubleshooting

    - **Connection Refused**: Ensure the target SIP endpoint is running
    - **No Audio**: Check audio device permissions and selection
    - **Call Fails**: Check network connectivity and SIP URI format

    ## License

    See LICENSE file for details.
    """
    |> EEx.eval_string(assigns: assigns)
  end
  
  defp test_template(assigns) do
    """
    defmodule <%= @module %>Test do
      use ExUnit.Case
      doctest <%= @module %>

      describe "start/1" do
        test "starts the UAC application" do
          assert {:ok, _pid} = <%= @module %>.start()
        end
        
        test "returns already started when called twice" do
          {:ok, _pid} = <%= @module %>.start()
          assert {:ok, _pid} = <%= @module %>.start()
        end
      end

      describe "status/0" do
        setup do
          {:ok, _pid} = <%= @module %>.start()
          :ok
        end
        
        test "returns idle status when no call active" do
          status = <%= @module %>.status()
          assert status.active_call == false
          assert status.call_id == nil
        end
      end
    end
    """
    |> EEx.eval_string(assigns: assigns)
  end
  
  defp formatter_template do
    """
    [
      import_deps: [:parrot_platform],
      inputs: ["{mix,.formatter}.exs", "{config,lib,test}/**/*.{ex,exs}"]
    ]
    """
  end
  
  defp gitignore_template do
    """
    # The directory Mix will write compiled artifacts to.
    /_build/

    # If you run "mix test --cover", coverage assets end up here.
    /cover/

    # The directory Mix downloads your dependencies sources to.
    /deps/

    # Where third-party dependencies like ExDoc output generated docs.
    /doc/

    # Ignore .fetch files in case you like to edit your project deps locally.
    /.fetch

    # If the VM crashes, it generates a dump, let's ignore it too.
    erl_crash.dump

    # Also ignore archive artifacts (built via "mix archive.build").
    *.ez

    # Ignore package tarball (built via "mix hex.build").
    *.tar

    # Temporary files, for example, from tests.
    /tmp/

    # Ignore .DS_Store files on macOS
    .DS_Store
    """
  end
  
  defp to_app_name(name) do
    name
    |> Path.basename()
    |> String.downcase()
    |> String.replace(~r/[^\w]/, "_")
    |> String.trim("_")
  end
  
  defp to_module_name(name) do
    name
    |> String.split(~r/[^a-zA-Z0-9]/)
    |> Enum.map(&String.capitalize/1)
    |> Enum.join()
  end
end
