defmodule Parrot.Sip.ConnectionTest do
  use ExUnit.Case, async: true

  alias Parrot.Sip.Connection
  alias Parrot.Sip.Message

  describe "new/6" do
    test "creates a new connection with specified parameters" do
      conn =
        Connection.new({127, 0, 0, 1}, 5060, {192, 168, 1, 2}, 5070, :udp, %{
          source_id: "test_source"
        })

      assert conn.local_addr == {{127, 0, 0, 1}, 5060}
      assert conn.remote_addr == {{192, 168, 1, 2}, 5070}
      assert conn.transport == :udp
      assert conn.options == %{source_id: "test_source"}
    end

    test "creates a new connection for stream transport" do
      conn = Connection.new({127, 0, 0, 1}, 5060, {192, 168, 1, 2}, 5070, :tcp)

      assert conn.local_addr == {{127, 0, 0, 1}, 5060}
      assert conn.remote_addr == {{192, 168, 1, 2}, 5070}
      assert conn.transport == :tcp
    end
  end

  describe "conn_data/2" do
    test "processes a valid SIP request" do
      conn = Connection.new({127, 0, 0, 1}, 5060, {192, 168, 1, 2}, 5070, :udp)

      request = """
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

      {_conn, {:new_request, message}} = Connection.conn_data(request, conn)

      assert message.method == :invite
      assert message.request_uri == "sip:bob@biloxi.com"
      assert message.source != nil
    end

    test "processes a valid SIP response" do
      conn = Connection.new({127, 0, 0, 1}, 5060, {192, 168, 1, 2}, 5070, :udp)

      response = """
      SIP/2.0 200 OK\r
      Via: SIP/2.0/UDP pc33.atlanta.com;branch=z9hG4bK776asdhds\r
      To: Bob <sip:bob@biloxi.com>;tag=a6c85cf\r
      From: Alice <sip:alice@atlanta.com>;tag=1928301774\r
      Call-ID: a84b4c76e66710@pc33.atlanta.com\r
      CSeq: 314159 INVITE\r
      Contact: <sip:bob@192.0.2.4>\r
      Content-Length: 0\r
      \r
      """

      {_conn, {:new_response, _via, message}} = Connection.conn_data(response, conn)

      assert message.status_code == 200
      assert message.reason_phrase == "OK"
      assert message.source != nil
    end

    test "handles invalid SIP message" do
      conn = Connection.new({127, 0, 0, 1}, 5060, {192, 168, 1, 2}, 5070, :udp)

      invalid_message = "This is not a valid SIP message"

      {_conn, {:bad_message, _, _}} = Connection.conn_data(invalid_message, conn)
    end

    test "adds received parameter to Via header" do
      conn = Connection.new({127, 0, 0, 1}, 5060, {192, 168, 1, 2}, 5070, :udp)

      request = """
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

      {_conn, {:new_request, message}} = Connection.conn_data(request, conn)

      via_header = Message.get_header(message, "via")
      assert via_header.parameters["received"] == "192.168.1.2"
    end

    test "adds rport parameter to Via header when rport is present" do
      conn = Connection.new({127, 0, 0, 1}, 5060, {192, 168, 1, 2}, 5070, :udp)

      request = """
      INVITE sip:bob@biloxi.com SIP/2.0\r
      Via: SIP/2.0/UDP pc33.atlanta.com;branch=z9hG4bK776asdhds;rport\r
      Max-Forwards: 70\r
      To: Bob <sip:bob@biloxi.com>\r
      From: Alice <sip:alice@atlanta.com>;tag=1928301774\r
      Call-ID: a84b4c76e66710@pc33.atlanta.com\r
      CSeq: 314159 INVITE\r
      Contact: <sip:alice@pc33.atlanta.com>\r
      Content-Length: 0\r
      \r
      """

      {_conn, {:new_request, message}} = Connection.conn_data(request, conn)

      via_header = Message.get_header(message, "via")

      assert via_header.host == "pc33.atlanta.com"
      assert via_header.host_type == :hostname
      assert via_header.parameters["branch"] == "z9hG4bK776asdhds"
      assert via_header.parameters["received"] == "192.168.1.2"
      assert via_header.parameters["rport"] == "5070"
    end

    test "does not add rport parameter to Via header when rport is not present" do
      conn = Connection.new({127, 0, 0, 1}, 5060, {192, 168, 1, 2}, 5070, :udp)

      request = """
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

      {_conn, {:new_request, message}} = Connection.conn_data(request, conn)

      via_header = Message.get_header(message, "via")
      refute via_header.parameters["rport"] == "5070"
    end
  end

  describe "source/1" do
    test "creates a source struct from connection" do
      conn =
        Connection.new({127, 0, 0, 1}, 5060, {192, 168, 1, 2}, 5070, :udp, %{
          source_id: "test_source"
        })

      source = Connection.source(conn)

      assert source.local == {{127, 0, 0, 1}, 5060}
      assert source.remote == {{192, 168, 1, 2}, 5070}
      assert source.transport == :udp
      assert source.source_id == "test_source"
    end
  end
end
