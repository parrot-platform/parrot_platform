defmodule Parrot.Media.AudioChunker do
  @moduledoc """
  Universal audio chunker that normalizes audio buffers into fixed-size chunks with consistent timestamps.
  
  This module handles both raw audio (PCM) and encoded audio (G.711, etc.) formats, solving the
  common problem of irregular buffer sizes from audio sources.

  ## Problem This Solves

  Audio sources deliver buffers of varying sizes based on hardware timing, system load, and 
  buffer availability. However, many audio encoders and RTP packetizers require exact frame sizes:
  
  - **OPUS at 48kHz**: Needs exactly 960 samples (20ms) per frame
  - **G.711 at 8kHz**: Needs exactly 160 samples (20ms) per RTP packet  
  - **OPUS at 48kHz with 10ms frames**: Needs exactly 480 samples
  - **G.722 at 16kHz**: Needs exactly 320 samples (20ms) per frame

  Without this chunker, you'll experience timestamp drift, encoding failures, or RTP packet loss.

  ## How It Works

  1. **Accumulates** incoming buffers of any size into an internal buffer
  2. **Extracts** exact-sized chunks when enough data is available
  3. **Assigns** perfectly regular timestamps (0ms, 20ms, 40ms, etc.)
  4. **Holds** leftover data for the next incoming buffer

  ## Configuration

  The chunker can operate in two modes:

  ### 1. Sample-based chunking (for raw audio)
  
  Specify `chunk_samples` to chunk by number of samples:
  
      # For OPUS encoder at 48kHz with 20ms frames
      child(:audio_chunker, %Parrot.Media.AudioChunker{
        chunk_samples: 960  # 20ms * 48kHz = 960 samples
      })

  ### 2. Duration-based chunking (for encoded audio like G.711)
  
  Specify `chunk_duration_ms` and `sample_rate` to chunk by time duration:
  
      # For G.711 RTP packets with 20ms duration
      child(:audio_chunker, %Parrot.Media.AudioChunker{
        chunk_duration_ms: 20,
        sample_rate: 8000  # G.711 uses 8kHz
      })

  ## Example Flow

      # Input: Irregular buffers from PortAudio
      [512 samples] → [1024 samples] → [256 samples] → [768 samples]
      
      # Output with chunk_samples=960: Perfect 960-sample chunks
      [960 samples, pts=0ms] → [960 samples, pts=20ms] → [640 samples held]
      
      # Output with chunk_duration_ms=20, sample_rate=8000: Perfect 160-byte chunks
      [160 bytes, pts=0ms] → [160 bytes, pts=20ms] → [160 bytes, pts=40ms]

  ## Options

    * `:chunk_samples` - Number of samples per chunk (for raw audio). Mutually exclusive with
                         `:chunk_duration_ms`. Use this when you know the exact sample count needed.
                         
    * `:chunk_duration_ms` - Duration of each chunk in milliseconds (for encoded audio). 
                             Requires `:sample_rate` to be set. Use this for time-based chunking.
                             
    * `:sample_rate` - Sample rate in Hz. Required when using `:chunk_duration_ms`.
                       Common values: 8000 (G.711), 16000 (G.722), 48000 (OPUS)
  """

  use Membrane.Filter

  alias Membrane.{Buffer, RawAudio, G711}

  def_input_pad(:input, 
    accepted_format: any_of(RawAudio, G711),
    flow_control: :auto
  )
  
  def_output_pad(:output,
    accepted_format: any_of(RawAudio, G711),
    flow_control: :auto
  )

  def_options(
    chunk_samples: [
      spec: pos_integer() | nil,
      default: nil,
      description: "Number of samples per chunk (for raw audio)"
    ],
    chunk_duration_ms: [
      spec: pos_integer() | nil,
      default: nil,
      description: "Chunk duration in milliseconds (for encoded audio)"
    ],
    sample_rate: [
      spec: pos_integer() | nil,
      default: nil,
      description: "Sample rate in Hz (required with chunk_duration_ms)"
    ]
  )

  @impl true
  def handle_init(_ctx, opts) do
    # Validate options
    cond do
      opts.chunk_samples != nil and opts.chunk_duration_ms != nil ->
        raise ArgumentError, 
          "Cannot specify both chunk_samples and chunk_duration_ms. Choose one based on your audio format."
      
      opts.chunk_samples == nil and opts.chunk_duration_ms == nil ->
        raise ArgumentError,
          "Must specify either chunk_samples (for raw audio) or chunk_duration_ms (for encoded audio)"
      
      opts.chunk_duration_ms != nil and opts.sample_rate == nil ->
        raise ArgumentError,
          "sample_rate is required when using chunk_duration_ms"
      
      true ->
        :ok
    end

    {[],
     %{
       # Configuration
       chunk_samples: opts.chunk_samples,
       chunk_duration_ms: opts.chunk_duration_ms,
       sample_rate: opts.sample_rate,
       
       # Runtime state
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
  
  For raw audio, calculates bytes based on sample format and channels.
  For encoded audio (G.711), uses 1 byte per sample.
  """
  def handle_stream_format(:input, stream_format, _ctx, state) do
    {bytes_per_chunk, chunk_duration_ns} = 
      calculate_chunk_parameters(stream_format, state)
    
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
          pts: chunk_pts,
          dts: chunk_pts
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

  # Calculate chunk parameters based on format and configuration
  defp calculate_chunk_parameters(%RawAudio{} = format, state) do
    if state.chunk_samples do
      # Sample-based chunking for raw audio
      bytes_per_sample = get_bytes_per_sample(format.sample_format)
      bytes_per_chunk = state.chunk_samples * format.channels * bytes_per_sample
      chunk_duration_ns = div(state.chunk_samples * 1_000_000_000, format.sample_rate)
      
      {bytes_per_chunk, chunk_duration_ns}
    else
      # Duration-based chunking for raw audio
      samples_per_chunk = div(format.sample_rate * state.chunk_duration_ms, 1000)
      bytes_per_sample = get_bytes_per_sample(format.sample_format)
      bytes_per_chunk = samples_per_chunk * format.channels * bytes_per_sample
      chunk_duration_ns = state.chunk_duration_ms * 1_000_000
      
      {bytes_per_chunk, chunk_duration_ns}
    end
  end

  defp calculate_chunk_parameters(%G711{}, state) do
    # G.711 has 1 byte per sample
    if state.chunk_duration_ms do
      # Use configured duration and sample rate
      samples_per_chunk = div(state.sample_rate * state.chunk_duration_ms, 1000)
      bytes_per_chunk = samples_per_chunk  # 1 byte per sample for G.711
      chunk_duration_ns = state.chunk_duration_ms * 1_000_000
      
      {bytes_per_chunk, chunk_duration_ns}
    else
      # Fallback: use chunk_samples if provided (though unusual for G.711)
      bytes_per_chunk = state.chunk_samples
      chunk_duration_ns = div(state.chunk_samples * 1_000_000_000, state.sample_rate || 8000)
      
      {bytes_per_chunk, chunk_duration_ns}
    end
  end

  # Recursively extract fixed-size chunks from accumulated data
  @doc false
  defp chunk_data(data, chunk_size, pts, duration_ns, acc) when byte_size(data) >= chunk_size do
    # Extract exactly chunk_size bytes
    <<chunk::binary-size(chunk_size), rest::binary>> = data
    
    # Recurse with remaining data, incrementing timestamp
    chunk_data(rest, chunk_size, pts + duration_ns, duration_ns, [{chunk, pts} | acc])
  end

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