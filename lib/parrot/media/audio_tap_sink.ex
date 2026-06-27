defmodule Parrot.Media.AudioTapSink do
  @moduledoc """
  A Membrane sink that forwards each inbound audio buffer to a target process as
  `{:parrot_audio_frame, ssrc, pcm}`.

  Drop-in replacement for the discard-only `Membrane.Debug.Sink` on the *receive*
  path, so an application can tap the decoded remote-leg audio — e.g. stream it
  to a transcriber, recorder, or VAD — without owning the media pipeline.

  `Parrot.Media.MembraneAlawPipeline` wires this sink in automatically when the
  session's media handler implements `c:Parrot.MediaHandler.handle_audio_frame/3`;
  otherwise it keeps the original `Membrane.Debug.Sink` (no behaviour change).
  """
  use Membrane.Sink

  alias Membrane.Buffer

  def_input_pad(:input, accepted_format: _any, flow_control: :auto)

  def_options(
    target: [
      spec: pid(),
      description: "Process that receives `{:parrot_audio_frame, ssrc, pcm}` messages."
    ],
    ssrc: [
      spec: term(),
      default: nil,
      description: "SSRC of the inbound RTP stream this sink drains."
    ]
  )

  @impl true
  def handle_init(_ctx, opts) do
    {[], %{target: opts.target, ssrc: opts.ssrc}}
  end

  @impl true
  def handle_buffer(:input, %Buffer{payload: payload}, _ctx, state) do
    send(state.target, {:parrot_audio_frame, state.ssrc, payload})
    {[], state}
  end
end
