defmodule Parrot.Media.G711Chunker do
  @moduledoc """
  Chunks G.711 encoded audio into RTP-sized packets.

  This module is a Membrane filter that takes G.711 encoded audio buffers and
  splits them into appropriately sized chunks for RTP transmission. For G.711
  audio at 8kHz, each 20ms RTP packet contains 160 samples (160 bytes).

  ## Example

      # In your pipeline
      child(:g711_chunker, %Parrot.Media.G711Chunker{
        chunk_duration: 20  # milliseconds
      })

  ## Options

    * `:chunk_duration` - Duration of each chunk in milliseconds (default: 20ms)
  """

  use Membrane.Filter

  alias Membrane.{Buffer, G711}

  def_input_pad(:input, accepted_format: G711, flow_control: :auto)
  def_output_pad(:output, accepted_format: G711, flow_control: :auto)

  def_options(
    chunk_duration: [
      spec: pos_integer(),
      default: 20,
      description: "Chunk duration in milliseconds"
    ]
  )

  @impl true
  def handle_init(_ctx, opts) do
    # For G.711: 8000 Hz sample rate, 1 byte per sample
    # samples per chunk
    chunk_size = div(8000 * opts.chunk_duration, 1000)

    {[],
     %{
       chunk_size: chunk_size,
       accumulator: <<>>,
       pts: 0,
       chunk_duration_ns: opts.chunk_duration * 1_000_000
     }}
  end

  @impl true
  def handle_stream_format(:input, stream_format, _ctx, state) do
    {[stream_format: {:output, stream_format}], state}
  end

  @impl true
  def handle_buffer(:input, %Buffer{payload: payload} = buffer, _ctx, state) do
    accumulator = state.accumulator <> payload

    {buffers, rest, pts} =
      chunk_data(accumulator, state.chunk_size, state.pts, state.chunk_duration_ns, [])

    state = %{state | accumulator: rest, pts: pts}

    # Preserve metadata from original buffer on the chunks
    output_buffers =
      Enum.map(buffers, fn {chunk, chunk_pts} ->
        %Buffer{
          payload: chunk,
          pts: chunk_pts,
          metadata: buffer.metadata
        }
      end)

    {[buffer: {:output, output_buffers}], state}
  end

  @impl true
  def handle_end_of_stream(:input, _ctx, state) do
    # Send any remaining data as the last chunk
    actions =
      if byte_size(state.accumulator) > 0 do
        buffer = %Buffer{
          payload: state.accumulator,
          pts: state.pts
        }

        [buffer: {:output, buffer}, end_of_stream: :output]
      else
        [end_of_stream: :output]
      end

    {actions, state}
  end

  defp chunk_data(data, chunk_size, pts, duration, acc) when byte_size(data) >= chunk_size do
    <<chunk::binary-size(chunk_size), rest::binary>> = data
    chunk_data(rest, chunk_size, pts + duration, duration, [{chunk, pts} | acc])
  end

  defp chunk_data(data, _chunk_size, pts, _duration, acc) do
    {Enum.reverse(acc), data, pts}
  end
end
