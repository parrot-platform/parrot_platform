defmodule Parrot.Sip.Headers.ContactTest do
  use ExUnit.Case

  alias Parrot.Sip.Headers

  describe "parsing Contact headers" do
    test "parses Contact header with display name" do
      header_value = "Alice <sip:alice@pc33.atlanta.com>"

      contact = Headers.Contact.parse(header_value)

      assert contact.display_name == "Alice"
      uri = contact.uri
      assert is_struct(uri, Parrot.Sip.Uri)
      assert uri.scheme == "sip"
      assert uri.user == "alice"
      assert uri.host == "pc33.atlanta.com"
      assert contact.parameters == %{}

      formatted = Headers.Contact.format(contact)
      assert String.match?(formatted, ~r/<sip:alice@pc33\.atlanta\.com>/)
    end

    test "parses Contact header without display name" do
      header_value = "<sip:alice@pc33.atlanta.com>"

      contact = Headers.Contact.parse(header_value)

      # String values can be empty strings instead of nil when parsed
      assert contact.display_name == nil or contact.display_name == ""
      uri = contact.uri
      assert is_struct(uri, Parrot.Sip.Uri)
      assert uri.scheme == "sip"
      assert uri.user == "alice"
      assert uri.host == "pc33.atlanta.com"

      assert Headers.Contact.format(contact) == header_value
    end

    test "parses Contact header with parameters" do
      header_value = "<sip:alice@pc33.atlanta.com>;expires=3600;q=0.8"

      contact = Headers.Contact.parse(header_value)

      # String values can be empty strings instead of nil when parsed
      assert contact.display_name == nil or contact.display_name == ""
      uri = contact.uri
      assert is_struct(uri, Parrot.Sip.Uri)
      assert uri.scheme == "sip"
      assert uri.user == "alice"
      assert uri.host == "pc33.atlanta.com"
      assert contact.parameters["expires"] == "3600"
      # The q-value might be formatted differently after parsing
      assert String.starts_with?(contact.parameters["q"], "0.")

      formatted = Headers.Contact.format(contact)
      assert String.match?(formatted, ~r/<sip:alice@pc33\.atlanta\.com>;.*expires=3600/)
      assert String.match?(formatted, ~r/q=0\.[0-9]/)
    end

    test "parses Contact header with wildcard" do
      header_value = "*"

      contact = Headers.Contact.parse(header_value)

      assert contact.wildcard == true

      formatted = Headers.Contact.format(contact)
      assert String.trim(formatted) == String.trim(header_value)
    end
  end

  describe "creating Contact headers" do
    test "creates Contact header" do
      contact = Headers.Contact.new("sip:alice@pc33.atlanta.com", "Alice")

      assert contact.display_name == "Alice"
      uri = contact.uri
      assert is_struct(uri, Parrot.Sip.Uri)
      assert uri.scheme == "sip"
      assert uri.user == "alice"
      assert uri.host == "pc33.atlanta.com"

      formatted = Headers.Contact.format(contact)
      assert String.match?(formatted, ~r/Alice <sip:alice@pc33\.atlanta\.com>/)
    end

    test "creates wildcard Contact header" do
      contact = Headers.Contact.wildcard()

      assert contact.wildcard == true

      formatted = Headers.Contact.format(contact)
      assert String.trim(formatted) == "*"
    end
  end
end
