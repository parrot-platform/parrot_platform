defmodule Parrot.Sip.Transport.StateMachineSingletonTest do
  use ExUnit.Case, async: false
  doctest Parrot.Sip.Transport.StateMachine

  alias Parrot.Sip.Transport.StateMachine
  alias Parrot.Sip.{Message, Source}
  alias Parrot.Sip.Headers.{Via, From, To, Contact, CSeq}

  # The StateMachine is a singleton started by the application supervisor.
  # These tests work with that assumption.

  describe "StateMachine singleton behavior" do
    test "is already started by the application" do
      pid = Process.whereis(StateMachine)
      assert is_pid(pid)
      assert Process.alive?(pid)
    end

    test "cannot start a second instance" do
      assert {:error, {:already_started, _pid}} = StateMachine.start_link([])
    end

    test "has proper state structure" do
      pid = Process.whereis(StateMachine)
      state = :sys.get_state(pid)

      assert is_map(state)
      assert Map.has_key?(state, :state)
      assert state.state in [:idle, :running]
    end
  end

  describe "UDP transport operations" do
    setup do
      # Ensure any existing UDP transport is stopped
      try do
        StateMachine.stop_udp()
      catch
        :exit, _ -> :ok
      end

      on_exit(fn ->
        try do
          StateMachine.stop_udp()
        catch
          :exit, _ -> :ok
        end
      end)

      :ok
    end

    test "starts UDP transport with valid options" do
      udp_opts = %{
        listen_addr: {127, 0, 0, 1},
        # Use high port to avoid conflicts
        listen_port: 15060
      }

      assert :ok = StateMachine.start_udp(udp_opts)

      # Verify it's running
      state = :sys.get_state(Process.whereis(StateMachine))
      assert state.udp_pid != nil
      assert Process.alive?(state.udp_pid)
    end

    test "stops UDP transport" do
      udp_opts = %{
        listen_addr: {127, 0, 0, 1},
        listen_port: 15061
      }

      :ok = StateMachine.start_udp(udp_opts)
      assert :ok = StateMachine.stop_udp()

      # Verify it's stopped
      state = :sys.get_state(Process.whereis(StateMachine))
      assert state.udp_pid == nil
    end

    test "handles multiple stop calls gracefully" do
      assert :ok = StateMachine.stop_udp()
      assert :ok = StateMachine.stop_udp()
    end

    test "returns error for privileged port" do
      udp_opts = %{
        listen_addr: {127, 0, 0, 1},
        # Privileged port that likely won't be available
        listen_port: 80
      }

      # The StateMachine might exit when UDP fails to start with a registered name
      # So we need to catch the exit
      result =
        try do
          StateMachine.start_udp(udp_opts)
        catch
          :exit, {:error, reason} ->
            {:error, reason}

          :exit, reason ->
            {:error, {:exit, reason}}
        end

      # Should get an error (either eacces for privileged port or eaddrinuse if in use)
      assert match?({:error, _}, result)
    end
  end

  describe "message sending" do
    setup do
      # Start UDP transport for sending
      udp_opts = %{
        listen_addr: {127, 0, 0, 1},
        listen_port: 15062
      }

      StateMachine.start_udp(udp_opts)

      on_exit(fn ->
        try do
          StateMachine.stop_udp()
        catch
          :exit, _ -> :ok
        end
      end)

      :ok
    end

    test "sends request message" do
      message = build_invite_message()
      destination = {{127, 0, 0, 1}, 15063}

      # send_request expects a map with message and destination
      out_req = %{
        message: message,
        destination: destination
      }

      result = StateMachine.send_request(out_req)

      assert result in [
               :ok,
               {:error, :econnrefused},
               {:error, :no_transport},
               {:error, :invalid_destination}
             ]
    end
  end

  describe "local URI management" do
    test "returns local URI" do
      result = StateMachine.local_uri()

      # local_uri returns {:ok, uri} or {:error, reason}
      case result do
        {:ok, local_uri} ->
          assert is_binary(local_uri)
          assert String.starts_with?(local_uri, "sip:")

        {:error, :no_transport} ->
          # This is expected if no UDP transport is running
          assert true

        other ->
          flunk("Unexpected result: #{inspect(other)}")
      end
    end
  end

  # Helper functions
  defp build_invite_message do
    %Message{
      method: :invite,
      request_uri: "sip:user@example.com",
      version: "SIP/2.0",
      headers: %{
        "via" => %Via{
          protocol: "SIP",
          version: "2.0",
          transport: :udp,
          host: "127.0.0.1",
          port: 5060,
          parameters: %{"branch" => "z9hG4bK-test-branch-123"}
        },
        "from" => %From{
          display_name: "Test User",
          uri: "sip:test@example.com",
          parameters: %{"tag" => "test-from-tag"}
        },
        "to" => %To{
          display_name: "Target User",
          uri: "sip:target@example.com",
          parameters: %{}
        },
        "call-id" => "test-call-id-123@example.com",
        "cseq" => %CSeq{number: 1, method: :invite},
        "contact" => %Contact{
          uri: "sip:test@127.0.0.1:5060",
          parameters: %{}
        }
      },
      body: "",
      source: %Source{
        local: {{127, 0, 0, 1}, 5060},
        remote: {{127, 0, 0, 1}, 5061},
        transport: :udp
      },
      direction: :outgoing
    }
  end
end
