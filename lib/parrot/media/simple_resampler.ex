defmodule Parrot.Media.SimpleResampler do
  @moduledoc """
  A simple audio resampler that downsamples from 48kHz to 8kHz.
  This is a basic implementation for testing - production code should use FFmpeg resampler.
  """
  
  use Membrane.Filter
  
  alias Membrane.{Buffer, RawAudio}
  
  def_input_pad :input,
    accepted_format: %RawAudio{
      sample_format: :s16le,
      sample_rate: 48000,
      channels: 1
    },
    availability: :always
  
  def_output_pad :output,
    accepted_format: %RawAudio{
      sample_format: :s16le,
      sample_rate: 8000,
      channels: 1
    },
    availability: :always
  
  @impl true
  def handle_init(_ctx, _opts) do
    state = %{
      accumulator: <<>>,
      ratio: 6  # 48000 / 8000 = 6
    }
    {[], state}
  end
  
  @impl true
  def handle_stream_format(:input, _stream_format, _ctx, state) do
    output_format = %RawAudio{
      sample_format: :s16le,
      sample_rate: 8000,
      channels: 1
    }
    
    {[stream_format: {:output, output_format}], state}
  end
  
  @impl true
  def handle_buffer(:input, buffer, _ctx, state) do
    # Simple downsampling - take every 6th sample
    # This is not a high-quality resampler but works for testing
    combined = state.accumulator <> buffer.payload
    
    # Process complete samples (2 bytes per sample for s16le)
    sample_size = 2
    complete_size = div(byte_size(combined), sample_size * state.ratio) * sample_size * state.ratio
    
    <<to_process::binary-size(complete_size), remainder::binary>> = combined
    
    # Downsample by taking every 6th sample
    downsampled = downsample_audio(to_process, state.ratio)
    
    output_buffer = %Buffer{
      payload: downsampled,
      metadata: buffer.metadata,
      pts: buffer.pts,
      dts: buffer.dts
    }
    
    new_state = %{state | accumulator: remainder}
    
    if byte_size(downsampled) > 0 do
      {[buffer: {:output, output_buffer}], new_state}
    else
      {[], new_state}
    end
  end
  
  @impl true
  def handle_end_of_stream(:input, _ctx, state) do
    # Process any remaining samples
    if byte_size(state.accumulator) > 0 do
      downsampled = downsample_audio(state.accumulator, state.ratio)
      
      if byte_size(downsampled) > 0 do
        buffer = %Buffer{payload: downsampled}
        {[buffer: {:output, buffer}, end_of_stream: :output], %{state | accumulator: <<>>}}
      else
        {[end_of_stream: :output], %{state | accumulator: <<>>}}
      end
    else
      {[end_of_stream: :output], state}
    end
  end
  
  defp downsample_audio(data, ratio) do
    # Take every nth sample where n = ratio
    samples = for <<sample::signed-little-16 <- data>>, do: sample
    
    samples
    |> Enum.take_every(ratio)
    |> Enum.map(&<<&1::signed-little-16>>)
    |> Enum.join()
  end
end