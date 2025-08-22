defmodule Parrot.Media.OpusPipeline do
  @moduledoc """
  Membrane pipeline for Opus RTP streaming.
  Uses the proper RTP.SessionBin approach like AlawPipeline.
  """

  use Membrane.Pipeline
  require Logger
  
  import Parrot.Media.PipelineHelpers

  @impl true
  def handle_init(_ctx, opts) do
    Logger.info("OpusPipeline: Starting for session #{opts.session_id}")
    Logger.info("  Audio file: #{inspect(opts.audio_file)}")

    # Check if file exists and get its size (only for actual file paths)
    if is_binary(opts.audio_file) do
      case File.stat(opts.audio_file) do
        {:ok, %{size: size}} ->
          Logger.info("  Audio file size: #{size} bytes")

        {:error, reason} ->
          Logger.error("  Cannot stat audio file: #{inspect(reason)}")
      end
    end

    Logger.info("  RTP destination: #{opts.remote_rtp_address}:#{opts.remote_rtp_port}")
    Logger.info("  Local RTP port: #{opts.local_rtp_port}")

    # Generate SSRC once for consistency
    ssrc = :rand.uniform(0xFFFFFFFF)
    has_audio? = has_audio_file?(opts)

    # Create bidirectional UDP endpoint
    udp_endpoint_spec = build_udp_endpoint_spec(opts, has_audio?)

    # Create RTP SessionBin for bidirectional RTP handling
    rtp_session_spec =
      child(:rtp, %Membrane.RTP.SessionBin{
        # payload type 111 = Opus (dynamic encoding)  
        fmt_mapping: %{111 => {:opus, 48000}}
      })

    # Receiving pipeline: UDP -> RTP -> Decoder
    receive_spec = [
      get_child(:udp_endpoint)
      |> via_in(Pad.ref(:rtp_input, make_ref()))
      |> get_child(:rtp)
    ]

    # Create sending pipeline components
    send_children_spec =
      if has_audio? do
        [
          # Source - read WAV file
          child(:file_source, %Membrane.File.Source{
            location: opts.audio_file
          }),
          # Parse WAV file
          child(:wav_parser, Membrane.WAV.Parser),
          # Resample to 48kHz for Opus BEFORE adding timestamps
          child(:resampler, %Membrane.FFmpeg.SWResample.Converter{
            output_stream_format: %Membrane.RawAudio{
              sample_format: :s16le,
              sample_rate: 48000,
              channels: 2
            }
          }),
          # Add timestamps AFTER resampling so they match the 48kHz rate
          child(:timestamp_generator, Parrot.Media.TimestampGenerator),
          # Encode to Opus
          child(:opus_encoder, %Membrane.Opus.Encoder{
            application: :voip,
            bitrate: 32_000
          }),
          # Add realtimer to pace the audio
          child(:realtimer, Membrane.Realtimer)
        ]
      else
        []
      end

    # Sending pipeline links
    send_links_spec =
      if has_audio? do
        [
          get_child(:file_source)
          |> get_child(:wav_parser)
          |> get_child(:resampler)
          |> get_child(:timestamp_generator)
          |> get_child(:opus_encoder)
          |> get_child(:realtimer)
          |> via_in(Pad.ref(:input, ssrc),
            options: [payloader: Membrane.RTP.Opus.Payloader]
          )
          |> get_child(:rtp)
          |> via_out(Pad.ref(:rtp_output, ssrc), options: [payload_type: 111])
          |> get_child(:udp_endpoint)
        ]
      else
        []
      end

    structure =
      [udp_endpoint_spec, rtp_session_spec] ++
        receive_spec ++ send_children_spec ++ send_links_spec

    {[spec: structure],
     %{
       session_id: opts.session_id,
       media_handler: opts.media_handler,
       handler_state: opts.handler_state,
       audio_file: opts.audio_file,
       udp_sink_config: "#{format_ip(opts.remote_rtp_address)}:#{opts.remote_rtp_port}"
     }}
  end

  @impl true
  def handle_element_start_of_stream(element, pad, _ctx, state) do
    Logger.debug(
      "OpusPipeline #{state.session_id}: Start of stream on #{inspect(element)}:#{inspect(pad)}"
    )

    case element do
      :udp_endpoint ->
        Logger.info("OpusPipeline #{state.session_id}: Started streaming")
        Logger.info("  Streaming RTP to #{inspect(get_in(state, [:udp_sink_config]))}")

      :file_source ->
        Logger.info(
          "OpusPipeline #{state.session_id}: File source started reading #{state.audio_file}"
        )

      :realtimer ->
        Logger.debug(
          "OpusPipeline #{state.session_id}: Realtimer ready - streaming at realtime pace"
        )

      _ ->
        # Handle start of stream for other elements
        {[], state}
    end

    {[], state}
  end

  @impl true
  def handle_element_end_of_stream(element, pad, _ctx, state) do
    Logger.debug(
      "OpusPipeline #{state.session_id}: End of stream on #{inspect(element)}:#{inspect(pad)}"
    )

    # Log specific elements for debugging
    case element do
      :file_source ->
        Logger.info("OpusPipeline #{state.session_id}: File source finished reading")
        {[], state}

      :realtimer ->
        Logger.info("OpusPipeline #{state.session_id}: Realtimer finished processing")
        {[], state}

      :udp_endpoint ->
        Logger.info("OpusPipeline #{state.session_id}: Finished streaming")

        # The MediaHandler behaviour uses handle_play_complete
        if state.media_handler do
          case state.media_handler.handle_play_complete(state.audio_file, state.handler_state) do
            {{:play, next_file}, new_handler_state} ->
              Logger.info(
                "OpusPipeline #{state.session_id}: Handler requested next file: #{next_file}"
              )

              # TODO: Implement dynamic file switching
              {[terminate: :normal], %{state | handler_state: new_handler_state}}

            {:stop, new_handler_state} ->
              Logger.info("OpusPipeline #{state.session_id}: Handler requested stop")
              {[terminate: :normal], %{state | handler_state: new_handler_state}}

            _ ->
              {[terminate: :normal], state}
          end
        else
          {[terminate: :normal], state}
        end

      element_name ->
        # Handle end of stream for other elements
        Logger.debug(
          "OpusPipeline #{state.session_id}: End of stream for #{inspect(element_name)}"
        )

        {[], state}
    end
  end

  @impl true
  def handle_child_notification(
        {:new_rtp_stream, ssrc, _pt, _extensions} = notification,
        :rtp,
        _ctx,
        state
      ) do
    Logger.info(
      "OpusPipeline #{state.session_id}: New incoming RTP stream with SSRC: #{ssrc}"
    )

    Logger.debug("  Full notification: #{inspect(notification)}")

    # Create a pipeline to handle incoming RTP audio
    receive_audio_spec = [
      get_child(:rtp)
      |> via_out(Pad.ref(:output, ssrc),
        options: [depayloader: Membrane.RTP.Opus.Depayloader]
      )
      |> child({:opus_decoder, ssrc}, Membrane.Opus.Decoder)
      |> child({:audio_sink, ssrc}, %Membrane.Debug.Sink{})
    ]

    {[spec: receive_audio_spec], state}
  end

  @impl true
  def handle_child_notification(_notification, _child, _ctx, state) do
    {[], state}
  end

  # IP utilities are now imported from PipelineHelpers
end