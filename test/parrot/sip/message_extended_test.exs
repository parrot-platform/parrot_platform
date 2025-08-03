defmodule Parrot.Sip.MessageExtendedTest do
  use ExUnit.Case, async: true

  alias Parrot.Sip.Message
  alias Parrot.Sip.Headers.{From, To, CSeq, Via}

  describe "new_response/2" do
    test "creates a response with standard reason phrase" do
      response = Message.new_response(200)
      assert response.status_code == 200
      assert response.reason_phrase == "OK"
      assert response.version == "SIP/2.0"
      assert response.headers == %{}
      assert response.body == ""
      assert response.direction == :outgoing
      assert response.dialog_id == nil
      assert response.transaction_id == nil
    end

    test "creates a response with dialog_id and transaction_id" do
      response =
        Message.new_response(200, "OK", %{}, dialog_id: "dlg123", transaction_id: "txn456")

      assert response.status_code == 200
      assert response.dialog_id == "dlg123"
      assert response.transaction_id == "txn456"
    end

    test "creates responses with different status codes" do
      resp_180 = Message.new_response(180)
      assert resp_180.status_code == 180
      assert resp_180.reason_phrase == "Ringing"
      assert resp_180.dialog_id == nil
      assert resp_180.transaction_id == nil

      resp_404 = Message.new_response(404)
      assert resp_404.status_code == 404
      assert resp_404.reason_phrase == "Not Found"
      assert resp_404.dialog_id == nil
      assert resp_404.transaction_id == nil

      resp_486 = Message.new_response(486)
      assert resp_486.status_code == 486
      assert resp_486.reason_phrase == "Busy Here"
      assert resp_486.dialog_id == nil
      assert resp_486.transaction_id == nil
    end

    test "creates a response with initial headers" do
      headers = %{"via" => %Via{host: "example.com"}}
      response = Message.new_response(200, "OK", headers, [])

      assert response.status_code == 200
      assert response.reason_phrase == "OK"
      assert response.headers == headers
      assert response.dialog_id == nil
      assert response.transaction_id == nil
    end

    test "creates a response with initial headers and ids" do
      headers = %{"via" => %Via{host: "example.com"}}

      response =
        Message.new_response(200, "OK", headers, dialog_id: "dlg999", transaction_id: "txn888")

      assert response.status_code == 200
      assert response.reason_phrase == "OK"
      assert response.headers == headers
      assert response.dialog_id == "dlg999"
      assert response.transaction_id == "txn888"
    end
  end

  describe "reply/2" do
    test "creates a response from a request with standard reason phrase" do
      request =
        Message.new_request(:invite, "sip:bob@example.com", %{},
          dialog_id: "dlg-req",
          transaction_id: "txn-req"
        )
        |> Message.set_header("from", %From{
          uri: "sip:alice@example.com",
          parameters: %{"tag" => "123"}
        })
        |> Message.set_header("to", %To{uri: "sip:bob@example.com"})
        |> Message.set_header("call-id", "abc123@example.com")
        |> Message.set_header("via", %Via{host: "example.com"})
        |> Message.set_header("cseq", %CSeq{number: 1, method: :invite})

      response = Message.reply(request, 200)

      assert response.status_code == 200
      assert response.reason_phrase == "OK"
      assert response.version == request.version
      assert response.headers["via"] == request.headers["via"]
      assert response.headers["from"] == request.headers["from"]
      assert response.headers["to"] == request.headers["to"]
      assert response.headers["call-id"] == request.headers["call-id"]
      assert response.headers["cseq"] == request.headers["cseq"]
      assert response.direction == :outgoing

      # reply/2 propagates dialog_id/transaction_id from the request
      assert response.dialog_id == request.dialog_id
      assert response.transaction_id == request.transaction_id
    end
  end

  describe "headers accessors" do
    setup do
      request =
        Message.new_request(:invite, "sip:bob@example.com", %{},
          dialog_id: "dlg-setup",
          transaction_id: "txn-setup"
        )
        |> Message.set_header("from", %From{
          uri: "sip:alice@example.com",
          parameters: %{"tag" => "123"}
        })
        |> Message.set_header("to", %To{uri: "sip:bob@example.com", parameters: %{"tag" => "456"}})
        |> Message.set_header("call-id", "abc123@example.com")
        |> Message.set_header("via", %Via{
          host: "example.com",
          parameters: %{"branch" => "z9hG4bKxyz"}
        })
        |> Message.set_header("cseq", %CSeq{number: 1, method: :invite})

      {:ok, message: request}
    end

    test "cseq/1 returns the CSeq header", %{message: message} do
      assert %CSeq{number: 1, method: :invite} = Message.cseq(message)
      assert message.dialog_id == "dlg-setup"
      assert message.transaction_id == "txn-setup"
    end

    test "from/1 returns the From header", %{message: message} do
      assert %From{uri: "sip:alice@example.com"} = Message.from(message)
    end

    test "to/1 returns the To header", %{message: message} do
      assert %To{uri: "sip:bob@example.com"} = Message.to(message)
    end

    test "call_id/1 returns the Call-ID header", %{message: message} do
      assert Message.call_id(message) == "abc123@example.com"
    end

    test "top_via/1 returns the top Via header", %{message: message} do
      assert %Via{host: "example.com"} = Message.top_via(message)
    end

    test "all_vias/1 returns all Via headers", %{message: message} do
      assert [%Via{host: "example.com"}] = Message.all_vias(message)

      # Add another Via header
      message =
        Message.set_header(message, "via", [
          %Via{host: "example.com", parameters: %{"branch" => "z9hG4bKxyz"}},
          %Via{host: "proxy.example.com", parameters: %{"branch" => "z9hG4bKabc"}}
        ])

      vias = Message.all_vias(message)
      assert length(vias) == 2
      assert Enum.at(vias, 0).host == "example.com"
      assert Enum.at(vias, 1).host == "proxy.example.com"
    end

    test "branch/1 returns the branch parameter from the top Via header", %{message: message} do
      assert Message.branch(message) == "z9hG4bKxyz"
    end

    test "dialog_id/1 returns a dialog ID for the message", %{message: message} do
      dialog_id = Message.dialog_id(message)

      assert dialog_id.call_id == "abc123@example.com"
      assert dialog_id.local_tag == "123"
      assert dialog_id.remote_tag == "456"
      assert dialog_id.direction == :uac
    end

    test "in_dialog?/1 checks if a message is within a dialog", %{message: message} do
      assert Message.in_dialog?(message)

      # Remove To tag
      message =
        Message.set_header(message, "to", %To{uri: "sip:bob@example.com", parameters: %{}})

      assert not Message.in_dialog?(message)
    end
  end

  describe "response status classification" do
    test "status_class/1 returns the status class" do
      assert Message.status_class(Message.new_response(100)) == 1
      assert Message.status_class(Message.new_response(200)) == 2
      assert Message.status_class(Message.new_response(302)) == 3
      assert Message.status_class(Message.new_response(404)) == 4
      assert Message.status_class(Message.new_response(500)) == 5
      assert Message.status_class(Message.new_response(603)) == 6
      assert Message.status_class(Message.new_request(:invite, "sip:bob@example.com")) == nil
    end

    test "is_provisional?/1 identifies 1xx responses" do
      assert Message.is_provisional?(Message.new_response(100))
      assert Message.is_provisional?(Message.new_response(180))
      assert not Message.is_provisional?(Message.new_response(200))
      assert not Message.is_provisional?(Message.new_response(404))
    end

    test "is_success?/1 identifies 2xx responses" do
      assert Message.is_success?(Message.new_response(200))
      assert Message.is_success?(Message.new_response(202))
      assert not Message.is_success?(Message.new_response(180))
      assert not Message.is_success?(Message.new_response(404))
    end

    test "is_redirect?/1 identifies 3xx responses" do
      assert Message.is_redirect?(Message.new_response(300))
      assert Message.is_redirect?(Message.new_response(302))
      assert not Message.is_redirect?(Message.new_response(200))
      assert not Message.is_redirect?(Message.new_response(404))
    end

    test "is_client_error?/1 identifies 4xx responses" do
      assert Message.is_client_error?(Message.new_response(400))
      assert Message.is_client_error?(Message.new_response(404))
      assert not Message.is_client_error?(Message.new_response(200))
      assert not Message.is_client_error?(Message.new_response(500))
    end

    test "is_server_error?/1 identifies 5xx responses" do
      assert Message.is_server_error?(Message.new_response(500))
      assert Message.is_server_error?(Message.new_response(503))
      assert not Message.is_server_error?(Message.new_response(200))
      assert not Message.is_server_error?(Message.new_response(404))
    end

    test "is_global_error?/1 identifies 6xx responses" do
      assert Message.is_global_error?(Message.new_response(600))
      assert Message.is_global_error?(Message.new_response(603))
      assert not Message.is_global_error?(Message.new_response(200))
      assert not Message.is_global_error?(Message.new_response(500))
    end

    test "is_failure?/1 identifies 4xx, 5xx, and 6xx responses" do
      assert Message.is_failure?(Message.new_response(400))
      assert Message.is_failure?(Message.new_response(500))
      assert Message.is_failure?(Message.new_response(600))
      assert not Message.is_failure?(Message.new_response(100))
      assert not Message.is_failure?(Message.new_response(200))
      assert not Message.is_failure?(Message.new_response(302))
    end
  end
end
