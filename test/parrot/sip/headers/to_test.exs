defmodule Parrot.Sip.Headers.ToTest do
  use ExUnit.Case

  alias Parrot.Sip.Headers

  describe "parsing To headers" do
    test "parses To header with display name and tag" do
      header_value = "Bob <sip:bob@biloxi.com>;tag=a6c85cf"

      to = Headers.To.parse(header_value)

      assert to.display_name == "Bob"
      uri = to.uri
      assert is_struct(uri, Parrot.Sip.Uri)
      assert uri.scheme == "sip"
      assert uri.user == "bob"
      assert uri.host == "biloxi.com"
      assert to.parameters["tag"] == "a6c85cf"

      formatted = Headers.To.format(to)
      assert String.match?(formatted, ~r/Bob <sip:bob@biloxi\.com>;tag=a6c85cf/)
    end

    test "parses To header without display name" do
      header_value = "<sip:bob@biloxi.com>;tag=a6c85cf"

      to = Headers.To.parse(header_value)

      assert to.display_name == nil
      uri = to.uri
      assert is_struct(uri, Parrot.Sip.Uri)
      assert uri.scheme == "sip"
      assert uri.user == "bob"
      assert uri.host == "biloxi.com"
      assert to.parameters["tag"] == "a6c85cf"

      formatted = Headers.To.format(to)
      assert String.match?(formatted, ~r/<sip:bob@biloxi\.com>;tag=a6c85cf/)
    end

    test "parses To header without tag" do
      header_value = "Bob <sip:bob@biloxi.com>"

      to = Headers.To.parse(header_value)

      assert to.display_name == "Bob"
      uri = to.uri
      assert is_struct(uri, Parrot.Sip.Uri)
      assert uri.scheme == "sip"
      assert uri.user == "bob"
      assert uri.host == "biloxi.com"
      assert to.parameters == %{}

      formatted = Headers.To.format(to)
      assert String.match?(formatted, ~r/Bob <sip:bob@biloxi\.com>/)
    end
  end

  describe "creating To headers" do
    test "creates To header" do
      to = Headers.To.new("sip:bob@biloxi.com", "Bob", %{"tag" => "a6c85cf"})

      assert to.display_name == "Bob"
      uri = to.uri
      assert is_struct(uri, Parrot.Sip.Uri)
      assert uri.scheme == "sip"
      assert uri.user == "bob"
      assert uri.host == "biloxi.com"
      assert to.parameters["tag"] == "a6c85cf"

      formatted = Headers.To.format(to)
      assert String.match?(formatted, ~r/Bob <sip:bob@biloxi\.com>;tag=a6c85cf/)
    end
  end
end
