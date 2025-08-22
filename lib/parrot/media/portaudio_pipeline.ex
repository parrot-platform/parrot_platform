defmodule Parrot.Media.PortAudioPipeline do
  @moduledoc """
  Membrane pipeline for bidirectional audio using system audio devices via PortAudio.

  This pipeline supports various combinations of audio sources and sinks:
  - Microphone to RTP (outbound audio)
  - RTP to Speaker (inbound audio)
  - File to Speaker (local playback)
  - RTP to File (recording)
  - Full duplex (microphone to RTP, RTP to speaker)

  ## Configuration Options

  - `:session_id` - Unique session identifier
  - `:audio_source` - `:device` | `:file` | `:silence`
  - `:audio_sink` - `:device` | `:file` | `:none`
  - `:audio_file` - Path to audio file when source is `:file`
  - `:output_file` - Path to output file when sink is `:file`
  - `:input_device_id` - PortAudio device ID for input (default: system default)
  - `:output_device_id` - PortAudio device ID for output (default: system default)
  - `:local_rtp_port` - Local RTP port
  - `:remote_rtp_address` - Remote RTP IP address
  - `:remote_rtp_port` - Remote RTP port
  """

  use Membrane.Pipeline
  require Logger

  alias Membrane.PortAudio
  alias Parrot.Media.G711Chunker

  @impl true
  def handle_init(_ctx, opts) do
    Logger.info("PortAudioPipeline: Starting for session #{opts.session_id}")
    Logger.info("  Audio source: #{opts.audio_source}, sink: #{opts.audio_sink}")

    # Validate options
    validate_opts!(opts)

    # Generate SSRC for RTP
    ssrc = :rand.uniform(0xFFFFFFFF)

    # Build appropriate pipeline structure based on source/sink combination
    structure = build_pipeline_structure(opts, ssrc)

    state = %{
      session_id: opts.session_id,
      audio_source: opts.audio_source,
      audio_sink: opts.audio_sink,
      playing: false,
      output_device_id: opts[:output_device_id]
    }

    {[spec: structure], state}
  end

  @impl true
  def handle_child_notification({:end_of_stream, _pad}, :file_source, _ctx, state) do
    Logger.info("PortAudioPipeline #{state.session_id}: Audio file playback completed")
    {[], state}
  end

  @impl true
  def handle_child_notification({:new_rtp_stream, ssrc, pt, _extensions}, :rtp, _ctx, state) do
    Logger.info(
      "PortAudioPipeline #{state.session_id}: New RTP stream detected - SSRC: #{ssrc}, PT: #{pt}"
    )

    # Only handle if we're expecting to receive audio
    if state.audio_sink == :device do
      Logger.debug("Creating receive pipeline for SSRC #{ssrc}, payload type #{pt}")
      # Create the decoder pipeline for this specific SSRC
      device_id = Map.get(state, :output_device_id)

      # Select appropriate depayloader and decoder based on payload type
      {depayloader, decoder_spec} =
        case pt do
          8 ->
            {Membrane.RTP.G711.Depayloader, Membrane.G711.Decoder}

          111 ->
            # Explicitly set sample rate for Opus decoder
            {Membrane.RTP.Opus.Depayloader, %Membrane.Opus.Decoder{sample_rate: 48_000}}

          _ ->
            Logger.warning("Unsupported payload type #{pt}, defaulting to G.711 A-law")
            {Membrane.RTP.G711.Depayloader, Membrane.G711.Decoder}
        end

      structure = [
        get_child(:rtp)
        |> via_out(Pad.ref(:output, ssrc),
          options: [depayloader: depayloader]
        )
        |> child({:decoder, ssrc}, decoder_spec)
        |> then(fn builder ->
          # Only add resampler for G.711 (8kHz -> 48kHz)
          # Opus already outputs at 48kHz
          if pt == 8 do
            builder
            |> child({:speaker_resampler, ssrc}, %Membrane.FFmpeg.SWResample.Converter{
              input_stream_format: %Membrane.RawAudio{
                sample_format: :s16le,
                sample_rate: 8000,
                channels: 1
              },
              output_stream_format: %Membrane.RawAudio{
                sample_format: :s16le,
                sample_rate: 48000,
                channels: 1
              }
            })
          else
            # Opus doesn't need resampling
            builder
          end
        end)
        |> child({:speaker_sink, ssrc}, %Membrane.PortAudio.Sink{
          device_id: device_id || :default,
          portaudio_buffer_size: 1024,
          latency: :high
        })
      ]

      {[spec: structure], state}
    else
      {[], state}
    end
  end

  @impl true
  def handle_child_notification(notification, child, _ctx, state) do
    Logger.debug(
      "PortAudioPipeline #{state.session_id}: Notification from #{child}: #{inspect(notification)}"
    )

    {[], state}
  end

  # Private functions

  defp validate_opts!(opts) do
    # Ensure required options are present
    required = [
      :session_id,
      :audio_source,
      :audio_sink,
      :local_rtp_port,
      :remote_rtp_address,
      :remote_rtp_port
    ]

    Enum.each(required, fn key ->
      if is_nil(opts[key]) do
        raise ArgumentError, "Required option #{key} is missing"
      end
    end)

    # Validate source/sink combinations
    case {opts.audio_source, opts.audio_sink} do
      {:file, _} when is_nil(opts.audio_file) ->
        raise ArgumentError, "audio_file is required when audio_source is :file"

      {_, :file} when is_nil(opts.output_file) ->
        raise ArgumentError, "output_file is required when audio_sink is :file"

      _ ->
        :ok
    end
  end

  defp build_pipeline_structure(opts, ssrc) do
    # Build common RTP elements
    udp_endpoint = build_udp_endpoint(opts)
    rtp_session = build_rtp_session()

    # Build source and sink pipelines
    source_spec = build_source_pipeline(opts.audio_source, opts, ssrc, udp_endpoint, rtp_session)
    sink_spec = build_sink_pipeline(opts.audio_sink, opts, udp_endpoint, rtp_session)

    # Combine specs
    [udp_endpoint, rtp_session] ++ source_spec ++ sink_spec
  end

  defp build_udp_endpoint(opts) do
    child(:udp_endpoint, %Membrane.UDP.Endpoint{
      local_port_no: opts.local_rtp_port,
      destination_port_no: opts.remote_rtp_port,
      destination_address: parse_ip!(opts.remote_rtp_address)
    })
  end

  defp build_rtp_session do
    child(:rtp, %Membrane.RTP.SessionBin{
      fmt_mapping: %{
        # G.711 A-law
        8 => {:PCMA, 8000},
        # OPUS codec (dynamic encoding)
        111 => {:opus, 48000}
      },
      # Send RTCP receiver reports
      rtcp_receiver_report_interval: Membrane.Time.seconds(5),
      # Send RTCP sender reports
      rtcp_sender_report_interval: Membrane.Time.seconds(5)
    })
  end

  # All build_source_pipeline/5 clauses grouped together
  defp build_source_pipeline(:device, opts, ssrc, _udp, _rtp) do
    device_id = opts[:input_device_id]
    selected_codec = opts[:selected_codec] || :pcma

    case selected_codec do
      :opus ->
        build_opus_source_pipeline(device_id, ssrc)

      _ ->
        build_pcma_source_pipeline(device_id, ssrc)
    end
  end

  defp build_source_pipeline(:file, opts, ssrc, _udp, _rtp) do
    selected_codec = opts[:selected_codec] || :pcma

    case selected_codec do
      :opus ->
        build_opus_file_pipeline(opts, ssrc)

      _ ->
        build_pcma_file_pipeline(opts, ssrc)
    end
  end

  defp build_source_pipeline(:silence, opts, ssrc, _udp, rtp) do
    selected_codec = opts[:selected_codec] || :pcma

    case selected_codec do
      :opus ->
        build_opus_silence_pipeline(ssrc, rtp)

      _ ->
        build_pcma_silence_pipeline(ssrc, rtp)
    end
  end

  defp build_source_pipeline(source, _opts, _ssrc, _udp, _rtp) when source in [:none, nil] do
    []
  end

  # Helper functions for build_source_pipeline
  defp build_pcma_source_pipeline(device_id, ssrc) do
    [
      # Microphone input
      child(:mic_source, %PortAudio.Source{
        device_id: device_id || :default,
        # Match sink buffer size
        portaudio_buffer_size: 512,
        # High latency for stability
        latency: :high
      }),

      # Resample from 48kHz to 8kHz for G.711 using high-quality FFmpeg resampler
      child(:resampler, %Membrane.FFmpeg.SWResample.Converter{
        output_stream_format: %Membrane.RawAudio{
          sample_format: :s16le,
          sample_rate: 8000,
          channels: 1
        }
      }),

      # Convert to G.711 A-law
      child(:g711_encoder, Parrot.Media.TimestampPreservingG711Encoder),

      # Chunk for RTP
      child(:g711_chunker, %G711Chunker{chunk_duration: 20}),

      # Add timing
      child(:realtimer, Membrane.Realtimer),

      # Links
      get_child(:mic_source)
      |> get_child(:resampler)
      |> get_child(:g711_encoder)
      |> get_child(:g711_chunker)
      |> get_child(:realtimer)
      |> via_in(Pad.ref(:input, ssrc),
        options: [payloader: Membrane.RTP.G711.Payloader]
      )
      |> get_child(:rtp)
      |> via_out(Pad.ref(:rtp_output, ssrc), options: [encoding: :PCMA])
      |> via_in(:input)
      |> get_child(:udp_endpoint)
    ]
  end

  defp build_opus_source_pipeline(device_id, ssrc) do
    [
      # Microphone input (PortAudio captures at 48kHz by default)
      child(:mic_source, %PortAudio.Source{
        device_id: device_id || :default,
        portaudio_buffer_size: 512,
        latency: :high
      }),

      # OPUS encoder (expects 48kHz input)
      child(:opus_encoder, %Membrane.Opus.Encoder{
        application: :voip,
        # 24 kbps for good voice quality
        bitrate: 24_000
      }),

      # Add timing
      child(:realtimer, Membrane.Realtimer),

      # Links
      get_child(:mic_source)
      |> get_child(:opus_encoder)
      |> get_child(:realtimer)
      |> via_in(Pad.ref(:input, ssrc),
        options: [payloader: Membrane.RTP.Opus.Payloader]
      )
      |> get_child(:rtp)
      |> via_out(Pad.ref(:rtp_output, ssrc), options: [payload_type: 111])
      |> via_in(:input)
      |> get_child(:udp_endpoint)
    ]
  end

  defp build_pcma_file_pipeline(opts, ssrc) do
    [
      # File source
      child(:file_source, %Membrane.File.Source{
        location: opts.audio_file
      }),

      # Parse WAV
      child(:wav_parser, Membrane.WAV.Parser),
      
      # Add timestamps to buffers from WAV parser
      child(:timestamp_generator, Parrot.Media.TimestampGenerator),

      # Convert to G.711
      child(:g711_encoder, Parrot.Media.TimestampPreservingG711Encoder),

      # Chunk for RTP
      child(:g711_chunker, %G711Chunker{chunk_duration: 20}),

      # Add timing
      child(:realtimer, Membrane.Realtimer),

      # Links
      get_child(:file_source)
      |> get_child(:wav_parser)
      |> get_child(:timestamp_generator)
      |> get_child(:g711_encoder)
      |> get_child(:g711_chunker)
      |> get_child(:realtimer)
      |> via_in(Pad.ref(:input, ssrc),
        options: [payloader: Membrane.RTP.G711.Payloader]
      )
      |> get_child(:rtp)
      |> via_out(Pad.ref(:rtp_output, ssrc), options: [encoding: :PCMA])
      |> via_in(:input)
      |> get_child(:udp_endpoint)
    ]
  end

  defp build_opus_file_pipeline(opts, ssrc) do
    [
      # File source
      child(:file_source, %Membrane.File.Source{
        location: opts.audio_file
      }),

      # Parse WAV
      child(:wav_parser, Membrane.WAV.Parser),
      
      # Add timestamps to buffers from WAV parser
      child(:timestamp_generator, Parrot.Media.TimestampGenerator),

      # Resample to 48kHz for OPUS
      child(:resampler, %Membrane.FFmpeg.SWResample.Converter{
        output_stream_format: %Membrane.RawAudio{
          sample_format: :s16le,
          sample_rate: 48000,
          channels: 2
        }
      }),

      # OPUS encoder
      child(:opus_encoder, %Membrane.Opus.Encoder{
        application: :voip,
        bitrate: 24_000
      }),

      # Add timing
      child(:realtimer, Membrane.Realtimer),

      # Links
      get_child(:file_source)
      |> get_child(:wav_parser)
      |> get_child(:timestamp_generator)
      |> get_child(:resampler)
      |> get_child(:opus_encoder)
      |> get_child(:realtimer)
      |> via_in(Pad.ref(:input, ssrc),
        options: [payloader: Membrane.RTP.Opus.Payloader]
      )
      |> get_child(:rtp)
      |> via_out(Pad.ref(:rtp_output, ssrc), options: [payload_type: 111])
      |> via_in(:input)
      |> get_child(:udp_endpoint)
    ]
  end

  defp build_pcma_silence_pipeline(ssrc, _rtp) do
    [
      # Silence generator
      child(:silence_source, %Parrot.Media.SilenceSource{
        interval: 20,
        sample_rate: 8000,
        channels: 1
      }),

      # G.711 A-law encoder
      child(:g711_encoder, Parrot.Media.TimestampPreservingG711Encoder),

      # Connect the pipeline
      get_child(:silence_source)
      |> get_child(:g711_encoder)
      |> via_in(Pad.ref(:input, ssrc),
        options: [payloader: Membrane.RTP.G711.Payloader]
      )
      |> get_child(:rtp)
      |> via_out(Pad.ref(:rtp_output, ssrc), options: [encoding: :PCMA])
      |> via_in(:input)
      |> get_child(:udp_endpoint)
    ]
  end

  defp build_opus_silence_pipeline(ssrc, _rtp) do
    [
      # Silence generator for OPUS (48kHz)
      child(:silence_source, %Parrot.Media.SilenceSource{
        interval: 20,
        sample_rate: 48000,
        # OPUS expects stereo
        channels: 2
      }),

      # OPUS encoder
      child(:opus_encoder, %Membrane.Opus.Encoder{
        application: :voip,
        bitrate: 24_000
      }),

      # Connect the pipeline
      get_child(:silence_source)
      |> get_child(:opus_encoder)
      |> via_in(Pad.ref(:input, ssrc),
        options: [payloader: Membrane.RTP.Opus.Payloader]
      )
      |> get_child(:rtp)
      |> via_out(Pad.ref(:rtp_output, ssrc), options: [payload_type: 111])
      |> via_in(:input)
      |> get_child(:udp_endpoint)
    ]
  end

  defp build_sink_pipeline(:device, _opts, _udp, _rtp) do
    # For device sink, we only set up the UDP -> RTP SessionBin connection
    # The actual decoder/resampler/sink chain will be created dynamically
    # when we receive the :new_rtp_stream notification with the actual SSRC
    [
      # Route UDP packets to RTP SessionBin
      get_child(:udp_endpoint)
      |> via_out(:output)
      |> via_in(Pad.ref(:rtp_input, make_ref()))
      |> get_child(:rtp)
    ]
  end

  defp build_sink_pipeline(:file, opts, _udp, _rtp) do
    [
      # Basic RTP depayloader that extracts audio from RTP packets
      child(:rtp_receiver, %Parrot.Media.BasicRTPDepayloader{
        clock_rate: 8000,
        selected_codec: opts[:selected_codec]
      }),

      # G.711 A-law decoder
      child(:g711_decoder, Membrane.G711.Decoder),

      # WAV writer
      child(:wav_writer, Membrane.WAV.Writer),

      # File sink
      child(:file_sink, %Membrane.File.Sink{
        location: opts.output_file
      }),

      # Direct link from UDP endpoint
      get_child(:udp_endpoint)
      |> via_out(:output)
      |> get_child(:rtp_receiver)
      |> get_child(:g711_decoder)
      |> get_child(:wav_writer)
      |> get_child(:file_sink)
    ]
  end

  defp build_sink_pipeline(sink, _opts, _udp, _rtp) when sink in [:none, nil] do
    # Even when we don't want to process received audio, we need to connect
    # the UDP endpoint's output pad to something. Use a Fake sink that drops all data.
    [
      child(:fake_sink, %Membrane.Debug.Sink{}),
      
      # Connect UDP output to fake sink to satisfy pad requirements
      get_child(:udp_endpoint)
      |> via_out(:output)
      |> get_child(:fake_sink)
    ]
  end

  defp parse_ip!(ip_string) when is_binary(ip_string) do
    case :inet.parse_address(String.to_charlist(ip_string)) do
      {:ok, ip_tuple} ->
        ip_tuple

      {:error, reason} ->
        raise ArgumentError, "Invalid IP address #{ip_string}: #{inspect(reason)}"
    end
  end
end
