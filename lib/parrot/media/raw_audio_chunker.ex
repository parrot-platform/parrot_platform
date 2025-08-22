defmodule Parrot.Media.RawAudioChunker do
  @moduledoc """
  Normalizes raw audio buffers into fixed-size chunks with consistent timestamps.

  ## Problem This Solves

  Audio sources (like PortAudio) often deliver buffers of varying sizes based on
  hardware timing, system load, and buffer availability. For example, you might
  receive buffers of 512, 1024, or 753 samples unpredictably.

  However, many audio encoders (especially Opus) REQUIRE exact frame sizes:
  - Opus at 48kHz needs exactly 960 samples (20ms) per frame
  - Opus at 48kHz with 10ms frames needs exactly 480 samples
  - G.711 at 8kHz needs exactly 160 samples (20ms) per frame

  Without this chunker, encoders will complain about timestamp drift or fail entirely.

  ## How It Works

  1. **Accumulates** incoming buffers of any size into an internal buffer
  2. **Extracts** exact-sized chunks when enough data is available
  3. **Assigns** perfectly regular timestamps (0ms, 20ms, 40ms, etc.)
  4. **Holds** leftover data for the next incoming buffer

  ## Example Flow

      # Input: Irregular buffers from PortAudio
      [512 samples] → [1024 samples] → [256 samples] → [768 samples]
      
      # Output: Perfect 960-sample chunks (at 48kHz, 20ms each)
      [960 samples, pts=0ms] → [960 samples, pts=20ms] → [640 samples held]

  ## Usage Example

      # For Opus encoder at 48kHz with 20ms frames
      child(:audio_chunker, %Parrot.Media.RawAudioChunker{
        chunk_size: 960  # MUST match Opus frame size requirement
      })

      # For Opus encoder at 48kHz with 10ms frames  
      child(:audio_chunker, %Parrot.Media.RawAudioChunker{
        chunk_size: 480
      })

  ## Options

    * `:chunk_size` - Number of samples per chunk (per channel). This MUST match
                      what your encoder expects. For Opus at 48kHz: 960 (20ms),
                      480 (10ms), 2880 (60ms). For G.711 at 8kHz: 160 (20ms).
  """

  use Membrane.Filter

  alias Membrane.{Buffer, RawAudio}

  def_input_pad(:input, accepted_format: RawAudio, flow_control: :auto)
  def_output_pad(:output, accepted_format: RawAudio, flow_control: :auto)

  def_options(
    chunk_size: [
      spec: pos_integer(),
      description: "Number of samples per chunk (per channel)"
    ]
  )

  @impl true
  def handle_init(_ctx, opts) do
    {[],
     %{
       chunk_size: opts.chunk_size,
       accumulator: <<>>,
       pts: 0,
       stream_format: nil,
       bytes_per_chunk: nil,
       chunk_duration_ns: nil
     }}
  end

  @impl true
  @doc """
  Handles incoming stream format and calculates chunking parameters.
  
  When we receive the audio format (e.g., 48kHz, mono, 16-bit), we calculate:
  - How many BYTES per chunk (chunk_size * channels * bytes_per_sample)
  - Duration of each chunk in nanoseconds for timestamp generation
  
  Example: 48kHz, mono, 16-bit (s16le), chunk_size=960
  - bytes_per_sample = 2 (16-bit = 2 bytes)
  - bytes_per_chunk = 960 * 1 * 2 = 1920 bytes
  - chunk_duration_ns = 960 / 48000 * 1_000_000_000 = 20_000_000 ns (20ms)
  """
  def handle_stream_format(:input, stream_format, _ctx, state) do
    bytes_per_sample = get_bytes_per_sample(stream_format.sample_format)
    bytes_per_chunk = state.chunk_size * stream_format.channels * bytes_per_sample
    
    # Calculate chunk duration in nanoseconds
    chunk_duration_ns = div(state.chunk_size * 1_000_000_000, stream_format.sample_rate)
    
    state = %{state | 
      stream_format: stream_format,
      bytes_per_chunk: bytes_per_chunk,
      chunk_duration_ns: chunk_duration_ns
    }
    
    {[stream_format: {:output, stream_format}], state}
  end

  @impl true
  @doc """
  Accumulates incoming audio data and outputs fixed-size chunks.
  
  This is the heart of the chunker. It:
  1. Adds new data to our accumulator buffer
  2. Extracts as many complete chunks as possible
  3. Keeps leftover data for next time
  4. Assigns monotonically increasing timestamps
  
  Example with 960-sample chunks (1920 bytes for 16-bit mono):
  - Receive 512 samples (1024 bytes) → accumulator has 1024 bytes → no output
  - Receive 1024 samples (2048 bytes) → accumulator has 3072 bytes → output 1 chunk, keep 1152 bytes
  - Receive 256 samples (512 bytes) → accumulator has 1664 bytes → no output
  - Receive 512 samples (1024 bytes) → accumulator has 2688 bytes → output 1 chunk, keep 768 bytes
  """
  def handle_buffer(:input, %Buffer{payload: payload}, _ctx, state) do
    # Add new data to what we already have
    accumulator = state.accumulator <> payload

    # Extract as many fixed-size chunks as possible
    {buffers, rest, pts} =
      chunk_data(accumulator, state.bytes_per_chunk, state.pts, state.chunk_duration_ns, [])

    # Update state with leftover data and new timestamp position
    state = %{state | accumulator: rest, pts: pts}

    # Create output buffers with proper timestamps
    output_buffers =
      Enum.map(buffers, fn {chunk, chunk_pts} ->
        %Buffer{
          payload: chunk,
          pts: chunk_pts,     # Presentation timestamp
          dts: chunk_pts      # Decode timestamp (same for audio)
        }
      end)

    {[buffer: {:output, output_buffers}], state}
  end

  @impl true
  def handle_end_of_stream(:input, _ctx, state) do
    # Send any remaining data as the last chunk, padded with silence if needed
    actions = 
      if byte_size(state.accumulator) > 0 do
        # Pad with silence to make a complete chunk
        padding_size = state.bytes_per_chunk - byte_size(state.accumulator)
        padded_payload = state.accumulator <> :binary.copy(<<0>>, padding_size)
        
        last_buffer = %Buffer{
          payload: padded_payload,
          pts: state.pts,
          dts: state.pts
        }
        [buffer: {:output, last_buffer}, end_of_stream: :output]
      else
        [end_of_stream: :output]
      end

    {actions, state}
  end

  # Recursively extract fixed-size chunks from accumulated data
  @doc false
  # When we have enough data for at least one chunk, extract it and recurse
  defp chunk_data(data, chunk_size, pts, duration_ns, acc) when byte_size(data) >= chunk_size do
    # Extract exactly chunk_size bytes
    <<chunk::binary-size(chunk_size), rest::binary>> = data
    
    # Recurse with remaining data, incrementing timestamp
    # Each chunk gets a timestamp that's duration_ns later than the previous
    chunk_data(rest, chunk_size, pts + duration_ns, duration_ns, [{chunk, pts} | acc])
  end

  # When we don't have enough data for a complete chunk, return what we have
  defp chunk_data(rest, _chunk_size, pts, _duration_ns, acc) do
    # Return: extracted chunks (reversed for correct order), leftover data, next timestamp
    {Enum.reverse(acc), rest, pts}
  end

  defp get_bytes_per_sample(:s16le), do: 2
  defp get_bytes_per_sample(:s16be), do: 2
  defp get_bytes_per_sample(:s32le), do: 4
  defp get_bytes_per_sample(:s32be), do: 4
  defp get_bytes_per_sample(:f32le), do: 4
  defp get_bytes_per_sample(:f32be), do: 4
  defp get_bytes_per_sample(:s8), do: 1
  defp get_bytes_per_sample(:u8), do: 1
  defp get_bytes_per_sample(_), do: 2  # Default to 16-bit
end