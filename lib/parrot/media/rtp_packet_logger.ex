defmodule Parrot.Media.RTPPacketLogger do
  @moduledoc """
  A simple Membrane filter that logs RTP packet information for debugging.
  """

  use Membrane.Filter
  require Logger

  def_input_pad(:input, accepted_format: _any, flow_control: :auto)
  def_output_pad(:output, accepted_format: _any, flow_control: :auto)

  def_options(
    dest_info: [
      spec: String.t(),
      default: "unknown",
      description: "Destination info for logging"
    ]
  )

  @impl true
  def handle_init(_ctx, opts) do
    {[], %{counter: 0, dest_info: opts.dest_info}}
  end

  @impl true
  def handle_buffer(:input, buffer, _ctx, state) do
    state = %{state | counter: state.counter + 1}

    if state.counter <= 5 || rem(state.counter, 100) == 0 do
      Logger.info(
        "RTP packet #{state.counter}: size=#{byte_size(buffer.payload)} bytes to #{state.dest_info}"
      )

      # Try to parse RTP header if it looks like RTP
      case buffer.payload do
        <<version::2, _padding::1, _extension::1, _cc::4, marker::1, pt::7, seq::16,
          _rest::binary>>
        when version == 2 ->
          Logger.info("  RTP header: pt=#{pt} seq=#{seq} marker=#{marker}")

        _ ->
          :ok
      end
    end

    {[buffer: {:output, buffer}], state}
  end
end
