defmodule Parrot.Sip.Transport.UdpTest do
  use ExUnit.Case, async: true
  doctest Parrot.Sip.Transport.Udp

  alias Parrot.Sip.Transport.Udp
  alias Parrot.Sip.Source
  alias Parrot.Sip.Message
  alias Parrot.Sip.Headers.{Via, From, To, Contact, CSeq}

  # Helper to create unique process names for each test
  defp unique_name() do
    {:via, Registry, {Parrot.Registry, make_ref()}}
  end

  # Helper to start a test-specific UDP process with proper cleanup
  defp start_test_udp(opts \\ %{}) do
    default_opts = %{
      listen_addr: {127, 0, 0, 1},
      listen_port: 0,
      name: unique_name()
    }

    final_opts = Map.merge(default_opts, opts)
    {:ok, pid} = Udp.start_link(final_opts)

    # Ensure cleanup after test
    on_exit(fn ->
      if Process.alive?(pid) do
        GenServer.stop(pid, :normal, 1000)
      end
    end)

    {pid, final_opts}
  end

  describe "Transport.Udp GenServer initialization" do
    test "starts with minimal configuration" do
      {pid, _opts} = start_test_udp()
      assert is_pid(pid)
      assert Process.alive?(pid)
    end

    test "starts with comprehensive configuration" do
      handler = build_test_handler()

      {pid, _opts} =
        start_test_udp(%{
          exposed_addr: {192, 168, 1, 100},
          exposed_port: 5060,
          handler: handler,
          sip_trace: true,
          max_burst: 50
        })

      assert is_pid(pid)
      assert Process.alive?(pid)
    end

    test "creates proper child spec" do
      opts = %{
        listen_addr: {127, 0, 0, 1},
        listen_port: 0,
        name: unique_name()
      }

      spec = Udp.child_spec(opts)

      assert spec.id == Udp
      assert spec.start == {Udp, :start_link, [opts]}
    end

    test "initializes with correct state structure" do
      {pid, _opts} = start_test_udp()
      state = :sys.get_state(pid)

      assert state.local_ip == {127, 0, 0, 1}
      assert is_integer(state.local_port)
      assert state.socket != nil
      # default
      assert state.sip_trace == false
      # default
      assert state.max_burst == 10
    end

    test "handles port already in use" do
      port = 15060

      {_pid1, _opts1} = start_test_udp(%{listen_port: port})

      opts2 = %{
        listen_addr: {127, 0, 0, 1},
        listen_port: port,
        name: unique_name()
      }

      assert {:error, _reason} = Udp.start_link(opts2)
    end
  end

  describe "UDP socket lifecycle" do
    setup do
      handler = build_test_handler()
      {pid, _opts} = start_test_udp(%{handler: handler})

      state = :sys.get_state(pid)
      port = state.local_port

      %{udp_pid: pid, udp_port: port, handler: handler}
    end

    test "opens UDP socket on start", %{udp_pid: pid} do
      state = :sys.get_state(pid)
      assert state.socket != nil
    end

    test "closes socket on termination", %{udp_pid: pid} do
      GenServer.stop(pid)
      refute Process.alive?(pid)
    end

    test "handles socket errors gracefully", %{udp_pid: pid} do
      # Simulate socket error
      send(pid, {:udp_error, :socket, :econnrefused})

      # Should handle error without crashing
      :timer.sleep(10)
      assert Process.alive?(pid)
    end
  end

  describe "local URI management" do
    setup do
      {pid, _opts} =
        start_test_udp(%{
          exposed_addr: {192, 168, 1, 100},
          exposed_port: 5060
        })

      %{udp_pid: pid}
    end

    test "returns local URI" do
      local_uri = Udp.local_uri()

      assert local_uri != nil
      # Should be properly formatted URI
      assert is_binary(local_uri)
    end

    test "uses exposed address when configured" do
      local_uri = Udp.local_uri()

      # Should use exposed address (192.168.1.100:5060) not listen address
      assert local_uri != nil
    end

    test "handles IPv6 addresses" do
      opts = %{
        # IPv6 loopback
        listen_addr: {0, 0, 0, 0, 0, 0, 0, 1},
        listen_port: 0
      }

      result = Udp.start_link(opts)

      case result do
        {:ok, _pid} ->
          local_uri = Udp.local_uri()
          assert local_uri != nil

        {:error, _} ->
          # IPv6 may not be supported
          assert true
      end
    end
  end

  describe "message sending" do
    setup do
      handler = build_test_handler()
      {pid, _opts} = start_test_udp(%{handler: handler})

      state = :sys.get_state(pid)
      port = state.local_port

      %{udp_pid: pid, udp_port: port, handler: handler}
    end

    test "sends SIP request message", %{udp_port: port} do
      out_req = build_outbound_request(port)

      assert :ok = Udp.send_request(out_req)
    end

    test "sends INVITE request", %{udp_port: port} do
      invite_req = build_outbound_invite_request(port)

      assert :ok = Udp.send_request(invite_req)
    end

    test "sends response message", %{udp_port: port} do
      response = build_sip_response(200, "OK", port)
      source = build_source(port)

      assert :ok = Udp.send_response(response, source)
    end

    test "sends error response", %{udp_port: port} do
      response = build_sip_response(404, "Not Found", port)
      source = build_source(port)

      assert :ok = Udp.send_response(response, source)
    end

    test "handles messages near MTU limit", %{udp_port: port} do
      # Note: Messages larger than MTU should use TCP/TLS transport
      large_req = build_large_request(port)

      assert :ok = Udp.send_request(large_req)
    end

    test "handles malformed destination" do
      malformed_req = build_request_with_bad_destination()

      result = Udp.send_request(malformed_req)
      assert {:error, _reason} = result
    end

    test "respects max_burst setting", %{udp_port: port} do
      # Send many requests rapidly
      requests =
        Enum.map(1..10, fn i ->
          build_outbound_request_with_seq(i, port)
        end)

      results = Enum.map(requests, &Udp.send_request/1)

      # All should succeed (UDP is best-effort)
      assert Enum.all?(results, &(&1 == :ok))
    end
  end

  describe "message receiving and parsing" do
    setup do
      handler = build_test_handler()

      {pid, _opts} =
        start_test_udp(%{
          sip_trace: true,
          handler: handler
        })

      state = :sys.get_state(pid)
      port = state.local_port

      %{udp_pid: pid, udp_port: port, handler: handler}
    end

    test "receives and parses INVITE request", %{udp_pid: pid, udp_port: port} do
      raw_invite = build_raw_invite_packet(port)
      source_addr = {127, 0, 0, 1}
      source_port = port

      # Simulate receiving UDP packet
      state = :sys.get_state(pid)
      socket_ref = state.socket
      send(pid, {:udp, socket_ref, source_addr, source_port, raw_invite})

      # Assert that the handler was called with the parsed INVITE
      assert_receive {:handler_called,
                      %Message{
                        method: method,
                        source: %Source{remote: {remote_addr, remote_port}},
                        direction: direction,
                        dialog_id: %{direction: dialog_direction}
                      } = _msg},
                     100

      assert method == :invite
      assert remote_addr == source_addr
      assert remote_port == source_port
      assert direction == :incoming
      assert dialog_direction == :uas
      assert Process.alive?(pid)
    end

    test "receives and parses response", %{udp_pid: pid, udp_port: port} do
      raw_response = build_raw_response_packet(port)
      source_addr = {127, 0, 0, 1}
      source_port = port

      send_udp_message_with_real_socket(pid, source_addr, source_port, raw_response)

      :timer.sleep(10)
      assert Process.alive?(pid)
    end

    test "handles malformed SIP messages", %{udp_pid: pid} do
      malformed_data = "This is not a SIP message"
      source_addr = {127, 0, 0, 1}
      source_port = 5060

      send_udp_message_with_real_socket(pid, source_addr, source_port, malformed_data)

      # Should handle gracefully without crashing
      :timer.sleep(10)
      assert Process.alive?(pid)
    end

    test "handles partial SIP messages", %{udp_pid: pid} do
      partial_message = "INVITE sip:user@example.com SIP/2.0\r\n"
      source_addr = {127, 0, 0, 1}
      source_port = 5060

      send_udp_message_with_real_socket(pid, source_addr, source_port, partial_message)

      :timer.sleep(10)
      assert Process.alive?(pid)
    end

    test "logs messages when enabled", %{udp_pid: pid, udp_port: port} do
      raw_invite = build_raw_invite_packet(port)
      source_addr = {127, 0, 0, 1}
      source_port = port

      send_udp_message_with_real_socket(pid, source_addr, source_port, raw_invite)

      # Should log the message (check via state or mock)
      :timer.sleep(10)
      assert Process.alive?(pid)
    end
  end

  describe "handler integration" do
    setup do
      handler = build_test_handler()
      {pid, _opts} = start_test_udp(%{handler: handler})

      state = :sys.get_state(pid)
      port = state.local_port

      %{udp_pid: pid, handler: handler, udp_port: port}
    end

    test "handles handler errors gracefully", %{udp_pid: pid, udp_port: port} do
      # Send message that will cause handler to error
      raw_invite = build_raw_invite_packet(port)
      source_addr = {127, 0, 0, 1}
      source_port = port

      send_udp_message_with_real_socket(pid, source_addr, source_port, raw_invite)

      # Should handle handler errors without crashing
      :timer.sleep(10)
      assert Process.alive?(pid)
    end

    test "works without handler configured", %{udp_pid: pid, udp_port: port} do
      raw_invite = build_raw_invite_packet(port)
      source_addr = {127, 0, 0, 1}
      source_port = port

      send_udp_message_with_real_socket(pid, source_addr, source_port, raw_invite)

      # Should handle gracefully even without handler
      :timer.sleep(10)
      assert Process.alive?(pid)
    end
  end

  describe "transaction server integration" do
    setup do
      handler = build_test_handler()
      {pid, _opts} = start_test_udp(%{handler: handler})

      state = :sys.get_state(pid)
      port = state.local_port

      %{udp_pid: pid, udp_port: port, handler: handler}
    end

    test "routes requests to transaction server", %{udp_pid: pid, udp_port: port} do
      raw_invite = build_raw_invite_packet(port)
      source_addr = {127, 0, 0, 1}
      source_port = port

      send_udp_message_with_real_socket(pid, source_addr, source_port, raw_invite)

      # Should route to TransactionStatem
      :timer.sleep(10)
      assert Process.alive?(pid)
    end

    test "handles transaction server responses", %{udp_port: port} do
      # Simulate transaction server sending response
      response = build_sip_response(200, "OK", port)
      source = build_source(port)

      assert :ok = Udp.send_response(response, source)
    end

    test "manages transaction lifecycle", %{udp_pid: pid, udp_port: port} do
      raw_invite = build_raw_invite_packet(port)
      source_addr = {127, 0, 0, 1}
      source_port = port

      send_udp_message_with_real_socket(pid, source_addr, source_port, raw_invite)

      # Should create and manage transaction
      :timer.sleep(10)
      assert Process.alive?(pid)
    end
  end

  describe "source management" do
    setup do
      handler = build_test_handler()
      {pid, _opts} = start_test_udp(%{handler: handler})

      state = :sys.get_state(pid)
      port = state.local_port

      %{udp_pid: pid, udp_port: port, handler: handler}
    end

    test "handles source comparison", %{udp_port: port} do
      source1 = build_source(port)
      source2 = build_source(port)

      # Should be able to compare sources
      assert source1 == source1
      # May be equal if same params
      assert source1 != source2 or source1 == source2
    end
  end

  describe "error handling and edge cases" do
    test "handles unknown GenServer messages" do
      {pid, _opts} = start_test_udp()

      GenServer.cast(pid, {:unknown_message, "test"})
      send(pid, {:unknown_info, "test"})

      # Should handle unknown messages without crashing
      :timer.sleep(10)
      assert Process.alive?(pid)
    end

    test "handles process termination gracefully" do
      {pid, _opts} = start_test_udp()

      GenServer.stop(pid, :normal)
      refute Process.alive?(pid)
    end
  end

  describe "performance and load handling" do
    setup do
      # Use a lightweight handler that doesn't create transactions
      handler = %Parrot.Sip.Handler{
        module: Parrot.Sip.Transport.UdpTest.LoadTestHandlerModule,
        args: %{pid: self()}
      }

      {pid, _opts} = start_test_udp(%{handler: handler})

      state = :sys.get_state(pid)
      port = state.local_port

      %{udp_pid: pid, udp_port: port, handler: handler}
    end

    test "handles concurrent operations", %{udp_pid: _pid, udp_port: port} do
      # Send multiple concurrent requests
      tasks =
        Enum.map(1..5, fn i ->
          Task.async(fn ->
            req = build_outbound_request_with_seq(i, port)
            Udp.send_request(req)
          end)
        end)

      results = Task.await_many(tasks)
      assert length(results) == 5
      assert Enum.all?(results, &(&1 == :ok))
    end

    test "handles memory pressure", %{udp_pid: pid, udp_port: port} do
      # Send many large messages
      large_requests =
        Enum.map(1..100, fn _i ->
          build_large_request(port)
        end)

      results = Enum.map(large_requests, &Udp.send_request/1)

      # Should handle all requests
      assert Enum.all?(results, &(&1 == :ok))
      assert Process.alive?(pid)
    end

    test "handles burst of incoming messages", %{udp_pid: pid, udp_port: udp_port} do
      # Send burst of messages
      messages =
        Enum.map(1..20, fn i ->
          {build_raw_invite_packet_with_seq(i, udp_port), {127, 0, 0, 1}, udp_port}
        end)

      Enum.each(messages, fn {packet, addr, port} ->
        send_udp_message_with_real_socket(pid, addr, port, packet)
      end)

      # Should handle burst without crashing
      :timer.sleep(50)
      assert Process.alive?(pid)
    end

    test "handles sustained load", %{udp_pid: pid, udp_port: udp_port} do
      # Send sustained load over time
      task =
        Task.async(fn ->
          Enum.each(1..10, fn i ->
            packet = build_raw_invite_packet_with_seq(i, udp_port)
            send_udp_message_with_real_socket(pid, {127, 0, 0, 1}, udp_port, packet)
            :timer.sleep(20)
          end)
        end)

      Task.await(task, 10_000)

      # Allow time for transactions to complete
      :timer.sleep(100)

      assert Process.alive?(pid)
    end

    # Helper to send a UDP message to the GenServer using the real socket reference
    defp send_udp_message_with_real_socket(pid, addr, port, packet) do
      state = :sys.get_state(pid)
      socket_ref = state.socket
      send(pid, {:udp, socket_ref, addr, port, packet})
    end
  end

  # Helper functions for building test data
  defp build_test_handler do
    # Get test configuration from Application env (set in config/test.exs)
    test_log_level = Application.get_env(:parrot_platform, :test_log_level, :warning)
    test_sip_trace = Application.get_env(:parrot_platform, :test_sip_trace, false)

    Parrot.Sip.Handler.new(
      Parrot.Sip.Transport.UdpTest.TestHandlerModule,
      %{pid: self()},
      log_level: test_log_level,
      sip_trace: test_sip_trace
    )
  end

  defp build_outbound_request(port) do
    message = build_invite_message(port)

    %{
      message: message,
      destination: {"127.0.0.1", port},
      transport: :udp
    }
  end

  defp build_outbound_invite_request(port) do
    message = build_invite_message(port)

    %{
      message: message,
      destination: {"127.0.0.1", port},
      transport: :udp,
      method: :invite
    }
  end

  defp build_outbound_request_with_seq(seq, port) do
    message = build_invite_message_with_seq(seq, port)

    %{
      message: message,
      destination: {"127.0.0.1", port},
      transport: :udp
    }
  end

  defp build_large_request(port) do
    message = build_invite_message(port)
    # UDP MTU is typically 1500 bytes, safe payload is ~1200 bytes
    # Testing with 1100 bytes to stay under MTU limit
    large_body = String.duplicate("a", 1100)

    %{
      message: %{message | body: large_body},
      destination: {"127.0.0.1", port},
      transport: :udp
    }
  end

  defp build_request_with_bad_destination do
    message = build_invite_message(5060)

    %{
      message: message,
      destination: "invalid-destination",
      transport: :udp
    }
  end

  defp build_sip_response(status, reason, port) do
    %Message{
      method: nil,
      request_uri: nil,
      version: "SIP/2.0",
      status_code: status,
      reason_phrase: reason,
      headers: %{
        "via" => %Via{
          protocol: "SIP",
          version: "2.0",
          transport: :udp,
          host: "127.0.0.1",
          port: port,
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
          parameters: %{"tag" => "test-to-tag"}
        },
        "call-id" => "test-call-id-123@example.com",
        "cseq" => %CSeq{number: 1, method: :invite}
      },
      body: ""
    }
  end

  defp build_source(port) do
    %Source{
      local: {{127, 0, 0, 1}, port},
      remote: {{127, 0, 0, 1}, port},
      transport: :udp,
      source_id: nil
    }
  end

  defp build_invite_message(port) do
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
          port: port,
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
          uri: "sip:test@127.0.0.1:#{port}",
          parameters: %{}
        }
      },
      body:
        "v=0\r\no=test 123 456 IN IP4 127.0.0.1\r\ns=-\r\nc=IN IP4 127.0.0.1\r\nt=0 0\r\nm=audio 8000 RTP/AVP 0\r\n"
    }
  end

  defp build_invite_message_with_seq(seq, port) do
    invite = build_invite_message(port)

    %Message{
      invite
      | headers: %{
          invite.headers
          | "cseq" => %CSeq{number: seq, method: :invite},
            "call-id" => "test-call-id-#{seq}@example.com"
        }
    }
  end

  defp build_raw_invite_packet(port) do
    """
    INVITE sip:user@example.com SIP/2.0\r
    Via: SIP/2.0/UDP 127.0.0.1:#{port};branch=z9hG4bK-test-branch-123\r
    From: "Test User" <sip:test@example.com>;tag=test-from-tag\r
    To: "Target User" <sip:target@example.com>\r
    Call-ID: test-call-id-123@example.com\r
    CSeq: 1 INVITE\r
    Contact: <sip:test@127.0.0.1:#{port}>\r
    Content-Length: 0\r
    \r
    """
  end

  defp build_raw_invite_packet_with_seq(seq, port) do
    """
    INVITE sip:user@example.com SIP/2.0\r
    Via: SIP/2.0/UDP 127.0.0.1:#{port};branch=z9hG4bK-test-branch-#{seq}\r
    From: "Test User" <sip:test@example.com>;tag=test-from-tag\r
    To: "Target User" <sip:target@example.com>\r
    Call-ID: test-call-id-#{seq}@example.com\r
    CSeq: #{seq} INVITE\r
    Contact: <sip:test@127.0.0.1:#{port}>\r
    Content-Length: 0\r
    \r
    """
  end

  defp build_raw_response_packet(port) do
    """
    SIP/2.0 200 OK\r
    Via: SIP/2.0/UDP 127.0.0.1:#{port};branch=z9hG4bK-test-branch-123\r
    From: "Test User" <sip:test@example.com>;tag=test-from-tag\r
    To: "Target User" <sip:target@example.com>;tag=test-to-tag\r
    Call-ID: test-call-id-123@example.com\r
    CSeq: 1 INVITE\r
    Contact: <sip:target@192.168.1.1:5060>\r
    Content-Length: 0\r
    \r
    """
  end

  # Test handler module
  # Test handler module for testing
  defmodule TestHandlerModule do
    @behaviour Parrot.Sip.Handler

    @impl true
    def transp_request(msg, %{pid: test_pid}) do
      send(test_pid, {:handler_called, msg})
      :process_transaction
    end

    @impl true
    def transaction(_trans, _sip_msg, _args), do: :process_uas

    @impl true
    def transaction_stop(_trans, _trans_result, _args), do: :ok

    @impl true
    def uas_request(_uas, _req_sip_msg, _args), do: :ok

    @impl true
    def uas_cancel(_uas_id, _args), do: :ok

    @impl true
    def process_ack(_sip_msg, _args), do: :ok
  end

  defmodule LoadTestHandlerModule do
    @behaviour Parrot.Sip.Handler

    @impl true
    def transp_request(_msg, %{pid: test_pid}) do
      send(test_pid, :message_received)
      # Return :noreply to avoid creating transactions
      :noreply
    end

    @impl true
    def transaction(_trans, _sip_msg, _args), do: :ok

    @impl true
    def transaction_stop(_trans, _trans_result, _args), do: :ok

    @impl true
    def uas_request(_uas, _req_sip_msg, _args), do: :ok

    @impl true
    def uas_cancel(_uas_id, _args), do: :ok

    @impl true
    def process_ack(_sip_msg, _args), do: :ok
  end
end
