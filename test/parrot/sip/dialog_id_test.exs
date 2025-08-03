defmodule Parrot.Sip.DialogIdTest do
  use ExUnit.Case, async: true

  alias Parrot.Sip.DialogId
  alias Parrot.Sip.Message
  alias Parrot.Sip.Headers.{From, To}

  describe "from_message/1" do
    test "creates a dialog ID from an incoming request message" do
      from_header = %From{parameters: %{"tag" => "123"}}
      to_header = %To{parameters: %{}}

      request = %Message{
        type: :request,
        direction: :incoming,
        headers: %{
          "from" => from_header,
          "to" => to_header,
          "call-id" => "abc@example.com"
        }
      }

      dialog_id = DialogId.from_message(request)

      assert dialog_id.call_id == "abc@example.com"
      assert dialog_id.local_tag == "123"
      assert dialog_id.remote_tag == nil
      assert dialog_id.direction == :uas
    end

    test "creates a dialog ID from an outgoing request message" do
      from_header = %From{parameters: %{"tag" => "123"}}
      to_header = %To{parameters: %{}}

      request = %Message{
        type: :request,
        direction: :outgoing,
        headers: %{
          "from" => from_header,
          "to" => to_header,
          "call-id" => "abc@example.com"
        }
      }

      dialog_id = DialogId.from_message(request)

      assert dialog_id.call_id == "abc@example.com"
      assert dialog_id.local_tag == "123"
      assert dialog_id.remote_tag == nil
      assert dialog_id.direction == :uac
    end

    test "creates a dialog ID from a response message" do
      from_header = %From{parameters: %{"tag" => "123"}}
      to_header = %To{parameters: %{"tag" => "456"}}

      response = %Message{
        type: :response,
        direction: :incoming,
        headers: %{
          "from" => from_header,
          "to" => to_header,
          "call-id" => "abc@example.com"
        }
      }

      dialog_id = DialogId.from_message(response)

      assert dialog_id.call_id == "abc@example.com"
      assert dialog_id.local_tag == "456"
      assert dialog_id.remote_tag == "123"
      assert dialog_id.direction == :uas
    end

    test "creates a dialog ID from an outgoing response message" do
      from_header = %From{parameters: %{"tag" => "123"}}
      to_header = %To{parameters: %{"tag" => "456"}}

      response = %Message{
        type: :response,
        direction: :outgoing,
        headers: %{
          "from" => from_header,
          "to" => to_header,
          "call-id" => "abc@example.com"
        }
      }

      dialog_id = DialogId.from_message(response)

      assert dialog_id.call_id == "abc@example.com"
      assert dialog_id.local_tag == "456"
      assert dialog_id.remote_tag == "123"
      assert dialog_id.direction == :uac
    end
  end

  describe "new/4" do
    test "creates a dialog ID with explicit components" do
      dialog_id = DialogId.new("abc@example.com", "123", "456", :uac)

      assert dialog_id.call_id == "abc@example.com"
      assert dialog_id.local_tag == "123"
      assert dialog_id.remote_tag == "456"
      assert dialog_id.direction == :uac
    end

    test "creates a dialog ID with default values" do
      dialog_id = DialogId.new("abc@example.com", "123")

      assert dialog_id.call_id == "abc@example.com"
      assert dialog_id.local_tag == "123"
      assert dialog_id.remote_tag == nil
      assert dialog_id.direction == :uac
    end
  end

  describe "is_complete?/1" do
    test "returns true for complete dialog ID" do
      dialog_id = DialogId.new("abc@example.com", "123", "456")
      assert DialogId.is_complete?(dialog_id)
    end

    test "returns false for incomplete dialog ID" do
      dialog_id = DialogId.new("abc@example.com", "123")
      assert not DialogId.is_complete?(dialog_id)

      dialog_id = %{dialog_id | local_tag: nil, remote_tag: "456"}
      assert not DialogId.is_complete?(dialog_id)
    end
  end

  describe "peer_dialog_id/1" do
    test "swaps local and remote tags" do
      dialog_id = DialogId.new("abc@example.com", "123", "456", :uac)
      peer_id = DialogId.peer_dialog_id(dialog_id)

      assert peer_id.call_id == dialog_id.call_id
      assert peer_id.local_tag == dialog_id.remote_tag
      assert peer_id.remote_tag == dialog_id.local_tag
      assert peer_id.direction == :uas

      # And vice versa
      dialog_id = DialogId.new("abc@example.com", "123", "456", :uas)
      peer_id = DialogId.peer_dialog_id(dialog_id)

      assert peer_id.direction == :uac
    end
  end

  describe "match?/2" do
    test "returns true for matching dialog IDs" do
      dialog_id1 = DialogId.new("abc@example.com", "123", "456", :uac)
      dialog_id2 = DialogId.new("abc@example.com", "123", "456", :uac)

      assert DialogId.match?(dialog_id1, dialog_id2)
    end

    test "returns true for peer dialog IDs" do
      dialog_id1 = DialogId.new("abc@example.com", "123", "456", :uac)
      dialog_id2 = DialogId.new("abc@example.com", "456", "123", :uas)

      assert DialogId.match?(dialog_id1, dialog_id2)
    end

    test "returns false for dialog IDs with different call-ids" do
      dialog_id1 = DialogId.new("abc@example.com", "123", "456", :uac)
      dialog_id2 = DialogId.new("def@example.com", "123", "456", :uac)

      assert not DialogId.match?(dialog_id1, dialog_id2)
    end

    test "returns false for dialog IDs with different tags" do
      dialog_id1 = DialogId.new("abc@example.com", "123", "456", :uac)
      dialog_id2 = DialogId.new("abc@example.com", "789", "456", :uac)
      dialog_id3 = DialogId.new("abc@example.com", "123", "789", :uac)

      assert not DialogId.match?(dialog_id1, dialog_id2)
      assert not DialogId.match?(dialog_id1, dialog_id3)
    end
  end

  describe "with_remote_tag/2" do
    test "updates dialog ID with remote tag" do
      dialog_id = DialogId.new("abc@example.com", "123")
      updated = DialogId.with_remote_tag(dialog_id, "456")

      assert updated.remote_tag == "456"
      assert updated.call_id == dialog_id.call_id
      assert updated.local_tag == dialog_id.local_tag
      assert updated.direction == dialog_id.direction
    end
  end

  describe "to_string/1" do
    test "formats dialog ID as string" do
      dialog_id = DialogId.new("abc@example.com", "123", "456", :uac)
      assert DialogId.to_string(dialog_id) == "abc@example.com;local=123;remote=456;uac"

      dialog_id = DialogId.new("abc@example.com", "123", nil, :uas)
      assert DialogId.to_string(dialog_id) == "abc@example.com;local=123;uas"
    end
  end
end
