defmodule Parrot.Sip.TransportTest do
  use ExUnit.Case, async: true

  alias Parrot.Sip.{Message, Transport}
  alias Parrot.Sip.Headers.{Via, From, To, CSeq}

  describe "serialize/1" do
    test "serializes a request message to binary" do
      request =
        Message.new_request(:invite, "sip:bob@example.com")
        |> Message.set_header("via", Via.new_with_branch("alice.atlanta.com"))
        |> Message.set_header("from", From.new_with_tag("sip:alice@atlanta.com", "Alice"))
        |> Message.set_header("to", To.new("sip:bob@example.com", "Bob"))
        |> Message.set_header("call-id", "abc123@atlanta.com")
        |> Message.set_header("cseq", CSeq.new(1, :invite))
        |> Message.set_header("max-forwards", 70)
        |> Message.set_header("content-type", "application/sdp")
        |> Message.set_body(
          "v=0\r\no=alice 2890844526 2890844526 IN IP4 alice.atlanta.com\r\ns=Session SDP\r\nc=IN IP4 alice.atlanta.com\r\nt=0 0\r\nm=audio 49172 RTP/AVP 0\r\na=rtpmap:0 PCMU/8000\r\n"
        )

      binary = Transport.serialize(request)

      assert is_binary(binary)
      assert String.starts_with?(binary, "INVITE sip:bob@example.com SIP/2.0\r\n")
      assert String.contains?(binary, "From: Alice <sip:alice@atlanta.com>;tag=")
      assert String.contains?(binary, "To: Bob <sip:bob@example.com>")
      assert String.contains?(binary, "Call-ID: abc123@atlanta.com")
      assert String.contains?(binary, "CSeq: 1 INVITE")
      assert String.contains?(binary, "Max-Forwards: 70")
      assert String.contains?(binary, "Content-Type: application/sdp")
      assert String.contains?(binary, "v=0")
    end

    test "quotes display names with spaces or special characters" do
      request =
        Message.new_request(:invite, "sip:bob@example.com")
        |> Message.set_header("from", From.new_with_tag("sip:alice@atlanta.com", "Alice Smith"))
        |> Message.set_header("to", To.new("sip:bob@example.com", "Bob & Co."))
        |> Message.set_header("call-id", "abc123@atlanta.com")
        |> Message.set_header("cseq", CSeq.new(1, :invite))
        |> Message.set_header("max-forwards", 70)

      binary = Transport.serialize(request)

      assert is_binary(binary)

      # these should be quoted due to spaces and special characters
      assert String.contains?(binary, "From: \"Alice Smith\" <sip:alice@atlanta.com>;tag=")
      assert String.contains?(binary, "To: \"Bob & Co.\" <sip:bob@example.com>")
    end

    test "serializes a response message to binary" do
      response =
        Message.new_response(200, "OK")
        |> Message.set_header("via", Via.new_with_branch("alice.atlanta.com"))
        |> Message.set_header("from", From.new_with_tag("sip:alice@atlanta.com", "Alice"))
        |> Message.set_header("to", To.new_with_tag("sip:bob@example.com", "Bob", "def456"))
        |> Message.set_header("call-id", "abc123@atlanta.com")
        |> Message.set_header("cseq", CSeq.new(1, :invite))
        |> Message.set_header("content-length", 0)

      binary = Transport.serialize(response)

      assert is_binary(binary)
      assert String.starts_with?(binary, "SIP/2.0 200 OK\r\n")
      assert String.contains?(binary, "From: Alice <sip:alice@atlanta.com>;tag=")
      assert String.contains?(binary, "To: Bob <sip:bob@example.com>;tag=def456")
      assert String.contains?(binary, "Call-ID: abc123@atlanta.com")
      assert String.contains?(binary, "CSeq: 1 INVITE")
      assert String.contains?(binary, "Content-Length: 0")
    end
  end

  describe "deserialize/2" do
    test "parses a binary SIP request into a Message struct" do
      raw_data =
        "INVITE sip:bob@biloxi.com SIP/2.0\r\n" <>
          "Via: SIP/2.0/UDP pc33.atlanta.com;branch=z9hG4bK776asdhds\r\n" <>
          "Max-Forwards: 70\r\n" <>
          "To: Bob <sip:bob@biloxi.com>\r\n" <>
          "From: Alice <sip:alice@atlanta.com>;tag=1928301774\r\n" <>
          "Call-ID: a84b4c76e66710@pc33.atlanta.com\r\n" <>
          "CSeq: 314159 INVITE\r\n" <>
          "Contact: <sip:alice@pc33.atlanta.com>\r\n" <>
          "Content-Type: application/sdp\r\n" <>
          "Content-Length: 0\r\n\r\n"

      source = %{
        type: :udp,
        host: "pc33.atlanta.com",
        port: 5060,
        local_host: "server.biloxi.com",
        local_port: 5060
      }

      {:ok, message} = Transport.deserialize(raw_data, source)

      assert message.method == :invite
      assert message.request_uri == "sip:bob@biloxi.com"
      assert message.direction == :incoming
      assert message.source == source
      assert message.headers["from"].display_name == "Alice"
      assert message.headers["to"].display_name == "Bob"
      assert message.headers["call-id"] == "a84b4c76e66710@pc33.atlanta.com"
      assert message.headers["cseq"].number == 314_159
    end

    test "parses a binary SIP response into a Message struct" do
      raw_data =
        "SIP/2.0 200 OK\r\n" <>
          "Via: SIP/2.0/UDP pc33.atlanta.com;branch=z9hG4bK776asdhds\r\n" <>
          "To: Bob <sip:bob@biloxi.com>;tag=a6c85cf\r\n" <>
          "From: Alice <sip:alice@atlanta.com>;tag=1928301774\r\n" <>
          "Call-ID: a84b4c76e66710@pc33.atlanta.com\r\n" <>
          "CSeq: 314159 INVITE\r\n" <>
          "Contact: <sip:bob@192.168.1.100>\r\n" <>
          "Content-Length: 0\r\n\r\n"

      source = %{
        type: :udp,
        host: "192.168.1.100",
        port: 5060,
        local_host: "pc33.atlanta.com",
        local_port: 5060
      }

      {:ok, message} = Transport.deserialize(raw_data, source)

      assert message.status_code == 200
      assert message.reason_phrase == "OK"
      assert message.direction == :incoming
      assert message.source == source
      assert message.headers["from"].display_name == "Alice"
      assert message.headers["to"].display_name == "Bob"
      assert message.headers["to"].parameters["tag"] == "a6c85cf"
      assert message.headers["call-id"] == "a84b4c76e66710@pc33.atlanta.com"
    end

    test "returns error for invalid SIP message" do
      raw_data = "INVALID DATA"

      source = %{
        type: :udp,
        host: "192.168.1.100",
        port: 5060,
        local_host: "192.168.1.1",
        local_port: 5060
      }

      result = Transport.deserialize(raw_data, source)
      assert {:error, _reason} = result
    end
  end

  describe "prepare_message/2" do
    test "adds appropriate Via header for requests" do
      request = Message.new_request(:invite, "sip:bob@example.com")

      opts = %{
        type: :udp,
        local_host: "alice.atlanta.com",
        local_port: 5060,
        remote_host: "proxy.example.com",
        remote_port: 5060,
        connection_timeout: 30000,
        keep_alive_interval: 30000
      }

      prepared = Transport.prepare_message(request, opts)

      via = Message.top_via(prepared)
      assert via != nil
      assert via.host == "alice.atlanta.com"
      assert via.port == 5060
      assert via.transport == :udp
      assert Map.has_key?(via.parameters, "branch")
      assert Map.has_key?(via.parameters, "rport")
      assert Map.has_key?(prepared.headers, "max-forwards")
      assert prepared.headers["max-forwards"] == 70
    end

    test "adds rport parameter for UDP transport" do
      request =
        Message.new_request(:invite, "sip:bob@example.com")
        |> Message.set_header(
          "via",
          Via.new("alice.atlanta.com", "udp", 5060, %{"branch" => "z9hG4bK123"})
        )

      opts = %{type: :udp, local_host: "alice.atlanta.com", local_port: 5060}

      prepared = Transport.prepare_message(request, opts)

      via = Message.top_via(prepared)
      assert Map.has_key?(via.parameters, "rport")
    end

    test "ensures branch parameter is RFC 3261 compliant" do
      request =
        Message.new_request(:invite, "sip:bob@example.com")
        |> Message.set_header(
          "via",
          Via.new("alice.atlanta.com", "udp", 5060, %{"branch" => "abc123"})
        )

      opts = %{type: :udp, local_host: "alice.atlanta.com", local_port: 5060}

      prepared = Transport.prepare_message(request, opts)

      via = Message.top_via(prepared)
      assert String.starts_with?(via.parameters["branch"], "z9hG4bK")
    end

    test "does not modify response messages" do
      response =
        Message.new_response(200, "OK")
        |> Message.set_header(
          "via",
          Via.new("alice.atlanta.com", "udp", 5060, %{"branch" => "z9hG4bK123"})
        )

      opts = %{type: :udp, local_host: "proxy.example.com", local_port: 5060}

      prepared = Transport.prepare_message(response, opts)

      # Response should remain unchanged
      assert prepared == response
    end
  end

  describe "determine_connection/2" do
    test "determines connection for request" do
      request = Message.new_request(:invite, "sip:bob@example.com")

      opts = %{
        type: :udp,
        local_host: "alice.atlanta.com",
        local_port: 5060,
        remote_host: "proxy.example.com",
        remote_port: 5060,
        connection_timeout: 30000
      }

      {:ok, connection} = Transport.determine_connection(request, opts)

      assert connection.type == :udp
      assert connection.local_host == "alice.atlanta.com"
      assert connection.local_port == 5060
      assert connection.remote_host == "proxy.example.com"
      assert connection.remote_port == 5060
    end

    test "determines connection for response" do
      response =
        Message.new_response(200, "OK")
        |> Message.set_header(
          "via",
          Via.new("alice.atlanta.com", "udp", 5060, %{"branch" => "z9hG4bK123"})
        )

      opts = %{type: :udp, local_host: "proxy.example.com", local_port: 5060}

      {:ok, connection} = Transport.determine_connection(response, opts)

      assert connection.type == :udp
      assert connection.local_host == "proxy.example.com"
      assert connection.local_port == 5060
      assert connection.remote_host == "alice.atlanta.com"
      assert connection.remote_port == 5060
    end

    test "determines connection using received/rport parameters" do
      response =
        Message.new_response(200, "OK")
        |> Message.set_header(
          "via",
          Via.new("alice.atlanta.com", "udp", 5060, %{
            "branch" => "z9hG4bK123",
            "received" => "192.168.1.100",
            "rport" => "12345"
          })
        )

      opts = %{type: :udp, local_host: "proxy.example.com", local_port: 5060}

      {:ok, connection} = Transport.determine_connection(response, opts)

      assert connection.remote_host == "192.168.1.100"
      assert connection.remote_port == 12345
    end

    test "returns error for response without Via header" do
      response = Message.new_response(200, "OK")
      opts = %{type: :udp, local_host: "proxy.example.com", local_port: 5060}

      result = Transport.determine_connection(response, opts)
      assert {:error, _reason} = result
    end
  end

  describe "create_source/5" do
    test "creates a source info map" do
      source = Transport.create_source(:udp, "192.168.1.100", 5060, "192.168.1.1", 5060)

      assert source.type == :udp
      assert source.host == "192.168.1.100"
      assert source.port == 5060
      assert source.local_host == "192.168.1.1"
      assert source.local_port == 5060
    end
  end
end
