defmodule Parrot.Media.BasicRTPDepayloader do
  @moduledoc """
  A basic RTP depayloader that extracts audio payload from RTP packets.
  This bypasses the complexity of the RTP SessionBin for simple use cases
  where you just need to extract G.711 audio from RTP packets.
  """

  use Membrane.Filter

  alias Membrane.Buffer
  alias Membrane.G711

  def_input_pad(:input,
    accepted_format: %Membrane.RemoteStream{type: :packetized},
    availability: :always
  )

  def_output_pad(:output,
    accepted_format: %G711{encoding: _encoding},
    availability: :always
  )

  def_options(
    clock_rate: [
      spec: pos_integer(),
      default: 8000,
      description: "Clock rate for the codec"
    ],
    selected_codec: [
      spec: :pcmu | :pcma,
      default: :pcmu,
      description: "Selected codec"
    ]
  )

  @impl true
  def handle_init(_ctx, opts) do
    state = %{
      clock_rate: opts.clock_rate,
      selected_codec: opts.selected_codec,
      last_timestamp: nil,
      last_seq_num: nil
    }

    {[], state}
  end

  @impl true
  def handle_playing(_ctx, state) do
    {[], state}
  end

  @impl true
  def handle_stream_format(:input, _stream_format, _ctx, state) do
    # Output the appropriate G.711 format
    format =
      case state.selected_codec do
        :pcma -> %G711{encoding: :PCMA}
        :pcmu -> %G711{encoding: :PCMU}
      end

    {[stream_format: {:output, format}], state}
  end

  @impl true
  def handle_buffer(:input, buffer, _ctx, state) do
    require Logger
    Logger.debug("BasicRTPDepayloader got buffer, size: #{byte_size(buffer.payload)}")

    # Parse RTP packet
    case parse_rtp_packet(buffer.payload) do
      {:ok, payload, seq_num, timestamp, payload_type} ->
        Logger.debug(
          "RTP packet received: seq=#{seq_num}, ts=#{timestamp}, pt=#{payload_type}, payload_size=#{byte_size(payload)}"
        )

        # Create output buffer with just the audio payload
        output_buffer = %Buffer{
          payload: payload,
          metadata: buffer.metadata,
          pts: buffer.pts,
          dts: buffer.dts
        }

        {[buffer: {:output, output_buffer}], state}

      {:error, reason} ->
        Logger.warning(
          "Failed to parse RTP packet: #{reason}, buffer size: #{byte_size(buffer.payload)}"
        )

        # Skip malformed packets
        {[], state}
    end
  end

  # Simple RTP parser - extracts payload from RTP packet
  defp parse_rtp_packet(<<
         _version::2,
         _padding::1,
         _extension::1,
         cc::4,
         _marker::1,
         payload_type::7,
         seq_num::16,
         timestamp::32,
         _ssrc::32,
         _csrc::binary-size(cc * 4),
         payload::binary
       >>) do
    {:ok, payload, seq_num, timestamp, payload_type}
  end

  defp parse_rtp_packet(_), do: {:error, :invalid_packet}
end
