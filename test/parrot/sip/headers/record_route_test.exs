defmodule Parrot.Sip.Headers.RecordRouteTest do
  use ExUnit.Case

  alias Parrot.Sip.Headers
  alias Parrot.Sip.Uri

  describe "parsing Record-Route headers" do
    test "parses Record-Route header" do
      header_value = "<sip:proxy1.example.com;lr>"

      record_route = Headers.RecordRoute.parse(header_value)

      assert record_route.uri.scheme == "sip"
      assert record_route.uri.host == "proxy1.example.com"
      assert record_route.uri.parameters["lr"] == ""

      formatted = Headers.RecordRoute.format(record_route)
      # Use string.trim to avoid any whitespace differences in formatted output
      assert String.trim(formatted) == String.trim(header_value)
    end

    test "parses Record-Route header with display name" do
      header_value = "Example Proxy <sip:proxy1.example.com;lr>"

      record_route = Headers.RecordRoute.parse(header_value)

      assert record_route.display_name == "Example Proxy"
      assert record_route.uri.scheme == "sip"
      assert record_route.uri.host == "proxy1.example.com"
      assert record_route.uri.parameters["lr"] == ""

      formatted = Headers.RecordRoute.format(record_route)
      assert String.trim(formatted) == String.trim(header_value)
    end

    test "parses Record-Route header with parameters" do
      header_value = "<sip:proxy1.example.com;lr>;param=value"

      record_route = Headers.RecordRoute.parse(header_value)

      assert record_route.uri.scheme == "sip"
      assert record_route.uri.host == "proxy1.example.com"
      assert record_route.uri.parameters["lr"] == ""
      assert record_route.parameters["param"] == "value"

      formatted = Headers.RecordRoute.format(record_route)
      assert String.trim(formatted) == String.trim(header_value)
    end

    test "parses list of Record-Route headers" do
      header_value = "<sip:proxy1.example.com;lr>, <sip:proxy2.example.com;lr>"

      record_routes = Headers.RecordRoute.parse_list(header_value)

      assert length(record_routes) == 2
      assert Enum.at(record_routes, 0).uri.host == "proxy1.example.com"
      assert Enum.at(record_routes, 1).uri.host == "proxy2.example.com"

      formatted = Headers.RecordRoute.format_list(record_routes)
      assert String.trim(formatted) == String.trim(header_value)
    end
  end

  describe "creating Record-Route headers" do
    test "creates Record-Route header" do
      uri = %Uri{scheme: "sip", host: "proxy1.example.com", parameters: %{"lr" => ""}}
      record_route = Headers.RecordRoute.new(uri)

      assert record_route.uri.scheme == "sip"
      assert record_route.uri.host == "proxy1.example.com"
      assert record_route.uri.parameters["lr"] == ""

      assert Headers.RecordRoute.format(record_route) == "<sip:proxy1.example.com;lr>"
    end

    test "creates Record-Route header with string URI" do
      record_route = Headers.RecordRoute.new("sip:proxy1.example.com;lr")

      assert record_route.uri.scheme == "sip"
      assert record_route.uri.host == "proxy1.example.com"
      assert record_route.uri.parameters["lr"] == ""

      formatted = Headers.RecordRoute.format(record_route)
      assert formatted == "<sip:proxy1.example.com;lr>"
    end

    test "creates Record-Route header with display name" do
      record_route = Headers.RecordRoute.new("sip:proxy1.example.com;lr", "Example Proxy")

      assert record_route.display_name == "Example Proxy"
      assert record_route.uri.scheme == "sip"
      assert record_route.uri.host == "proxy1.example.com"
      assert record_route.uri.parameters["lr"] == ""

      formatted = Headers.RecordRoute.format(record_route)
      assert formatted == "Example Proxy <sip:proxy1.example.com;lr>"
    end
  end
end
