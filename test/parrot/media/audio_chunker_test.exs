defmodule Parrot.Media.AudioChunkerTest do
  use ExUnit.Case, async: true
  
  import Membrane.Testing.Assertions
  alias Membrane.Testing.Pipeline
  alias Membrane.{Buffer, RawAudio, G711, Time}
  alias Parrot.Media.AudioChunker

  describe "initialization" do
    test "raises error when neither chunk_samples nor chunk_duration_ms is specified" do
      assert_raise ArgumentError, ~r/Must specify either chunk_samples/, fn ->
        AudioChunker.handle_init(nil, %{
          chunk_samples: nil,
          chunk_duration_ms: nil,
          sample_rate: nil
        })
      end
    end

    test "raises error when both chunk_samples and chunk_duration_ms are specified" do
      assert_raise ArgumentError, ~r/Cannot specify both/, fn ->
        AudioChunker.handle_init(nil, %{
          chunk_samples: 960,
          chunk_duration_ms: 20,
          sample_rate: 48000
        })
      end
    end

    test "raises error when chunk_duration_ms is specified without sample_rate" do
      assert_raise ArgumentError, ~r/sample_rate is required/, fn ->
        AudioChunker.handle_init(nil, %{
          chunk_samples: nil,
          chunk_duration_ms: 20,
          sample_rate: nil
        })
      end
    end

    test "initializes correctly with chunk_samples" do
      {[], state} = AudioChunker.handle_init(nil, %{
        chunk_samples: 960,
        chunk_duration_ms: nil,
        sample_rate: nil
      })
      
      assert state.chunk_samples == 960
      assert state.chunk_duration_ms == nil
      assert state.accumulator == <<>>
      assert state.pts == 0
    end

    test "initializes correctly with chunk_duration_ms and sample_rate" do
      {[], state} = AudioChunker.handle_init(nil, %{
        chunk_samples: nil,
        chunk_duration_ms: 20,
        sample_rate: 8000
      })
      
      assert state.chunk_duration_ms == 20
      assert state.sample_rate == 8000
      assert state.accumulator == <<>>
      assert state.pts == 0
    end
  end

  describe "raw audio chunking with chunk_samples" do
    setup do
      # Setup for 48kHz mono audio with 960 samples per chunk (20ms)
      opts = %{
        chunk_samples: 960,
        chunk_duration_ms: nil,
        sample_rate: nil
      }
      
      {[], initial_state} = AudioChunker.handle_init(nil, opts)
      
      stream_format = %RawAudio{
        sample_format: :s16le,
        sample_rate: 48000,
        channels: 1
      }
      
      {[stream_format: {:output, ^stream_format}], state} = 
        AudioChunker.handle_stream_format(:input, stream_format, nil, initial_state)
      
      %{state: state, stream_format: stream_format}
    end

    test "chunks exact-sized buffer", %{state: state} do
      # 960 samples * 2 bytes = 1920 bytes
      exact_buffer = %Buffer{
        payload: :binary.copy(<<0>>, 1920),
        pts: 0
      }
      
      {[buffer: {:output, output_buffers}], new_state} = 
        AudioChunker.handle_buffer(:input, exact_buffer, nil, state)
      
      assert length(output_buffers) == 1
      [chunk] = output_buffers
      assert byte_size(chunk.payload) == 1920
      assert chunk.pts == 0
      assert chunk.dts == 0
      assert new_state.accumulator == <<>>
      assert new_state.pts == 20_000_000  # 20ms in nanoseconds
    end

    test "accumulates undersized buffer", %{state: state} do
      # 512 samples * 2 bytes = 1024 bytes
      small_buffer = %Buffer{
        payload: :binary.copy(<<0>>, 1024),
        pts: 0
      }
      
      {[buffer: {:output, output_buffers}], new_state} = 
        AudioChunker.handle_buffer(:input, small_buffer, nil, state)
      
      assert output_buffers == []
      assert byte_size(new_state.accumulator) == 1024
      assert new_state.pts == 0  # No chunk output, so pts doesn't advance
    end

    test "outputs multiple chunks from oversized buffer", %{state: state} do
      # 2000 samples * 2 bytes = 4000 bytes (2 chunks + 160 bytes leftover)
      large_buffer = %Buffer{
        payload: :binary.copy(<<0>>, 4000),
        pts: 0
      }
      
      {[buffer: {:output, output_buffers}], new_state} = 
        AudioChunker.handle_buffer(:input, large_buffer, nil, state)
      
      assert length(output_buffers) == 2
      
      [chunk1, chunk2] = output_buffers
      assert byte_size(chunk1.payload) == 1920
      assert chunk1.pts == 0
      assert byte_size(chunk2.payload) == 1920
      assert chunk2.pts == 20_000_000
      
      assert byte_size(new_state.accumulator) == 160  # 80 samples leftover
      assert new_state.pts == 40_000_000  # 40ms
    end

    test "handles multiple small buffers that accumulate to chunks", %{state: state} do
      # First buffer: 512 samples * 2 bytes = 1024 bytes
      buffer1 = %Buffer{payload: :binary.copy(<<1>>, 1024), pts: 0}
      {[buffer: {:output, out1}], state1} = 
        AudioChunker.handle_buffer(:input, buffer1, nil, state)
      assert out1 == []
      
      # Second buffer: 512 samples * 2 bytes = 1024 bytes
      # Total: 1024 samples > 960, so outputs 1 chunk
      buffer2 = %Buffer{payload: :binary.copy(<<2>>, 1024), pts: nil}
      {[buffer: {:output, out2}], state2} = 
        AudioChunker.handle_buffer(:input, buffer2, nil, state1)
      assert length(out2) == 1
      [chunk] = out2
      assert byte_size(chunk.payload) == 1920
      assert chunk.pts == 0
      assert byte_size(state2.accumulator) == 128  # 64 samples leftover
      
      # Third buffer: 900 samples * 2 bytes = 1800 bytes
      # Total with leftover: 964 samples > 960, so outputs 1 chunk
      buffer3 = %Buffer{payload: :binary.copy(<<3>>, 1800), pts: nil}
      {[buffer: {:output, out3}], state3} = 
        AudioChunker.handle_buffer(:input, buffer3, nil, state2)
      assert length(out3) == 1
      [chunk2] = out3
      assert byte_size(chunk2.payload) == 1920
      assert chunk2.pts == 20_000_000
      assert byte_size(state3.accumulator) == 8  # 4 samples leftover
    end

    test "pads final partial chunk on end_of_stream", %{state: state} do
      # Add partial buffer
      partial_buffer = %Buffer{payload: :binary.copy(<<1>>, 1000), pts: 0}
      {[buffer: {:output, []}], state_with_data} = 
        AudioChunker.handle_buffer(:input, partial_buffer, nil, state)
      
      {actions, _final_state} = 
        AudioChunker.handle_end_of_stream(:input, nil, state_with_data)
      
      assert [buffer: {:output, last_buffer}, end_of_stream: :output] = actions
      assert byte_size(last_buffer.payload) == 1920  # Padded to full chunk size
      assert last_buffer.pts == 0
    end
  end

  describe "G.711 chunking with chunk_duration_ms" do
    setup do
      # Setup for G.711 at 8kHz with 20ms chunks (160 samples)
      opts = %{
        chunk_samples: nil,
        chunk_duration_ms: 20,
        sample_rate: 8000
      }
      
      {[], initial_state} = AudioChunker.handle_init(nil, opts)
      
      stream_format = %G711{encoding: :PCMA}
      
      {[stream_format: {:output, ^stream_format}], state} = 
        AudioChunker.handle_stream_format(:input, stream_format, nil, initial_state)
      
      %{state: state, stream_format: stream_format}
    end

    test "chunks G.711 into 160-byte packets for 20ms RTP", %{state: state} do
      # Exact 160 bytes (20ms of G.711 at 8kHz)
      exact_buffer = %Buffer{
        payload: :binary.copy(<<0>>, 160),
        pts: 0
      }
      
      {[buffer: {:output, output_buffers}], new_state} = 
        AudioChunker.handle_buffer(:input, exact_buffer, nil, state)
      
      assert length(output_buffers) == 1
      [chunk] = output_buffers
      assert byte_size(chunk.payload) == 160
      assert chunk.pts == 0
      assert new_state.pts == 20_000_000  # 20ms
    end

    test "accumulates and chunks G.711 data correctly", %{state: state} do
      # 400 bytes = 2.5 chunks (2 complete + 80 bytes leftover)
      large_buffer = %Buffer{
        payload: :binary.copy(<<0>>, 400),
        pts: 0
      }
      
      {[buffer: {:output, output_buffers}], new_state} = 
        AudioChunker.handle_buffer(:input, large_buffer, nil, state)
      
      assert length(output_buffers) == 2
      
      [chunk1, chunk2] = output_buffers
      assert byte_size(chunk1.payload) == 160
      assert chunk1.pts == 0
      assert byte_size(chunk2.payload) == 160
      assert chunk2.pts == 20_000_000
      
      assert byte_size(new_state.accumulator) == 80  # Half a chunk leftover
      assert new_state.pts == 40_000_000
    end
  end

  describe "raw audio chunking with chunk_duration_ms" do
    setup do
      # Setup for 48kHz stereo audio with 10ms chunks
      opts = %{
        chunk_samples: nil,
        chunk_duration_ms: 10,
        sample_rate: 48000
      }
      
      {[], initial_state} = AudioChunker.handle_init(nil, opts)
      
      stream_format = %RawAudio{
        sample_format: :s16le,
        sample_rate: 48000,
        channels: 2
      }
      
      {[stream_format: {:output, ^stream_format}], state} = 
        AudioChunker.handle_stream_format(:input, stream_format, nil, initial_state)
      
      %{state: state, stream_format: stream_format}
    end

    test "calculates correct chunk size for duration-based raw audio", %{state: state} do
      # 10ms at 48kHz = 480 samples
      # 480 samples * 2 channels * 2 bytes = 1920 bytes
      assert state.bytes_per_chunk == 1920
      assert state.chunk_duration_ns == 10_000_000  # 10ms
    end

    test "chunks stereo audio with duration-based config", %{state: state} do
      # Exact chunk size
      exact_buffer = %Buffer{
        payload: :binary.copy(<<0>>, 1920),
        pts: 0
      }
      
      {[buffer: {:output, output_buffers}], new_state} = 
        AudioChunker.handle_buffer(:input, exact_buffer, nil, state)
      
      assert length(output_buffers) == 1
      [chunk] = output_buffers
      assert byte_size(chunk.payload) == 1920
      assert chunk.pts == 0
      assert new_state.pts == 10_000_000  # 10ms
    end
  end

  describe "timestamp continuity" do
    setup do
      opts = %{
        chunk_samples: 960,
        chunk_duration_ms: nil,
        sample_rate: nil
      }
      
      {[], initial_state} = AudioChunker.handle_init(nil, opts)
      
      stream_format = %RawAudio{
        sample_format: :s16le,
        sample_rate: 48000,
        channels: 1
      }
      
      {[stream_format: {:output, ^stream_format}], state} = 
        AudioChunker.handle_stream_format(:input, stream_format, nil, initial_state)
      
      %{state: state}
    end

    test "maintains continuous timestamps across multiple buffers", %{state: state} do
      # Process several buffers and verify timestamp continuity
      buffers = [
        %Buffer{payload: :binary.copy(<<0>>, 1024), pts: 0},     # 512 samples
        %Buffer{payload: :binary.copy(<<0>>, 2048), pts: nil},   # 1024 samples (outputs 1 chunk)
        %Buffer{payload: :binary.copy(<<0>>, 512), pts: nil},    # 256 samples  
        %Buffer{payload: :binary.copy(<<0>>, 1536), pts: nil},   # 768 samples (outputs 1 chunk)
        %Buffer{payload: :binary.copy(<<0>>, 2000), pts: nil}    # 1000 samples (outputs 1 chunk)
      ]
      
      {all_outputs, _final_state} = 
        Enum.reduce(buffers, {[], state}, fn buffer, {outputs_acc, state_acc} ->
          {[buffer: {:output, new_outputs}], new_state} = 
            AudioChunker.handle_buffer(:input, buffer, nil, state_acc)
          {outputs_acc ++ new_outputs, new_state}
        end)
      
      # Should have exactly 3 chunks output
      assert length(all_outputs) == 3
      
      # Verify timestamps are continuous
      [chunk1, chunk2, chunk3] = all_outputs
      assert chunk1.pts == 0
      assert chunk2.pts == 20_000_000
      assert chunk3.pts == 40_000_000
    end
  end

  describe "integration test with pipeline" do
    test "works in a real pipeline with raw audio" do
      import Membrane.ChildrenSpec
      
      pipeline = Pipeline.start_link_supervised!(
        spec: [
          child(:source, %Membrane.Testing.Source{
            output: [
              %Buffer{payload: :binary.copy(<<0>>, 1024), pts: 0},
              %Buffer{payload: :binary.copy(<<0>>, 2048), pts: Time.milliseconds(10)},
              %Buffer{payload: :binary.copy(<<0>>, 1920), pts: Time.milliseconds(30)}
            ],
            stream_format: %RawAudio{
              sample_format: :s16le,
              sample_rate: 48000,
              channels: 1
            }
          })
          |> child(:chunker, %AudioChunker{
            chunk_samples: 960
          })
          |> child(:sink, Membrane.Testing.Sink)
        ]
      )
      
      assert_sink_stream_format(pipeline, :sink, %RawAudio{
        sample_format: :s16le,
        sample_rate: 48000,
        channels: 1
      })
      
      # Should receive 2 complete chunks (960 samples each)
      assert_sink_buffer(pipeline, :sink, %Buffer{payload: payload1, pts: 0})
      assert byte_size(payload1) == 1920
      
      assert_sink_buffer(pipeline, :sink, %Buffer{payload: payload2, pts: 20_000_000})
      assert byte_size(payload2) == 1920
      
      Pipeline.terminate(pipeline)
    end

    test "works in a real pipeline with G.711" do
      import Membrane.ChildrenSpec
      
      pipeline = Pipeline.start_link_supervised!(
        spec: [
          child(:source, %Membrane.Testing.Source{
            output: [
              %Buffer{payload: :binary.copy(<<0>>, 100), pts: 0},
              %Buffer{payload: :binary.copy(<<0>>, 200), pts: Time.milliseconds(12)},
              %Buffer{payload: :binary.copy(<<0>>, 180), pts: Time.milliseconds(37)}
            ],
            stream_format: %G711{encoding: :PCMA}
          })
          |> child(:chunker, %AudioChunker{
            chunk_duration_ms: 20,
            sample_rate: 8000
          })
          |> child(:sink, Membrane.Testing.Sink)
        ]
      )
      
      assert_sink_stream_format(pipeline, :sink, %G711{encoding: :PCMA})
      
      # Should receive 3 complete 160-byte chunks
      assert_sink_buffer(pipeline, :sink, %Buffer{payload: payload1, pts: 0})
      assert byte_size(payload1) == 160
      
      assert_sink_buffer(pipeline, :sink, %Buffer{payload: payload2, pts: 20_000_000})
      assert byte_size(payload2) == 160
      
      assert_sink_buffer(pipeline, :sink, %Buffer{payload: payload3, pts: 40_000_000})
      assert byte_size(payload3) == 160
      
      Pipeline.terminate(pipeline)
    end
  end
end