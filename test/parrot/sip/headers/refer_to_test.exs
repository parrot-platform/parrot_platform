defmodule Parrot.Sip.Headers.ReferToTest do
  use ExUnit.Case

  alias Parrot.Sip.Headers.ReferTo
  alias Parrot.Sip.Uri

  describe "parsing Refer-To headers" do
    test "parses simple Refer-To header" do
      header = "<sip:alice@example.com>"
      refer_to = ReferTo.parse(header)

      assert refer_to.display_name == nil
      uri = refer_to.uri
      assert is_struct(uri, Uri)
      assert uri.scheme == "sip"
      assert uri.user == "alice"
      assert uri.host == "example.com"
      assert refer_to.parameters == %{}
    end

    test "parses Refer-To header with display name" do
      header = "Alice <sip:alice@example.com>"
      refer_to = ReferTo.parse(header)

      assert refer_to.display_name == "Alice"
      uri = refer_to.uri
      assert is_struct(uri, Uri)
      assert uri.scheme == "sip"
      assert uri.user == "alice"
      assert uri.host == "example.com"
      assert refer_to.parameters == %{}
    end

    test "parses Refer-To header with quoted display name" do
      header = "\"Alice Smith\" <sip:alice@example.com>"
      refer_to = ReferTo.parse(header)

      assert refer_to.display_name == "Alice Smith"
      uri = refer_to.uri
      assert is_struct(uri, Uri)
      assert uri.scheme == "sip"
      assert uri.user == "alice"
      assert uri.host == "example.com"
      assert refer_to.parameters == %{}
    end

    test "parses Refer-To header with parameters" do
      header = "<sip:alice@example.com>;method=INVITE;early-only"
      refer_to = ReferTo.parse(header)

      assert refer_to.display_name == nil
      assert is_struct(refer_to.uri, Uri)
      assert refer_to.uri.scheme == "sip"
      assert refer_to.uri.user == "alice"
      assert refer_to.uri.host == "example.com"
      assert refer_to.parameters == %{"method" => "INVITE", "early-only" => ""}
    end

    test "parses Refer-To header with Replaces parameter" do
      header =
        "<sip:alice@example.com?Replaces=12345%40example.com%3Bto-tag%3D12345%3Bfrom-tag%3D54321>"

      refer_to = ReferTo.parse(header)

      assert refer_to.display_name == nil
      uri = refer_to.uri
      assert is_struct(uri, Parrot.Sip.Uri)
      assert uri.scheme == "sip"
      assert uri.user == "alice"
      assert uri.host == "example.com"
      assert uri.headers["Replaces"] == "12345%40example.com%3Bto-tag%3D12345%3Bfrom-tag%3D54321"
      assert refer_to.parameters == %{}
    end

    test "parses Refer-To header with Replaces and parameters" do
      header =
        "<sip:alice@example.com?Replaces=12345%40example.com%3Bto-tag%3D12345%3Bfrom-tag%3D54321>;method=INVITE"

      refer_to = ReferTo.parse(header)

      assert refer_to.display_name == nil
      uri = refer_to.uri
      assert is_struct(uri, Parrot.Sip.Uri)
      assert uri.scheme == "sip"
      assert uri.user == "alice"
      assert uri.host == "example.com"
      assert uri.headers["Replaces"] == "12345%40example.com%3Bto-tag%3D12345%3Bfrom-tag%3D54321"
      assert refer_to.parameters == %{"method" => "INVITE"}
    end

    test "parses Refer-To header with URI parameters and headers" do
      header =
        "<sip:alice@example.com;transport=tcp?Replaces=12345%40example.com%3Bto-tag%3D12345%3Bfrom-tag%3D54321>"

      refer_to = ReferTo.parse(header)

      assert refer_to.display_name == nil
      uri = refer_to.uri
      assert is_struct(uri, Parrot.Sip.Uri)
      assert uri.scheme == "sip"
      assert uri.user == "alice"
      assert uri.host == "example.com"
      assert uri.parameters["transport"] == "tcp"
      assert uri.headers["Replaces"] == "12345%40example.com%3Bto-tag%3D12345%3Bfrom-tag%3D54321"
      assert refer_to.parameters == %{}
    end
  end

  describe "formatting Refer-To headers" do
    test "formats simple Refer-To header" do
      uri = %Uri{
        scheme: "sip",
        user: "alice",
        host: "example.com"
      }

      refer_to = %ReferTo{
        display_name: nil,
        uri: uri,
        parameters: %{}
      }

      assert ReferTo.format(refer_to) == "<sip:alice@example.com>"
    end

    test "formats Refer-To header with display name" do
      uri = %Uri{
        scheme: "sip",
        user: "alice",
        host: "example.com"
      }

      refer_to = %ReferTo{
        display_name: "Alice",
        uri: uri,
        parameters: %{}
      }

      assert ReferTo.format(refer_to) == "Alice <sip:alice@example.com>"
    end

    test "formats Refer-To header with parameters" do
      uri = %Uri{
        scheme: "sip",
        user: "alice",
        host: "example.com"
      }

      refer_to = %ReferTo{
        display_name: nil,
        uri: uri,
        parameters: %{"method" => "INVITE", "early-only" => ""}
      }

      formatted = ReferTo.format(refer_to)

      assert formatted == "<sip:alice@example.com>;method=INVITE;early-only" ||
               formatted == "<sip:alice@example.com>;early-only;method=INVITE"
    end
  end

  describe "extracting URI parameters and headers" do
    test "extracts URI parameters" do
      uri = %Uri{
        scheme: "sip",
        user: "alice",
        host: "example.com",
        parameters: %{"transport" => "tcp", "lr" => ""}
      }

      refer_to = %ReferTo{uri: uri}

      params = ReferTo.uri_parameters(refer_to)
      assert params == %{"transport" => "tcp", "lr" => ""}
    end

    test "extracts URI headers" do
      uri = %Uri{
        scheme: "sip",
        user: "alice",
        host: "example.com",
        headers: %{
          "Replaces" => "12345%40example.com%3Bto-tag%3D12345%3Bfrom-tag%3D54321",
          "Priority" => "urgent"
        }
      }

      refer_to = %ReferTo{uri: uri}

      headers = ReferTo.uri_headers(refer_to)

      assert headers == %{
               "Replaces" => "12345%40example.com%3Bto-tag%3D12345%3Bfrom-tag%3D54321",
               "Priority" => "urgent"
             }
    end

    test "returns empty map for no URI parameters" do
      uri = %Uri{
        scheme: "sip",
        user: "alice",
        host: "example.com"
      }

      refer_to = %ReferTo{uri: uri}

      assert ReferTo.uri_parameters(refer_to) == %{}
    end

    test "returns empty map for no URI headers" do
      uri = %Uri{
        scheme: "sip",
        user: "alice",
        host: "example.com"
      }

      refer_to = %ReferTo{uri: uri}

      assert ReferTo.uri_headers(refer_to) == %{}
    end
  end

  describe "handling Replaces parameter" do
    test "extracts Replaces parameter" do
      uri = %Uri{
        scheme: "sip",
        user: "alice",
        host: "example.com",
        headers: %{"Replaces" => "12345%40example.com%3Bto-tag%3D12345%3Bfrom-tag%3D54321"}
      }

      refer_to = %ReferTo{uri: uri}

      replaces = ReferTo.replaces(refer_to)
      assert replaces == "12345@example.com;to-tag=12345;from-tag=54321"
    end

    test "returns nil when no Replaces parameter" do
      uri = %Uri{
        scheme: "sip",
        user: "alice",
        host: "example.com"
      }

      refer_to = %ReferTo{uri: uri}

      assert ReferTo.replaces(refer_to) == nil
    end

    test "parses Replaces parameter components" do
      uri = %Uri{
        scheme: "sip",
        user: "alice",
        host: "example.com",
        headers: %{"Replaces" => "12345%40example.com%3Bto-tag%3D12345%3Bfrom-tag%3D54321"}
      }

      refer_to = %ReferTo{uri: uri}

      components = ReferTo.parse_replaces(refer_to)

      assert components == %{
               "call_id" => "12345@example.com",
               "to_tag" => "12345",
               "from_tag" => "54321"
             }
    end

    test "returns nil when parsing Replaces but none exists" do
      uri = %Uri{
        scheme: "sip",
        user: "alice",
        host: "example.com"
      }

      refer_to = %ReferTo{uri: uri}

      assert ReferTo.parse_replaces(refer_to) == nil
    end

    test "creates Refer-To header with Replaces parameter" do
      refer_to =
        ReferTo.new_with_replaces(
          "sip:bob@example.com",
          "Bob",
          "call123@example.com",
          "to-tag-123",
          "from-tag-456"
        )

      assert refer_to.display_name == "Bob"
      uri = refer_to.uri
      assert is_struct(uri, Uri)
      assert uri.scheme == "sip"
      assert uri.user == "bob"
      assert uri.host == "example.com"

      replaces = ReferTo.replaces(refer_to)
      assert replaces == "call123@example.com;to-tag=to-tag-123;from-tag=from-tag-456"

      components = ReferTo.parse_replaces(refer_to)
      assert components["call_id"] == "call123@example.com"
      assert components["to_tag"] == "to-tag-123"
      assert components["from_tag"] == "from-tag-456"
    end
  end
end
