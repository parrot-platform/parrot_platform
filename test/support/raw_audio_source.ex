defmodule Parrot.Test.RawAudioSource do
  @moduledoc """
  A test source that generates RawAudio buffers for testing audio elements.
  """
  use Membrane.Source

  alias Membrane.{Buffer, RawAudio}

  def_options(
    stream_format: [
      spec: RawAudio.t(),
      default: %RawAudio{
        sample_rate: 8000,
        channels: 1,
        sample_format: :s16le
      }
    ],
    buffers: [
      spec: [Buffer.t()],
      default: []
    ]
  )

  def_output_pad(:output,
    flow_control: :manual,
    accepted_format: RawAudio,
    availability: :always
  )

  @impl true
  def handle_init(_ctx, opts) do
    {[], %{stream_format: opts.stream_format, buffers: opts.buffers, demand: 0}}
  end

  @impl true
  def handle_playing(_ctx, state) do
    {[stream_format: {:output, state.stream_format}], state}
  end

  @impl true
  def handle_demand(:output, size, :buffers, _ctx, state) do
    new_demand = state.demand + size
    {actions, remaining_buffers} = send_buffers(state.buffers, new_demand)

    new_state = %{
      state
      | buffers: remaining_buffers,
        demand: if(remaining_buffers == [], do: new_demand, else: 0)
    }

    if remaining_buffers == [] and actions == [] do
      {[end_of_stream: :output], new_state}
    else
      {actions, new_state}
    end
  end

  @impl true
  def handle_parent_notification({:buffer, buffer}, _ctx, state) do
    if state.demand > 0 do
      {[buffer: {:output, buffer}], %{state | demand: state.demand - 1}}
    else
      {[], %{state | buffers: state.buffers ++ [buffer]}}
    end
  end

  defp send_buffers([], _demand), do: {[], []}
  defp send_buffers(buffers, 0), do: {[], buffers}

  defp send_buffers([buffer | rest], demand) do
    {actions, remaining} = send_buffers(rest, demand - 1)
    {[buffer: {:output, buffer}] ++ actions, remaining}
  end
end
