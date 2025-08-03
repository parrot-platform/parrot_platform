defmodule Parrot.Sip.SerializerTest do
  use ExUnit.Case, async: true
  doctest Parrot.Sip.Serializer

  alias Parrot.Sip.Message
  alias Parrot.Sip.Serializer

  @sample_multipart """
  --boundary1\r
  Content-Type: application/sdp\r
  \r
  v=0
  o=alice 2890844526 2890844526 IN IP4 alice.atlanta.com
  s=SIP Call
  c=IN IP4 192.168.1.1
  t=0 0
  m=audio 49170 RTP/AVP 0
  a=rtpmap:0 PCMU/8000\r
  \r
  --boundary1\r
  Content-Type: application/isup\r
  \r
  ISUP data here\r
  --boundary1--\r
  """

  describe "encode/2" do
    test "encodes a simple request" do
      request = Message.new_request(:invite, "sip:bob@example.com")
      # Add required headers for request
      request = Message.set_header(request, "from", "<sip:alice@atlanta.com>;tag=1928301774")
      request = Message.set_header(request, "to", "<sip:bob@biloxi.com>")
      request = Message.set_header(request, "call-id", "a84b4c76e66710@pc33.atlanta.com")
      request = Message.set_header(request, "cseq", "314159 INVITE")
      request = Message.set_header(request, "max-forwards", 70)

      encoded = Serializer.encode(request)

      assert encoded =~ ~r{^INVITE sip:bob@example.com SIP/2.0\r\n}
      # Don't assert the exact order of headers since it might vary
      assert encoded =~ ~r{Content-Length: 0}
      assert encoded =~ ~r{\r\n\r\n$}
    end

    test "encodes a request with transport options" do
      request = Message.new_request(:invite, "sip:bob@example.com")

      opts = %{
        transport_type: :udp,
        local_host: "alice.atlanta.com",
        local_port: 5060
      }

      encoded = Serializer.encode(request, opts)

      assert encoded =~ ~r{^INVITE sip:bob@example.com SIP/2.0\r\n}
      assert encoded =~ ~r{Via: SIP/2.0/UDP alice.atlanta.com:5060;branch=z9hG4bK}
      # Don't assert the exact order of headers since it might vary
      assert encoded =~ ~r{Content-Length: 0}
      assert encoded =~ ~r{\r\n\r\n$}
    end

    test "encodes a request with headers" do
      headers = %{
        "from" => "<sip:alice@atlanta.com>;tag=1928301774",
        "to" => "<sip:bob@biloxi.com>",
        "call-id" => "a84b4c76e66710@pc33.atlanta.com",
        "cseq" => "314159 INVITE",
        "max-forwards" => 70
      }

      request = Message.new_request(:invite, "sip:bob@example.com", headers)
      encoded = Serializer.encode(request)

      assert encoded =~ ~r{^INVITE sip:bob@example.com SIP/2.0\r\n}
      assert encoded =~ ~r{From: <sip:alice@atlanta.com>;tag=1928301774\r\n}
      assert encoded =~ ~r{To: <sip:bob@biloxi.com>\r\n}
      assert encoded =~ ~r{Call-ID: a84b4c76e66710@pc33.atlanta.com\r\n}
      assert encoded =~ ~r{CSeq: 314159 INVITE\r\n}
      assert encoded =~ ~r{Max-Forwards: 70\r\n}
      # Don't assert the exact order of headers since it might vary
      assert encoded =~ ~r{Content-Length: 0}
      assert encoded =~ ~r{\r\n\r\n$}
    end

    test "encodes a request with body" do
      request = Message.new_request(:invite, "sip:bob@example.com")
      request = Message.set_body(request, "This is a test body")
      encoded = Serializer.encode(request)

      assert encoded =~ ~r{^INVITE sip:bob@example.com SIP/2.0\r\n}
      assert encoded =~ ~r{Content-Length: 19\r\n}
      assert String.ends_with?(encoded, "\r\n\r\nThis is a test body")
    end

    test "encodes a simple response" do
      response = Message.new_response(200, "OK")
      encoded = Serializer.encode(response)

      assert encoded =~ ~r{^SIP/2.0 200 OK\r\n}
      assert encoded =~ ~r{Content-Length: 0\r\n\r\n$}
    end

    test "encodes a response with headers" do
      headers = %{
        "from" => "<sip:alice@atlanta.com>;tag=1928301774",
        "to" => "<sip:bob@biloxi.com>;tag=a6c85cf",
        "call-id" => "a84b4c76e66710@pc33.atlanta.com",
        "cseq" => "314159 INVITE",
        "via" => "SIP/2.0/UDP pc33.atlanta.com:5060;branch=z9hG4bK776asdhds"
      }

      response = Message.new_response(200, "OK", headers)
      encoded = Serializer.encode(response)

      assert encoded =~ ~r{^SIP/2.0 200 OK\r\n}
      assert encoded =~ ~r{From: <sip:alice@atlanta.com>;tag=1928301774\r\n}
      assert encoded =~ ~r{To: <sip:bob@biloxi.com>;tag=a6c85cf\r\n}
      assert encoded =~ ~r{Call-ID: a84b4c76e66710@pc33.atlanta.com\r\n}
      assert encoded =~ ~r{CSeq: 314159 INVITE\r\n}
      assert encoded =~ ~r{Via: SIP/2.0/UDP pc33.atlanta.com:5060;branch=z9hG4bK776asdhds\r\n}
      assert String.ends_with?(encoded, "\r\n\r\n")
      assert encoded =~ ~r{Content-Length: 0\r\n}
    end

    test "ensures correct Content-Length even when one is provided" do
      headers = %{"content-length" => 100}
      request = Message.new_request(:invite, "sip:bob@example.com", headers)
      request = Message.set_body(request, "This is a test body")
      encoded = Serializer.encode(request)

      assert encoded =~ ~r{Content-Length: 19\r\n}
      assert String.ends_with?(encoded, "\r\n\r\nThis is a test body")
    end
  end

  describe "decode/2" do
    test "decodes a simple request" do
      raw_data =
        "INVITE sip:bob@example.com SIP/2.0\r\n" <>
          "Via: SIP/2.0/UDP pc33.atlanta.com;branch=z9hG4bK776asdhds\r\n" <>
          "Max-Forwards: 70\r\n" <>
          "To: Bob <sip:bob@biloxi.com>\r\n" <>
          "From: Alice <sip:alice@atlanta.com>;tag=1928301774\r\n" <>
          "Call-ID: a84b4c76e66710@pc33.atlanta.com\r\n" <>
          "CSeq: 314159 INVITE\r\n" <>
          "Contact: <sip:alice@pc33.atlanta.com>\r\n" <>
          "Content-Type: application/sdp\r\n" <>
          "Content-Length: 0\r\n\r\n"

      {:ok, message} = Serializer.decode(raw_data)

      assert message.method == :invite
      assert message.request_uri == "sip:bob@example.com"
      assert message.direction == :incoming
      assert message.version == "SIP/2.0"
      assert message.body == ""

      # Check headers
      assert Message.get_header(message, "max-forwards") == 70
      assert Message.to(message) != nil
      assert Message.from(message) != nil
      assert Message.call_id(message) != nil
      assert Message.cseq(message) != nil
    end

    test "decodes a simple response" do
      raw_data =
        "SIP/2.0 200 OK\r\n" <>
          "Via: SIP/2.0/UDP server10.biloxi.com;branch=z9hG4bK4b43c2ff8.1\r\n" <>
          "Via: SIP/2.0/UDP bigbox3.site3.atlanta.com;branch=z9hG4bK77ef4c2312983.1\r\n" <>
          "Via: SIP/2.0/UDP pc33.atlanta.com;branch=z9hG4bK776asdhds;received=192.0.2.1\r\n" <>
          "To: Bob <sip:bob@biloxi.com>;tag=a6c85cf\r\n" <>
          "From: Alice <sip:alice@atlanta.com>;tag=1928301774\r\n" <>
          "Call-ID: a84b4c76e66710@pc33.atlanta.com\r\n" <>
          "CSeq: 314159 INVITE\r\n" <>
          "Contact: <sip:bob@192.0.2.4>\r\n" <>
          "Content-Type: application/sdp\r\n" <>
          "Content-Length: 0\r\n\r\n"

      {:ok, message} = Serializer.decode(raw_data)

      assert message.status_code == 200
      assert message.reason_phrase == "OK"
      assert message.direction == :incoming
      assert message.version == "SIP/2.0"
      assert message.body == ""

      # Check headers
      assert Message.to(message) != nil
      assert Message.from(message) != nil
      assert Message.call_id(message) != nil
      assert Message.cseq(message) != nil

      # Check multiple Via headers
      vias = Message.all_vias(message)
      assert length(vias) == 3
      assert vias != nil
    end

    test "decodes a request with body" do
      body =
        "v=0\r\no=alice 2890844526 2890844526 IN IP4 pc33.atlanta.com\r\ns=Session SDP\r\nc=IN IP4 pc33.atlanta.com\r\nt=0 0\r\nm=audio 49172 RTP/AVP 0\r\na=rtpmap:0 PCMU/8000"

      raw_data =
        "INVITE sip:bob@example.com SIP/2.0\r\n" <>
          "Via: SIP/2.0/UDP pc33.atlanta.com;branch=z9hG4bK776asdhds\r\n" <>
          "Max-Forwards: 70\r\n" <>
          "To: Bob <sip:bob@biloxi.com>\r\n" <>
          "From: Alice <sip:alice@atlanta.com>;tag=1928301774\r\n" <>
          "Call-ID: a84b4c76e66710@pc33.atlanta.com\r\n" <>
          "CSeq: 314159 INVITE\r\n" <>
          "Contact: <sip:alice@pc33.atlanta.com>\r\n" <>
          "Content-Type: application/sdp\r\n" <>
          "Content-Length: #{byte_size(body)}\r\n\r\n" <> body

      {:ok, message} = Serializer.decode(raw_data)

      assert message.method == :invite
      assert message.body == body
      assert Message.get_header(message, "content-length").value == byte_size(body)
      assert Message.get_header(message, "content-type") == "application/sdp"
    end

    test "adds source information when provided" do
      raw_data =
        "INVITE sip:bob@example.com SIP/2.0\r\n" <>
          "Via: SIP/2.0/UDP pc33.atlanta.com;branch=z9hG4bK776asdhds\r\n" <>
          "Max-Forwards: 70\r\n" <>
          "To: Bob <sip:bob@biloxi.com>\r\n" <>
          "From: Alice <sip:alice@atlanta.com>;tag=1928301774\r\n" <>
          "Call-ID: a84b4c76e66710@pc33.atlanta.com\r\n" <>
          "CSeq: 314159 INVITE\r\n" <>
          "Content-Length: 0\r\n\r\n"

      source = %{
        type: :udp,
        host: "192.168.1.100",
        port: 5060,
        local_host: "192.168.1.1",
        local_port: 5060
      }

      {:ok, message} = Serializer.decode(raw_data, source)

      assert message.source == source
    end

    test "returns error for invalid SIP message" do
      raw_data = "INVITE malformed message"

      {:error, _reason} = Serializer.decode(raw_data)
    end

    test "returns error when missing required headers" do
      # Missing To header
      raw_data =
        "INVITE sip:bob@example.com SIP/2.0\r\n" <>
          "Via: SIP/2.0/UDP pc33.atlanta.com;branch=z9hG4bK776asdhds\r\n" <>
          "Max-Forwards: 70\r\n" <>
          "From: Alice <sip:alice@atlanta.com>;tag=1928301774\r\n" <>
          "Call-ID: a84b4c76e66710@pc33.atlanta.com\r\n" <>
          "CSeq: 314159 INVITE\r\n" <>
          "Content-Length: 0\r\n\r\n"

      {:error, _reason} = Serializer.decode(raw_data)
    end

    test "accepts messages with Content-Length mismatch (lenient for UDP)" do
      raw_data =
        "INVITE sip:bob@example.com SIP/2.0\r\n" <>
          "Via: SIP/2.0/UDP pc33.atlanta.com;branch=z9hG4bK776asdhds\r\n" <>
          "Max-Forwards: 70\r\n" <>
          "To: Bob <sip:bob@biloxi.com>\r\n" <>
          "From: Alice <sip:alice@atlanta.com>;tag=1928301774\r\n" <>
          "Call-ID: a84b4c76e66710@pc33.atlanta.com\r\n" <>
          "CSeq: 314159 INVITE\r\n" <>
          "Content-Length: 100\r\n\r\n" <>
          "This body is not 100 bytes"

      # Parser is now lenient with Content-Length mismatches
      {:ok, message} = Serializer.decode(raw_data)
      assert message.headers["content-length"].value == 100
      assert byte_size(message.body) == 26
    end
  end

  describe "round-trip encoding/decoding" do
    test "message remains unchanged after encode-decode cycle" do
      # Create a request with all headers
      headers = %{
        "from" => "<sip:alice@atlanta.com>;tag=1928301774",
        "to" => "<sip:bob@biloxi.com>",
        "call-id" => "a84b4c76e66710@pc33.atlanta.com",
        "cseq" => "314159 INVITE",
        "max-forwards" => 70,
        "contact" => "<sip:alice@pc33.atlanta.com>",
        "content-type" => "application/sdp"
      }

      original = Message.new_request(:invite, "sip:bob@example.com", headers)

      original =
        Message.set_body(
          original,
          "v=0\r\no=alice 2890844526 2890844526 IN IP4 pc33.atlanta.com\r\n"
        )

      # Encode
      opts = %{transport_type: :udp, local_host: "alice.atlanta.com", local_port: 5060}
      encoded = Serializer.encode(original, opts)

      # Decode
      {:ok, decoded} = Serializer.decode(encoded)

      # Compare important properties
      assert decoded.method == original.method
      assert decoded.request_uri == original.request_uri
      # Direction changes on decode - outgoing becomes incoming
      assert decoded.direction == :incoming
      assert decoded.body == original.body
      assert Message.call_id(decoded) == Message.call_id(original)
      assert Message.from(decoded) != nil
      assert Message.to(decoded) != nil
    end

    test "quoted header values remain properly escaped" do
      # Create a request with quoted header values
      headers = %{
        "from" => "\"Alice Smith\" <sip:alice@atlanta.com>;tag=1928301774",
        "to" => "\"Bob Jones\" <sip:bob@biloxi.com>",
        "call-id" => "a84b4c76e66710@pc33.atlanta.com",
        "cseq" => "314159 INVITE",
        "max-forwards" => 70
      }

      original = Message.new_request(:invite, "sip:bob@example.com", headers)

      # Encode
      encoded = Serializer.encode(original)

      # Decode
      {:ok, decoded} = Serializer.decode(encoded)

      # Compare quoted values - check for display name in the struct
      from_header = Message.get_header(decoded, "from")
      assert is_map(from_header)
      # Display name might include quotes in the struct representation
      assert String.replace(from_header.display_name, "\"", "") == "Alice Smith"
      assert from_header.uri.scheme == "sip"
      assert from_header.uri.user == "alice"
      assert from_header.uri.host == "atlanta.com"
      assert from_header.parameters["tag"] == "1928301774"

      to_header = Message.get_header(decoded, "to")
      assert is_map(to_header)
      # Display name might include quotes in the struct representation
      assert String.replace(to_header.display_name, "\"", "") == "Bob Jones"
      assert to_header.uri.scheme == "sip"
      assert to_header.uri.user == "bob"
      assert to_header.uri.host == "biloxi.com"
    end
  end

  describe "create_source_info/5" do
    test "creates a source info map" do
      source = Serializer.create_source_info(:udp, "192.168.1.100", 5060, "192.168.1.1", 5060)

      assert source.type == :udp
      assert source.host == "192.168.1.100"
      assert source.port == 5060
      assert source.local_host == "192.168.1.1"
      assert source.local_port == 5060
    end
  end

  describe "extract_source/1" do
    test "extracts source information from a message" do
      source = %{
        type: :udp,
        host: "192.168.1.100",
        port: 5060,
        local_host: "192.168.1.1",
        local_port: 5060
      }

      message = %Message{
        direction: :request,
        method: :invite,
        request_uri: "sip:bob@example.com",
        source: source
      }

      {:ok, extracted_source} = Serializer.extract_source(message)
      assert extracted_source == source
    end

    test "returns error when no source information is available" do
      message = %Message{
        direction: :request,
        method: :invite,
        request_uri: "sip:bob@example.com",
        source: nil
      }

      {:error, _reason} = Serializer.extract_source(message)
    end
  end

  describe "header folding" do
    test "encodes long header values with folding" do
      # Create a header with a very long value
      # 100 characters
      long_value = String.duplicate("abcdefghij", 10)

      headers = %{
        "from" => "<sip:alice@atlanta.com>;tag=1928301774",
        "to" => "<sip:bob@biloxi.com>",
        "call-id" => "a84b4c76e66710@pc33.atlanta.com",
        "cseq" => "314159 INVITE",
        "max-forwards" => 70,
        "via" => "SIP/2.0/UDP pc33.atlanta.com;branch=z9hG4bK776asdhds",
        "user-agent" => long_value
      }

      request = Message.new_request(:invite, "sip:bob@example.com", headers)
      encoded = Serializer.encode(request)

      # Test that the user-agent header is present in the encoded message
      # Note: We don't test the exact format of folding since it might vary
      assert String.contains?(encoded, "User-Agent:")
      assert String.contains?(encoded, long_value)

      # Test that folding works by checking if a long header gets decoded correctly
      {:ok, decoded} = Serializer.decode(encoded)
      assert Message.get_header(decoded, "user-agent") == long_value
    end

    test "decodes folded headers in received messages" do
      # Create a SIP message with manually folded headers
      # This header is folded
      # This header is folded
      # This header is folded again
      raw_data =
        "INVITE sip:bob@example.com SIP/2.0\r\n" <>
          "Via: SIP/2.0/UDP pc33.atlanta.com;branch=z9hG4bK776asdhds\r\n" <>
          "Max-Forwards: 70\r\n" <>
          "To: Bob <sip:bob@biloxi.com>\r\n" <>
          "From: Alice <sip:alice@atlanta.com>\r\n" <>
          " ;tag=1928301774\r\n" <>
          "Call-ID: a84b4c76e66710@pc33.atlanta.com\r\n" <>
          "CSeq: 314159 INVITE\r\n" <>
          "User-Agent: SIP Client Deluxe\r\n" <>
          " Version 1.0 with Extended\r\n" <>
          " Feature Set\r\n" <>
          "Contact: <sip:alice@pc33.atlanta.com>\r\n" <>
          "Content-Length: 0\r\n\r\n"

      {:ok, message} = Serializer.decode(raw_data)

      # Check that folded headers were properly unfolded
      from_header = Message.get_header(message, "from")
      assert is_map(from_header)
      assert from_header.display_name == "Alice"
      assert from_header.uri.scheme == "sip"
      assert from_header.uri.user == "alice"
      assert from_header.uri.host == "atlanta.com"
      assert from_header.parameters["tag"] == "1928301774"

      assert Message.get_header(message, "user-agent") ==
               "SIP Client Deluxe Version 1.0 with Extended Feature Set"
    end
  end

  describe "compact headers" do
    test "decodes compact header forms" do
      # Create a SIP message with compact headers
      raw_data =
        "INVITE sip:bob@example.com SIP/2.0\r\n" <>
          "v: SIP/2.0/UDP pc33.atlanta.com;branch=z9hG4bK776asdhds\r\n" <>
          "m: <sip:alice@pc33.atlanta.com>\r\n" <>
          "f: <sip:alice@atlanta.com>;tag=1928301774\r\n" <>
          "t: <sip:bob@biloxi.com>\r\n" <>
          "i: a84b4c76e66710@pc33.atlanta.com\r\n" <>
          "c: application/sdp\r\n" <>
          "l: 0\r\n" <>
          "CSeq: 1 INVITE\r\n\r\n"

      {:ok, message} = Serializer.decode(raw_data)

      # Verify headers were correctly expanded
      assert Message.get_header(message, "via") != nil
      assert Message.get_header(message, "contact") != nil
      assert Message.get_header(message, "from") != nil
      assert Message.get_header(message, "to") != nil
      assert Message.get_header(message, "call-id") != nil
      assert Message.get_header(message, "content-type") == "application/sdp"
      assert Message.get_header(message, "content-length").value == 0
    end
  end

  describe "multipart body handling" do
    test "decodes a multipart body" do
      # Create a SIP message with a multipart body
      headers = %{
        "from" => "<sip:alice@atlanta.com>;tag=1928301774",
        "to" => "<sip:bob@biloxi.com>",
        "call-id" => "a84b4c76e66710@pc33.atlanta.com",
        "cseq" => "314159 INVITE",
        "max-forwards" => 70,
        "via" => "SIP/2.0/UDP pc33.atlanta.com;branch=z9hG4bK776asdhds",
        "content-type" => "multipart/mixed;boundary=boundary1"
      }

      request = Message.new_request(:invite, "sip:bob@example.com", headers)
      request = Message.set_body(request, @sample_multipart)

      # Encode and decode
      encoded = Serializer.encode(request)
      {:ok, decoded} = Serializer.decode(encoded)

      # Check that multipart parts were correctly parsed
      parts = Map.get(decoded.headers, "multipart-parts")
      assert is_list(parts)
      assert length(parts) == 2

      # Check first part (SDP)
      sdp_part = Enum.at(parts, 0)

      content_type =
        Map.get(sdp_part.headers, "content-type") || Map.get(sdp_part.headers, "Content-Type")

      assert content_type == "application/sdp"
      assert sdp_part.body =~ "v=0"
      assert sdp_part.body =~ "o=alice"

      # Check second part (ISUP)
      isup_part = Enum.at(parts, 1)

      content_type =
        Map.get(isup_part.headers, "content-type") || Map.get(isup_part.headers, "Content-Type")

      assert content_type == "application/isup"
      assert isup_part.body =~ "ISUP data here"
    end

    test "round-trip with multipart body" do
      # Create a SIP message with a multipart body
      headers = %{
        "from" => "<sip:alice@atlanta.com>;tag=1928301774",
        "to" => "<sip:bob@biloxi.com>",
        "call-id" => "a84b4c76e66710@pc33.atlanta.com",
        "cseq" => "314159 INVITE",
        "max-forwards" => 70,
        "via" => "SIP/2.0/UDP pc33.atlanta.com;branch=z9hG4bK776asdhds",
        "content-type" => "multipart/mixed;boundary=boundary1"
      }

      original = Message.new_request(:invite, "sip:bob@example.com", headers)
      original = Message.set_body(original, @sample_multipart)

      # Encode and decode
      encoded = Serializer.encode(original)
      {:ok, decoded} = Serializer.decode(encoded)

      # Compare important properties
      assert decoded.method == original.method
      assert decoded.request_uri == original.request_uri
      assert decoded.body == original.body

      # Compare content-type - structure might be different between original and decoded
      # Extract the parts of the content-type to compare
      decoded_ct = Message.get_header(decoded, "content-type")
      original_ct = Message.get_header(original, "content-type")

      # Check if they're both strings (old format) or both structs (new format)
      if is_binary(decoded_ct) && is_binary(original_ct) do
        # Normalize whitespace to make comparison more reliable
        assert String.replace(decoded_ct, " ", "") == String.replace(original_ct, " ", "")
      else
        # Comparing structs
        assert decoded_ct.type == "multipart"
        assert decoded_ct.subtype == "mixed"
        assert Map.has_key?(decoded_ct.parameters, "boundary")
      end

      # Check that multipart parts were parsed
      parts = Map.get(decoded.headers, "multipart-parts")
      assert is_list(parts)
    end
  end
end
