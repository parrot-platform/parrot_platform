defmodule Parrot.Media.AudioChunkerIntegrationTest do
  @moduledoc """
  Integration tests to verify AudioChunker works correctly with both
  OPUS and PCMA codecs in the PortAudioPipeline context.
  """
  use ExUnit.Case, async: true

  alias Parrot.Media.AudioChunker
  alias Membrane.{Buffer, RawAudio, G711}

  describe "OPUS codec compatibility" do
    test "chunks raw audio for OPUS encoder (48kHz, 960 samples)" do
      # Initialize chunker for OPUS
      {[], state} =
        AudioChunker.handle_init(nil, %{
          # OPUS needs exactly 960 samples at 48kHz for 20ms
          chunk_samples: 960,
          chunk_duration_ms: nil,
          sample_rate: nil
        })

      # Set up stream format for 48kHz mono audio (typical for OPUS)
      stream_format = %RawAudio{
        sample_format: :s16le,
        sample_rate: 48000,
        channels: 1
      }

      {[stream_format: {:output, ^stream_format}], state} =
        AudioChunker.handle_stream_format(:input, stream_format, nil, state)

      # Simulate PortAudio delivering varying buffer sizes
      # Random sizes from PortAudio
      buffer_sizes = [512, 1024, 753, 1200, 800]

      accumulated_output = []

      final_state =
        Enum.reduce(buffer_sizes, {accumulated_output, state}, fn size, {output_acc, state_acc} ->
          # Create buffer of specified size in samples (2 bytes per sample for s16le)
          buffer = %Buffer{
            payload: :binary.copy(<<0>>, size * 2),
            pts: nil
          }

          {[buffer: {:output, chunks}], new_state} =
            AudioChunker.handle_buffer(:input, buffer, nil, state_acc)

          {output_acc ++ chunks, new_state}
        end)
        |> elem(1)

      # Total samples: 512 + 1024 + 753 + 1200 + 800 = 4289 samples
      # Expected chunks: 4289 / 960 = 4 complete chunks with 329 samples leftover

      chunks =
        Enum.reduce(buffer_sizes, {[], state}, fn size, {chunks_acc, state_acc} ->
          buffer = %Buffer{
            payload: :binary.copy(<<0>>, size * 2),
            pts: nil
          }

          {[buffer: {:output, new_chunks}], new_state} =
            AudioChunker.handle_buffer(:input, buffer, nil, state_acc)

          {chunks_acc ++ new_chunks, new_state}
        end)
        |> elem(0)

      # Verify we got exactly 4 chunks
      assert length(chunks) == 4

      # Verify each chunk is exactly 960 samples (1920 bytes)
      Enum.each(chunks, fn chunk ->
        assert byte_size(chunk.payload) == 1920
      end)

      # Verify timestamps are properly spaced (20ms apart)
      assert Enum.at(chunks, 0).pts == 0
      assert Enum.at(chunks, 1).pts == 20_000_000
      assert Enum.at(chunks, 2).pts == 40_000_000
      assert Enum.at(chunks, 3).pts == 60_000_000

      # Verify leftover in accumulator
      # 4289 - (4 * 960) = 449 samples = 898 bytes
      assert byte_size(final_state.accumulator) == 898
    end
  end

  describe "PCMA codec compatibility" do
    test "chunks G.711 for PCMA RTP packets (8kHz, 20ms)" do
      # Initialize chunker for G.711/PCMA
      {[], state} =
        AudioChunker.handle_init(nil, %{
          chunk_samples: nil,
          # Standard RTP packet duration
          chunk_duration_ms: 20,
          # G.711 operates at 8kHz
          sample_rate: 8000
        })

      # Set up stream format for G.711 PCMA
      stream_format = %G711{encoding: :PCMA}

      {[stream_format: {:output, ^stream_format}], state} =
        AudioChunker.handle_stream_format(:input, stream_format, nil, state)

      # G.711 at 8kHz, 20ms = 160 samples = 160 bytes (1 byte per sample)
      assert state.bytes_per_chunk == 160
      assert state.chunk_duration_ns == 20_000_000

      # Simulate receiving G.711 encoded data in various sizes
      # Random sizes
      buffer_sizes = [100, 200, 150, 180, 90]

      chunks =
        Enum.reduce(buffer_sizes, {[], state}, fn size, {chunks_acc, state_acc} ->
          buffer = %Buffer{
            # G.711 silence pattern
            payload: :binary.copy(<<0xD5>>, size),
            pts: nil
          }

          {[buffer: {:output, new_chunks}], new_state} =
            AudioChunker.handle_buffer(:input, buffer, nil, state_acc)

          {chunks_acc ++ new_chunks, new_state}
        end)
        |> elem(0)

      # Total bytes: 100 + 200 + 150 + 180 + 90 = 720 bytes
      # Expected chunks: 720 / 160 = 4 complete chunks with 80 bytes leftover

      # Verify we got exactly 4 chunks
      assert length(chunks) == 4

      # Verify each chunk is exactly 160 bytes
      Enum.each(chunks, fn chunk ->
        assert byte_size(chunk.payload) == 160
      end)

      # Verify timestamps are properly spaced (20ms apart)
      assert Enum.at(chunks, 0).pts == 0
      assert Enum.at(chunks, 1).pts == 20_000_000
      assert Enum.at(chunks, 2).pts == 40_000_000
      assert Enum.at(chunks, 3).pts == 60_000_000
    end
  end

  describe "codec switching scenario" do
    test "can be reconfigured between OPUS and PCMA requirements" do
      # First, configure for OPUS
      {[], opus_state} =
        AudioChunker.handle_init(nil, %{
          chunk_samples: 960,
          chunk_duration_ms: nil,
          sample_rate: nil
        })

      opus_format = %RawAudio{
        sample_format: :s16le,
        sample_rate: 48000,
        channels: 1
      }

      {_, opus_state} = AudioChunker.handle_stream_format(:input, opus_format, nil, opus_state)
      # 960 samples * 2 bytes
      assert opus_state.bytes_per_chunk == 1920

      # Now configure a new instance for PCMA
      {[], pcma_state} =
        AudioChunker.handle_init(nil, %{
          chunk_samples: nil,
          chunk_duration_ms: 20,
          sample_rate: 8000
        })

      pcma_format = %G711{encoding: :PCMA}

      {_, pcma_state} = AudioChunker.handle_stream_format(:input, pcma_format, nil, pcma_state)
      # 160 samples * 1 byte
      assert pcma_state.bytes_per_chunk == 160

      # Both configurations are valid and independent
      assert opus_state.chunk_samples == 960
      assert pcma_state.chunk_duration_ms == 20
      assert pcma_state.sample_rate == 8000
    end
  end
end
