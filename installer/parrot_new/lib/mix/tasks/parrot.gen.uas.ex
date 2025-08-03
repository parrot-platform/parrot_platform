defmodule Mix.Tasks.Parrot.Gen.Uas do
  @shortdoc "Generates a new Parrot UAS (User Agent Server) application"
  @moduledoc """
  Generates a new Parrot UAS application from a template.

  ## Usage

      mix parrot.gen.uas APP_NAME [OPTIONS]

  ## Examples

      mix parrot.gen.uas my_uas_app
      mix parrot.gen.uas my_uas_app --port 5080
      mix parrot.gen.uas my_uas_app --module MyCompany.UasApp

  ## Options

    * `--port` - The SIP port to listen on (default: 5060)
    * `--module` - The module name to use (default: derived from app name)
    * `--no-media` - Skip media handler implementation
    * `--no-examples` - Skip example handlers

  The generator creates:

    * A complete UAS application module implementing `Parrot.UasHandler`
    * Optional `Parrot.MediaHandler` implementation
    * Example SIP method handlers (INVITE, BYE, OPTIONS, etc.)
    * README with usage instructions
    * Basic test file

  The generated application will:

    * Answer incoming calls (INVITE)
    * Play audio files when media is enabled
    * Handle basic SIP methods
    * Clean up resources properly
  """

  use Mix.Task
  import Mix.Generator

  @switches [
    port: :integer,
    module: :string,
    no_media: :boolean,
    no_examples: :boolean
  ]

  @impl Mix.Task
  def run(args) do
    case OptionParser.parse!(args, switches: @switches) do
      {opts, [app_name]} ->
        generate(app_name, opts)

      {_, _} ->
        Mix.raise("Expected exactly one argument (the application name)")
    end
  end

  defp generate(app_name, opts) do
    path = Path.expand(app_name)
    app = to_app_name(app_name)
    module = opts[:module] || to_module_name(app_name)
    port = opts[:port] || 5060
    include_media = !opts[:no_media]
    include_examples = !opts[:no_examples]

    binding = [
      app: app,
      module: module,
      port: port,
      include_media: include_media,
      include_examples: include_examples
    ]

    create_directory(path)
    create_directory(Path.join(path, "lib"))
    create_directory(Path.join(path, "test"))

    create_file(Path.join(path, "mix.exs"), EEx.eval_string(mix_exs_template(), assigns: binding))

    create_file(
      Path.join(path, "README.md"),
      EEx.eval_string(readme_template(), assigns: binding)
    )

    create_file(
      Path.join(path, "lib/#{app}.ex"),
      EEx.eval_string(app_module_template(), assigns: binding)
    )

    create_file(
      Path.join(path, "test/#{app}_test.exs"),
      EEx.eval_string(test_template(), assigns: binding)
    )

    create_file(Path.join(path, ".gitignore"), gitignore_template())
    create_file(Path.join(path, ".formatter.exs"), formatter_template())

    Mix.shell().info("""

    Your Parrot UAS application has been generated!

    To get started:

        cd #{app_name}
        mix deps.get
        iex -S mix

    Then in iex:

        iex> #{module}.start()

    Your SIP endpoint will be available at:
        sip:service@<your-ip>:#{port}

    Check the README.md for more information.
    """)
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

  # Template functions

  defp readme_template do
    """
    # <%= @module %> - Parrot UAS Application

    A SIP User Agent Server (UAS) application built with Parrot Platform.

    ## Overview

    This application implements a SIP UAS that:<%= if @include_media do %>
    - Answers incoming calls
    - Plays audio files to callers
    - Handles media sessions<% else %>
    - Answers incoming calls
    - Responds to SIP requests<% end %><%= if @include_examples do %>
    - Includes example handlers for common SIP methods<% end %>

    ## Running the Application

    ```elixir
    # Start the application
    <%= @module %>.start()

    # Or with custom port
    <%= @module %>.start(port: <%= @port %>)
    ```

    ## Configuration

    The UAS listens on port <%= @port %> by default. Connect your SIP client to:
    ```
    sip:service@<your-ip>:<%= @port %>
    ```

    ## Features
    <%= if @include_media do %>
    ### Media Handling

    The application implements `Parrot.MediaHandler` behaviour for:
    - Automatic audio playback when calls connect
    - Playlist support for multiple audio files
    - Graceful error handling
    <% end %>
    ### SIP Methods

    Handles the following SIP methods:
    - INVITE - Accept incoming calls
    - ACK - Acknowledge call setup
    - BYE - End calls gracefully
    - CANCEL - Cancel pending calls
    - OPTIONS - Report capabilities<%= if @include_examples do %>
    - REGISTER - Registration handling
    - INFO - Information requests<% end %>

    ## Customization

    ### Audio Files<%= if @include_media do %>

    By default, the application uses the Parrot Platform welcome audio file. To use your own audio files, modify the `audio_config` in `process_invite/2`:

    ```elixir
    audio_config = %{
      welcome_file: "path/to/your/welcome.wav",
      menu_file: "path/to/your/menu.wav",
      music_file: "path/to/your/music.wav",
      goodbye_file: "path/to/your/goodbye.wav"
    }
    ```

    Note: Audio files must be in WAV format (PCM, 8000 Hz, mono).
    <% end %>
    ### SIP Behavior

    Each SIP method handler can be customized. For example, to add authentication:

    ```elixir
    def handle_invite(request, state) do
      if authenticated?(request) do
        process_invite(request, state)
      else
        {:respond, 401, "Unauthorized", %{"WWW-Authenticate" => "..."}, ""}
      end
    end
    ```

    ## Architecture

    The application uses:
    - `Parrot.UasHandler` for SIP protocol handling<%= if @include_media do %>
    - `Parrot.MediaHandler` for media session management<% end %>
    - Registry for process discovery
    - Supervised processes for reliability

    ## Testing

    Use any SIP client (like Linphone, Zoiper, or MicroSIP) to test:

    1. Configure your SIP client:
       - Username: `service` (or any username)
       - Domain: `<server-ip>`
       - Port: `<%= @port %>`
       - No authentication required

    2. Make a call to `sip:service@<server-ip>:<%= @port %>`

    3. The UAS will answer and <%= if @include_media do %>play audio<% else %>accept the call<% end %>

    ## Extending

    To add new functionality:

    1. Add new SIP method handlers
    2. Implement additional media controls
    3. Add authentication/authorization
    4. Integrate with external systems

    See the Parrot Platform documentation for more details.
    """
  end

  defp app_module_template do
    """
    defmodule <%= @module %> do
      @moduledoc \"\"\"
      A SIP User Agent Server (UAS) application built with Parrot Platform.
      
      This UAS answers incoming calls<%= if @include_media do %>, plays audio files,<% end %> and handles basic SIP operations.
      \"\"\"

      use Parrot.UasHandler<%= if @include_media do %>
      @behaviour Parrot.MediaHandler<% end %>
      require Logger

      @default_port <%= @port %>

      def start(opts \\\\ []) do
        port = Keyword.get(opts, :port, @default_port)
        
        Logger.info("Starting <%= @module %> on port \#{port}")
        Logger.info("Connect your SIP client to sip:service@<your-ip>:\#{port}")
        
        # Start the SIP transport with our handler
        # Handler configuration options:
        # - log_level: Controls verbosity (:debug shows transaction states, :info is quieter)
        # - sip_trace: When true, logs all SIP messages sent/received
        handler = Parrot.Sip.Handler.new(
          Parrot.Sip.HandlerAdapter.Core,
          {__MODULE__, %{calls: %{}}},
          log_level: :info,
          sip_trace: true
        )
        
        case Parrot.Sip.Transport.StateMachine.start_udp(%{
          handler: handler,
          listen_port: port
        }) do
          :ok ->
            Logger.info("<%= @module %> started successfully!")
            :ok
          {:error, {:already_started, _pid}} = error ->
            Logger.info("<%= @module %> already running on port \#{port}")
            error
        end
      end

      # Transaction callbacks for INVITE state machine
      @impl true
      def handle_transaction_invite_trying(_request, _transaction, _state) do
        Logger.info("[<%= @module %>] INVITE transaction: trying")
        :noreply
      end

      @impl true
      def handle_transaction_invite_proceeding(request, _transaction, state) do
        Logger.info("[<%= @module %>] INVITE transaction: proceeding")
        process_invite(request, state)
      end

      @impl true
      def handle_transaction_invite_completed(_request, _transaction, _state) do
        Logger.info("[<%= @module %>] INVITE transaction: completed")
        :noreply
      end

      # Main SIP method handlers
      @impl true
      def handle_invite(request, state) do
        Logger.info("[<%= @module %>] Direct INVITE handler called")
        process_invite(request, state)
      end

      @impl true
      def handle_ack(request, _state) when not is_nil(request) do
        Logger.info("[<%= @module %>] ACK received")<%= if @include_media do %>
        
        dialog_id = Parrot.Sip.DialogId.from_message(request)
        
        # Find and start the media session
        case Registry.lookup(Parrot.Registry, {:uas_media, dialog_id.call_id}) do
          [{_pid, media_session_id}] ->
            Logger.info("[<%= @module %>] Starting media playback for session: \#{media_session_id}")
            Task.start(fn ->
              Process.sleep(100)
              Parrot.Media.MediaSession.start_media(media_session_id)
            end)
          [] ->
            Logger.warning("[<%= @module %>] No media session found for call: \#{dialog_id.call_id}")
        end<% end %>
        
        :noreply
      end

      def handle_ack(nil, _state), do: :noreply

      @impl true
      def handle_bye(request, _state) when not is_nil(request) do
        Logger.info("[<%= @module %>] BYE received, ending call")<%= if @include_media do %>
        
        dialog_id = Parrot.Sip.DialogId.from_message(request)
        
        # Clean up media session
        case Registry.lookup(Parrot.Registry, {:uas_media, dialog_id.call_id}) do
          [{_pid, media_session_id}] ->
            Logger.info("[<%= @module %>] Terminating media session: \#{media_session_id}")
            try do
              Parrot.Media.MediaSession.terminate_session(media_session_id)
            rescue
              RuntimeError ->
                Logger.warning("[<%= @module %>] Media session \#{media_session_id} already terminated")
            end
            Registry.unregister(Parrot.Registry, {:uas_media, dialog_id.call_id})
          [] ->
            Logger.info("[<%= @module %>] No media session found for call: \#{dialog_id.call_id}")
        end<% end %>
        
        {:respond, 200, "OK", %{}, ""}
      end

      def handle_bye(nil, _state), do: {:respond, 200, "OK", %{}, ""}

      @impl true
      def handle_cancel(_request, _state) do
        Logger.info("[<%= @module %>] CANCEL received")
        {:respond, 200, "OK", %{}, ""}
      end

      @impl true
      def handle_options(_request, _state) do
        Logger.info("[<%= @module %>] OPTIONS received")
        allow_methods = "INVITE, ACK, BYE, CANCEL, OPTIONS<%= if @include_examples do %>, INFO, REGISTER<% end %>"
        {:respond, 200, "OK", %{"Allow" => allow_methods}, ""}
      end<%= if @include_examples do %>

      @impl true
      def handle_register(_request, _state) do
        Logger.info("[<%= @module %>] REGISTER received")
        {:respond, 200, "OK", %{}, ""}
      end

      @impl true
      def handle_info(_request, _state) do
        Logger.info("[<%= @module %>] INFO received")
        {:respond, 200, "OK", %{}, ""}
      end<% end %><%= if @include_media do %>

      # MediaHandler callbacks
      
      @impl Parrot.MediaHandler
      def init(args) do
        Logger.info("[<%= @module %> MediaHandler] Initializing with args: \#{inspect(args)}")
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
        Logger.info("[<%= @module %> MediaHandler] Session started: \#{session_id}")
        Logger.info("  Options: \#{inspect(opts)}")
        {:ok, Map.put(state, :session_id, session_id)}
      end
      
      @impl Parrot.MediaHandler
      def handle_session_stop(session_id, reason, state) do
        Logger.info("[<%= @module %> MediaHandler] Session stopped: \#{session_id}, reason: \#{inspect(reason)}")
        Logger.info("  Final call stats: \#{inspect(state.call_stats)}")
        {:ok, state}
      end
      
      @impl Parrot.MediaHandler
      def handle_offer(sdp, direction, state) do
        Logger.info("[<%= @module %> MediaHandler] Received SDP offer (\#{direction})")
        Logger.debug("  SDP: \#{String.trim(sdp)}")
        {:noreply, state}
      end
      
      @impl Parrot.MediaHandler
      def handle_answer(sdp, direction, state) do
        Logger.info("[<%= @module %> MediaHandler] Received SDP answer (\#{direction})")
        Logger.debug("  SDP: \#{String.trim(sdp)}")
        {:noreply, state}
      end
      
      @impl Parrot.MediaHandler
      def handle_codec_negotiation(offered_codecs, supported_codecs, state) do
        Logger.info("[<%= @module %> MediaHandler] Negotiating codecs")
        Logger.info("  Offered: \#{inspect(offered_codecs)}")
        Logger.info("  Supported: \#{inspect(supported_codecs)}")
        
        # Prefer opus, then pcmu, then pcma
        codec = cond do
          :opus in offered_codecs and :opus in supported_codecs -> :opus
          :pcmu in offered_codecs and :pcmu in supported_codecs -> :pcmu
          :pcma in offered_codecs and :pcma in supported_codecs -> :pcma
          true -> 
            Enum.find(offered_codecs, fn c -> c in supported_codecs end)
        end
        
        if codec do
          Logger.info("  Selected codec: \#{codec}")
          {:ok, codec, state}
        else
          Logger.error("  No common codec found!")
          {:error, :no_common_codec, state}
        end
      end
      
      @impl Parrot.MediaHandler
      def handle_negotiation_complete(_local_sdp, _remote_sdp, codec, state) do
        Logger.info("[<%= @module %> MediaHandler] Negotiation complete with codec: \#{codec}")
        {:ok, Map.put(state, :negotiated_codec, codec)}
      end
      
      @impl Parrot.MediaHandler
      def handle_stream_start(session_id, direction, state) do
        Logger.info("[<%= @module %> MediaHandler] Stream started for \#{session_id} (\#{direction})")
        
        # Start playing welcome message
        if state.welcome_file && File.exists?(state.welcome_file) do
          Logger.info("  Playing welcome file: \#{state.welcome_file}")
          {{:play, state.welcome_file}, %{state | current_state: :welcome}}
        else
          Logger.warning("  No welcome file configured")
          {:ok, state}
        end
      end
      
      @impl Parrot.MediaHandler
      def handle_stream_stop(session_id, reason, state) do
        Logger.info("[<%= @module %> MediaHandler] Stream stopped for \#{session_id}, reason: \#{inspect(reason)}")
        {:ok, state}
      end
      
      @impl Parrot.MediaHandler
      def handle_stream_error(session_id, error, state) do
        Logger.error("[<%= @module %> MediaHandler] Stream error for \#{session_id}: \#{inspect(error)}")
        {:continue, state}
      end
      
      @impl Parrot.MediaHandler
      def handle_play_complete(file_path, state) do
        Logger.info("[<%= @module %> MediaHandler] Playback completed: \#{file_path}")
        
        case state.current_state do
          :welcome ->
            # After welcome, play menu if available
            cond do
              state.menu_file && File.exists?(state.menu_file) ->
                Logger.info("  Playing menu file: \#{state.menu_file}")
                {{:play, state.menu_file}, %{state | current_state: :menu}}
              true ->
                Logger.info("  No menu file, stopping playback")
                {:stop, %{state | current_state: :done}}
            end
            
          :menu ->
            Logger.info("  Menu completed, stopping playback")
            {:stop, %{state | current_state: :done}}
            
          _ ->
            {:stop, state}
        end
      end
      
      @impl Parrot.MediaHandler
      def handle_media_request(request, state) do
        Logger.info("[<%= @module %> MediaHandler] Media request: \#{inspect(request)}")
        
        case request do
          {:play_dtmf, digits} ->
            Logger.info("  Playing DTMF digits: \#{digits}")
            {:ok, :dtmf_played, state}
            
          {:adjust_volume, level} ->
            Logger.info("  Adjusting volume to: \#{level}")
            {:ok, :volume_adjusted, state}
            
          _ ->
            Logger.warning("  Unknown media request")
            {:error, :unknown_request, state}
        end
      end<% end %>

      # Private functions

      defp process_invite(nil, _state) do
        Logger.error("[<%= @module %>] Cannot process nil INVITE")
        {:respond, 500, "Internal Server Error", %{}, ""}
      end

      defp process_invite(request, _state) do
        from = request.headers["from"]
        Logger.info("[<%= @module %>] Processing INVITE from: \#{from.display_name || from.uri.user}")<%= if @include_media do %>
        
        dialog_id = Parrot.Sip.DialogId.from_message(request)
        dialog_id_str = Parrot.Sip.DialogId.to_string(dialog_id)
        media_session_id = "media_\#{dialog_id_str}"
        
        # Configure audio files for this call
        priv_dir = :code.priv_dir(:parrot_platform)
        audio_config = %{
          welcome_file: Path.join(priv_dir, "audio/parrot-welcome.wav"),
          menu_file: Path.join(priv_dir, "audio/parrot-welcome.wav"),  # Using same file for demo
          music_file: Path.join(priv_dir, "audio/parrot-welcome.wav"),
          goodbye_file: Path.join(priv_dir, "audio/parrot-welcome.wav"),
          current_state: :welcome
        }
        
        # Start media session
        case start_media_session(media_session_id, dialog_id_str, audio_config) do
          {:ok, _pid} ->
            # Process SDP offer and generate answer
            case Parrot.Media.MediaSession.process_offer(media_session_id, request.body) do
              {:ok, sdp_answer} ->
                Logger.info("[<%= @module %>] Call accepted, SDP negotiated")
                
                # Register media session for later lookup
                Registry.register(Parrot.Registry, {:uas_media, dialog_id.call_id}, media_session_id)
                
                {:respond, 200, "OK", %{}, sdp_answer}
                
              {:error, reason} ->
                Logger.error("[<%= @module %>] SDP negotiation failed: \#{inspect(reason)}")
                {:respond, 488, "Not Acceptable Here", %{}, ""}
            end
            
          {:error, reason} ->
            Logger.error("[<%= @module %>] Failed to create media session: \#{inspect(reason)}")
            {:respond, 500, "Internal Server Error", %{}, ""}
        end<% else %>
        
        # Simple response without media
        {:respond, 200, "OK", %{}, ""}<% end %>
      end<%= if @include_media do %>
      
      defp start_media_session(session_id, dialog_id, audio_config) do
        Parrot.Media.MediaSessionSupervisor.start_session(
          id: session_id,
          dialog_id: dialog_id,
          role: :uas,
          owner: self(),
          audio_file: audio_config.welcome_file,
          media_handler: __MODULE__,
          handler_args: audio_config,
          supported_codecs: [:pcma]  # Only G.711 A-law for now (Opus send not implemented)
        )
      end<% end %>
    end
    """
  end

  defp test_template do
    """
    defmodule <%= @module %>Test do
      use ExUnit.Case
      
      describe "<%= @module %>" do
        test "module exists" do
          assert function_exported?(<%= @module %>, :start, 0)
          assert function_exported?(<%= @module %>, :start, 1)
        end
        
        test "implements required behaviours" do
          behaviours = <%= @module %>.__info__(:attributes)[:behaviour] || []
          assert Parrot.UasHandler in behaviours<%= if @include_media do %>
          assert Parrot.MediaHandler in behaviours<% end %>
        end
      end
    end
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

    # Where 3rd-party dependencies like ExDoc output generated docs.
    /doc/

    # Ignore .fetch files in case you like to edit your project deps locally.
    /.fetch

    # If the VM crashes, it generates a dump, let's ignore it too.
    erl_crash.dump

    # Also ignore archive artifacts (built via "mix archive.build").
    *.ez

    # Ignore package tarball (built via "mix hex.build").
    *.tar

    # Ignore Elixir Language Server files
    /.elixir_ls/

    # Ignore OS files
    .DS_Store
    Thumbs.db

    # Ignore editor files
    *.swp
    *.swo
    *~
    .idea/
    .vscode/
    """
  end

  defp mix_exs_template do
    """
    defmodule <%= @module %>.MixProject do
      use Mix.Project

      def project do
        [
          app: :<%= @app %>,
          version: "0.1.0",
          elixir: "~> 1.14",
          start_permanent: Mix.env() == :prod,
          deps: deps()
        ]
      end

      # Run "mix help compile.app" to learn about applications.
      def application do
        [
          extra_applications: [:logger]
        ]
      end

      # Run "mix help deps" to learn about dependencies.
      defp deps do
        [
          {:parrot_platform, "~> 0.0.1-alpha.1"}
        ]
      end
    end
    """
  end

  defp formatter_template do
    """
    # Used by "mix format"
    [
      inputs: ["{mix,.formatter}.exs", "{config,lib,test}/**/*.{ex,exs}"]
    ]
    """
  end
end
