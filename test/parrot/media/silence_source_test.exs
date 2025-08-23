defmodule Parrot.Media.SilenceSourceTest do
  use ExUnit.Case, async: false

  @moduletag :slow

  import Membrane.ChildrenSpec

  alias Parrot.Media.SilenceSource
  alias Membrane.Testing
  alias Membrane.Buffer
  alias Membrane.RawAudio

  describe "SilenceSource" do
    test "generates silence frames at specified interval" do
      import Membrane.Testing.Assertions

      pipeline =
        Testing.Pipeline.start_link_supervised!(
          spec:
            child(:source, %SilenceSource{
              interval: 20,
              sample_rate: 8000,
              channels: 1
            })
            |> child(:sink, Testing.Sink)
        )

      # Let it run for approximately 100ms
      assert_sink_buffer(pipeline, :sink, buffer, 150)

      # Should receive a buffer with silence data
      assert %Buffer{payload: payload} = buffer

      # At 8000 Hz, 20ms = 160 samples
      # Each sample is 2 bytes (s16le), so 320 bytes total
      assert byte_size(payload) == 320

      # Verify it's all zeros (silence)
      assert payload == <<0::size(320)-unit(8)>>

      # Should receive more buffers at regular intervals
      assert_sink_buffer(pipeline, :sink, _buffer2, 50)
      assert_sink_buffer(pipeline, :sink, _buffer3, 50)

      Testing.Pipeline.terminate(pipeline, force?: true)
    end

    test "sends correct stream format" do
      import Membrane.Testing.Assertions

      pipeline =
        Testing.Pipeline.start_link_supervised!(
          spec:
            child(:source, %SilenceSource{
              interval: 20,
              sample_rate: 16000,
              channels: 2
            })
            |> child(:sink, Testing.Sink)
        )

      # Should receive stream format first
      assert_sink_stream_format(pipeline, :sink, stream_format, 100)

      assert %RawAudio{
               sample_rate: 16000,
               channels: 2,
               sample_format: :s16le
             } = stream_format

      Testing.Pipeline.terminate(pipeline, force?: true)
    end

    test "generates buffers continuously until stopped" do
      import Membrane.Testing.Assertions

      pipeline =
        Testing.Pipeline.start_link_supervised!(
          spec:
            child(:source, %SilenceSource{interval: 10})
            |> child(:sink, Testing.Sink)
        )

      # Verify it generates multiple buffers continuously
      assert_sink_buffer(pipeline, :sink, _buffer1, 100)
      assert_sink_buffer(pipeline, :sink, _buffer2, 50)
      assert_sink_buffer(pipeline, :sink, _buffer3, 50)
      assert_sink_buffer(pipeline, :sink, _buffer4, 50)

      # Clean termination
      Testing.Pipeline.terminate(pipeline, force?: true)
    end

    test "generates correct frame size for different configurations" do
      import Membrane.Testing.Assertions

      # Test with 48kHz, 2 channels, 10ms intervals
      pipeline =
        Testing.Pipeline.start_link_supervised!(
          spec:
            child(:source, %SilenceSource{
              interval: 10,
              sample_rate: 48000,
              channels: 2
            })
            |> child(:sink, Testing.Sink)
        )

      assert_sink_buffer(pipeline, :sink, buffer, 100)

      # 48000 Hz, 10ms = 480 samples
      # 2 channels, 2 bytes per sample = 1920 bytes
      assert byte_size(buffer.payload) == 1920

      Testing.Pipeline.terminate(pipeline, force?: true)
    end

    test "maintains consistent PTS timing" do
      import Membrane.Testing.Assertions
      import Membrane.Time

      pipeline =
        Testing.Pipeline.start_link_supervised!(
          spec:
            child(:source, %SilenceSource{
              interval: 20,
              sample_rate: 8000,
              channels: 1
            })
            |> child(:sink, Testing.Sink)
        )

      # Collect several buffers
      assert_sink_buffer(pipeline, :sink, buffer1, 100)
      assert_sink_buffer(pipeline, :sink, buffer2, 50)
      assert_sink_buffer(pipeline, :sink, buffer3, 50)

      # Check PTS values are increasing correctly
      assert buffer1.pts == 0
      assert buffer2.pts == milliseconds(20)
      assert buffer3.pts == milliseconds(40)

      # Check duration metadata
      assert buffer1.metadata.duration == milliseconds(20)
      assert buffer2.metadata.duration == milliseconds(20)
      assert buffer3.metadata.duration == milliseconds(20)

      Testing.Pipeline.terminate(pipeline, force?: true)
    end
  end
end
