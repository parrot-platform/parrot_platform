defmodule Parrot.Sip.SimpleHeaderTest do
  use ExUnit.Case, async: true

  alias Parrot.Sip.Parser

  test "parsing headers produces usable map values" do
    raw_message = """
    INVITE sip:bob@biloxi.com SIP/2.0\r
    Via: SIP/2.0/UDP pc33.atlanta.com;branch=z9hG4bK776asdhds\r
    To: Bob <sip:bob@biloxi.com>\r
    From: Alice <sip:alice@atlanta.com>;tag=1928301774\r
    Call-ID: a84b4c76e66710@pc33.atlanta.com\r
    CSeq: 314159 INVITE\r
    Content-Length: 0\r
    \r
    """

    {:ok, message} = Parser.parse(raw_message)

    # Check that headers are maps with expected keys
    via = message.headers["via"]
    assert is_map(via)
    assert via.host == "pc33.atlanta.com"
    assert via.transport == :udp

    from = message.headers["from"]
    assert is_map(from)
    assert from.display_name == "Alice"
    assert from.uri.scheme == "sip"
    assert from.uri.user == "alice"
    assert from.uri.host == "atlanta.com"

    to = message.headers["to"]
    assert is_map(to)
    assert to.display_name == "Bob"
    assert to.uri.scheme == "sip"
    assert to.uri.user == "bob"
    assert to.uri.host == "biloxi.com"

    cseq = message.headers["cseq"]
    assert is_map(cseq)
    assert cseq.number == 314_159
    assert cseq.method == :invite

    # Primitives should be directly accessible
    assert message.headers["call-id"] == "a84b4c76e66710@pc33.atlanta.com"
    assert message.headers["content-length"].value == 0
  end
end
