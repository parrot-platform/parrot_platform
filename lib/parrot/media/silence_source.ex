defmodule Parrot.Media.SilenceSource do
  @moduledoc """
  Membrane element that generates silence frames for RTP transmission.

  This is useful for scenarios where we need to maintain an RTP stream
  but don't have actual audio to send (e.g., hold scenarios, testing).
  """

  use Membrane.Source

  alias Membrane.{Buffer, RawAudio}
  alias Membrane.Time

  @sample_rate 8000
  @channels 1
  @sample_format :s16le
  @frame_duration_ms 20
  @bytes_per_sample 2

  def_output_pad(:output,
    flow_control: :push,
    accepted_format: RawAudio
  )

  def_options(
    interval: [
      spec: pos_integer(),
      default: @frame_duration_ms,
      description: "Interval in milliseconds between silence frames"
    ],
    sample_rate: [
      spec: pos_integer(),
      default: @sample_rate,
      description: "Sample rate for the silence audio"
    ],
    channels: [
      spec: pos_integer(),
      default: @channels,
      description: "Number of audio channels"
    ]
  )

  @impl true
  def handle_init(_ctx, opts) do
    state = %{
      interval: opts.interval,
      sample_rate: opts.sample_rate,
      channels: opts.channels,
      timer_ref: nil,
      pts: 0,
      frame_duration: Time.milliseconds(opts.interval)
    }

    {[], state}
  end

  @impl true
  def handle_playing(_ctx, state) do
    # Start the timer when we transition to playing
    timer_ref = Process.send_after(self(), :send_frame, 0)

    stream_format = %RawAudio{
      sample_rate: state.sample_rate,
      channels: state.channels,
      sample_format: @sample_format
    }

    {[stream_format: {:output, stream_format}], %{state | timer_ref: timer_ref}}
  end

  @impl true
  def handle_info(:send_frame, _ctx, state) do
    # Generate silence buffer
    silence_data = generate_silence_frame(state)

    buffer = %Buffer{
      payload: silence_data,
      pts: state.pts,
      dts: state.pts,
      metadata: %{
        duration: state.frame_duration
      }
    }

    # Schedule next frame
    timer_ref = Process.send_after(self(), :send_frame, state.interval)

    # Update PTS for next frame
    new_state = %{state | timer_ref: timer_ref, pts: state.pts + state.frame_duration}

    {[buffer: {:output, buffer}], new_state}
  end

  @impl true
  def handle_terminate_request(_ctx, state) do
    # Cancel timer if it exists
    if state.timer_ref do
      Process.cancel_timer(state.timer_ref)
    end

    {[], %{state | timer_ref: nil}}
  end

  defp generate_silence_frame(state) do
    # Calculate frame size based on current settings
    samples_per_frame = div(state.sample_rate * state.interval, 1000)
    frame_size = samples_per_frame * @bytes_per_sample * state.channels

    # Generate silence (zeros)
    <<0::size(frame_size)-unit(8)>>
  end
end
