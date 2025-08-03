defmodule Parrot.Media.MembraneRtpPipeline do
  @moduledoc """
  Proper Membrane pipeline for RTP audio streaming.
  Uses Membrane's built-in RTP and audio handling capabilities.
  """

  use Membrane.Pipeline
  require Logger

  alias Membrane.RTP

  @impl true
  def handle_init(_ctx, opts) do
    Logger.info("MembraneRtpPipeline: Starting for session #{opts.session_id}")

    structure = [
      # Source - read WAV file
      child(:file_source, %Membrane.File.Source{
        location: opts.audio_file
      }),

      # Parse WAV file
      child(:wav_parser, Membrane.WAV.Parser),

      # Convert to RTP payload format
      child(:rtp_payloader, %RTP.PayloaderBin{
        payloader: RTP.G711.Payloader,
        # PCMU
        payload_type: 0,
        clock_rate: 8000,
        ssrc: :rand.uniform(0xFFFFFFFF)
      }),

      # Send via UDP
      child(:udp_sink, %Membrane.UDP.Sink{
        destination_address: parse_ip(opts.remote_rtp_address),
        destination_port_no: opts.remote_rtp_port,
        local_port_no: opts.local_rtp_port
      }),

      # Pipeline connections
      get_child(:file_source)
      |> get_child(:wav_parser)
      |> get_child(:rtp_payloader)
      |> get_child(:udp_sink)
    ]

    {[spec: structure],
     %{
       session_id: opts.session_id,
       media_handler: opts.media_handler,
       handler_state: opts.handler_state,
       audio_file: opts.audio_file
     }}
  end

  @impl true
  def handle_element_start_of_stream(:udp_sink, _pad, _ctx, state) do
    Logger.info("MembraneRtpPipeline #{state.session_id}: Started streaming")

    if state.media_handler do
      state.media_handler.handle_playback_started(
        state.session_id,
        state.audio_file,
        state.handler_state
      )
    end

    {[], state}
  end

  @impl true
  def handle_element_end_of_stream(:udp_sink, _pad, _ctx, state) do
    Logger.info("MembraneRtpPipeline #{state.session_id}: Finished streaming")

    if state.media_handler do
      case state.media_handler.handle_play_complete(
             state.audio_file,
             state.handler_state
           ) do
        {{:play, next_file}, _new_handler_state} ->
          Logger.info("MembraneRtpPipeline #{state.session_id}: Playing next file: #{next_file}")
          # In a real implementation, you'd update the file source here
          # For now, we'll just terminate
          {[terminate: :normal], state}

        {:stop, _new_handler_state} ->
          {[terminate: :normal], state}

        _ ->
          {[terminate: :normal], state}
      end
    else
      {[terminate: :normal], state}
    end
  end

  defp parse_ip(ip) when is_binary(ip) do
    case :inet.parse_address(String.to_charlist(ip)) do
      {:ok, ip_tuple} -> ip_tuple
      _ -> {127, 0, 0, 1}
    end
  end

  defp parse_ip(ip) when is_tuple(ip), do: ip
  defp parse_ip(_), do: {127, 0, 0, 1}
end
