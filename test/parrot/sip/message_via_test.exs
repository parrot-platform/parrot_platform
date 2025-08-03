defmodule Parrot.Sip.MessageViaTest do
  use ExUnit.Case, async: true

  alias Parrot.Sip.Message
  alias Parrot.Sip.Headers.Via

  test "handles Via headers as strings and converts to structs" do
    message =
      Message.new_request(:invite, "sip:bob@example.com", %{},
        dialog_id: "dlg-via",
        transaction_id: "txn-via"
      )

    # Set a Via header as a string
    message =
      Message.set_header(
        message,
        "via",
        "SIP/2.0/UDP client.atlanta.com:5060;branch=z9hG4bK74bf9"
      )

    assert message.dialog_id == "dlg-via"
    assert message.transaction_id == "txn-via"

    # Get the Via header, should be a struct
    via = Message.get_header(message, "via")
    assert is_struct(via, Via)
    assert via.host == "client.atlanta.com"
    assert via.port == 5060
    assert via.transport == :udp
    assert via.parameters["branch"] == "z9hG4bK74bf9"

    # Set a Via header as a list of strings
    message =
      Message.set_header(
        message,
        "via",
        [
          "SIP/2.0/UDP client.atlanta.com:5060;branch=z9hG4bK74bf9",
          "SIP/2.0/TCP server.biloxi.com:5061;branch=z9hG4bK123"
        ]
      )

    assert message.dialog_id == "dlg-via"
    assert message.transaction_id == "txn-via"

    # Get all Via headers, should be a list of structs
    vias = Message.all_vias(message)
    assert is_list(vias)
    assert length(vias) == 2
    assert Enum.all?(vias, &is_struct(&1, Via))

    # First Via should be from client.atlanta.com
    first_via = List.first(vias)
    assert first_via.host == "client.atlanta.com"
    assert first_via.transport == :udp

    # Second Via should be from server.biloxi.com
    second_via = List.last(vias)
    assert second_via.host == "server.biloxi.com"
    assert second_via.transport == :tcp
  end

  test "can modify Via headers with MessageHelper" do
    alias Parrot.Sip.MessageHelper

    message =
      Message.new_request(:invite, "sip:bob@example.com", %{},
        dialog_id: "dlg-via2",
        transaction_id: "txn-via2"
      )

    message =
      Message.set_header(
        message,
        "via",
        "SIP/2.0/UDP client.atlanta.com:5060;branch=z9hG4bK74bf9"
      )

    assert message.dialog_id == "dlg-via2"
    assert message.transaction_id == "txn-via2"

    # Add received parameter
    updated = MessageHelper.set_received_parameter(message, "192.168.1.1")
    via = Message.get_header(updated, "via")

    # Via should be a struct and have the received parameter
    assert is_struct(via, Via)
    assert via.parameters["received"] == "192.168.1.1"

    # Convert back to string for assertion
    via_string = Via.format(via)
    assert via_string =~ "received=192.168.1.1"

    # Add rport parameter
    with_rport = MessageHelper.set_rport_parameter(message, 12345)
    rport_via = Message.get_header(with_rport, "via")

    # Via should be a struct and have the rport parameter
    assert is_struct(rport_via, Via)
    assert rport_via.parameters["rport"] == "12345"

    # Convert back to string for assertion
    rport_string = Via.format(rport_via)
    assert rport_string =~ "rport=12345"
  end
end
