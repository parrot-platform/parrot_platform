defmodule Parrot.Sip.Headers.FromTest do
  use ExUnit.Case

  alias Parrot.Sip.Headers

  describe "parsing From headers" do
    test "parses From header with display name and tag" do
      header_value = "Alice <sip:alice@atlanta.com>;tag=1928301774"

      from = Headers.From.parse(header_value)

      assert from.display_name == "Alice"
      uri = from.uri
      assert is_struct(uri, Parrot.Sip.Uri)
      assert uri.scheme == "sip"
      assert uri.user == "alice"
      assert uri.host == "atlanta.com"
      assert from.parameters["tag"] == "1928301774"

      formatted = Headers.From.format(from)
      assert String.match?(formatted, ~r/Alice <sip:alice@atlanta\.com>;tag=1928301774/)
    end

    test "parses From header without display name" do
      header_value = "<sip:alice@atlanta.com>;tag=1928301774"

      from = Headers.From.parse(header_value)

      assert from.display_name == nil
      uri = from.uri
      assert is_struct(uri, Parrot.Sip.Uri)
      assert uri.scheme == "sip"
      assert uri.user == "alice"
      assert uri.host == "atlanta.com"
      assert from.parameters["tag"] == "1928301774"

      formatted = Headers.From.format(from)
      assert String.match?(formatted, ~r/<sip:alice@atlanta\.com>;tag=1928301774/)
    end

    test "parses From header without tag" do
      header_value = "Alice <sip:alice@atlanta.com>"

      from = Headers.From.parse(header_value)

      assert from.display_name == "Alice"
      uri = from.uri
      assert is_struct(uri, Parrot.Sip.Uri)
      assert uri.scheme == "sip"
      assert uri.user == "alice"
      assert uri.host == "atlanta.com"
      assert from.parameters == %{}

      formatted = Headers.From.format(from)
      assert String.match?(formatted, ~r/Alice <sip:alice@atlanta\.com>/)
    end

    test "parses From header with quoted display name" do
      header_value = ~s("Alice Smith" <sip:alice@atlanta.com>;tag=1928301774)

      from = Headers.From.parse(header_value)

      assert from.display_name == "\"Alice Smith\""
      uri = from.uri
      assert is_struct(uri, Parrot.Sip.Uri)
      assert uri.scheme == "sip"
      assert uri.user == "alice"
      assert uri.host == "atlanta.com"
      assert from.parameters["tag"] == "1928301774"

      formatted = Headers.From.format(from)
      assert String.match?(formatted, ~r/"Alice Smith" <sip:alice@atlanta\.com>;tag=1928301774/)
    end
  end

  describe "creating From headers" do
    test "creates From header" do
      from = Headers.From.new("sip:alice@atlanta.com", "Alice", "1928301774")

      assert from.display_name == "Alice"
      uri = from.uri
      assert is_struct(uri, Parrot.Sip.Uri)
      assert uri.scheme == "sip"
      assert uri.user == "alice"
      assert uri.host == "atlanta.com"
      assert from.parameters["tag"] == "1928301774"

      formatted = Headers.From.format(from)
      assert String.match?(formatted, ~r/Alice <sip:alice@atlanta\.com>;tag=1928301774/)
    end

    test "generates tag parameter" do
      tag = Headers.From.generate_tag()

      assert is_binary(tag)
      assert String.length(tag) >= 8
    end
  end
end
