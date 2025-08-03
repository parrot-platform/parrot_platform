defmodule Parrot.Sip.ParserTest do
  use ExUnit.Case

  alias Parrot.Sip.Parser

  describe "parse/1" do
    test "parses a basic SIP request" do
      raw_message = """
      INVITE sip:user@example.com SIP/2.0\r
      Via: SIP/2.0/UDP 192.168.1.1:5060;branch=z9hG4bK776asdhds\r
      To: <sip:user@example.com>\r
      From: <sip:caller@example.net>;tag=1928301774\r
      Call-ID: a84b4c76e66710\r
      CSeq: 1 INVITE\r
      Max-Forwards: 70\r
      Content-Length: 0\r
      \r
      """

      {:ok, message} = Parser.parse(raw_message)

      assert message.method == :invite
      assert message.request_uri == "sip:user@example.com"
      assert message.version == "SIP/2.0"
      assert message.type == :request
      assert message.direction == :incoming
    end

    test "parses a basic SIP response" do
      raw_message = """
      SIP/2.0 200 OK\r
      Via: SIP/2.0/UDP 192.168.1.1:5060;branch=z9hG4bK776asdhds\r
      To: <sip:user@example.com>;tag=93810874\r
      From: <sip:caller@example.net>;tag=1928301774\r
      Call-ID: a84b4c76e66710\r
      CSeq: 1 INVITE\r
      Content-Length: 0\r
      \r
      """

      {:ok, message} = Parser.parse(raw_message)

      assert message.status_code == 200
      assert message.reason_phrase == "OK"
      assert message.version == "SIP/2.0"
      assert message.type == :response
      assert message.direction == :incoming
    end

    test "handles request with multiple header values" do
      raw_message = """
      REGISTER sip:registrar.example.com SIP/2.0\r
      Via: SIP/2.0/UDP 192.0.2.1:5060;branch=z9hG4bK776asdhds\r
      To: <sip:user@example.com>\r
      From: <sip:user@example.com>;tag=1928301774\r
      Call-ID: a84b4c76e66710\r
      CSeq: 1 REGISTER\r
      Contact: <sip:user@192.0.2.1>;q=0.7;expires=3600\r
      Contact: <sip:user@192.0.2.2>;q=0.5\r
      Supported: path, 100rel\r
      Allow: INVITE, ACK, CANCEL, OPTIONS, BYE\r
      Content-Length: 0\r
      \r
      """

      {:ok, message} = Parser.parse(raw_message)

      assert message.method == :register
      assert message.headers["supported"] == ["path", "100rel"]
      # Allow header now uses a method set struct
      allow_methods = message.headers["allow"]
      assert Enum.member?(allow_methods, :invite)
      assert Enum.member?(allow_methods, :ack)
      assert Enum.member?(allow_methods, :cancel)
      assert Enum.member?(allow_methods, :options)
      assert Enum.member?(allow_methods, :bye)
    end

    test "handles different header case sensitivity properly" do
      raw_message = """
      INVITE sip:user@example.com SIP/2.0\r
      via: SIP/2.0/UDP 192.168.1.1:5060;branch=z9hG4bK776asdhds\r
      To: <sip:user@example.com>\r
      FROM: <sip:caller@example.net>;tag=1928301774\r
      Call-ID: a84b4c76e66710\r
      CSeq: 1 INVITE\r
      Max-Forwards: 70\r
      CONTENT-length: 0\r
      \r
      """

      {:ok, message} = Parser.parse(raw_message)

      assert message.headers["via"]
      assert message.headers["from"]
      assert message.headers["content-length"].value == 0
    end

    test "parses request with custom headers" do
      raw_message = """
      SUBSCRIBE sip:user@example.com SIP/2.0\r
      Via: SIP/2.0/UDP 192.168.1.1:5060;branch=z9hG4bK776asdhds\r
      To: <sip:user@example.com>\r
      From: <sip:caller@example.net>;tag=1928301774\r
      Call-ID: a84b4c76e66710\r
      CSeq: 1 SUBSCRIBE\r
      Event: presence\r
      Expires: 3600\r
      X-Custom-Header: CustomValue\r
      Content-Length: 0\r
      \r
      """

      {:ok, message} = Parser.parse(raw_message)

      assert message.method == :subscribe
      assert message.headers["event"].event == "presence"
      assert message.headers["expires"] == 3600
      assert message.headers["x-custom-header"] == "CustomValue"
    end

    test "handles empty header values" do
      raw_message = """
      OPTIONS sip:user@example.com SIP/2.0\r
      Via: SIP/2.0/UDP 192.168.1.1:5060;branch=z9hG4bK776asdhds\r
      To: <sip:user@example.com>\r
      From: <sip:caller@example.net>;tag=1928301774\r
      Call-ID: a84b4c76e66710\r
      CSeq: 1 OPTIONS\r
      Subject: \r
      Content-Length: 0\r
      \r
      """

      {:ok, message} = Parser.parse(raw_message)

      assert message.method == :options
      # Empty subject header is parsed into a Subject struct with empty value
      assert message.headers["subject"].value == ""
    end

    test "handles whitespace in header values" do
      raw_message = """
      INVITE sip:user@example.com SIP/2.0\r
      Via:     SIP/2.0/UDP 192.168.1.1:5060;branch=z9hG4bK776asdhds\r
      To:    <sip:user@example.com>\r
      From:  <sip:caller@example.net>;tag=1928301774\r
      Call-ID:      a84b4c76e66710\r
      CSeq:  1 INVITE\r
      Content-Length:   0\r
      \r
      """

      {:ok, message} = Parser.parse(raw_message)

      assert message.method == :invite
      assert message.headers["call-id"] == "a84b4c76e66710"
      assert message.headers["cseq"].number == 1
    end

    test "handles folded header values" do
      raw_message = """
      INVITE sip:user@example.com SIP/2.0\r
      Via: SIP/2.0/UDP 192.168.1.1:5060;branch=z9hG4bK776asdhds\r
      Subject: This is a\r
       folded header\r
       value\r
      To: <sip:user@example.com>\r
      From: <sip:caller@example.net>;tag=1928301774\r
      Call-ID: a84b4c76e66710\r
      CSeq: 1 INVITE\r
      Content-Length: 0\r
      \r
      """

      {:ok, message} = Parser.parse(raw_message)

      assert message.method == :invite
      assert message.headers["subject"].value == "This is a folded header value"
    end

    test "handles complex display names in address headers" do
      raw_message = """
      INVITE sip:user@example.com SIP/2.0\r
      Via: SIP/2.0/UDP 192.168.1.1:5060;branch=z9hG4bK776asdhds\r
      To: "User Name (with parentheses)" <sip:user@example.com>\r
      From: "Caller \"with quotes\"" <sip:caller@example.net>;tag=1928301774\r
      Call-ID: a84b4c76e66710\r
      CSeq: 1 INVITE\r
      Content-Length: 0\r
      \r
      """

      {:ok, message} = Parser.parse(raw_message)

      # Display name might include quotes in the internal representation
      assert String.replace(message.headers["to"].display_name, "\"", "") ==
               "User Name (with parentheses)"

      # For from header with escaped quotes, we need to handle differently
      from_display = message.headers["from"].display_name
      # Remove surrounding quotes if present
      from_display = String.replace(from_display, ~r/^"|"$/, "")
      assert from_display == "Caller \"with quotes\""
    end

    test "rejects invalid message with invalid CRLF" do
      raw_message = """
      INVITE sip:user@example.com SIP/2.0
      Via: SIP/2.0/UDP 192.168.1.1:5060;branch=z9hG4bK776asdhds
      To: <sip:user@example.com>
      From: <sip:caller@example.net>;tag=1928301774
      Call-ID: a84b4c76e66710
      CSeq: 1 INVITE
      Content-Length: 0

      """

      assert {:error, _reason} = Parser.parse(raw_message)
    end

    test "rejects message with missing required headers" do
      raw_message = """
      INVITE sip:user@example.com SIP/2.0\r
      Via: SIP/2.0/UDP 192.168.1.1:5060;branch=z9hG4bK776asdhds\r
      To: <sip:user@example.com>\r
      From: <sip:caller@example.net>;tag=1928301774\r
      Content-Length: 0\r
      \r
      """

      assert {:error, _reason} = Parser.parse(raw_message)
    end

    test "rejects malformed request line" do
      raw_message = """
      MALFORMED REQUEST LINE\r
      Via: SIP/2.0/UDP 192.168.1.1:5060;branch=z9hG4bK776asdhds\r
      To: <sip:user@example.com>\r
      From: <sip:caller@example.net>;tag=1928301774\r
      Call-ID: a84b4c76e66710\r
      CSeq: 1 INVITE\r
      Content-Length: 0\r
      \r
      """

      assert {:error, _reason} = Parser.parse(raw_message)
    end
  end
end
