defmodule Parrot.Sip.DialogTest do
  use ExUnit.Case

  alias Parrot.Sip.Dialog
  alias Parrot.Sip.Message
  alias Parrot.Sip.Headers

  describe "dialog creation" do
    test "creates a dialog from UAS perspective" do
      invite = create_invite_request()
      response = create_200_ok_response(invite)

      {:ok, dialog} = Dialog.uas_create(invite, response)

      assert is_binary(dialog.id)
      assert dialog.state == :confirmed
      assert dialog.call_id == invite.headers["call-id"]
      assert dialog.local_tag == "a6c85cf"
      assert dialog.remote_tag == "1928301774"
      assert dialog.local_uri == "sip:bob@biloxi.com"
      assert dialog.remote_uri == "sip:alice@atlanta.com"
      assert dialog.remote_target == "sip:alice@pc33.atlanta.com"
      assert dialog.local_seq == 0
      assert dialog.remote_seq == 314_159
      assert dialog.secure == false
      assert dialog.route_set == []
    end

    test "creates an early dialog from UAS perspective" do
      invite = create_invite_request()
      response = create_180_ringing_response(invite)

      {:ok, dialog} = Dialog.uas_create(invite, response)

      assert is_binary(dialog.id)
      assert dialog.state == :early
      assert dialog.call_id == invite.headers["call-id"]
      assert dialog.local_tag == "a6c85cf"
      assert dialog.remote_tag == "1928301774"
    end

    test "creates a dialog from UAC perspective" do
      invite = create_invite_request()
      response = create_200_ok_response(invite)

      {:ok, dialog} = Dialog.uac_create(invite, response)

      assert is_binary(dialog.id)
      assert dialog.state == :confirmed
      assert dialog.call_id == invite.headers["call-id"]
      assert dialog.local_tag == "1928301774"
      assert dialog.remote_tag == "a6c85cf"
      assert dialog.local_uri == "sip:alice@atlanta.com"
      assert dialog.remote_uri == "sip:bob@biloxi.com"
      assert dialog.remote_target == "sip:bob@192.0.2.4"
      assert dialog.local_seq == 314_159
      assert dialog.remote_seq == 0
      assert dialog.secure == false
      assert dialog.route_set == []
    end

    test "creates an early dialog from UAC perspective" do
      invite = create_invite_request()
      response = create_180_ringing_response(invite)

      {:ok, dialog} = Dialog.uac_create(invite, response)

      assert is_binary(dialog.id)
      assert dialog.state == :early
      assert dialog.call_id == invite.headers["call-id"]
      assert dialog.local_tag == "1928301774"
      assert dialog.remote_tag == "a6c85cf"
    end
  end

  describe "dialog ID generation" do
    test "generates consistent dialog ID for UAS" do
      invite = create_invite_request()
      response = create_200_ok_response(invite)

      {:ok, dialog1} = Dialog.uas_create(invite, response)
      {:ok, dialog2} = Dialog.uas_create(invite, response)

      assert is_binary(dialog1.id)
      assert dialog1.id == dialog2.id
    end

    test "generates consistent dialog ID for UAC" do
      invite = create_invite_request()
      response = create_200_ok_response(invite)

      {:ok, dialog1} = Dialog.uac_create(invite, response)
      {:ok, dialog2} = Dialog.uac_create(invite, response)

      assert is_binary(dialog1.id)
      assert dialog1.id == dialog2.id
    end
  end

  describe "dialog state management" do
    test "processes in-dialog request (UAS)" do
      invite = create_invite_request()
      response = create_200_ok_response(invite)

      {:ok, dialog} = Dialog.uas_create(invite, response)
      bye = create_bye_request(dialog)

      {:ok, updated_dialog} = Dialog.uas_process(bye, dialog)

      assert updated_dialog.state == :terminated
    end

    test "creates request in dialog (UAC)" do
      invite = create_invite_request()
      response = create_200_ok_response(invite)

      {:ok, dialog} = Dialog.uac_create(invite, response)

      {:ok, bye, updated_dialog} = Dialog.uac_request(:bye, dialog)

      assert updated_dialog.local_seq == 314_160
      assert bye.method == :bye
      assert bye.headers["cseq"].number == 314_160
      assert bye.headers["from"].parameters["tag"] == "1928301774"
      assert bye.headers["to"].parameters["tag"] == "a6c85cf"
      assert bye.headers["call-id"] == "a84b4c76e66710@pc33.atlanta.com"
    end

    test "processes response to in-dialog request" do
      invite = create_invite_request()
      response = create_200_ok_response(invite)

      {:ok, dialog} = Dialog.uac_create(invite, response)
      {:ok, bye, dialog_after_bye} = Dialog.uac_request(:bye, dialog)
      bye_response = create_bye_response(bye)

      {:ok, final_dialog} = Dialog.uac_response(bye_response, dialog_after_bye)

      assert final_dialog.state == :terminated
    end

    test "updates early dialog to confirmed" do
      invite = create_invite_request()
      provisional = create_180_ringing_response(invite)

      {:ok, early_dialog} = Dialog.uac_create(invite, provisional)
      assert early_dialog.state == :early

      final = create_200_ok_response(invite)
      {:ok, confirmed_dialog} = Dialog.uac_response(final, early_dialog)

      assert confirmed_dialog.state == :confirmed
    end
  end

  describe "dialog utilities" do
    test "checks if dialog is early" do
      invite = create_invite_request()
      provisional = create_180_ringing_response(invite)
      final = create_200_ok_response(invite)

      {:ok, early_dialog} = Dialog.uac_create(invite, provisional)
      {:ok, confirmed_dialog} = Dialog.uac_create(invite, final)

      assert Dialog.is_early?(early_dialog)
      refute Dialog.is_early?(confirmed_dialog)
    end

    test "checks if dialog is secure" do
      invite = create_invite_request()
      response = create_200_ok_response(invite)

      {:ok, dialog} = Dialog.uac_create(invite, response)

      refute Dialog.is_secure?(dialog)

      # Create a secure dialog
      secure_invite = %{invite | request_uri: "sips:bob@biloxi.com"}
      {:ok, secure_dialog} = Dialog.uac_create(secure_invite, response)

      assert Dialog.is_secure?(secure_dialog)
    end
  end

  # Helper functions to create test messages

  defp create_invite_request do
    %Message{
      method: :invite,
      request_uri: "sip:bob@biloxi.com",
      direction: :request,
      version: "SIP/2.0",
      headers: %{
        "via" => %Headers.Via{
          protocol: "SIP",
          version: "2.0",
          transport: :udp,
          host: "pc33.atlanta.com",
          parameters: %{"branch" => "z9hG4bK776asdhds"}
        },
        "to" => %Headers.To{
          display_name: "Bob",
          uri: %Parrot.Sip.Uri{
            scheme: "sip",
            user: "bob",
            host: "biloxi.com",
            parameters: %{},
            headers: %{},
            host_type: :hostname
          }
        },
        "from" => %Headers.From{
          display_name: "Alice",
          uri: %Parrot.Sip.Uri{
            scheme: "sip",
            user: "alice",
            host: "atlanta.com",
            parameters: %{},
            headers: %{},
            host_type: :hostname
          },
          parameters: %{"tag" => "1928301774"}
        },
        "call-id" => "a84b4c76e66710@pc33.atlanta.com",
        "cseq" => %Headers.CSeq{number: 314_159, method: :invite},
        "contact" => %Headers.Contact{
          uri: %Parrot.Sip.Uri{
            scheme: "sip",
            user: "alice",
            host: "pc33.atlanta.com",
            parameters: %{},
            headers: %{},
            host_type: :hostname
          }
        },
        "max-forwards" => 70
      },
      body:
        "v=0\r\no=alice 2890844526 2890844526 IN IP4 pc33.atlanta.com\r\ns=Session SDP\r\nc=IN IP4 pc33.atlanta.com\r\nt=0 0\r\nm=audio 49172 RTP/AVP 0\r\na=rtpmap:0 PCMU/8000\r\n"
    }
  end

  defp create_200_ok_response(request) do
    %Message{
      status_code: 200,
      reason_phrase: "OK",
      direction: :response,
      version: "SIP/2.0",
      headers: %{
        "via" => request.headers["via"],
        "to" => %{request.headers["to"] | parameters: %{"tag" => "a6c85cf"}},
        "from" => request.headers["from"],
        "call-id" => request.headers["call-id"],
        "cseq" => request.headers["cseq"],
        "contact" => %Headers.Contact{
          uri: %Parrot.Sip.Uri{
            scheme: "sip",
            user: "bob",
            host: "192.0.2.4",
            parameters: %{},
            headers: %{},
            host_type: :hostname
          }
        }
      },
      body:
        "v=0\r\no=bob 2890844527 2890844527 IN IP4 192.0.2.4\r\ns=\r\nc=IN IP4 192.0.2.4\r\nt=0 0\r\nm=audio 3456 RTP/AVP 0\r\na=rtpmap:0 PCMU/8000\r\n"
    }
  end

  defp create_180_ringing_response(request) do
    %Message{
      status_code: 180,
      reason_phrase: "Ringing",
      direction: :response,
      version: "SIP/2.0",
      headers: %{
        "via" => request.headers["via"],
        "to" => %{request.headers["to"] | parameters: %{"tag" => "a6c85cf"}},
        "from" => request.headers["from"],
        "call-id" => request.headers["call-id"],
        "cseq" => request.headers["cseq"],
        "contact" => %Headers.Contact{
          uri: %Parrot.Sip.Uri{
            scheme: "sip",
            user: "bob",
            host: "192.0.2.4",
            parameters: %{},
            headers: %{},
            host_type: :hostname
          }
        }
      },
      body: ""
    }
  end

  defp create_bye_request(dialog) do
    %Message{
      method: :bye,
      request_uri: dialog.remote_target,
      direction: :request,
      version: "SIP/2.0",
      headers: %{
        "via" => %Headers.Via{
          protocol: "SIP",
          version: "2.0",
          transport: :udp,
          host: "pc33.atlanta.com",
          parameters: %{"branch" => "z9hG4bK776asdhds"}
        },
        "to" => %Headers.To{
          display_name: nil,
          uri: %Parrot.Sip.Uri{scheme: "sip", user: "bob", host: "biloxi.com"},
          parameters: %{"tag" => dialog.remote_tag}
        },
        "from" => %Headers.From{
          display_name: nil,
          uri: %Parrot.Sip.Uri{scheme: "sip", user: "alice", host: "atlanta.com"},
          parameters: %{"tag" => dialog.local_tag}
        },
        "call-id" => dialog.call_id,
        "cseq" => %Headers.CSeq{number: dialog.local_seq + 1, method: :bye},
        "max-forwards" => 70
      },
      body: ""
    }
  end

  defp create_bye_response(bye_request) do
    %Message{
      status_code: 200,
      reason_phrase: "OK",
      direction: :response,
      version: "SIP/2.0",
      headers: %{
        "via" => bye_request.headers["via"],
        "to" => bye_request.headers["to"],
        "from" => bye_request.headers["from"],
        "call-id" => bye_request.headers["call-id"],
        "cseq" => bye_request.headers["cseq"]
      },
      body: ""
    }
  end
end
