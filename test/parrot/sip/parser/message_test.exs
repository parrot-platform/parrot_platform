defmodule Parrot.Sip.Parser.MessageTest do
  use ExUnit.Case

  alias Parrot.Sip.Parser
  alias Parrot.Sip.Headers.Via

  describe "Headers.Via.topmost/1 and take_topmost/1" do
    test "topmost/1 returns the first Via from a SIP message struct" do
      raw = """
      SIP/2.0 200 OK\r
      Via: SIP/2.0/UDP host1;branch=abc\r
      Via: SIP/2.0/TCP host2;branch=def\r
      To: <sip:bob@biloxi.com>\r
      From: <sip:alice@atlanta.com>;tag=123\r
      Call-ID: abc123@host\r
      CSeq: 1 INVITE\r
      \r
      """

      {:ok, msg} = Parser.parse(raw)
      top = Via.topmost(msg)
      assert top.host == "host1"
      assert top.parameters["branch"] == "abc"
      assert top.transport == :udp
    end

    test "topmost/1 returns the only Via from a SIP message struct with one Via" do
      raw = """
      SIP/2.0 200 OK\r
      Via: SIP/2.0/UDP host1;branch=abc\r
      To: <sip:bob@biloxi.com>\r
      From: <sip:alice@atlanta.com>;tag=123\r
      Call-ID: abc123@host\r
      CSeq: 1 INVITE\r
      \r
      """

      {:ok, msg} = Parser.parse(raw)
      top = Via.topmost(msg)
      assert top.host == "host1"
      assert top.parameters["branch"] == "abc"
      assert top.transport == :udp
    end

    test "take_topmost/1 returns {topmost, rest} from a SIP message struct with multiple vias" do
      raw = """
      SIP/2.0 200 OK\r
      Via: SIP/2.0/UDP host1;branch=abc\r
      Via: SIP/2.0/TCP host2;branch=def\r
      To: <sip:bob@biloxi.com>\r
      From: <sip:alice@atlanta.com>;tag=123\r
      Call-ID: abc123@host\r
      CSeq: 1 INVITE\r
      \r
      """

      {:ok, msg} = Parser.parse(raw)
      {top, rest} = Via.take_topmost(msg)
      assert top.host == "host1"
      assert Enum.at(rest, 0).host == "host2"
      assert Enum.at(rest, 0).parameters["branch"] == "def"
    end

    test "take_topmost/1 returns {topmost, nil} from a SIP message struct with one Via" do
      raw = """
      SIP/2.0 200 OK\r
      Via: SIP/2.0/UDP host1;branch=abc\r
      To: <sip:bob@biloxi.com>\r
      From: <sip:alice@atlanta.com>;tag=123\r
      Call-ID: abc123@host\r
      CSeq: 1 INVITE\r
      \r
      """

      {:ok, msg} = Parser.parse(raw)
      {top, rest} = Via.take_topmost(msg)
      assert top.host == "host1"
      assert rest == nil
    end
  end

  describe "parsing SIP requests" do
    test "parses an INVITE request" do
      # Use a fixed body with precise line endings for content length calculation
      body =
        "v=0\r\no=alice 2890844526 2890844526 IN IP4 pc33.atlanta.com\r\ns=Session SDP\r\nc=IN IP4 pc33.atlanta.com\r\nt=0 0\r\nm=audio 49172 RTP/AVP 0\r\na=rtpmap:0 PCMU/8000"

      content_length = byte_size(body)

      # Construct the raw message with exact Content-Length
      raw_message =
        "INVITE sip:bob@biloxi.com SIP/2.0\r\n" <>
          "Via: SIP/2.0/UDP pc33.atlanta.com;branch=z9hG4bK776asdhds\r\n" <>
          "Max-Forwards: 70\r\n" <>
          "To: Bob <sip:bob@biloxi.com>\r\n" <>
          "From: Alice <sip:alice@atlanta.com>;tag=1928301774\r\n" <>
          "Call-ID: a84b4c76e66710@pc33.atlanta.com\r\n" <>
          "CSeq: 314159 INVITE\r\n" <>
          "Contact: <sip:alice@pc33.atlanta.com>\r\n" <>
          "Content-Type: application/sdp\r\n" <>
          "Content-Length: #{content_length}\r\n\r\n" <>
          body

      result = Parser.parse(raw_message)

      {:ok, message} = result

      assert message.method == :invite
      assert message.request_uri == "sip:bob@biloxi.com"
      assert message.version == "SIP/2.0"
      assert message.type == :request
      assert message.direction == :incoming

      # Check headers
      assert message.headers["via"].host == "pc33.atlanta.com"
      assert message.headers["via"].parameters["branch"] == "z9hG4bK776asdhds"

      assert message.headers["from"].display_name == "Alice"
      # URI is now a struct
      assert message.headers["from"].uri.scheme == "sip"
      assert message.headers["from"].uri.user == "alice"
      assert message.headers["from"].uri.host == "atlanta.com"
      assert message.headers["from"].parameters["tag"] == "1928301774"

      assert message.headers["to"].display_name == "Bob"
      # URI is now a struct
      assert message.headers["to"].uri.scheme == "sip"
      assert message.headers["to"].uri.user == "bob"
      assert message.headers["to"].uri.host == "biloxi.com"

      assert message.headers["call-id"] == "a84b4c76e66710@pc33.atlanta.com"

      assert message.headers["cseq"].number == 314_159
      assert message.headers["cseq"].method == :invite

      assert message.headers["content-type"].type == "application"
      assert message.headers["content-type"].subtype == "sdp"
      assert message.headers["content-length"].value == content_length

      # Check body content
      assert message.body =~ "v=0"
      assert message.body =~ "m=audio 49172 RTP/AVP 0"
      # Verify exact content length match
      assert byte_size(message.body) == message.headers["content-length"].value
      assert byte_size(message.body) == content_length
    end

    test "parses a REGISTER request" do
      raw_message = """
      REGISTER sip:registrar.example.com SIP/2.0\r
      Via: SIP/2.0/UDP 192.0.2.1:5060;branch=z9hG4bKnashds7\r
      Max-Forwards: 70\r
      To: Bob <sip:bob@example.com>\r
      From: Bob <sip:bob@example.com>;tag=a73kszlfl\r
      Call-ID: 1j9FpLxk3uxtm8tn@192.0.2.1\r
      CSeq: 1 REGISTER\r
      Contact: <sip:bob@192.0.2.1>\r
      Expires: 3600\r
      Content-Length: 0\r
      \r
      """

      {:ok, message} = Parser.parse(raw_message)

      assert message.method == :register
      assert message.request_uri == "sip:registrar.example.com"

      assert message.headers["to"].display_name == "Bob"
      assert message.headers["to"].uri.scheme == "sip"
      assert message.headers["to"].uri.user == "bob"
      assert message.headers["to"].uri.host == "example.com"

      assert message.headers["from"].display_name == "Bob"
      assert message.headers["from"].uri.scheme == "sip"
      assert message.headers["from"].uri.user == "bob"
      assert message.headers["from"].uri.host == "example.com"
      assert message.headers["from"].parameters["tag"] == "a73kszlfl"

      assert message.headers["expires"] == 3600
      assert message.headers["call-id"] == "1j9FpLxk3uxtm8tn@192.0.2.1"

      assert message.headers["cseq"].number == 1
      assert message.headers["cseq"].method == :register

      assert message.headers["content-length"].value == 0
      assert message.body == ""
    end

    test "parses an OPTIONS request" do
      raw_message = """
      OPTIONS sip:bob@example.com SIP/2.0\r
      Via: SIP/2.0/UDP 192.168.1.100:5060;branch=z9hG4bK776asdhds\r
      Max-Forwards: 70\r
      To: <sip:bob@example.com>\r
      From: <sip:alice@example.com>;tag=1928301774\r
      Call-ID: a84b4c76e66710@192.168.1.100\r
      CSeq: 63104 OPTIONS\r
      Contact: <sip:alice@192.168.1.100>\r
      Accept: application/sdp\r
      Content-Length: 0\r
      \r
      """

      {:ok, message} = Parser.parse(raw_message)

      assert message.method == :options
      assert message.request_uri == "sip:bob@example.com"

      assert message.headers["to"].display_name == nil
      assert message.headers["to"].uri.scheme == "sip"
      assert message.headers["to"].uri.user == "bob"
      assert message.headers["to"].uri.host == "example.com"

      assert message.headers["from"].display_name == nil
      assert message.headers["from"].uri.scheme == "sip"
      assert message.headers["from"].uri.user == "alice"
      assert message.headers["from"].uri.host == "example.com"

      assert message.headers["accept"].type == "application"
      assert message.headers["accept"].subtype == "sdp"
      assert message.headers["content-length"].value == 0
      assert message.body == ""
    end
  end

  describe "parsing SIP responses" do
    test "parses a 200 OK response" do
      raw_message = """
      SIP/2.0 200 OK\r
      Via: SIP/2.0/UDP server10.biloxi.com;branch=z9hG4bKnashds8;received=192.0.2.3\r
      Via: SIP/2.0/UDP bigbox3.site3.atlanta.com;branch=z9hG4bK77ef4c2312983.1;received=192.0.2.2\r
      Via: SIP/2.0/UDP pc33.atlanta.com;branch=z9hG4bK776asdhds;received=192.0.2.1\r
      To: Bob <sip:bob@biloxi.com>;tag=a6c85cf\r
      From: Alice <sip:alice@atlanta.com>;tag=1928301774\r
      Call-ID: a84b4c76e66710@pc33.atlanta.com\r
      CSeq: 314159 INVITE\r
      Contact: <sip:bob@192.0.2.4>\r
      Content-Type: application/sdp\r
      Content-Length: 121\r
      \r
      v=0
      o=bob 2890844527 2890844527 IN IP4 192.0.2.4
      s=
      c=IN IP4 192.0.2.4
      t=0 0
      m=audio 3456 RTP/AVP 0
      a=rtpmap:0 PCMU/8000
      """

      {:ok, message} = Parser.parse(raw_message)

      assert message.status_code == 200
      assert message.reason_phrase == "OK"
      assert message.version == "SIP/2.0"
      assert message.type == :response
      assert message.direction == :incoming

      # Check Via headers (should be a list)
      via_list = message.headers["via"]
      assert length(via_list) == 3
      [via1, via2, via3] = via_list

      assert via1.host == "server10.biloxi.com"
      assert via1.parameters["branch"] == "z9hG4bKnashds8"
      assert via1.parameters["received"] == "192.0.2.3"

      assert via2.host == "bigbox3.site3.atlanta.com"
      assert via3.host == "pc33.atlanta.com"

      assert message.headers["to"].display_name == "Bob"
      assert message.headers["to"].uri.scheme == "sip"
      assert message.headers["to"].uri.user == "bob"
      assert message.headers["to"].uri.host == "biloxi.com"
      assert message.headers["to"].parameters["tag"] == "a6c85cf"

      assert message.headers["cseq"].number == 314_159
      assert message.headers["cseq"].method == :invite

      assert message.headers["content-type"].type == "application"
      assert message.headers["content-type"].subtype == "sdp"
      assert message.headers["content-length"].value == 121

      assert message.body =~ "v=0"
      assert message.body =~ "m=audio 3456 RTP/AVP 0"
    end

    test "parses a 180 Ringing response" do
      raw_message = """
      SIP/2.0 180 Ringing\r
      Via: SIP/2.0/UDP server10.biloxi.com;branch=z9hG4bKnashds8;received=192.0.2.3\r
      Via: SIP/2.0/UDP bigbox3.site3.atlanta.com;branch=z9hG4bK77ef4c2312983.1;received=192.0.2.2\r
      Via: SIP/2.0/UDP pc33.atlanta.com;branch=z9hG4bK776asdhds;received=192.0.2.1\r
      To: Bob <sip:bob@biloxi.com>;tag=a6c85cf\r
      From: Alice <sip:alice@atlanta.com>;tag=1928301774\r
      Call-ID: a84b4c76e66710@pc33.atlanta.com\r
      Contact: <sip:bob@192.0.2.4>\r
      CSeq: 314159 INVITE\r
      Content-Length: 0\r
      \r
      """

      {:ok, message} = Parser.parse(raw_message)

      assert message.status_code == 180
      assert message.reason_phrase == "Ringing"
      assert message.type == :response
      assert message.direction == :incoming

      via_list = message.headers["via"]
      assert length(via_list) == 3

      assert message.headers["to"].display_name == "Bob"
      assert message.headers["to"].parameters["tag"] == "a6c85cf"

      assert message.headers["from"].display_name == "Alice"
      assert message.headers["from"].parameters["tag"] == "1928301774"

      assert message.headers["cseq"].number == 314_159
      assert message.headers["cseq"].method == :invite

      assert message.headers["content-length"].value == 0
      assert message.body == ""
    end

    test "parses a 404 Not Found response" do
      raw_message = """
      SIP/2.0 404 Not Found\r
      Via: SIP/2.0/UDP server10.biloxi.com;branch=z9hG4bKnashds8;received=192.0.2.3\r
      To: Bob <sip:bob@biloxi.com>;tag=a6c85cf\r
      From: Alice <sip:alice@atlanta.com>;tag=1928301774\r
      Call-ID: a84b4c76e66710@pc33.atlanta.com\r
      CSeq: 314159 INVITE\r
      Content-Length: 0\r
      \r
      """

      {:ok, message} = Parser.parse(raw_message)

      assert message.status_code == 404
      assert message.reason_phrase == "Not Found"
      assert message.type == :response
      assert message.direction == :incoming

      assert message.headers["to"].display_name == "Bob"
      assert message.headers["to"].parameters["tag"] == "a6c85cf"

      assert message.headers["cseq"].number == 314_159
      assert message.headers["cseq"].method == :invite
    end
  end

  describe "handling malformed messages" do
    test "returns error for missing request line" do
      raw_message = """
      Via: SIP/2.0/UDP pc33.atlanta.com;branch=z9hG4bK776asdhds\r
      Max-Forwards: 70\r
      \r
      """

      assert {:error, reason} = Parser.parse(raw_message)
      assert reason =~ "Invalid SIP message format"
    end

    test "returns error for invalid request method" do
      raw_message = """
      UNKNOWN sip:bob@biloxi.com SIP/2.0\r
      Via: SIP/2.0/UDP pc33.atlanta.com;branch=z9hG4bK776asdhds\r
      \r
      """

      assert {:error, reason} = Parser.parse(raw_message)
      assert reason =~ "Invalid SIP message format"
    end

    test "returns error for invalid status code" do
      raw_message = """
      SIP/2.0 999 Invalid Status\r
      Via: SIP/2.0/UDP server10.biloxi.com;branch=z9hG4bKnashds8\r
      \r
      """

      assert {:error, reason} = Parser.parse(raw_message)
      assert reason =~ "Invalid SIP message format"
    end

    test "returns error for missing required headers" do
      raw_message = """
      INVITE sip:bob@biloxi.com SIP/2.0\r
      Max-Forwards: 70\r
      \r
      """

      assert {:error, reason} = Parser.parse(raw_message)
      assert reason =~ "Invalid SIP message format"
    end
  end

  describe "parsing multipart bodies" do
    test "parses a message with multipart/mixed content" do
      raw_message = """
      INVITE sip:bob@biloxi.com SIP/2.0\r
      Via: SIP/2.0/UDP pc33.atlanta.com;branch=z9hG4bK776asdhds\r
      To: Bob <sip:bob@biloxi.com>\r
      From: Alice <sip:alice@atlanta.com>;tag=1928301774\r
      Call-ID: a84b4c76e66710@pc33.atlanta.com\r
      CSeq: 314159 INVITE\r
      Content-Type: multipart/mixed; boundary=boundary42\r
      Content-Length: 270\r
      \r
      --boundary42
      Content-Type: application/sdp

      v=0
      o=alice 2890844526 2890844526 IN IP4 pc33.atlanta.com
      s=Session SDP
      c=IN IP4 pc33.atlanta.com
      t=0 0
      m=audio 49172 RTP/AVP 0

      --boundary42
      Content-Type: text/plain

      This is an example of a multipart message.
      --boundary42--
      """

      {:ok, message} = Parser.parse(raw_message)

      assert message.method == :invite
      assert message.headers["content-type"].type == "multipart"
      assert message.headers["content-type"].subtype == "mixed"
      assert message.headers["content-type"].parameters["boundary"] == "boundary42"

      # Body parsing details would depend on your implementation
      assert message.body =~ "--boundary42"
      assert message.body =~ "application/sdp"
      assert message.body =~ "text/plain"
    end
  end
end
