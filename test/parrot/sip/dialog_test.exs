defmodule Parrot.Sip.DialogTest do
  use ExUnit.Case, async: true

  alias Parrot.Sip.Dialog
  alias Parrot.Sip.Message
  alias Parrot.Sip.Headers.{From, To, CSeq, Contact}
  alias Parrot.Sip.Uri

  describe "from_message/1" do
    test "extracts dialog ID from incoming request" do
      request = %Message{
        type: :request,
        method: :invite,
        direction: :incoming,
        headers: %{
          "from" => %From{parameters: %{"tag" => "from-tag-123"}},
          "to" => %To{parameters: %{"tag" => "to-tag-456"}},
          "call-id" => "call-123@example.com"
        }
      }

      dialog_id = Dialog.from_message(request)

      assert dialog_id.call_id == "call-123@example.com"
      assert dialog_id.local_tag == "from-tag-123"
      assert dialog_id.remote_tag == "to-tag-456"
      assert dialog_id.direction == :uas
    end

    test "extracts dialog ID from outgoing request" do
      request = %Message{
        type: :request,
        method: :bye,
        direction: :outgoing,
        headers: %{
          "from" => %From{parameters: %{"tag" => "from-tag-123"}},
          "to" => %To{parameters: %{"tag" => "to-tag-456"}},
          "call-id" => "call-123@example.com"
        }
      }

      dialog_id = Dialog.from_message(request)

      assert dialog_id.call_id == "call-123@example.com"
      assert dialog_id.local_tag == "from-tag-123"
      assert dialog_id.remote_tag == "to-tag-456"
      assert dialog_id.direction == :uac
    end

    test "extracts dialog ID from incoming response" do
      response = %Message{
        type: :response,
        status_code: 200,
        direction: :incoming,
        headers: %{
          "from" => %From{parameters: %{"tag" => "from-tag-123"}},
          "to" => %To{parameters: %{"tag" => "to-tag-456"}},
          "call-id" => "call-123@example.com"
        }
      }

      dialog_id = Dialog.from_message(response)

      # For responses, tags are swapped
      assert dialog_id.call_id == "call-123@example.com"
      assert dialog_id.local_tag == "to-tag-456"
      assert dialog_id.remote_tag == "from-tag-123"
      assert dialog_id.direction == :uas
    end

    test "handles missing To tag in initial request" do
      request = %Message{
        type: :request,
        method: :invite,
        direction: :incoming,
        headers: %{
          "from" => %From{parameters: %{"tag" => "from-tag-123"}},
          "to" => %To{parameters: %{}},
          "call-id" => "call-123@example.com"
        }
      }

      dialog_id = Dialog.from_message(request)

      assert dialog_id.call_id == "call-123@example.com"
      assert dialog_id.local_tag == "from-tag-123"
      assert dialog_id.remote_tag == nil
      assert dialog_id.direction == :uas
    end
  end

  describe "to_string/1" do
    test "generates consistent dialog ID string with complete tags" do
      dialog = %Dialog{
        call_id: "abc@example.com",
        local_tag: "tag-123",
        remote_tag: "tag-456"
      }

      result = Dialog.to_string(dialog)
      assert result == "abc@example.com;local=tag-123;remote=tag-456"
    end

    test "generates dialog ID string without remote tag" do
      dialog = %Dialog{
        call_id: "abc@example.com",
        local_tag: "tag-123",
        remote_tag: nil
      }

      result = Dialog.to_string(dialog)
      assert result == "abc@example.com;local=tag-123"
    end

    test "generates dialog ID string from map with direction" do
      dialog_id = %{
        call_id: "abc@example.com",
        local_tag: "tag-123",
        remote_tag: "tag-456",
        direction: :uac
      }

      result = Dialog.to_string(dialog_id)
      assert result == "abc@example.com;local=tag-123;remote=tag-456;uac"
    end

    test "generates dialog ID string from map without direction" do
      dialog_id = %{
        call_id: "abc@example.com",
        local_tag: "tag-123",
        remote_tag: nil
      }

      result = Dialog.to_string(dialog_id)
      assert result == "abc@example.com;local=tag-123"
    end
  end

  describe "is_complete?/1" do
    test "returns true for complete dialog ID" do
      dialog = %Dialog{
        local_tag: "tag-123",
        remote_tag: "tag-456"
      }

      assert Dialog.is_complete?(dialog)
    end

    test "returns false for dialog ID without remote tag" do
      dialog = %Dialog{
        local_tag: "tag-123",
        remote_tag: nil
      }

      refute Dialog.is_complete?(dialog)
    end

    test "returns false for dialog ID without local tag" do
      dialog = %Dialog{
        local_tag: nil,
        remote_tag: "tag-456"
      }

      refute Dialog.is_complete?(dialog)
    end

    test "works with map dialog ID" do
      dialog_id = %{
        local_tag: "tag-123",
        remote_tag: "tag-456"
      }

      assert Dialog.is_complete?(dialog_id)
    end
  end

  describe "new/4" do
    test "creates dialog ID with all parameters" do
      dialog_id = Dialog.new("call-123", "local-456", "remote-789", :uas)

      assert dialog_id.call_id == "call-123"
      assert dialog_id.local_tag == "local-456"
      assert dialog_id.remote_tag == "remote-789"
      assert dialog_id.direction == :uas
    end

    test "creates dialog ID with default direction" do
      dialog_id = Dialog.new("call-123", "local-456", "remote-789")

      assert dialog_id.direction == :uac
    end

    test "creates dialog ID without remote tag" do
      dialog_id = Dialog.new("call-123", "local-456")

      assert dialog_id.remote_tag == nil
      assert dialog_id.direction == :uac
    end
  end

  describe "peer_dialog_id/1" do
    test "swaps tags and direction for UAC" do
      dialog_id = %{
        call_id: "call-123",
        local_tag: "local-456",
        remote_tag: "remote-789",
        direction: :uac
      }

      peer = Dialog.peer_dialog_id(dialog_id)

      assert peer.call_id == "call-123"
      assert peer.local_tag == "remote-789"
      assert peer.remote_tag == "local-456"
      assert peer.direction == :uas
    end

    test "swaps tags and direction for UAS" do
      dialog_id = %{
        call_id: "call-123",
        local_tag: "local-456",
        remote_tag: "remote-789",
        direction: :uas
      }

      peer = Dialog.peer_dialog_id(dialog_id)

      assert peer.call_id == "call-123"
      assert peer.local_tag == "remote-789"
      assert peer.remote_tag == "local-456"
      assert peer.direction == :uac
    end
  end

  describe "match?/2" do
    test "returns true for identical dialog IDs" do
      dialog_id1 = %{
        call_id: "call-123",
        local_tag: "tag-456",
        remote_tag: "tag-789"
      }

      dialog_id2 = %{
        call_id: "call-123",
        local_tag: "tag-456",
        remote_tag: "tag-789"
      }

      assert Dialog.match?(dialog_id1, dialog_id2)
    end

    test "returns true for swapped tags (peer perspectives)" do
      dialog_id1 = %{
        call_id: "call-123",
        local_tag: "tag-456",
        remote_tag: "tag-789"
      }

      dialog_id2 = %{
        call_id: "call-123",
        local_tag: "tag-789",
        remote_tag: "tag-456"
      }

      assert Dialog.match?(dialog_id1, dialog_id2)
    end

    test "returns false for different call IDs" do
      dialog_id1 = %{
        call_id: "call-123",
        local_tag: "tag-456",
        remote_tag: "tag-789"
      }

      dialog_id2 = %{
        call_id: "call-999",
        local_tag: "tag-456",
        remote_tag: "tag-789"
      }

      refute Dialog.match?(dialog_id1, dialog_id2)
    end

    test "returns false for different tags" do
      dialog_id1 = %{
        call_id: "call-123",
        local_tag: "tag-456",
        remote_tag: "tag-789"
      }

      dialog_id2 = %{
        call_id: "call-123",
        local_tag: "tag-111",
        remote_tag: "tag-222"
      }

      refute Dialog.match?(dialog_id1, dialog_id2)
    end
  end

  describe "with_remote_tag/2" do
    test "updates dialog ID with remote tag" do
      dialog_id = %{
        call_id: "call-123",
        local_tag: "local-456",
        remote_tag: nil
      }

      updated = Dialog.with_remote_tag(dialog_id, "remote-789")

      assert updated.remote_tag == "remote-789"
      assert updated.call_id == "call-123"
      assert updated.local_tag == "local-456"
    end

    test "overwrites existing remote tag" do
      dialog_id = %{
        call_id: "call-123",
        local_tag: "local-456",
        remote_tag: "old-remote"
      }

      updated = Dialog.with_remote_tag(dialog_id, "new-remote")

      assert updated.remote_tag == "new-remote"
    end
  end

  describe "uas_create/2" do
    setup do
      request = %Message{
        method: :invite,
        request_uri: "sip:bob@example.com",
        headers: %{
          "from" => %From{
            uri: Uri.parse!("sip:alice@example.com"),
            parameters: %{"tag" => "from-tag-123"}
          },
          "to" => %To{
            uri: Uri.parse!("sip:bob@example.com"),
            parameters: %{}
          },
          "call-id" => "call-123@example.com",
          "cseq" => %CSeq{number: 100, method: :invite},
          "contact" => %Contact{
            uri: Uri.parse!("sip:alice@192.168.1.100:5060")
          }
        }
      }

      response = %Message{
        type: :response,
        status_code: 200,
        headers: %{
          "from" => %From{
            uri: Uri.parse!("sip:alice@example.com"),
            parameters: %{"tag" => "from-tag-123"}
          },
          "to" => %To{
            uri: Uri.parse!("sip:bob@example.com"),
            parameters: %{"tag" => "to-tag-456"}
          },
          "call-id" => "call-123@example.com",
          "cseq" => %CSeq{number: 100, method: :invite}
        }
      }

      {:ok, request: request, response: response}
    end

    test "creates dialog from UAS perspective", %{request: request, response: response} do
      {:ok, dialog} = Dialog.uas_create(request, response)

      assert dialog.call_id == "call-123@example.com"
      assert dialog.local_tag == "to-tag-456"
      assert dialog.remote_tag == "from-tag-123"
      assert dialog.local_uri == "sip:bob@example.com"
      assert dialog.remote_uri == "sip:alice@example.com"
      assert dialog.remote_target == "sip:alice@192.168.1.100:5060"
      assert dialog.remote_seq == 100
      assert dialog.local_seq == 0
      assert dialog.state == :confirmed
    end

    test "creates early dialog for provisional response", %{request: request} do
      provisional = %Message{
        type: :response,
        status_code: 180,
        headers: %{
          "from" => %From{
            uri: Uri.parse!("sip:alice@example.com"),
            parameters: %{"tag" => "from-tag-123"}
          },
          "to" => %To{
            uri: Uri.parse!("sip:bob@example.com"),
            parameters: %{"tag" => "to-tag-456"}
          },
          "call-id" => "call-123@example.com",
          "cseq" => %CSeq{number: 100, method: :invite}
        }
      }

      {:ok, dialog} = Dialog.uas_create(request, provisional)

      assert dialog.state == :early
    end
  end

  describe "uac_create/2" do
    setup do
      request = %Message{
        method: :invite,
        request_uri: "sip:bob@example.com",
        headers: %{
          "from" => %From{
            uri: Uri.parse!("sip:alice@example.com"),
            parameters: %{"tag" => "from-tag-123"}
          },
          "to" => %To{
            uri: Uri.parse!("sip:bob@example.com"),
            parameters: %{}
          },
          "call-id" => "call-123@example.com",
          "cseq" => %CSeq{number: 100, method: :invite}
        }
      }

      response = %Message{
        type: :response,
        status_code: 200,
        headers: %{
          "from" => %From{
            uri: Uri.parse!("sip:alice@example.com"),
            parameters: %{"tag" => "from-tag-123"}
          },
          "to" => %To{
            uri: Uri.parse!("sip:bob@example.com"),
            parameters: %{"tag" => "to-tag-456"}
          },
          "call-id" => "call-123@example.com",
          "cseq" => %CSeq{number: 100, method: :invite},
          "contact" => %Contact{
            uri: Uri.parse!("sip:bob@192.168.1.200:5060")
          }
        }
      }

      {:ok, request: request, response: response}
    end

    test "creates dialog from UAC perspective", %{request: request, response: response} do
      {:ok, dialog} = Dialog.uac_create(request, response)

      assert dialog.call_id == "call-123@example.com"
      assert dialog.local_tag == "from-tag-123"
      assert dialog.remote_tag == "to-tag-456"
      assert dialog.local_uri == "sip:alice@example.com"
      assert dialog.remote_uri == "sip:bob@example.com"
      assert dialog.remote_target == "sip:bob@192.168.1.200:5060"
      assert dialog.local_seq == 100
      assert dialog.remote_seq == 0
      assert dialog.state == :confirmed
    end
  end

  describe "generate_id/4" do
    test "generates consistent dialog ID" do
      id = Dialog.generate_id(:uac, "call-123", "local-456", "remote-789")

      assert id == "call-123;local=local-456;remote=remote-789;uac"
    end

    test "dialog ID is consistent between UAC and UAS perspectives" do
      # When the same dialog is viewed from different perspectives
      uac_id = Dialog.generate_id(:uac, "call-123", "alice-tag", "bob-tag")
      uas_id = Dialog.generate_id(:uas, "call-123", "bob-tag", "alice-tag")

      # The IDs should be different but related
      assert uac_id == "call-123;local=alice-tag;remote=bob-tag;uac"
      assert uas_id == "call-123;local=bob-tag;remote=alice-tag;uas"
    end
  end
end
