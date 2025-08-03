defmodule Parrot.Media.MembraneAlawPipeline do
  @moduledoc """
  Membrane pipeline for G.711 A-law RTP streaming.
  Uses the official Membrane G711 encoder (A-law) and RTP payloader.
  """

  use Membrane.Pipeline
  require Logger

  @impl true
  def handle_init(_ctx, opts) do
    Logger.info("MembraneAlawPipeline: Starting for session #{opts.session_id}")
    Logger.info("  Audio file: #{opts.audio_file}")

    # Check if file exists and get its size
    case File.stat(opts.audio_file) do
      {:ok, %{size: size}} ->
        Logger.info("  Audio file size: #{size} bytes")

      {:error, reason} ->
        Logger.error("  Cannot stat audio file: #{inspect(reason)}")
    end

    Logger.info("  RTP destination: #{opts.remote_rtp_address}:#{opts.remote_rtp_port}")
    Logger.info("  Local RTP port: #{opts.local_rtp_port}")

    # Generate SSRC once for consistency
    ssrc = :rand.uniform(0xFFFFFFFF)

    # Create bidirectional UDP endpoint first
    udp_endpoint_spec =
      child(:udp_endpoint, %Membrane.UDP.Endpoint{
        local_port_no: opts.local_rtp_port,
        destination_port_no: opts.remote_rtp_port,
        destination_address:
          case parse_ip(opts.remote_rtp_address) do
            {:ok, ip} ->
              ip

            {:error, reason} ->
              raise "Invalid remote RTP address: #{inspect(opts.remote_rtp_address)}, reason: #{inspect(reason)}"
          end
      })

    # Create RTP SessionBin for bidirectional RTP handling
    rtp_session_spec =
      child(:rtp, %Membrane.RTP.SessionBin{
        # payload type 8 = G.711 A-law
        fmt_mapping: %{8 => {"PCMA", 8000}}
      })

    # Receiving pipeline: UDP -> RTP -> Decoder
    receive_spec = [
      get_child(:udp_endpoint)
      |> via_in(Pad.ref(:rtp_input, make_ref()))
      |> get_child(:rtp)
    ]

    # Sending pipeline children
    send_children_spec = [
      # Source - read WAV file
      child(:file_source, %Membrane.File.Source{
        location: opts.audio_file
      }),

      # Parse WAV file
      child(:wav_parser, Membrane.WAV.Parser),

      # Convert to G.711 A-law
      child(:g711_encoder, Membrane.G711.Encoder),

      # Chunk G.711 data into RTP-sized packets
      child(:g711_chunker, %Parrot.Media.G711Chunker{
        # 20ms packets
        chunk_duration: 20
      }),

      # Add realtimer to pace the audio
      child(:realtimer, Membrane.Realtimer),

      # RTP packet logger
      child(:rtp_debug, %Parrot.Media.RTPPacketLogger{
        dest_info:
          case parse_ip(opts.remote_rtp_address) do
            {:ok, ip} -> "#{format_ip(ip)}:#{opts.remote_rtp_port}"
            {:error, _} -> "invalid_ip:#{opts.remote_rtp_port}"
          end
      })
    ]

    # Sending pipeline links
    send_links_spec = [
      get_child(:file_source)
      |> get_child(:wav_parser)
      |> get_child(:g711_encoder)
      |> get_child(:g711_chunker)
      |> get_child(:realtimer)
      |> via_in(Pad.ref(:input, ssrc),
        options: [payloader: Membrane.RTP.G711.Payloader]
      )
      |> get_child(:rtp)
      |> via_out(Pad.ref(:rtp_output, ssrc), options: [encoding: :PCMA])
      |> get_child(:rtp_debug)
      |> get_child(:udp_endpoint)
    ]

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
      "MembraneAlawPipeline #{state.session_id}: Start of stream on #{inspect(element)}:#{inspect(pad)}"
    )

    case element do
      :udp_endpoint ->
        Logger.info("MembraneAlawPipeline #{state.session_id}: Started streaming")
        Logger.info("  Streaming RTP to #{inspect(get_in(state, [:udp_sink_config]))}")

      # Note: We could call a handler callback here when playback starts,
      # but our MediaHandler behaviour doesn't define this callback yet

      :file_source ->
        Logger.info(
          "MembraneAlawPipeline #{state.session_id}: File source started reading #{state.audio_file}"
        )

      :realtimer ->
        Logger.debug(
          "MembraneAlawPipeline #{state.session_id}: Realtimer ready - streaming at realtime pace"
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
      "MembraneAlawPipeline #{state.session_id}: End of stream on #{inspect(element)}:#{inspect(pad)}"
    )

    # Log specific elements for debugging
    case element do
      :file_source ->
        Logger.info("MembraneAlawPipeline #{state.session_id}: File source finished reading")
        {[], state}

      :realtimer ->
        Logger.info("MembraneAlawPipeline #{state.session_id}: Realtimer finished processing")
        {[], state}

      :udp_endpoint ->
        Logger.info("MembraneAlawPipeline #{state.session_id}: Finished streaming")

        # The MediaHandler behaviour uses handle_play_complete, not handle_playback_completed
        if state.media_handler do
          case state.media_handler.handle_play_complete(state.audio_file, state.handler_state) do
            {{:play, next_file}, new_handler_state} ->
              Logger.info(
                "MembraneAlawPipeline #{state.session_id}: Handler requested next file: #{next_file}"
              )

              # TODO: Implement dynamic file switching
              {[terminate: :normal], %{state | handler_state: new_handler_state}}

            {:stop, new_handler_state} ->
              Logger.info("MembraneAlawPipeline #{state.session_id}: Handler requested stop")
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
          "MembraneAlawPipeline #{state.session_id}: End of stream for #{inspect(element_name)}"
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
      "MembraneAlawPipeline #{state.session_id}: New incoming RTP stream with SSRC: #{ssrc}"
    )

    Logger.debug("  Full notification: #{inspect(notification)}")

    # Create a pipeline to handle incoming RTP audio
    receive_audio_spec = [
      get_child(:rtp)
      |> via_out(Pad.ref(:output, ssrc),
        options: [depayloader: Membrane.RTP.G711.Depayloader]
      )
      |> child({:g711_decoder, ssrc}, Membrane.G711.Decoder)
      |> child({:audio_sink, ssrc}, %Membrane.Debug.Sink{})
    ]

    {[spec: receive_audio_spec], state}
  end

  @impl true
  def handle_child_notification(_notification, _child, _ctx, state) do
    {[], state}
  end

  defp parse_ip(ip) when is_binary(ip) do
    case :inet.parse_address(String.to_charlist(ip)) do
      {:ok, ip_tuple} -> {:ok, ip_tuple}
      {:error, reason} -> {:error, {:invalid_ip_address, ip, reason}}
    end
  end

  defp parse_ip(ip) when is_tuple(ip) and tuple_size(ip) == 4 do
    # Validate IPv4 tuple
    if Enum.all?(Tuple.to_list(ip), &(&1 >= 0 and &1 <= 255)) do
      {:ok, ip}
    else
      {:error, {:invalid_ipv4_tuple, ip}}
    end
  end

  defp parse_ip(ip) when is_tuple(ip) and tuple_size(ip) == 8 do
    # Validate IPv6 tuple
    if Enum.all?(Tuple.to_list(ip), &(&1 >= 0 and &1 <= 65535)) do
      {:ok, ip}
    else
      {:error, {:invalid_ipv6_tuple, ip}}
    end
  end

  defp parse_ip(ip), do: {:error, {:invalid_ip_format, ip}}

  defp format_ip(ip) when is_binary(ip), do: ip
  defp format_ip({a, b, c, d}), do: "#{a}.#{b}.#{c}.#{d}"
  defp format_ip(ip), do: inspect(ip)
end
