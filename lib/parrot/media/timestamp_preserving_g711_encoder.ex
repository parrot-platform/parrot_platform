defmodule Parrot.Media.TimestampPreservingG711Encoder do
  @moduledoc """
  Wrapper around Membrane.G711.Encoder that preserves timestamps.
  
  The standard G711 encoder doesn't preserve pts/dts timestamps from input buffers,
  which causes issues downstream in the RTP pipeline.
  """
  
  use Membrane.Filter
  
  alias Membrane.{G711, RawAudio, Buffer}
  
  def_input_pad :input,
    flow_control: :auto,
    accepted_format: %RawAudio{
      channels: 1,
      sample_rate: 8000,
      sample_format: :s16le
    }

  def_output_pad :output,
    flow_control: :auto,
    accepted_format: %G711{encoding: :PCMA}

  @impl true
  def handle_init(_ctx, _opts) do
    {[], %{}}
  end
  
  @impl true
  def handle_stream_format(:input, _stream_format, _ctx, state) do
    stream_format = %G711{encoding: :PCMA}
    {[stream_format: {:output, stream_format}], state}
  end

  @impl true
  def handle_buffer(:input, buffer, _ctx, state) do
    %Buffer{payload: payload, pts: pts, dts: dts, metadata: metadata} = buffer
    
    # Ensure even number of bytes
    if rem(byte_size(payload), 2) != 0 do
      raise "Failed to encode the payload: payload contains odd number of bytes"
    end
    
    # Encode to G.711 A-law
    encoded_payload = 
      for <<sample::integer-signed-little-16 <- payload>>, into: <<>> do
        <<G711.LUT.alaw_encode(sample)>>
      end
    
    # Create new buffer preserving timestamps
    output_buffer = %Buffer{
      payload: encoded_payload,
      pts: pts,
      dts: dts,
      metadata: metadata
    }
    
    {[buffer: {:output, output_buffer}], state}
  end

  @impl true
  def handle_end_of_stream(:input, _ctx, state) do
    {[end_of_stream: :output], state}
  end
end