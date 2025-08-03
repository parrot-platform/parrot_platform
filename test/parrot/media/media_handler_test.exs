defmodule Parrot.Media.MediaHandlerTest do
  use ExUnit.Case, async: true

  # Define a test handler for testing the behaviour
  defmodule MediaTestHandler do
    @behaviour Parrot.MediaHandler

    @impl true
    def init(args) do
      {:ok, args}
    end

    @impl true
    def handle_session_start(session_id, _opts, state) do
      case state[:on_session_start] do
        :error -> {:error, :test_error, state}
        _ -> {:ok, Map.put(state, :session_id, session_id)}
      end
    end

    @impl true
    def handle_session_stop(session_id, reason, state) do
      {:ok, Map.put(state, :stopped_with, {session_id, reason})}
    end

    @impl true
    def handle_offer(sdp, direction, state) do
      case state[:on_offer] do
        :modify -> {:ok, "modified_" <> sdp, state}
        :reject -> {:reject, :bad_offer, state}
        _ -> {:noreply, Map.put(state, :last_offer, {sdp, direction})}
      end
    end

    @impl true
    def handle_answer(sdp, direction, state) do
      case state[:on_answer] do
        :modify -> {:ok, "modified_" <> sdp, state}
        :reject -> {:reject, :bad_answer, state}
        _ -> {:noreply, Map.put(state, :last_answer, {sdp, direction})}
      end
    end

    @impl true
    def handle_codec_negotiation(offered, supported, state) do
      case state[:codec_preference] do
        :error ->
          {:error, :no_common_codec, state}

        :list ->
          {:ok, [:opus, :pcmu], state}

        codec when is_atom(codec) and not is_nil(codec) ->
          {:ok, codec, state}

        _ ->
          # Default behavior - pick first common codec
          # Find first codec in offered that is also in supported
          codec = Enum.find(offered, fn c -> Enum.member?(supported, c) end)

          if codec do
            {:ok, codec, state}
          else
            {:error, :no_common_codec, state}
          end
      end
    end

    @impl true
    def handle_negotiation_complete(local_sdp, remote_sdp, selected_codec, state) do
      updated_state =
        Map.merge(state, %{
          local_sdp: local_sdp,
          remote_sdp: remote_sdp,
          selected_codec: selected_codec,
          negotiation_complete: true
        })

      case state[:on_negotiation_complete] do
        :error -> {:error, :negotiation_failed, updated_state}
        _ -> {:ok, updated_state}
      end
    end

    @impl true
    def handle_stream_start(_session_id, _direction, state) do
      case state[:on_stream_start] do
        {:play, file} -> {{:play, file}, Map.put(state, :stream_started, true)}
        actions when is_list(actions) -> {actions, Map.put(state, :stream_started, true)}
        action -> {action, Map.put(state, :stream_started, true)}
      end
    end

    @impl true
    def handle_stream_stop(session_id, reason, state) do
      {:ok, Map.put(state, :stream_stopped, {session_id, reason})}
    end

    @impl true
    def handle_stream_error(_session_id, error, state) do
      case state[:on_stream_error] do
        :retry -> {:retry, Map.put(state, :last_error, error)}
        :stop -> {:stop, error, state}
        _ -> {:continue, Map.put(state, :last_error, error)}
      end
    end

    @impl true
    def handle_play_complete(file_path, state) do
      queue = Map.get(state, :play_queue, [])

      case queue do
        [next | rest] ->
          {{:play, next}, Map.merge(state, %{play_queue: rest, last_played: file_path})}

        [] ->
          {:noreply, Map.put(state, :last_played, file_path)}
      end
    end

    @impl true
    def handle_media_request(request, state) do
      case request do
        {:custom_action, action} -> {action, state}
        :get_state -> {{:state, state}, state}
        _ -> {:error, :unknown_request, state}
      end
    end
  end

  describe "init/1" do
    test "initializes handler state" do
      assert {:ok, %{test: true}} = MediaTestHandler.init(%{test: true})
    end
  end

  describe "handle_session_start/3" do
    test "handles successful session start" do
      state = %{}
      assert {:ok, new_state} = MediaTestHandler.handle_session_start("session_1", [], state)
      assert new_state.session_id == "session_1"
    end

    test "handles session start error" do
      state = %{on_session_start: :error}

      assert {:error, :test_error, ^state} =
               MediaTestHandler.handle_session_start("session_1", [], state)
    end
  end

  describe "handle_offer/3" do
    test "accepts offer without modification" do
      state = %{}
      sdp = "v=0\r\no=- 123 456 IN IP4 192.168.1.1\r\n"

      assert {:noreply, new_state} = MediaTestHandler.handle_offer(sdp, :inbound, state)
      assert new_state.last_offer == {sdp, :inbound}
    end

    test "modifies SDP offer" do
      state = %{on_offer: :modify}
      sdp = "v=0\r\n"

      assert {:ok, modified_sdp, ^state} = MediaTestHandler.handle_offer(sdp, :inbound, state)
      assert modified_sdp == "modified_v=0\r\n"
    end

    test "rejects offer" do
      state = %{on_offer: :reject}

      assert {:reject, :bad_offer, ^state} =
               MediaTestHandler.handle_offer("v=0\r\n", :inbound, state)
    end
  end

  describe "handle_codec_negotiation/3" do
    test "selects opus when available in both lists" do
      state = %{codec_preference: :opus}
      offered = [:pcmu, :opus, :pcma]
      supported = [:opus, :pcmu, :pcma]

      assert {:ok, :opus, ^state} =
               MediaTestHandler.handle_codec_negotiation(offered, supported, state)
    end

    test "selects first common codec when no preference" do
      state = %{}
      offered = [:pcmu, :pcma, :opus]
      supported = [:opus, :pcma]

      assert {:ok, :pcma, ^state} =
               MediaTestHandler.handle_codec_negotiation(offered, supported, state)
    end

    test "returns error when no common codec" do
      state = %{}
      offered = [:g729, :ilbc]
      supported = [:opus, :pcmu, :pcma]

      assert {:error, :no_common_codec, ^state} =
               MediaTestHandler.handle_codec_negotiation(offered, supported, state)
    end

    test "returns codec list when configured" do
      state = %{codec_preference: :list}
      offered = [:opus, :pcmu, :pcma]
      supported = [:opus, :pcmu, :pcma]

      assert {:ok, [:opus, :pcmu], ^state} =
               MediaTestHandler.handle_codec_negotiation(offered, supported, state)
    end
  end

  describe "handle_stream_start/3" do
    test "returns play action" do
      state = %{on_stream_start: {:play, "/audio/welcome.wav"}}

      assert {{:play, "/audio/welcome.wav"}, new_state} =
               MediaTestHandler.handle_stream_start("session_1", :outbound, state)

      assert new_state.stream_started == true
    end

    test "returns multiple actions" do
      state = %{on_stream_start: [{:play, "/audio/1.wav"}, :pause]}

      assert {actions, new_state} =
               MediaTestHandler.handle_stream_start("session_1", :inbound, state)

      assert actions == [{:play, "/audio/1.wav"}, :pause]
      assert new_state.stream_started == true
    end

    test "returns noreply" do
      state = %{on_stream_start: :noreply}

      assert {:noreply, new_state} =
               MediaTestHandler.handle_stream_start("session_1", :bidirectional, state)

      assert new_state.stream_started == true
    end
  end

  describe "handle_play_complete/2" do
    test "plays next file from queue" do
      state = %{play_queue: ["/audio/2.wav", "/audio/3.wav"]}

      assert {{:play, "/audio/2.wav"}, new_state} =
               MediaTestHandler.handle_play_complete("/audio/1.wav", state)

      assert new_state.play_queue == ["/audio/3.wav"]
      assert new_state.last_played == "/audio/1.wav"
    end

    test "returns noreply when queue is empty" do
      state = %{play_queue: []}

      assert {:noreply, new_state} = MediaTestHandler.handle_play_complete("/audio/1.wav", state)
      assert new_state.last_played == "/audio/1.wav"
    end
  end

  describe "handle_media_request/2" do
    test "handles custom actions" do
      state = %{}

      assert {{:play, "/test.wav"}, ^state} =
               MediaTestHandler.handle_media_request(
                 {:custom_action, {:play, "/test.wav"}},
                 state
               )
    end

    test "returns error for unknown requests" do
      state = %{}

      assert {:error, :unknown_request, ^state} =
               MediaTestHandler.handle_media_request(:unknown, state)
    end
  end
end
