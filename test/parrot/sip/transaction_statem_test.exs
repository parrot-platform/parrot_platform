defmodule Parrot.Sip.TransactionStatemTest do
  use ExUnit.Case, async: false

  alias Parrot.Sip.TransactionStatem
  alias Parrot.Sip.Message
  alias Parrot.Sip.Headers.{Via, From, To, CSeq, Contact}
  alias Parrot.Sip.TestHandler

  require Logger

  setup do
    :ok
  end

  describe "message pattern matching" do
    test "correctly matches INVITE method" do
      message = create_invite_request_with_branch("z9hG4bKpattern123")
      assert message.method == :invite
      assert Message.is_request?(message) == true
    end

    test "correctly matches response messages" do
      request = create_invite_request_with_branch("z9hG4bKresp_pattern123")
      response = Message.reply(request, 200, "OK")

      assert Message.is_response?(response) == true
      assert response.status_code == 200
      assert response.reason_phrase == "OK"
    end

    test "extracts header information cleanly" do
      message = create_invite_request_with_branch("z9hG4bKheader123")

      # Test improved pattern matching for headers
      assert %Via{} = Message.top_via(message)
      assert %From{} = Message.from(message)
      assert %To{} = Message.to(message)
      assert %CSeq{} = Message.cseq(message)
      assert is_binary(Message.call_id(message))
    end

    test "handles in-dialog detection" do
      # Create a message that appears to be in-dialog
      message = create_bye_request_in_dialog()

      assert Message.in_dialog?(message) == true
    end
  end

  describe "transaction server functions" do
    test "server_process handles ACK requests" do
      message = %Message{
        method: :ack,
        type: :request,
        direction: :incoming,
        request_uri: "sip:bob@biloxi.com",
        version: "SIP/2.0",
        headers: %{
          "via" => %Via{
            protocol: "SIP",
            version: "2.0",
            transport: :udp,
            host: "pc33.atlanta.com",
            port: 5060,
            parameters: %{"branch" => "z9hG4bKnashds8"}
          },
          "from" => %From{
            display_name: "Alice",
            uri: "sip:alice@atlanta.com",
            parameters: %{"tag" => "1928301774"}
          },
          "to" => %To{
            display_name: "Bob",
            uri: "sip:bob@biloxi.com",
            parameters: %{"tag" => "314159"}
          },
          "call-id" => "a84b4c76e66710@pc33.atlanta.com",
          "cseq" => %CSeq{number: 314_159, method: :ack}
        },
        body: "",
        source: %Parrot.Sip.Source{
          local: {{127, 0, 0, 1}, 5060},
          remote: {{192, 168, 1, 100}, 5060},
          transport: :udp,
          source_id: nil
        }
      }

      handler = TestHandler.new()

      # For ACK, should delegate to UAS.process_ack
      # We'll mock this for now
      assert :ok == TransactionStatem.server_process(message, handler)
    end

    test "server_process handles INVITE requests - new transaction" do
      message = create_invite_request_with_branch("z9hG4bKnew123")
      handler = TestHandler.new()

      # Should create new transaction since no existing one
      assert :ok == TransactionStatem.server_process(message, handler)
    end

    test "server_process handles in-dialog requests" do
      message = create_bye_request_in_dialog()
      handler = TestHandler.new()

      # Should handle in-dialog request
      assert :ok == TransactionStatem.server_process(message, handler)
    end

    test "server_process handles REGISTER requests" do
      message = create_register_request_with_branch("z9hG4bKreg123")
      handler = TestHandler.new()

      dbg(message)

      # Should create new transaction
      assert :ok == TransactionStatem.server_process(message, handler)
    end

    test "create_server_response creates response properly" do
      request = create_invite_request_with_branch("z9hG4bKresp456")
      response = Message.reply(request, 200, "OK")

      # Should handle response creation
      assert :ok == TransactionStatem.create_server_response(response, request)
    end

    test "server_cancel handles CANCEL for non-existent transaction" do
      cancel = create_cancel_request_standalone()

      # Should return 481 response for non-existent transaction
      assert {:reply, response} = TransactionStatem.server_cancel(cancel)
      assert response.status_code == 481
      assert response.reason_phrase == "Call/Transaction Does Not Exist"
    end

    test "server_cancel handles CANCEL request properly" do
      cancel = create_cancel_request_standalone()

      # Should return proper response structure
      assert {:reply, response} = TransactionStatem.server_cancel(cancel)
      assert Message.is_response?(response)
      assert response.status_code in [200, 481]
    end

    test "count function returns integer" do
      count = TransactionStatem.count()
      assert is_integer(count)
    end
  end

  describe "transaction ID generation and matching" do
    test "generates consistent transaction IDs" do
      message1 = create_invite_request_with_branch("z9hG4bKsame123")
      message2 = create_invite_request_with_branch("z9hG4bKsame123")

      # Same branch should generate same transaction ID
      id1 = Parrot.Sip.Transaction.generate_id(message1)
      id2 = Parrot.Sip.Transaction.generate_id(message2)

      assert id1 == id2
    end

    test "generates different transaction IDs for different branches" do
      message1 = create_invite_request_with_branch("z9hG4bKdiff1")
      message2 = create_invite_request_with_branch("z9hG4bKdiff2")

      # Different branches should generate different transaction IDs
      id1 = Parrot.Sip.Transaction.generate_id(message1)
      id2 = Parrot.Sip.Transaction.generate_id(message2)

      assert id1 != id2
    end

    test "handles RFC 2543 transaction ID generation" do
      message = create_invite_request_without_branch()

      # Should generate transaction ID even without branch parameter
      id = Parrot.Sip.Transaction.generate_id(message)
      assert is_tuple(id) or is_binary(id)
    end
  end

  describe "improved pattern matching" do
    test "matches dialog state correctly" do
      # Request with no To tag - not in dialog
      new_dialog_msg = create_invite_request_with_branch("z9hG4bKnew789")
      assert Message.in_dialog?(new_dialog_msg) == false

      # Request with both From and To tags - in dialog
      in_dialog_msg = create_bye_request_in_dialog()
      assert Message.in_dialog?(in_dialog_msg) == true
    end

    test "extracts branch parameter correctly" do
      message = create_invite_request_with_branch("z9hG4bKbranch456")
      via = Message.top_via(message)

      assert via.parameters["branch"] == "z9hG4bKbranch456"
    end

    test "handles missing branch parameter gracefully" do
      message = create_invite_request_without_branch()
      via = Message.top_via(message)

      # Should not have branch parameter
      assert Map.get(via.parameters, "branch") == nil
    end

    test "identifies transaction types by method" do
      invite_msg = create_invite_request_with_branch("z9hG4bKinvite123")
      register_msg = create_register_request_with_branch("z9hG4bKreg123")
      ack_msg = %Message{method: :ack}
      bye_msg = create_bye_request_in_dialog()

      assert invite_msg.method == :invite
      assert register_msg.method == :register
      assert ack_msg.method == :ack
      assert bye_msg.method == :bye
    end
  end

  describe "response handling improvements" do
    test "creates proper response structure" do
      request = create_invite_request_with_branch("z9hG4bKtest789")
      response = Message.reply(request, 180, "Ringing")

      assert Message.is_response?(response)
      assert response.status_code == 180
      assert response.reason_phrase == "Ringing"

      # Should copy headers from request appropriately
      assert response.headers["via"] == request.headers["via"]
      assert response.headers["from"] == request.headers["from"]
      assert response.headers["call-id"] == request.headers["call-id"]
      assert response.headers["cseq"] == request.headers["cseq"]
    end

    test "handles different response codes" do
      request = create_invite_request_with_branch("z9hG4bKcodes123")

      # Test different response types
      trying = Message.reply(request, 100, "Trying")
      ringing = Message.reply(request, 180, "Ringing")
      ok = Message.reply(request, 200, "OK")
      not_found = Message.reply(request, 404, "Not Found")

      assert Message.is_provisional?(trying)
      assert Message.is_provisional?(ringing)
      assert Message.is_success?(ok)
      assert Message.is_client_error?(not_found)
    end

    test "maintains transaction correlation in responses" do
      request = create_invite_request_with_branch("z9hG4bKcorr123")
      response = Message.reply(request, 200, "OK")

      # Response should have same branch as request
      req_via = Message.top_via(request)
      resp_via = Message.top_via(response)

      assert req_via.parameters["branch"] == resp_via.parameters["branch"]
    end
  end

  # Helper functions for creating test messages

  defp create_invite_request_without_branch do
    %Message{
      type: :request,
      direction: :incoming,
      method: :invite,
      request_uri: "sip:bob@biloxi.com",
      version: "SIP/2.0",
      headers: %{
        "via" => %Via{
          protocol: "SIP",
          version: "2.0",
          transport: :udp,
          host: "pc33.atlanta.com",
          port: 5060,
          # No branch parameter for RFC 2543 style
          parameters: %{}
        },
        "from" => %From{
          display_name: "Alice",
          uri: "sip:alice@atlanta.com",
          parameters: %{"tag" => "1928301774"}
        },
        "to" => %To{
          display_name: "Bob",
          uri: "sip:bob@biloxi.com",
          # With tag to make it appear in-dialog for RFC 2543 ID generation
          parameters: %{"tag" => "314159"}
        },
        "call-id" => "a84b4c76e66710@pc33.atlanta.com",
        "cseq" => %CSeq{
          number: 314_159,
          method: :invite
        },
        "contact" => %Contact{
          display_name: nil,
          uri: "sip:alice@pc33.atlanta.com",
          parameters: %{}
        }
      },
      body: ""
    }
  end

  defp create_invite_request_with_branch(branch) do
    %Message{
      type: :request,
      direction: :incoming,
      method: :invite,
      request_uri: "sip:bob@biloxi.com",
      version: "SIP/2.0",
      headers: %{
        "via" => %Via{
          protocol: "SIP",
          version: "2.0",
          transport: :udp,
          host: "pc33.atlanta.com",
          port: 5060,
          parameters: %{"branch" => branch}
        },
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
        "call-id" => "a84b4c76e66710@pc33.atlanta.com",
        "cseq" => %CSeq{
          number: 314_159,
          method: :invite
        },
        "contact" => %Contact{
          display_name: nil,
          uri: "sip:alice@pc33.atlanta.com",
          parameters: %{}
        }
      },
      body: ""
    }
  end

  defp create_register_request_with_branch(branch) do
    %Message{
      type: :request,
      direction: :incoming,
      method: :register,
      request_uri: "sip:registrar.biloxi.com",
      version: "SIP/2.0",
      headers: %{
        "via" => %Via{
          protocol: "SIP",
          version: "2.0",
          transport: :udp,
          host: "pc33.atlanta.com",
          port: 5060,
          parameters: %{"branch" => branch}
        },
        "from" => %From{
          display_name: "Alice",
          uri: "sip:alice@atlanta.com",
          parameters: %{"tag" => "1928301774"}
        },
        "to" => %To{
          display_name: "Alice",
          uri: "sip:alice@atlanta.com",
          parameters: %{}
        },
        "call-id" => "a84b4c76e66710@pc33.atlanta.com",
        "cseq" => %CSeq{
          number: 314_159,
          method: :register
        },
        "contact" => %Contact{
          display_name: nil,
          uri: "sip:alice@pc33.atlanta.com",
          parameters: %{}
        }
      },
      body: ""
    }
  end

  defp create_cancel_request_standalone do
    %Message{
      type: :request,
      direction: :incoming,
      method: :cancel,
      request_uri: "sip:bob@biloxi.com",
      version: "SIP/2.0",
      headers: %{
        "via" => %Via{
          protocol: "SIP",
          version: "2.0",
          transport: :udp,
          host: "pc33.atlanta.com",
          port: 5060,
          parameters: %{"branch" => "z9hG4bKnonexistent"}
        },
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
        "call-id" => "nonexistent@pc33.atlanta.com",
        "cseq" => %CSeq{
          number: 314_159,
          method: :cancel
        }
      },
      body: ""
    }
  end

  defp create_cancel_request(original_invite) do
    %{
      original_invite
      | method: :cancel,
        type: :request,
        direction: :incoming,
        headers:
          Map.update!(original_invite.headers, "cseq", fn cseq ->
            %{cseq | method: :cancel}
          end)
    }
  end

  defp create_bye_request_in_dialog do
    %Message{
      type: :request,
      direction: :incoming,
      method: :bye,
      request_uri: "sip:alice@pc33.atlanta.com",
      version: "SIP/2.0",
      headers: %{
        "via" => %Via{
          protocol: "SIP",
          version: "2.0",
          transport: :udp,
          host: "biloxi.com",
          port: 5060,
          parameters: %{"branch" => "z9hG4bKbye123"}
        },
        "from" => %From{
          display_name: "Bob",
          uri: "sip:bob@biloxi.com",
          parameters: %{"tag" => "8321234356"}
        },
        "to" => %To{
          display_name: "Alice",
          uri: "sip:alice@atlanta.com",
          # Both tags present = in-dialog
          parameters: %{"tag" => "1928301774"}
        },
        "call-id" => "a84b4c76e66710@pc33.atlanta.com",
        "cseq" => %CSeq{
          number: 231,
          method: :bye
        }
      },
      body: ""
    }
  end
end
