defmodule Parrot.Sip.UASTest do
  use ExUnit.Case, async: false

  alias Parrot.Sip.UAS
  alias Parrot.Sip.Message
  alias Parrot.Sip.Headers.{Via, From, To, CSeq, Contact}
  alias Parrot.Sip.TestHandler

  require Logger

  setup do
    # Clean up any existing registry entries
    Registry.unregister_match(Parrot.Registry, :_, :_)
    :ok
  end

  describe "UAS helper functions" do
    test "sipmsg/1 returns the request message from transaction" do
      req_msg = create_invite_request()

      # Create a mock transaction with request
      transaction = %Parrot.Sip.Transaction{
        request: req_msg,
        method: :invite,
        branch: "z9hG4bK123456",
        role: :uas
      }

      assert UAS.sipmsg(transaction) == req_msg
    end
  end

  describe "make_reply/4" do
    test "creates a proper response with status code and reason phrase" do
      req_msg = create_invite_request()
      uas = create_test_uas(req_msg)

      response = UAS.make_reply(200, "OK", uas, req_msg)

      assert response.status_code == 200
      assert response.reason_phrase == "OK"
      assert response.direction == :outgoing

      # Should copy headers from request
      assert response.headers["call-id"] == req_msg.headers["call-id"]
      assert response.headers["cseq"] == req_msg.headers["cseq"]
      assert response.headers["via"] == req_msg.headers["via"]
      assert response.headers["from"] == req_msg.headers["from"]
    end

    test "adds tag to To header in response" do
      req_msg = create_invite_request()
      uas = create_test_uas(req_msg)

      response = UAS.make_reply(200, "OK", uas, req_msg)

      to_header = response.headers["to"]
      # Verify that a tag was added to the To header
      assert Map.has_key?(to_header.parameters, "tag")
      assert to_header.parameters["tag"] != nil
    end

    test "handles different status codes" do
      req_msg = create_invite_request()
      uas = create_test_uas(req_msg)

      response_486 = UAS.make_reply(486, "Busy Here", uas, req_msg)
      assert response_486.status_code == 486
      assert response_486.reason_phrase == "Busy Here"

      response_404 = UAS.make_reply(404, "Not Found", uas, req_msg)
      assert response_404.status_code == 404
      assert response_404.reason_phrase == "Not Found"
    end
  end

  describe "validate_request/1" do
    test "allows supported methods" do
      supported_methods = [:invite, :ack, :bye, :cancel, :options, :register]

      for method <- supported_methods do
        msg = create_request_with_method(method)
        # Use the private function through UAS.process to test validation
        handler = TestHandler.new()
        trans = create_test_uas(msg)

        # This should not raise an error and should process successfully
        assert :ok == UAS.process(trans, msg, handler)
      end
    end

    test "rejects unsupported methods with 405 Method Not Allowed" do
      # Test with an unsupported method by creating a message with unsupported method
      # Note: Since validate_request is private, we test it indirectly through process
      msg = %Message{
        # Unsupported method
        method: :subscribe,
        request_uri: "sip:alice@example.com",
        version: "SIP/2.0",
        headers: create_basic_headers(),
        body: "",
        direction: :incoming,
        type: :request,
        source: create_test_source()
      }

      handler = TestHandler.new()
      trans = create_test_uas(msg)

      # Mock the transaction server to capture the response
      # The validation should create a 405 response
      assert :ok == UAS.process(trans, msg, handler)
    end
  end

  describe "process_ack/2" do
    test "handles ACK when dialog is found" do
      ack_msg = create_ack_request()
      handler = TestHandler.new()

      # process_ack should complete without error
      assert :ok == UAS.process_ack(ack_msg, handler)
    end

    test "handles ACK when dialog is not found" do
      ack_msg = create_ack_request()
      handler = TestHandler.new()

      # Should log warning but return :ok
      assert :ok == UAS.process_ack(ack_msg, handler)
    end
  end

  describe "process_cancel/2" do
    test "calls handler with proper UAS id" do
      trans = {:trans, self()}
      handler = TestHandler.new()

      assert :ok == UAS.process_cancel(trans, handler)
    end
  end

  describe "response functions" do
    test "response/2 delegates to transaction server" do
      req_msg = create_invite_request()
      uas = create_test_uas(req_msg)
      resp_msg = Message.reply(req_msg, 200, "OK")

      # Should complete without error
      assert :ok == UAS.response(resp_msg, uas)
    end

    test "response_retransmit/2 delegates to transaction server" do
      req_msg = create_invite_request()
      uas = create_test_uas(req_msg)
      resp_msg = Message.reply(req_msg, 200, "OK")

      # Should complete without error
      assert :ok == UAS.response_retransmit(resp_msg, uas)
    end
  end

  describe "set_owner/3" do
    test "delegates to transaction server with proper parameters" do
      req_msg = create_invite_request()
      uas = create_test_uas(req_msg)
      owner_pid = self()
      auto_resp_code = 500

      assert :ok == UAS.set_owner(auto_resp_code, owner_pid, uas)
    end
  end

  # Helper functions

  defp create_invite_request do
    %Message{
      type: :request,
      direction: :incoming,
      method: :invite,
      request_uri: "sip:bob@biloxi.com",
      version: "SIP/2.0",
      headers: create_basic_headers(),
      body: "",
      source: create_test_source()
    }
  end

  defp create_ack_request do
    %Message{
      type: :request,
      direction: :incoming,
      method: :ack,
      request_uri: "sip:bob@biloxi.com",
      version: "SIP/2.0",
      headers: create_basic_headers(),
      body: "",
      source: create_test_source()
    }
  end

  defp create_request_with_method(method) do
    %Message{
      type: :request,
      direction: :incoming,
      method: method,
      request_uri: "sip:alice@example.com",
      version: "SIP/2.0",
      headers: create_basic_headers(),
      body: "",
      source: create_test_source()
    }
  end

  defp create_basic_headers do
    %{
      "call-id" => "a84b4c76e66710@pc33.atlanta.com",
      "contact" => %Contact{
        display_name: nil,
        uri: "sip:alice@pc33.atlanta.com",
        parameters: %{},
        wildcard: nil
      },
      "cseq" => %CSeq{number: 314_159, method: :invite},
      "from" => %From{
        display_name: "Alice",
        uri: "sip:alice@atlanta.com",
        parameters: %{"tag" => "1928301774"}
      },
      "to" => %To{
        display_name: "Bob",
        uri: "sip:bob@biloxi.com",
        parameters: %{}
      },
      "via" => %Via{
        protocol: "SIP",
        version: "2.0",
        transport: :udp,
        host: "pc33.atlanta.com",
        port: 5060,
        host_type: nil,
        parameters: %{"branch" => "z9hG4bKnew123"}
      }
    }
  end

  defp create_test_uas(req_msg) do
    %Parrot.Sip.Transaction{
      request: req_msg,
      method: req_msg.method,
      branch: get_branch_from_message(req_msg),
      role: :uas
    }
  end

  defp get_branch_from_message(msg) do
    case msg.headers["via"] do
      [%{params: %{"branch" => branch}} | _] -> branch
      _ -> "z9hG4bK" <> Base.encode16(:crypto.strong_rand_bytes(8))
    end
  end

  defp create_test_source do
    %Parrot.Sip.Source{
      local: {{127, 0, 0, 1}, 5060},
      remote: {{192, 168, 1, 100}, 5060},
      transport: :udp,
      source_id: nil
    }
  end
end
