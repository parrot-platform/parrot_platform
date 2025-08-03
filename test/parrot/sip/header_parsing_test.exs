defmodule Parrot.Sip.HeaderParsingTest do
  use ExUnit.Case, async: true

  alias Parrot.Sip.Parser

  describe "header parsing into structs" do
    test "Via header is parsed into proper struct" do
      raw_message = """
      INVITE sip:bob@biloxi.com SIP/2.0\r
      Via: SIP/2.0/UDP pc33.atlanta.com;branch=z9hG4bK776asdhds\r
      Max-Forwards: 70\r
      To: Bob <sip:bob@biloxi.com>\r
      From: Alice <sip:alice@atlanta.com>;tag=1928301774\r
      Call-ID: a84b4c76e66710@pc33.atlanta.com\r
      CSeq: 314159 INVITE\r
      Contact: <sip:alice@pc33.atlanta.com>\r
      Content-Length: 0\r
      \r
      """

      {:ok, message} = Parser.parse(raw_message)

      via = message.headers["via"]
      assert is_map(via)
      assert via.host == "pc33.atlanta.com"
      assert via.transport == :udp
      assert via.parameters["branch"] == "z9hG4bK776asdhds"
    end

    test "From header is parsed into proper struct" do
      raw_message = """
      INVITE sip:bob@biloxi.com SIP/2.0\r
      Via: SIP/2.0/UDP pc33.atlanta.com;branch=z9hG4bK776asdhds\r
      Max-Forwards: 70\r
      To: Bob <sip:bob@biloxi.com>\r
      From: Alice <sip:alice@atlanta.com>;tag=1928301774\r
      Call-ID: a84b4c76e66710@pc33.atlanta.com\r
      CSeq: 314159 INVITE\r
      Contact: <sip:alice@pc33.atlanta.com>\r
      Content-Length: 0\r
      \r
      """

      {:ok, message} = Parser.parse(raw_message)

      from = message.headers["from"]
      assert is_map(from)
      assert from.display_name == "Alice"
      assert from.uri.scheme == "sip"
      assert from.uri.user == "alice"
      assert from.uri.host == "atlanta.com"
      assert from.parameters["tag"] == "1928301774"
    end

    test "To header is parsed into proper struct" do
      raw_message = """
      INVITE sip:bob@biloxi.com SIP/2.0\r
      Via: SIP/2.0/UDP pc33.atlanta.com;branch=z9hG4bK776asdhds\r
      Max-Forwards: 70\r
      To: Bob <sip:bob@biloxi.com>\r
      From: Alice <sip:alice@atlanta.com>;tag=1928301774\r
      Call-ID: a84b4c76e66710@pc33.atlanta.com\r
      CSeq: 314159 INVITE\r
      Contact: <sip:alice@pc33.atlanta.com>\r
      Content-Length: 0\r
      \r
      """

      {:ok, message} = Parser.parse(raw_message)

      to = message.headers["to"]
      assert is_map(to)
      assert to.display_name == "Bob"
      assert to.uri.scheme == "sip"
      assert to.uri.user == "bob"
      assert to.uri.host == "biloxi.com"
    end

    test "CSeq header is parsed into proper struct" do
      raw_message = """
      INVITE sip:bob@biloxi.com SIP/2.0\r
      Via: SIP/2.0/UDP pc33.atlanta.com;branch=z9hG4bK776asdhds\r
      Max-Forwards: 70\r
      To: Bob <sip:bob@biloxi.com>\r
      From: Alice <sip:alice@atlanta.com>;tag=1928301774\r
      Call-ID: a84b4c76e66710@pc33.atlanta.com\r
      CSeq: 314159 INVITE\r
      Contact: <sip:alice@pc33.atlanta.com>\r
      Content-Length: 0\r
      \r
      """

      {:ok, message} = Parser.parse(raw_message)

      cseq = message.headers["cseq"]
      assert is_map(cseq)
      assert cseq.number == 314_159
      assert cseq.method == :invite
    end

    test "Contact header is parsed into proper struct" do
      raw_message = """
      INVITE sip:bob@biloxi.com SIP/2.0\r
      Via: SIP/2.0/UDP pc33.atlanta.com;branch=z9hG4bK776asdhds\r
      Max-Forwards: 70\r
      To: Bob <sip:bob@biloxi.com>\r
      From: Alice <sip:alice@atlanta.com>;tag=1928301774\r
      Call-ID: a84b4c76e66710@pc33.atlanta.com\r
      CSeq: 314159 INVITE\r
      Contact: <sip:alice@pc33.atlanta.com>\r
      Content-Length: 0\r
      \r
      """

      {:ok, message} = Parser.parse(raw_message)

      contact = message.headers["contact"]
      assert is_map(contact)
      assert contact.uri.scheme == "sip"
      assert contact.uri.user == "alice"
      assert contact.uri.host == "pc33.atlanta.com"
    end

    test "Content-Length is parsed properly" do
      raw_message = """
      INVITE sip:bob@biloxi.com SIP/2.0\r
      Via: SIP/2.0/UDP pc33.atlanta.com;branch=z9hG4bK776asdhds\r
      Max-Forwards: 70\r
      To: Bob <sip:bob@biloxi.com>\r
      From: Alice <sip:alice@atlanta.com>;tag=1928301774\r
      Call-ID: a84b4c76e66710@pc33.atlanta.com\r
      CSeq: 314159 INVITE\r
      Contact: <sip:alice@pc33.atlanta.com>\r
      Content-Length: 123\r
      \r
      """

      # Parser is now lenient with Content-Length mismatches for UDP
      {:ok, message} = Parser.parse(raw_message)
      assert message.headers["content-length"].value == 123
      assert byte_size(message.body) == 0
    end

    test "Multiple Via headers are parsed properly" do
      raw_message = """
      SIP/2.0 200 OK\r
      Via: SIP/2.0/UDP server1.example.com;branch=z9hG4bK87asdks7\r
      Via: SIP/2.0/UDP client.atlanta.com;branch=z9hG4bK776asdhds;received=192.0.2.1\r
      To: Bob <sip:bob@biloxi.com>;tag=a6c85cf\r
      From: Alice <sip:alice@atlanta.com>;tag=1928301774\r
      Call-ID: a84b4c76e66710@pc33.atlanta.com\r
      CSeq: 314159 INVITE\r
      Contact: <sip:bob@192.0.2.4>\r
      Content-Length: 0\r
      \r
      """

      {:ok, message} = Parser.parse(raw_message)

      via_list = message.headers["via"]
      assert is_list(via_list)
      assert length(via_list) == 2

      [first_via, second_via] = via_list
      assert is_map(first_via)
      assert is_map(second_via)

      assert first_via.host == "server1.example.com"
      assert second_via.host == "client.atlanta.com"
      assert second_via.parameters["received"] == "192.0.2.1"
    end
  end
end
