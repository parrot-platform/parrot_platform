defmodule Parrot.Sip.MessageHelperTest do
  use ExUnit.Case, async: true
  doctest Parrot.Sip.MessageHelper

  alias Parrot.Sip.Message
  alias Parrot.Sip.MessageHelper

  describe "set_received_parameter/2" do
    test "adds received parameter to Via header" do
      message = Message.new_request(:invite, "sip:bob@example.com")

      message =
        Message.set_header(
          message,
          "via",
          "SIP/2.0/UDP client.atlanta.com:5060;branch=z9hG4bK74bf9"
        )

      updated = MessageHelper.set_received_parameter(message, "192.168.1.1")

      via = Message.get_header(updated, "via")
      via_string = Parrot.Sip.Headers.Via.format(via)
      assert via_string =~ "received=192.168.1.1"
    end

    test "replaces existing received parameter" do
      message = Message.new_request(:invite, "sip:bob@example.com")

      message =
        Message.set_header(
          message,
          "via",
          "SIP/2.0/UDP client.atlanta.com:5060;branch=z9hG4bK74bf9;received=10.0.0.1"
        )

      updated = MessageHelper.set_received_parameter(message, "192.168.1.1")

      via = Message.get_header(updated, "via")
      via_string = Parrot.Sip.Headers.Via.format(via)
      assert via_string =~ "received=192.168.1.1"
      refute via_string =~ "received=10.0.0.1"
    end

    test "returns message unchanged when no Via header" do
      message = Message.new_request(:invite, "sip:bob@example.com")

      updated = MessageHelper.set_received_parameter(message, "192.168.1.1")

      assert updated == message
    end
  end

  describe "set_rport_parameter/2" do
    test "adds rport parameter with value to Via header" do
      message = Message.new_request(:invite, "sip:bob@example.com")

      message =
        Message.set_header(
          message,
          "via",
          "SIP/2.0/UDP client.atlanta.com:5060;branch=z9hG4bK74bf9"
        )

      updated = MessageHelper.set_rport_parameter(message, 12345)

      via = Message.get_header(updated, "via")
      via_string = Parrot.Sip.Headers.Via.format(via)
      assert via_string =~ "rport=12345"
    end

    test "replaces empty rport parameter" do
      message = Message.new_request(:invite, "sip:bob@example.com")

      message =
        Message.set_header(
          message,
          "via",
          "SIP/2.0/UDP client.atlanta.com:5060;branch=z9hG4bK74bf9;rport"
        )

      updated = MessageHelper.set_rport_parameter(message, 12345)

      via = Message.get_header(updated, "via")
      via_string = Parrot.Sip.Headers.Via.format(via)
      assert via_string =~ "rport=12345"
      refute via_string =~ "rport;"
    end

    test "replaces existing rport parameter value" do
      message = Message.new_request(:invite, "sip:bob@example.com")

      message =
        Message.set_header(
          message,
          "via",
          "SIP/2.0/UDP client.atlanta.com:5060;branch=z9hG4bK74bf9;rport=9999"
        )

      updated = MessageHelper.set_rport_parameter(message, 12345)

      via = Message.get_header(updated, "via")
      via_string = Parrot.Sip.Headers.Via.format(via)
      assert via_string =~ "rport=12345"
      refute via_string =~ "rport=9999"
    end
  end

  describe "remove_top_via/1" do
    test "removes the top Via header when only one is present" do
      message = Message.new_response(200, "OK", %{}, [])

      message =
        Message.set_header(
          message,
          "via",
          "SIP/2.0/UDP server.biloxi.com:5060;branch=z9hG4bK74bf9"
        )

      updated = MessageHelper.remove_top_via(message)
      assert Message.get_header(updated, "via") == nil
    end

    test "removes only the top Via header when multiple are present" do
      message = Message.new_response(200, "OK", %{}, [])

      message =
        Message.set_header(message, "via", [
          "SIP/2.0/UDP server.biloxi.com:5060;branch=z9hG4bK74bf9",
          "SIP/2.0/UDP client.atlanta.com:5060;branch=z9hG4bK74bf8"
        ])

      updated = MessageHelper.remove_top_via(message)

      vias = Message.all_vias(updated)
      assert length(vias) == 1
      assert Enum.at(vias, 0).host == "client.atlanta.com"
    end

    test "returns message unchanged when no Via headers" do
      message = Message.new_response(200, "OK", %{}, [])

      updated = MessageHelper.remove_top_via(message)

      assert updated == message
    end
  end

  describe "apply_nat_handling/2" do
    test "adds both received and rport parameters when needed" do
      message = Message.new_request(:invite, "sip:bob@example.com")

      message =
        Message.set_header(
          message,
          "via",
          "SIP/2.0/UDP client.atlanta.com:5060;branch=z9hG4bK74bf9;rport"
        )

      source_info = %{host: "192.168.1.100", port: 12345}

      updated = MessageHelper.apply_nat_handling(message, source_info)

      via = Message.get_header(updated, "via")
      assert via.parameters["received"] == "192.168.1.100"
      assert via.parameters["rport"] == "12345"
    end

    test "only adds received parameter when host differs" do
      message = Message.new_request(:invite, "sip:bob@example.com")

      via =
        Parrot.Sip.Headers.Via.parse("SIP/2.0/UDP client.atlanta.com:5060;branch=z9hG4bK74bf9")

      message = Message.set_header(message, "via", via)

      source_info = %{host: "192.168.1.100", port: 5060}

      updated = MessageHelper.apply_nat_handling(message, source_info)

      via = Message.get_header(updated, "via")
      assert via.parameters["received"] == "192.168.1.100"
    end

    test "only adds rport parameter when empty rport present and port differs" do
      message = Message.new_request(:invite, "sip:bob@example.com")

      message =
        Message.set_header(
          message,
          "via",
          "SIP/2.0/UDP 192.168.1.100:5060;branch=z9hG4bK74bf9;rport"
        )

      source_info = %{host: "192.168.1.100", port: 12345}

      updated = MessageHelper.apply_nat_handling(message, source_info)

      via = Message.get_header(updated, "via")
      assert via.parameters["rport"] == "12345"
    end
  end

  describe "symmetric_response_routing/2" do
    test "sets response source based on received and rport in request" do
      request = Message.new_request(:invite, "sip:bob@example.com")

      request =
        Message.set_header(
          request,
          "via",
          "SIP/2.0/UDP client.atlanta.com:5060;branch=z9hG4bK74bf9;received=192.168.1.100;rport=12345"
        )

      response = Message.new_response(200, "OK", %{}, [])

      routed_response = MessageHelper.symmetric_response_routing(request, response)

      assert routed_response.source.type == :udp
      assert routed_response.source.host == "192.168.1.100"
      assert routed_response.source.port == 12345
    end

    test "falls back to Via host/port when no received/rport" do
      request = Message.new_request(:invite, "sip:bob@example.com")

      request =
        Message.set_header(
          request,
          "via",
          "SIP/2.0/UDP client.atlanta.com:5060;branch=z9hG4bK74bf9"
        )

      response = Message.new_response(200, "OK", %{}, [])

      routed_response = MessageHelper.symmetric_response_routing(request, response)

      assert routed_response.source.type == :udp
      assert routed_response.source.host == "client.atlanta.com"
      assert routed_response.source.port == 5060
    end

    test "uses received but falls back to Via port when no rport value" do
      request = Message.new_request(:invite, "sip:bob@example.com")

      request =
        Message.set_header(
          request,
          "via",
          "SIP/2.0/UDP client.atlanta.com:5060;branch=z9hG4bK74bf9;received=192.168.1.100;rport"
        )

      response = Message.new_response(200, "OK", %{}, [])

      routed_response = MessageHelper.symmetric_response_routing(request, response)

      assert routed_response.source.host == "192.168.1.100"
      assert routed_response.source.port == 5060
    end

    test "extracts transport type from Via" do
      request = Message.new_request(:invite, "sip:bob@example.com")

      request =
        Message.set_header(
          request,
          "via",
          "SIP/2.0/TLS client.atlanta.com:5061;branch=z9hG4bK74bf9"
        )

      response = Message.new_response(200, "OK", %{}, [])

      routed_response = MessageHelper.symmetric_response_routing(request, response)

      assert routed_response.source.type == :tls
    end
  end

  describe "add_route_header/3" do
    test "adds a route header when none exists" do
      message = Message.new_request(:invite, "sip:bob@example.com")

      updated = MessageHelper.add_route_header(message, "<sip:proxy.biloxi.com;lr>")

      assert Message.get_header(updated, "route") == ["<sip:proxy.biloxi.com;lr>"]
    end

    test "prepends route when one already exists" do
      message = Message.new_request(:invite, "sip:bob@example.com")
      message = Message.set_header(message, "route", "<sip:proxy1.atlanta.com;lr>")

      updated = MessageHelper.add_route_header(message, "<sip:proxy2.biloxi.com;lr>")

      routes = Message.get_header(updated, "route")
      assert is_list(routes)
      assert length(routes) == 2
      assert hd(routes) == "<sip:proxy2.biloxi.com;lr>"
    end

    test "appends route when prepend is false" do
      message = Message.new_request(:invite, "sip:bob@example.com")
      route = "<sip:proxy1.atlanta.com;lr>"
      message = Message.set_header(message, "route", route)

      updated = MessageHelper.add_route_header(message, "<sip:proxy2.biloxi.com;lr>", false)

      routes = Message.get_header(updated, "route")
      assert is_list(routes)
      assert length(routes) == 2
      assert List.last(routes) == "<sip:proxy2.biloxi.com;lr>"
    end
  end

  describe "add_record_route/2" do
    test "adds a record-route header when none exists" do
      message = Message.new_request(:invite, "sip:bob@example.com")

      updated = MessageHelper.add_record_route(message, "<sip:proxy.biloxi.com;lr>")

      assert Message.get_header(updated, "record-route") == ["<sip:proxy.biloxi.com;lr>"]
    end

    test "prepends record-route when one already exists" do
      message = Message.new_request(:invite, "sip:bob@example.com")
      message = Message.set_header(message, "record-route", "<sip:proxy1.atlanta.com;lr>")

      updated = MessageHelper.add_record_route(message, "<sip:proxy2.biloxi.com;lr>")

      record_routes = Message.get_header(updated, "record-route")
      assert is_list(record_routes)
      assert length(record_routes) == 2
      assert hd(record_routes) == "<sip:proxy2.biloxi.com;lr>"
    end
  end

  describe "extract_multipart_part/2" do
    test "extracts a part from multipart body by content type" do
      # Create a message with multipart parts in headers
      sdp_part = %{
        headers: %{"content-type" => "application/sdp"},
        body: "v=0\r\no=alice 2890844526 2890844526 IN IP4 alice.atlanta.com\r\n"
      }

      isup_part = %{
        headers: %{"content-type" => "application/isup"},
        body: "ISUP data here"
      }

      message = %Message{
        direction: :request,
        method: :invite,
        request_uri: "sip:bob@example.com",
        headers: %{
          "content-type" => "multipart/mixed;boundary=boundary1",
          "multipart-parts" => [sdp_part, isup_part]
        }
      }

      # Extract SDP part
      {:ok, part} = MessageHelper.extract_multipart_part(message, "application/sdp")
      assert part.body =~ "v=0"
      assert get_in(part, [:headers, "content-type"]) == "application/sdp"

      # Extract ISUP part
      {:ok, part} = MessageHelper.extract_multipart_part(message, "application/isup")
      assert part.body =~ "ISUP data here"
    end

    test "returns error when no part with matching content type" do
      message = %Message{
        direction: :request,
        method: :invite,
        request_uri: "sip:bob@example.com",
        headers: %{
          "content-type" => "multipart/mixed;boundary=boundary1",
          "multipart-parts" => [
            %{
              headers: %{"content-type" => "application/sdp"},
              body: "v=0\r\n"
            }
          ]
        }
      }

      {:error, reason} = MessageHelper.extract_multipart_part(message, "application/isup")
      assert reason =~ "No part with content type"
    end

    test "returns error when message has no multipart parts" do
      message = Message.new_request(:invite, "sip:bob@example.com")

      {:error, reason} = MessageHelper.extract_multipart_part(message, "application/sdp")
      assert reason =~ "does not contain parsed multipart body"
    end
  end
end
