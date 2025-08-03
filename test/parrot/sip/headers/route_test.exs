defmodule Parrot.Sip.Headers.RouteTest do
  use ExUnit.Case

  alias Parrot.Sip.Headers
  alias Parrot.Sip.Uri

  describe "parsing Route headers" do
    test "parses Route header" do
      header_value = "<sip:proxy1.example.com;lr>"

      route = Headers.Route.parse(header_value)

      assert route.uri.scheme == "sip"
      assert route.uri.host == "proxy1.example.com"
      assert route.uri.parameters["lr"] == ""

      formatted = Headers.Route.format(route)
      assert String.trim(formatted) == String.trim(header_value)
    end

    test "parses Route header with display name" do
      header_value = "Example Proxy <sip:proxy1.example.com;lr>"

      route = Headers.Route.parse(header_value)

      assert route.display_name == "Example Proxy"
      assert route.uri.scheme == "sip"
      assert route.uri.host == "proxy1.example.com"
      assert route.uri.parameters["lr"] == ""

      formatted = Headers.Route.format(route)
      assert String.trim(formatted) == String.trim(header_value)
    end

    test "parses Route header with parameters" do
      header_value = "<sip:proxy1.example.com;lr>;param=value"

      route = Headers.Route.parse(header_value)

      assert route.uri.scheme == "sip"
      assert route.uri.host == "proxy1.example.com"
      assert route.uri.parameters["lr"] == ""
      assert route.parameters["param"] == "value"

      formatted = Headers.Route.format(route)
      assert String.trim(formatted) == String.trim(header_value)
    end

    test "parses list of Route headers" do
      header_value = "<sip:proxy1.example.com;lr>, <sip:proxy2.example.com;lr>"

      routes = Headers.Route.parse_list(header_value)

      assert length(routes) == 2
      assert Enum.at(routes, 0).uri.host == "proxy1.example.com"
      assert Enum.at(routes, 1).uri.host == "proxy2.example.com"

      formatted = Headers.Route.format_list(routes)
      assert String.trim(formatted) == String.trim(header_value)
    end
  end

  describe "creating Route headers" do
    test "creates Route header" do
      uri = %Uri{scheme: "sip", host: "proxy1.example.com", parameters: %{"lr" => ""}}
      route = Headers.Route.new(uri)

      assert route.uri.scheme == "sip"
      assert route.uri.host == "proxy1.example.com"
      assert route.uri.parameters["lr"] == ""

      formatted = Headers.Route.format(route)
      assert formatted == "<sip:proxy1.example.com;lr>"
    end

    test "creates Route header with string URI" do
      route = Headers.Route.new("sip:proxy1.example.com;lr")

      assert route.uri.scheme == "sip"
      assert route.uri.host == "proxy1.example.com"
      assert route.uri.parameters["lr"] == ""

      formatted = Headers.Route.format(route)
      assert formatted == "<sip:proxy1.example.com;lr>"
    end

    test "creates Route header with display name" do
      route = Headers.Route.new("sip:proxy1.example.com;lr", "Example Proxy")

      assert route.display_name == "Example Proxy"
      assert route.uri.scheme == "sip"
      assert route.uri.host == "proxy1.example.com"
      assert route.uri.parameters["lr"] == ""

      formatted = Headers.Route.format(route)
      assert formatted == "Example Proxy <sip:proxy1.example.com;lr>"
    end
  end
end
