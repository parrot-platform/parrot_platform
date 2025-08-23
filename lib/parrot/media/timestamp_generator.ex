defmodule Parrot.Media.TimestampGenerator do
  @moduledoc """
  Adds timestamps to buffers that don't have them.

  This is useful after elements like WAV parser that don't set timestamps.
  """

  use Membrane.Filter

  alias Membrane.{Buffer, RawAudio, Time}

  def_input_pad(:input,
    flow_control: :auto,
    accepted_format: RawAudio
  )

  def_output_pad(:output,
    flow_control: :auto,
    accepted_format: RawAudio
  )

  @impl true
  def handle_init(_ctx, _opts) do
    {[], %{stream_format: nil, samples_processed: 0}}
  end

  @impl true
  def handle_stream_format(:input, stream_format, _ctx, state) do
    {[stream_format: {:output, stream_format}], %{state | stream_format: stream_format}}
  end

  @impl true
  def handle_buffer(:input, %Buffer{pts: nil} = buffer, _ctx, state) do
    # Buffer needs timestamp - calculate based on samples processed
    {output_buffer, new_state} = add_timestamp_and_update_state(buffer, state)
    {[buffer: {:output, output_buffer}], new_state}
  end

  @impl true
  def handle_buffer(:input, %Buffer{} = buffer, _ctx, state) do
    # Buffer already has timestamp - just update sample count
    new_state = update_samples_processed(buffer, state)
    {[buffer: {:output, buffer}], new_state}
  end

  @impl true
  def handle_end_of_stream(:input, _ctx, state) do
    {[end_of_stream: :output], state}
  end

  # Private functions with pattern matching

  defp add_timestamp_and_update_state(buffer, %{stream_format: nil} = state) do
    # No stream format yet - can't calculate timestamp
    {%Buffer{buffer | pts: 0, dts: 0}, state}
  end

  defp add_timestamp_and_update_state(
         %Buffer{payload: payload} = buffer,
         %{stream_format: stream_format, samples_processed: samples_processed} = state
       ) do
    pts = calculate_pts(samples_processed, stream_format.sample_rate)
    samples = calculate_samples(payload, stream_format)

    output_buffer = %Buffer{buffer | pts: pts, dts: pts}
    new_state = %{state | samples_processed: samples_processed + samples}

    {output_buffer, new_state}
  end

  defp update_samples_processed(%Buffer{}, %{stream_format: nil} = state) do
    state
  end

  defp update_samples_processed(
         %Buffer{payload: payload},
         %{stream_format: stream_format, samples_processed: samples_processed} = state
       ) do
    samples = calculate_samples(payload, stream_format)
    %{state | samples_processed: samples_processed + samples}
  end

  defp calculate_pts(samples_processed, sample_rate) do
    Time.nanoseconds(div(samples_processed * 1_000_000_000, sample_rate))
  end

  defp calculate_samples(payload, %RawAudio{sample_format: format, channels: channels}) do
    bytes_per_sample = get_bytes_per_sample(format)
    div(byte_size(payload), bytes_per_sample * channels)
  end

  # Pattern match on sample formats for bytes per sample
  defp get_bytes_per_sample(:s8), do: 1
  defp get_bytes_per_sample(:u8), do: 1
  defp get_bytes_per_sample(:s16le), do: 2
  defp get_bytes_per_sample(:s16be), do: 2
  defp get_bytes_per_sample(:u16le), do: 2
  defp get_bytes_per_sample(:u16be), do: 2
  defp get_bytes_per_sample(:s24le), do: 3
  defp get_bytes_per_sample(:s24be), do: 3
  defp get_bytes_per_sample(:u24le), do: 3
  defp get_bytes_per_sample(:u24be), do: 3
  defp get_bytes_per_sample(:s32le), do: 4
  defp get_bytes_per_sample(:s32be), do: 4
  defp get_bytes_per_sample(:u32le), do: 4
  defp get_bytes_per_sample(:u32be), do: 4
  defp get_bytes_per_sample(:f32le), do: 4
  defp get_bytes_per_sample(:f32be), do: 4
  defp get_bytes_per_sample(:f64le), do: 8
  defp get_bytes_per_sample(:f64be), do: 8
  # Default to 16-bit
  defp get_bytes_per_sample(_), do: 2
end
