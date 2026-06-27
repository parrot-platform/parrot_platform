defmodule Parrot.Media.AudioTapSinkTest do
  use ExUnit.Case, async: true

  alias Membrane.Buffer
  alias Parrot.Media.AudioTapSink

  test "handle_init keeps the target pid and ssrc" do
    opts = %AudioTapSink{target: self(), ssrc: 42}
    assert {[], state} = AudioTapSink.handle_init(%{}, opts)
    assert state.target == self()
    assert state.ssrc == 42
  end

  test "handle_buffer forwards the payload to the target as {:parrot_audio_frame, ssrc, pcm}" do
    state = %{target: self(), ssrc: 7}
    buffer = %Buffer{payload: <<1, 2, 3, 4>>}

    assert {[], ^state} = AudioTapSink.handle_buffer(:input, buffer, %{}, state)
    assert_receive {:parrot_audio_frame, 7, <<1, 2, 3, 4>>}
  end

  test "each buffer produces its own frame message (order preserved)" do
    state = %{target: self(), ssrc: :leg_a}

    AudioTapSink.handle_buffer(:input, %Buffer{payload: <<1>>}, %{}, state)
    AudioTapSink.handle_buffer(:input, %Buffer{payload: <<2>>}, %{}, state)

    assert_receive {:parrot_audio_frame, :leg_a, <<1>>}
    assert_receive {:parrot_audio_frame, :leg_a, <<2>>}
  end
end
