defmodule Parrot.Media.MediaSession do
  @moduledoc """
  Manages media sessions for SIP calls.

  MediaSession is responsible for:
    * SDP negotiation (offer/answer)
    * RTP port allocation
    * Media pipeline lifecycle management
    * Codec negotiation

  ## State Machine

  The MediaSession implements a state machine with the following states:
    * `:idle` - Initial state, waiting for SDP offer
    * `:negotiating` - Processing SDP offer/answer
    * `:ready` - Media parameters negotiated, ready to start
    * `:active` - Media flowing
    * `:terminating` - Cleanup in progress

  ## Example

      {:ok, session} = MediaSession.start_link(
        id: "session_123",
        role: :uas,
        audio_file: "/path/to/audio.wav"
      )

      {:ok, answer} = MediaSession.process_offer(session, sdp_offer)
  """

  @behaviour :gen_statem

  require Logger

  alias ExSDP

  # Child spec for supervisor
  def child_spec(opts) do
    %{
      id: Keyword.get(opts, :id, __MODULE__),
      start: {__MODULE__, :start_link, [opts]},
      type: :worker,
      restart: :temporary,
      shutdown: 5000
    }
  end

  # State data structure
  defmodule Data do
    @moduledoc false
    defstruct [
      # Session ID
      :id,
      # Dialog ID this media session belongs to
      :dialog_id,
      # :uac or :uas
      :role,
      # Local SDP
      :local_sdp,
      # Remote SDP
      :remote_sdp,
      # RTP parameters
      :local_rtp_port,
      :remote_rtp_port,
      :remote_rtp_address,
      # Membrane pipeline PID
      :pipeline_pid,
      # Audio file to play (if any)
      :audio_file,
      # Owner process
      :owner_pid,
      # Monitor reference for owner
      :owner_monitor,
      # Media handler module
      :media_handler,
      # Media handler state
      :handler_state,
      # Supported codecs (ordered by preference)
      :supported_codecs,
      # Selected codec for this session
      :selected_codec,
      # Pipeline module to use
      :pipeline_module,
      # Audio source configuration
      :audio_source,
      # Audio sink configuration
      :audio_sink,
      # Output file for recording
      :output_file,
      # PortAudio device IDs
      :input_device_id,
      :output_device_id
    ]

    @type t :: %__MODULE__{
            id: String.t(),
            dialog_id: String.t(),
            role: :uac | :uas,
            local_sdp: String.t() | nil,
            remote_sdp: String.t() | nil,
            local_rtp_port: non_neg_integer() | nil,
            remote_rtp_port: non_neg_integer() | nil,
            remote_rtp_address: String.t() | nil,
            pipeline_pid: pid() | nil,
            audio_file: String.t() | nil,
            owner_pid: pid() | nil,
            owner_monitor: reference() | nil,
            media_handler: module() | nil,
            handler_state: term(),
            supported_codecs: list(),
            selected_codec: atom() | nil,
            pipeline_module: module() | nil,
            audio_source: :file | :device | :silence | nil,
            audio_sink: :none | :device | :file | nil,
            output_file: String.t() | nil,
            input_device_id: non_neg_integer() | nil,
            output_device_id: non_neg_integer() | nil
          }
  end

  # Public API

  @doc """
  Starts a media session.

  ## Options

  - `:id` - Session ID (required)
  - `:dialog_id` - Dialog ID this session belongs to (required)
  - `:role` - `:uac` or `:uas` (required)
  - `:owner` - Owner process PID (optional, defaults to caller)
  - `:audio_file` - Path to audio file to play (optional, used when audio_source is :file)
  - `:audio_source` - Source of audio: `:file` | `:device` | `:silence` (optional, defaults to :file if audio_file provided)
  - `:audio_sink` - Destination for received audio: `:none` | `:device` | `:file` (optional, defaults to :none)
  - `:output_file` - Path to save received audio when audio_sink is :file (optional)
  - `:input_device_id` - PortAudio device ID for microphone when audio_source is :device (optional)
  - `:output_device_id` - PortAudio device ID for speaker when audio_sink is :device (optional)
  - `:media_handler` - Media handler module (optional)
  - `:handler_state` - Initial handler state (optional)
  - `:supported_codecs` - List of supported codecs in preference order (optional, defaults to [:pcma])
  """
  @spec start_link(keyword()) :: {:ok, pid()} | {:error, term()}
  def start_link(opts) do
    Logger.debug("MediaSession.start_link called with opts: #{inspect(opts)}")

    result =
      :gen_statem.start_link(
        {:via, Registry, {Parrot.Registry, {:media_session, opts[:id]}}},
        __MODULE__,
        opts,
        []
      )

    Logger.debug("MediaSession.start_link result: #{inspect(result)}")
    result
  end

  @doc """
  Generates an SDP offer (UAC case).
  """
  @spec generate_offer(String.t() | pid()) :: {:ok, String.t()} | {:error, term()}
  def generate_offer(session) do
    :gen_statem.call(get_pid(session), :generate_offer)
  end

  @doc """
  Processes an SDP offer and generates an answer.

  ## Examples

      iex> {:ok, answer} = MediaSession.process_offer("session_1", "v=0\\r\\n...")
      {:ok, "v=0\\r\\no=- 123456 123456 IN IP4 127.0.0.1\\r\\n..."}

  ## Parameters

    * `session_id` - The session identifier
    * `sdp_offer` - The SDP offer as a string

  ## Returns

    * `{:ok, sdp_answer}` - Successfully negotiated, returns SDP answer
    * `{:error, reason}` - Negotiation failed
  """
  @spec process_offer(String.t() | pid(), String.t()) :: {:ok, String.t()} | {:error, term()}
  def process_offer(session, sdp_offer) do
    Logger.debug("MediaSession.process_offer called for session: #{inspect(session)}")
    :gen_statem.call(get_pid(session), {:process_offer, sdp_offer})
  end

  @doc """
  Processes an SDP answer (UAC case).
  """
  @spec process_answer(String.t() | pid(), String.t()) :: :ok | {:error, term()}
  def process_answer(session, sdp_answer) do
    :gen_statem.call(get_pid(session), {:process_answer, sdp_answer})
  end

  @doc """
  Starts the media streams.
  """
  @spec start_media(String.t() | pid()) :: :ok | {:error, term()}
  def start_media(session) do
    :gen_statem.call(get_pid(session), :start_media)
  end

  @doc """
  Pauses the media streams.
  """
  @spec pause_media(String.t() | pid()) :: :ok | {:error, term()}
  def pause_media(session) do
    :gen_statem.call(get_pid(session), :pause_media)
  end

  @doc """
  Resumes the media streams.
  """
  @spec resume_media(String.t() | pid()) :: :ok | {:error, term()}
  def resume_media(session) do
    :gen_statem.call(get_pid(session), :resume_media)
  end

  @doc """
  Terminates the media session.
  """
  @spec terminate_session(String.t() | pid()) :: :ok
  def terminate_session(session) do
    :gen_statem.stop(get_pid(session))
  end

  # Callbacks

  @impl true
  def callback_mode, do: :state_functions

  @impl true
  def init(opts) do
    id = Keyword.fetch!(opts, :id)
    dialog_id = Keyword.fetch!(opts, :dialog_id)
    role = Keyword.fetch!(opts, :role)
    owner_pid = Keyword.get(opts, :owner, self())
    audio_file = Keyword.get(opts, :audio_file)
    media_handler = Keyword.get(opts, :media_handler)
    handler_args = Keyword.get(opts, :handler_args, %{})
    # G.711 A-law by default
    supported_codecs = Keyword.get(opts, :supported_codecs, [:pcma])

    # New audio configuration options
    audio_source = Keyword.get(opts, :audio_source, if(audio_file, do: :file, else: :silence))
    audio_sink = Keyword.get(opts, :audio_sink, :none)
    output_file = Keyword.get(opts, :output_file)
    input_device_id = Keyword.get(opts, :input_device_id)
    output_device_id = Keyword.get(opts, :output_device_id)

    # Get pre-allocated RTP port if provided
    local_rtp_port = Keyword.get(opts, :local_rtp_port)

    # Monitor the owner process
    owner_monitor = Process.monitor(owner_pid)

    data = %Data{
      id: id,
      dialog_id: dialog_id,
      role: role,
      audio_file: audio_file,
      owner_pid: owner_pid,
      owner_monitor: owner_monitor,
      media_handler: media_handler,
      handler_state: nil,
      supported_codecs: supported_codecs,
      selected_codec: nil,
      pipeline_module: nil,
      audio_source: audio_source,
      audio_sink: audio_sink,
      output_file: output_file,
      input_device_id: input_device_id,
      output_device_id: output_device_id,
      local_rtp_port: local_rtp_port
    }

    # Call media handler init if provided
    data =
      if media_handler do
        case media_handler.init(handler_args || %{}) do
          {:ok, new_handler_state} ->
            # Call handle_session_start callback
            case media_handler.handle_session_start(id, opts, new_handler_state) do
              {:ok, handler_state} ->
                %{data | handler_state: handler_state}

              {:error, reason, handler_state} ->
                Logger.error("MediaHandler failed to start session: #{inspect(reason)}")
                %{data | handler_state: handler_state}
            end

          {:stop, reason} ->
            Logger.error("MediaHandler init failed: #{inspect(reason)}")
            data
        end
      else
        data
      end

    Logger.info("MediaSession #{id} starting for dialog #{dialog_id} as #{role}")

    {:ok, :idle, data}
  end

  # State: idle

  def idle({:call, from}, :generate_offer, data) when data.role == :uac do
    # Generate SDP offer
    {:ok, sdp, updated_data} = generate_sdp_offer(data)
    Logger.debug("MediaSession #{data.id}: Generated SDP offer")
    {:next_state, :negotiating, updated_data, [{:reply, from, {:ok, sdp}}]}
  end

  def idle({:call, from}, {:process_offer, sdp_offer}, data) when data.role == :uas do
    Logger.info("MediaSession #{data.id}: Processing SDP offer in idle state")

    # Call handler's handle_offer callback if available
    if data.media_handler do
      case data.media_handler.handle_offer(sdp_offer, :inbound, data.handler_state) do
        {:ok, modified_sdp, new_state} ->
          data = %{data | handler_state: new_state}
          process_offer_internal(from, modified_sdp, data)

        {:reject, reason, new_state} ->
          Logger.warning("MediaSession #{data.id}: Handler rejected offer: #{inspect(reason)}")

          {:keep_state, %{data | handler_state: new_state},
           [{:reply, from, {:error, {:handler_rejected, reason}}}]}

        {:noreply, new_state} ->
          data = %{data | handler_state: new_state}
          process_offer_internal(from, sdp_offer, data)
      end
    else
      process_offer_internal(from, sdp_offer, data)
    end
  end

  defp process_offer_internal(from, sdp_offer, data) do
    # Process SDP offer and generate answer
    case process_sdp_offer(sdp_offer, data) do
      {:ok, sdp_answer, updated_data} ->
        Logger.info("MediaSession #{data.id}: Successfully processed offer and generated answer")

        Logger.debug(
          "MediaSession #{data.id}: Local RTP port: #{updated_data.local_rtp_port}, Remote: #{updated_data.remote_rtp_address}:#{updated_data.remote_rtp_port}"
        )

        {:next_state, :ready, updated_data, [{:reply, from, {:ok, sdp_answer}}]}

      {:error, reason} = error ->
        Logger.error("MediaSession #{data.id}: Failed to process offer: #{inspect(reason)}")
        {:next_state, :idle, data, [{:reply, from, error}]}
    end
  end

  # State: negotiating

  def negotiating({:call, from}, {:process_answer, sdp_answer}, data) when data.role == :uac do
    # Process SDP answer
    case process_sdp_answer(sdp_answer, data) do
      {:ok, updated_data} ->
        Logger.debug("MediaSession #{data.id}: Processed SDP answer")
        {:next_state, :ready, updated_data, [{:reply, from, :ok}]}

      {:error, reason} = error ->
        Logger.error("MediaSession #{data.id}: Failed to process answer: #{inspect(reason)}")
        {:next_state, :negotiating, data, [{:reply, from, error}]}
    end
  end

  def negotiating(event_type, event_content, data) do
    handle_common_event(event_type, event_content, :negotiating, data)
  end

  # State: ready

  def ready({:call, from}, :start_media, data) do
    Logger.info("MediaSession #{data.id}: Starting media pipeline in ready state")

    # Notify handler that stream is starting
    {action, updated_data} =
      if data.media_handler do
        case data.media_handler.handle_stream_start(data.id, :outbound, data.handler_state) do
          {:noreply, new_state} ->
            {:noreply, %{data | handler_state: new_state}}

          {actions, new_state} when is_list(actions) ->
            {List.first(actions), %{data | handler_state: new_state}}

          {action, new_state} ->
            {action, %{data | handler_state: new_state}}
        end
      else
        {:noreply, data}
      end

    # Process any media action from handler
    updated_data = process_media_action(action, updated_data)

    # Start media pipeline
    case start_media_pipeline(updated_data) do
      {:ok, pipeline_pid} ->
        Logger.info(
          "MediaSession #{data.id}: Media pipeline started successfully with PID: #{inspect(pipeline_pid)}"
        )

        final_data = %{updated_data | pipeline_pid: pipeline_pid}
        {:next_state, :active, final_data, [{:reply, from, :ok}]}

      {:error, reason} = error ->
        Logger.error(
          "MediaSession #{data.id}: Failed to start media pipeline: #{inspect(reason)}"
        )

        {:next_state, :ready, updated_data, [{:reply, from, error}]}
    end
  end

  def ready(event_type, event_content, data) do
    handle_common_event(event_type, event_content, :ready, data)
  end

  # State: active

  def active({:call, from}, :pause_media, data) do
    # Pause media pipeline
    case pause_media_pipeline(data) do
      :ok ->
        Logger.info("MediaSession #{data.id}: Paused media")
        {:next_state, :paused, data, [{:reply, from, :ok}]}

      {:error, reason} = error ->
        Logger.error("MediaSession #{data.id}: Failed to pause media: #{inspect(reason)}")
        {:next_state, :active, data, [{:reply, from, error}]}
    end
  end

  def active(event_type, event_content, data) do
    handle_common_event(event_type, event_content, :active, data)
  end

  # State: paused

  def paused({:call, from}, :resume_media, data) do
    # Resume media pipeline
    case resume_media_pipeline(data) do
      :ok ->
        Logger.info("MediaSession #{data.id}: Resumed media")
        {:next_state, :active, data, [{:reply, from, :ok}]}

      {:error, reason} = error ->
        Logger.error("MediaSession #{data.id}: Failed to resume media: #{inspect(reason)}")
        {:next_state, :paused, data, [{:reply, from, error}]}
    end
  end

  def paused(event_type, event_content, data) do
    handle_common_event(event_type, event_content, :paused, data)
  end

  # State: terminated

  def terminated(event_type, event_content, data) do
    handle_common_event(event_type, event_content, :terminated, data)
  end

  # Common event handling

  defp handle_common_event(:info, {:DOWN, ref, :process, pid, reason}, _state, data) do
    cond do
      ref == data.owner_monitor ->
        Logger.info("MediaSession #{data.id}: Owner process terminated: #{inspect(reason)}")
        cleanup_session(data)
        {:stop, :normal}

      pid == data.pipeline_pid ->
        Logger.warning(
          "MediaSession #{data.id}: Membrane pipeline terminated: #{inspect(reason)}"
        )

        updated_data = %{data | pipeline_pid: nil}
        {:next_state, :ready, updated_data}

      true ->
        Logger.debug("MediaSession #{data.id}: Unknown process down: #{inspect(pid)}")
        {:keep_state_and_data, []}
    end
  end

  defp handle_common_event({:call, from}, :get_state, state, data) do
    state_info = %{
      state: state,
      id: data.id,
      dialog_id: data.dialog_id,
      role: data.role,
      has_local_sdp: data.local_sdp != nil,
      has_remote_sdp: data.remote_sdp != nil,
      pipeline_active: data.pipeline_pid != nil
    }

    {:keep_state_and_data, [{:reply, from, state_info}]}
  end

  defp handle_common_event(event_type, event_content, state, data) do
    Logger.warning(
      "MediaSession #{data.id}: Unhandled event in state #{inspect(state)}: #{inspect(event_type)} #{inspect(event_content)}"
    )

    {:keep_state_and_data, []}
  end

  # Private helpers

  # Codec mapping between symbols and RTP payload types
  # Codec mapping - using standard SDP names
  defp codec_info(:pcma), do: {8, "PCMA/8000", Parrot.Media.MembraneAlawPipeline}
  # Use dynamic PT 111
  defp codec_info(:opus), do: {111, "opus/48000/2", Parrot.Media.RtpPipeline}

  defp get_codec_payload_type(codec) do
    {pt, _, _} = codec_info(codec)
    pt
  end

  defp get_codec_rtpmap(codec) do
    {pt, rtpmap, _} = codec_info(codec)
    {pt, rtpmap}
  end

  defp get_pipeline_module(codec) do
    {_, _, module} = codec_info(codec)
    module
  end

  defp get_pipeline_module_for_config(codec, data) do
    # Use PortAudioPipeline if using device audio
    if data.audio_source == :device || data.audio_sink == :device do
      Parrot.Media.PortAudioPipeline
    else
      # Use codec-specific pipeline for file/network only
      get_pipeline_module(codec)
    end
  end

  defp get_pid(session) when is_binary(session) do
    case Registry.lookup(Parrot.Registry, {:media_session, session}) do
      [{pid, _}] -> pid
      [] -> raise "MediaSession #{session} not found"
    end
  end

  defp get_pid(pid) when is_pid(pid), do: pid

  defp generate_sdp_offer(data) do
    # Allocate local RTP port
    local_rtp_port = allocate_rtp_port()

    # Build media formats based on supported codecs
    formats = Enum.map(data.supported_codecs, &get_codec_payload_type/1)

    # Build RTP mappings
    attributes =
      Enum.flat_map(data.supported_codecs, fn codec ->
        {pt, rtpmap} = get_codec_rtpmap(codec)

        [
          %ExSDP.Attribute.RTPMapping{
            payload_type: pt,
            encoding: String.split(rtpmap, "/") |> List.first(),
            clock_rate: rtpmap |> String.split("/") |> Enum.at(1) |> String.to_integer()
          }
        ]
      end) ++ [:sendrecv]

    # Create SDP using ex_sdp
    sdp = %ExSDP{
      version: 0,
      origin: %ExSDP.Origin{
        username: "-",
        session_id: :os.system_time(:second),
        session_version: :os.system_time(:second),
        network_type: "IN",
        address: {127, 0, 0, 1}
      },
      session_name: "Parrot Media Session",
      connection_data: %ExSDP.ConnectionData{
        network_type: "IN",
        address: {127, 0, 0, 1}
      },
      timing: %ExSDP.Timing{
        start_time: 0,
        stop_time: 0
      },
      media: [
        %ExSDP.Media{
          type: :audio,
          port: local_rtp_port,
          protocol: "RTP/AVP",
          fmt: formats,
          attributes: attributes
        }
      ]
    }

    sdp_string = to_string(sdp)
    updated_data = %{data | local_sdp: sdp_string, local_rtp_port: local_rtp_port}
    {:ok, sdp_string, updated_data}
  end

  defp process_sdp_offer(sdp_offer, data) do
    Logger.debug("MediaSession #{data.id}: Parsing SDP offer")
    # Parse remote SDP using ex_sdp
    case ExSDP.parse(sdp_offer) do
      {:ok, parsed_sdp} ->
        # Extract audio media
        audio_media = Enum.find(parsed_sdp.media, &(&1.type == :audio))

        if audio_media do
          # Extract remote RTP info
          remote_rtp_port = audio_media.port

          remote_rtp_address =
            case parsed_sdp.connection_data do
              %{address: addr} when is_tuple(addr) ->
                addr |> Tuple.to_list() |> Enum.join(".")

              %{address: addr} when is_binary(addr) ->
                addr

              %{address: addr} ->
                to_string(addr)

              _ ->
                Logger.warning(
                  "MediaSession #{data.id}: No connection data in SDP, defaulting to 127.0.0.1"
                )

                "127.0.0.1"
            end

          Logger.info(
            "MediaSession #{data.id}: Remote RTP endpoint: #{remote_rtp_address}:#{remote_rtp_port}"
          )

          # Find common codec between offer and our supported codecs
          offered_codecs = extract_offered_codecs(audio_media)

          # Call handler for codec negotiation if available
          {selected_codec, handler_state} =
            if data.media_handler do
              case data.media_handler.handle_codec_negotiation(
                     offered_codecs,
                     data.supported_codecs,
                     data.handler_state
                   ) do
                {:ok, codec, new_state} when is_atom(codec) ->
                  {codec, new_state}

                {:ok, codec_list, new_state} when is_list(codec_list) ->
                  # Take the first codec from the preference list that's in offered_codecs
                  codec = Enum.find(codec_list, fn c -> c in offered_codecs end) || hd(codec_list)
                  {codec, new_state}

                {:error, :no_common_codec, new_state} ->
                  Logger.warning("MediaSession #{data.id}: Handler found no common codec")
                  {nil, new_state}
              end
            else
              {select_best_codec(offered_codecs, data.supported_codecs), data.handler_state}
            end

          # Update handler state
          data = %{data | handler_state: handler_state}

          if selected_codec do
            Logger.info("MediaSession #{data.id}: Selected codec: #{inspect(selected_codec)}")

            # Use existing local RTP port if already allocated, otherwise allocate new one
            local_rtp_port =
              if data.local_rtp_port do
                Logger.info(
                  "MediaSession #{data.id}: Using pre-allocated local RTP port: #{data.local_rtp_port}"
                )

                data.local_rtp_port
              else
                port = allocate_rtp_port()
                Logger.info("MediaSession #{data.id}: Allocated new local RTP port: #{port}")
                port
              end

            # Generate answer SDP with selected codec
            sdp_answer = generate_answer_sdp(local_rtp_port, selected_codec)

            # Determine pipeline module based on selected codec and audio config
            pipeline_module = get_pipeline_module_for_config(selected_codec, data)

            updated_data = %{
              data
              | local_sdp: sdp_answer,
                remote_sdp: sdp_offer,
                local_rtp_port: local_rtp_port,
                remote_rtp_port: remote_rtp_port,
                remote_rtp_address: remote_rtp_address,
                selected_codec: selected_codec,
                pipeline_module: pipeline_module
            }

            # Call handle_negotiation_complete if handler exists
            final_data =
              if updated_data.media_handler do
                case updated_data.media_handler.handle_negotiation_complete(
                       sdp_answer,
                       sdp_offer,
                       selected_codec,
                       updated_data.handler_state
                     ) do
                  {:ok, new_state} ->
                    %{updated_data | handler_state: new_state}

                  {:error, reason, new_state} ->
                    Logger.error(
                      "MediaSession #{data.id}: Handler negotiation complete error: #{inspect(reason)}"
                    )

                    %{updated_data | handler_state: new_state}
                end
              else
                updated_data
              end

            Logger.info("MediaSession #{data.id}: SDP negotiation complete")
            {:ok, sdp_answer, final_data}
          else
            {:error, :no_common_codec}
          end
        else
          {:error, :no_audio_media}
        end

      {:error, reason} ->
        Logger.error("MediaSession #{data.id}: Failed to parse SDP: #{inspect(reason)}")
        {:error, {:sdp_parse_error, reason}}
    end
  end

  defp extract_offered_codecs(audio_media) do
    # Map payload types to codec names
    static_codec_map = %{
      8 => :pcma
    }

    # Extract dynamic codecs from rtpmap attributes
    dynamic_codecs =
      audio_media.attributes
      |> Enum.filter(&match?(%ExSDP.Attribute.RTPMapping{}, &1))
      |> Enum.map(fn rtpmap ->
        case String.downcase(rtpmap.encoding) do
          "opus" -> {rtpmap.payload_type, :opus}
          "pcma" -> {rtpmap.payload_type, :pcma}
          _ -> nil
        end
      end)
      |> Enum.reject(&is_nil/1)
      |> Map.new()

    # Merge static and dynamic codecs
    codec_map = Map.merge(static_codec_map, dynamic_codecs)

    # Extract codecs from fmt list
    audio_media.fmt
    |> Enum.map(fn pt -> codec_map[pt] end)
    |> Enum.reject(&is_nil/1)
  end

  defp select_best_codec(offered_codecs, supported_codecs) do
    # Find first codec that appears in both lists (preference order from supported_codecs)
    Enum.find(supported_codecs, :pcma, fn codec ->
      codec in offered_codecs
    end)
  end

  defp generate_answer_sdp(local_rtp_port, selected_codec) do
    {pt, rtpmap} = get_codec_rtpmap(selected_codec)

    sdp = %ExSDP{
      version: 0,
      origin: %ExSDP.Origin{
        username: "-",
        session_id: :os.system_time(:second),
        session_version: :os.system_time(:second),
        network_type: "IN",
        address: {127, 0, 0, 1}
      },
      session_name: "Parrot Media Session",
      connection_data: %ExSDP.ConnectionData{
        network_type: "IN",
        address: {127, 0, 0, 1}
      },
      timing: %ExSDP.Timing{
        start_time: 0,
        stop_time: 0
      },
      media: [
        %ExSDP.Media{
          type: :audio,
          port: local_rtp_port,
          protocol: "RTP/AVP",
          fmt: [pt],
          attributes: [
            %ExSDP.Attribute.RTPMapping{
              payload_type: pt,
              encoding: String.split(rtpmap, "/") |> List.first(),
              clock_rate: rtpmap |> String.split("/") |> Enum.at(1) |> String.to_integer()
            },
            :sendrecv
          ]
        }
      ]
    }

    to_string(sdp)
  end

  defp process_sdp_answer(sdp_answer, data) do
    # Parse remote SDP using ex_sdp
    case ExSDP.parse(sdp_answer) do
      {:ok, parsed_sdp} ->
        # Extract audio media
        audio_media = Enum.find(parsed_sdp.media, &(&1.type == :audio))

        if audio_media do
          # Extract remote RTP info
          remote_rtp_port = audio_media.port

          remote_rtp_address =
            case parsed_sdp.connection_data do
              %{address: addr} when is_tuple(addr) ->
                addr |> Tuple.to_list() |> Enum.join(".")

              %{address: addr} when is_binary(addr) ->
                addr

              %{address: addr} ->
                to_string(addr)

              _ ->
                Logger.warning(
                  "MediaSession #{data.id}: No connection data in SDP, defaulting to 127.0.0.1"
                )

                "127.0.0.1"
            end

          # Extract selected codec from answer
          answered_codecs = extract_offered_codecs(audio_media)
          selected_codec = List.first(answered_codecs, :pcma)

          # Determine pipeline module based on selected codec and audio config
          pipeline_module = get_pipeline_module_for_config(selected_codec, data)

          updated_data = %{
            data
            | remote_sdp: sdp_answer,
              remote_rtp_port: remote_rtp_port,
              remote_rtp_address: remote_rtp_address,
              selected_codec: selected_codec,
              pipeline_module: pipeline_module
          }

          {:ok, updated_data}
        else
          {:error, :no_audio_media}
        end

      {:error, reason} ->
        {:error, {:sdp_parse_error, reason}}
    end
  end

  defp allocate_rtp_port(config \\ %{}) do
    min_port = Map.get(config, :min_rtp_port, 16384)
    max_port = Map.get(config, :max_rtp_port, 32768)
    max_attempts = Map.get(config, :max_port_attempts, 100)

    case find_available_port(min_port, max_port, max_attempts) do
      {:ok, port} ->
        port

      {:error, :no_ports_available} ->
        # Fallback to random port as last resort
        Logger.error(
          "Failed to find available RTP port in range #{min_port}-#{max_port}, using random port"
        )

        min_port + :rand.uniform(max_port - min_port)
    end
  end

  defp find_available_port(min_port, max_port, max_attempts) do
    Stream.iterate(0, &(&1 + 1))
    |> Stream.take(max_attempts)
    |> Stream.map(fn _ ->
      port = min_port + :rand.uniform(max_port - min_port)

      case :gen_udp.open(port, [:binary, {:active, false}]) do
        {:ok, socket} ->
          :gen_udp.close(socket)
          {:ok, port}

        {:error, :eaddrinuse} ->
          {:error, :in_use}

        error ->
          error
      end
    end)
    |> Enum.find({:error, :no_ports_available}, fn
      {:ok, _port} -> true
      _ -> false
    end)
  end

  defp start_media_pipeline(data) do
    Logger.info("MediaSession #{data.id}: Creating Membrane pipeline for RTP audio streaming")

    Logger.info(
      "MediaSession #{data.id}: Remote endpoint from data: #{data.remote_rtp_address}:#{data.remote_rtp_port}"
    )

    # Create Membrane pipeline for RTP audio streaming
    init_arg = %{
      session_id: data.id,
      local_rtp_port: data.local_rtp_port,
      remote_rtp_address: data.remote_rtp_address,
      remote_rtp_port: data.remote_rtp_port,
      audio_file: data.audio_file || :default_audio,
      media_handler: data.media_handler,
      handler_state: data.handler_state,
      # Pass new audio configuration
      audio_source: data.audio_source,
      audio_sink: data.audio_sink,
      output_file: data.output_file,
      input_device_id: data.input_device_id,
      output_device_id: data.output_device_id,
      # Pass the selected codec
      selected_codec: data.selected_codec
    }

    Logger.info("MediaSession #{data.id}: Pipeline init args: #{inspect(init_arg)}")

    # Use the dynamically selected pipeline module based on negotiated codec
    pipeline_module = data.pipeline_module || Parrot.Media.RtpPipeline

    Logger.info(
      "MediaSession #{data.id}: Using pipeline module: #{inspect(pipeline_module)} for codec: #{inspect(data.selected_codec)}"
    )

    # Start the pipeline based on the module type
    start_result =
      if pipeline_module == Parrot.Media.RtpPipeline do
        # RtpPipeline is a GenServer
        GenServer.start_link(pipeline_module, init_arg)
      else
        # MembraneAlawPipeline uses Membrane.Pipeline
        Membrane.Pipeline.start_link(pipeline_module, init_arg)
      end

    case start_result do
      {:ok, pipeline_pid} ->
        Logger.info(
          "MediaSession #{data.id}: Membrane pipeline created with PID: #{inspect(pipeline_pid)}"
        )

        Process.monitor(pipeline_pid)
        {:ok, pipeline_pid}

      {:ok, _supervisor_pid, pipeline_pid} ->
        # Membrane.Pipeline.start_link returns {ok, supervisor_pid, pipeline_pid}
        Logger.info(
          "MediaSession #{data.id}: Membrane pipeline created with PID: #{inspect(pipeline_pid)}"
        )

        Process.monitor(pipeline_pid)
        {:ok, pipeline_pid}

      {:error, reason} = error ->
        Logger.error(
          "MediaSession #{data.id}: Failed to start Membrane pipeline: #{inspect(reason)}"
        )

        error
    end
  end

  defp process_media_action({:play, file_path}, data) do
    process_media_action({:play, file_path, []}, data)
  end

  defp process_media_action({:play, file_path, _opts}, data) do
    Logger.info("MediaSession #{data.id}: Playing file: #{file_path}")
    # Update the audio file and restart pipeline if needed
    %{data | audio_file: file_path}
  end

  defp process_media_action(:stop, data) do
    Logger.info("MediaSession #{data.id}: Stopping media")
    stop_media_pipeline(data)
    data
  end

  defp process_media_action(:pause, data) do
    Logger.info("MediaSession #{data.id}: Pausing media")
    pause_media_pipeline(data)
    data
  end

  defp process_media_action(:resume, data) do
    Logger.info("MediaSession #{data.id}: Resuming media")
    resume_media_pipeline(data)
    data
  end

  defp process_media_action({:record, _file_path}, data) do
    Logger.warning("MediaSession #{data.id}: Recording not yet implemented")
    data
  end

  defp process_media_action({:bridge, _target_session}, data) do
    Logger.warning("MediaSession #{data.id}: Bridging not yet implemented")
    data
  end

  defp process_media_action({:inject_audio, _audio_data}, data) do
    Logger.warning("MediaSession #{data.id}: Audio injection not yet implemented")
    data
  end

  defp process_media_action(:noreply, data), do: data

  defp process_media_action(actions, data) when is_list(actions) do
    Enum.reduce(actions, data, &process_media_action/2)
  end

  defp process_media_action(action, data) do
    Logger.warning("MediaSession #{data.id}: Unknown media action: #{inspect(action)}")
    data
  end

  defp stop_media_pipeline(data) do
    if data.pipeline_pid && Process.alive?(data.pipeline_pid) do
      Logger.info("MediaSession #{data.id}: Stopping pipeline")
      ensure_pipeline_termination(data.pipeline_pid, data.pipeline_module)
    end

    %{data | pipeline_pid: nil}
  end

  defp pause_media_pipeline(data) do
    # Membrane pipelines don't have direct pause/resume methods
    # Would need to implement this via pipeline messages
    if data.pipeline_pid && Process.alive?(data.pipeline_pid) do
      # TODO: Send pause message to pipeline
      :ok
    else
      {:error, :no_pipeline}
    end
  end

  defp resume_media_pipeline(data) do
    # Membrane pipelines don't have direct pause/resume methods
    # Would need to implement this via pipeline messages
    if data.pipeline_pid && Process.alive?(data.pipeline_pid) do
      # TODO: Send resume message to pipeline
      :ok
    else
      {:error, :no_pipeline}
    end
  end

  defp cleanup_session(data) do
    # Stop media pipeline if running
    if data.pipeline_pid && Process.alive?(data.pipeline_pid) do
      Logger.debug("MediaSession #{data.id}: Stopping Membrane pipeline")
      # Use ensure_pipeline_termination for proper cleanup
      ensure_pipeline_termination(data.pipeline_pid, data.pipeline_module)
    end

    Logger.info("MediaSession #{data.id}: Cleaned up resources")
  end

  defp ensure_pipeline_termination(pipeline_pid, pipeline_module) when is_pid(pipeline_pid) do
    ref = Process.monitor(pipeline_pid)

    termination_result =
      if pipeline_module == Parrot.Media.RtpPipeline do
        try do
          GenServer.stop(pipeline_pid, :normal, 5_000)
        catch
          :exit, _ -> :ok
        end
      else
        case Membrane.Pipeline.terminate(pipeline_pid) do
          :ok -> :ok
          error -> error
        end
      end

    case termination_result do
      :ok ->
        receive do
          {:DOWN, ^ref, :process, ^pipeline_pid, _reason} ->
            :ok
        after
          5_000 ->
            Logger.error(
              "Pipeline #{inspect(pipeline_pid)} failed to terminate gracefully, forcing shutdown"
            )

            Process.exit(pipeline_pid, :kill)

            receive do
              {:DOWN, ^ref, :process, ^pipeline_pid, _reason} -> :ok
            after
              1_000 -> :timeout
            end
        end

      error ->
        Process.demonitor(ref, [:flush])
        Logger.error("Failed to terminate pipeline #{inspect(pipeline_pid)}: #{inspect(error)}")
        error
    end
  end

  @impl true
  def terminate(reason, _state, data) do
    Logger.info("MediaSession #{data.id}: Terminating due to #{inspect(reason)}")
    cleanup_session(data)
    :ok
  end
end
