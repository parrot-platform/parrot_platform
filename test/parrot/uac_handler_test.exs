defmodule Parrot.UacHandlerTest do
  use ExUnit.Case, async: true

  alias Parrot.Sip.UacHandlerAdapter
  alias Parrot.Sip.Message
  alias Parrot.Sip.Headers.{CSeq, Contact}

  # Test handler module
  defmodule TestUacHandler do
    use Parrot.UacHandler

    @impl true
    def init(args) do
      {:ok, Map.put(args, :initialized, true)}
    end

    @impl true
    def handle_provisional(%{status_code: 100} = response, state) do
      send(state.test_pid, {:provisional, response})
      {:ok, Map.put(state, :got_trying, true)}
    end

    @impl true
    def handle_provisional(%{status_code: 180} = response, state) do
      send(state.test_pid, {:provisional, response})
      {:ok, Map.put(state, :got_ringing, true)}
    end

    @impl true
    def handle_success(%{status_code: 200} = response, state) do
      send(state.test_pid, {:success, response})
      
      if state[:custom_ack] do
        {:send_ack, %{"x-custom" => "header"}, "custom body", Map.put(state, :got_success, true)}
      else
        {:ok, Map.put(state, :got_success, true)}
      end
    end

    @impl true
    def handle_redirect(%{status_code: 302} = response, state) do
      send(state.test_pid, {:redirect, response})
      
      if state[:follow_redirect] do
        {:follow_redirect, Map.put(state, :got_redirect, true)}
      else
        {:ok, Map.put(state, :got_redirect, true)}
      end
    end

    @impl true
    def handle_client_error(%{status_code: 404} = response, state) do
      send(state.test_pid, {:client_error, response})
      {:ok, Map.put(state, :got_not_found, true)}
    end

    @impl true
    def handle_server_error(%{status_code: 500} = response, state) do
      send(state.test_pid, {:server_error, response})
      {:ok, Map.put(state, :got_server_error, true)}
    end

    @impl true
    def handle_global_failure(%{status_code: 603} = response, state) do
      send(state.test_pid, {:global_failure, response})
      {:stop, :declined, Map.put(state, :got_decline, true)}
    end

    @impl true
    def handle_error(:timeout, state) do
      send(state.test_pid, {:error, :timeout})
      {:stop, :timeout, Map.put(state, :got_timeout, true)}
    end

    @impl true
    def handle_call_established(dialog_id, state) do
      send(state.test_pid, {:call_established, dialog_id})
      {:ok, Map.put(state, :call_established, true)}
    end

    @impl true
    def handle_info({:custom_message, data}, state) do
      send(state.test_pid, {:info, data})
      {:noreply, Map.put(state, :got_info, data)}
    end
  end

  setup do
    # Set test mode to avoid real transport calls
    Process.put(:uac_handler_test_mode, true)
    Process.put(:uac_handler_test_pid, self())
    :ok
  end

  describe "UacHandler behaviour" do
    test "init callback is called when creating adapter" do
      init_args = %{test_pid: self(), initial: true}
      callback = UacHandlerAdapter.create_callback(TestUacHandler, init_args)

      assert is_function(callback, 1)
    end

    test "handles provisional responses" do
      callback = create_test_callback()

      # Test 100 Trying
      trying_response = create_response(100, "Trying")
      callback.({:response, trying_response})

      assert_receive {:provisional, ^trying_response}

      # Test 180 Ringing
      ringing_response = create_response(180, "Ringing")
      callback.({:response, ringing_response})

      assert_receive {:provisional, ^ringing_response}
    end

    test "handles success responses" do
      callback = create_test_callback()

      success_response = create_response(200, "OK")
      callback.({:response, success_response})

      assert_receive {:success, ^success_response}
    end

    test "handles success response to INVITE with automatic ACK" do
      callback = create_test_callback()

      # Create 200 OK response to INVITE
      invite_response = create_response(200, "OK", %{
        "cseq" => %CSeq{number: 1, method: "INVITE"},
        "contact" => %Contact{uri: "sip:user@example.com"}
      })

      # Should process the response
      callback.({:response, invite_response})

      assert_receive {:success, ^invite_response}
    end

    test "handles success response to INVITE with custom ACK" do
      callback = create_test_callback(%{custom_ack: true})

      invite_response = create_response(200, "OK", %{
        "cseq" => %CSeq{number: 1, method: "INVITE"},
        "contact" => %Contact{uri: "sip:user@example.com"}
      })

      callback.({:response, invite_response})

      assert_receive {:success, ^invite_response}
    end

    test "handles redirect responses" do
      callback = create_test_callback()

      redirect_response = create_response(302, "Moved Temporarily", %{
        "contact" => %Contact{uri: "sip:new@location.com"}
      })
      
      callback.({:response, redirect_response})

      assert_receive {:redirect, ^redirect_response}
    end

    test "handles client error responses" do
      callback = create_test_callback()

      error_response = create_response(404, "Not Found")
      callback.({:response, error_response})

      assert_receive {:client_error, ^error_response}
    end

    test "handles server error responses" do
      callback = create_test_callback()

      error_response = create_response(500, "Internal Server Error")
      callback.({:response, error_response})

      assert_receive {:server_error, ^error_response}
    end

    test "handles global failure responses" do
      callback = create_test_callback()

      decline_response = create_response(603, "Decline")
      result = callback.({:response, decline_response})

      assert_receive {:global_failure, ^decline_response}
      assert result == {:stop, :declined}
    end

    test "handles transaction errors" do
      callback = create_test_callback()

      result = callback.({:error, :timeout})

      assert_receive {:error, :timeout}
      assert result == {:stop, :timeout}
    end

    test "handles arbitrary messages via handle_info" do
      callback = create_test_callback()

      callback.({:message, {:custom_message, "test data"}})

      assert_receive {:info, "test data"}
    end

    test "handles transaction stop messages" do
      callback = create_test_callback()

      result = callback.({:stop, :normal})

      assert result == {:stop, :normal}
    end
  end

  describe "UacHandler default implementations" do
    defmodule DefaultUacHandler do
      use Parrot.UacHandler
    end

    test "default implementations handle all response types" do
      callback = UacHandlerAdapter.create_callback(DefaultUacHandler, %{})

      # All of these should not crash
      assert {:ok, _} = callback.({:response, create_response(100, "Trying")})
      assert {:ok, _} = callback.({:response, create_response(200, "OK")})
      assert {:ok, _} = callback.({:response, create_response(302, "Moved")})
      assert {:ok, _} = callback.({:response, create_response(404, "Not Found")})
      assert {:ok, _} = callback.({:response, create_response(500, "Server Error")})
      assert {:ok, _} = callback.({:response, create_response(603, "Decline")})
      assert {:stop, :test_error} = callback.({:error, :test_error})
    end
  end

  describe "UacHandlerAdapter.create_callback_with_state" do
    test "creates callback with pre-initialized state" do
      handler_state = %{test_pid: self(), pre_initialized: true}
      callback = UacHandlerAdapter.create_callback_with_state(
        TestUacHandler,
        handler_state,
        dialog_id: "test-dialog"
      )

      response = create_response(200, "OK")
      callback.({:response, response})

      assert_receive {:success, ^response}
    end
  end

  # Helper functions

  defp create_test_callback(extra_state \\ %{}) do
    init_args = Map.merge(%{test_pid: self()}, extra_state)
    UacHandlerAdapter.create_callback(TestUacHandler, init_args)
  end

  defp create_response(status, reason, extra_headers \\ %{}) do
    headers = Map.merge(%{
      "to" => "sip:bob@example.com",
      "from" => "sip:alice@example.com",
      "call-id" => "test-call-#{System.unique_integer()}",
      "cseq" => "1 INVITE",
      "via" => "SIP/2.0/UDP 192.168.1.1:5060;branch=z9hG4bK123"
    }, extra_headers)

    %Message{
      type: :response,
      status_code: status,
      reason_phrase: reason,
      headers: headers,
      body: ""
    }
  end
end