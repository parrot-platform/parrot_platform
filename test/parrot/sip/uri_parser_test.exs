defmodule Parrot.Sip.UriParserTest do
  use ExUnit.Case

  alias Parrot.Sip.UriParser

  describe "parse/1" do
    test "parses basic SIP URI" do
      uri_string = "sip:alice@atlanta.com"

      assert {:ok, components} = UriParser.parse(uri_string)
      assert components.scheme == "sip"
      assert components.user == "alice"
      assert components.host == "atlanta.com"
      assert components.port == nil
      assert components.parameters == %{}
      assert components.headers == %{}
    end

    test "parses SIP URI with port" do
      uri_string = "sip:alice@atlanta.com:5060"

      assert {:ok, components} = UriParser.parse(uri_string)
      assert components.scheme == "sip"
      assert components.user == "alice"
      assert components.host == "atlanta.com"
      assert components.port == 5060
      assert components.parameters == %{}
      assert components.headers == %{}
    end

    test "parses SIP URI with parameters" do
      uri_string = "sip:alice@atlanta.com;transport=tcp;user=phone"

      assert {:ok, components} = UriParser.parse(uri_string)
      assert components.scheme == "sip"
      assert components.user == "alice"
      assert components.host == "atlanta.com"
      assert components.port == nil
      assert components.parameters == %{"transport" => "tcp", "user" => "phone"}
      assert components.headers == %{}
    end

    test "parses SIP URI with headers" do
      uri_string = "sip:alice@atlanta.com?subject=project%20x&priority=urgent"

      assert {:ok, components} = UriParser.parse(uri_string)
      assert components.scheme == "sip"
      assert components.user == "alice"
      assert components.host == "atlanta.com"
      assert components.port == nil
      assert components.parameters == %{}
      assert components.headers == %{"subject" => "project%20x", "priority" => "urgent"}
    end

    test "returns error for invalid scheme" do
      uri_string = "invalid:alice@atlanta.com"

      assert {:error, reason} = UriParser.parse(uri_string)
      assert reason =~ "Invalid scheme"
    end
  end

  describe "extract_parameters/1" do
    test "extracts simple parameters" do
      params_str = "transport=tcp;user=phone"
      params = UriParser.extract_parameters(params_str)

      assert params == %{"transport" => "tcp", "user" => "phone"}
    end

    test "extracts parameters without values" do
      params_str = "lr;transport=tcp"
      params = UriParser.extract_parameters(params_str)

      assert params == %{"lr" => "", "transport" => "tcp"}
    end

    test "returns empty map for empty string" do
      assert UriParser.extract_parameters("") == %{}
    end
  end

  describe "extract_headers/1" do
    test "extracts simple headers" do
      headers_str = "subject=project&priority=urgent"
      headers = UriParser.extract_headers(headers_str)

      assert headers == %{"subject" => "project", "priority" => "urgent"}
    end

    test "extracts headers without values" do
      headers_str = "empty&subject=project"
      headers = UriParser.extract_headers(headers_str)

      assert headers == %{"empty" => "", "subject" => "project"}
    end

    test "returns empty map for empty string" do
      assert UriParser.extract_headers("") == %{}
    end
  end

  describe "determine_host_type/1" do
    test "identifies hostname" do
      assert UriParser.determine_host_type("example.com") == :hostname
    end

    test "identifies IPv4" do
      assert UriParser.determine_host_type("192.168.1.1") == :ipv4
    end
  end

  describe "parse_address/1" do
    test "parses user@host" do
      assert {:ok, address} = UriParser.parse_address("alice@atlanta.com")
      assert address.user == "alice"
      assert address.host == "atlanta.com"
      assert address.port == nil
    end

    test "parses user@host:port" do
      assert {:ok, address} = UriParser.parse_address("alice@atlanta.com:5060")
      assert address.user == "alice"
      assert address.host == "atlanta.com"
      assert address.port == 5060
    end

    test "parses host only" do
      assert {:ok, address} = UriParser.parse_address("atlanta.com")
      assert address.user == nil
      assert address.host == "atlanta.com"
      assert address.port == nil
    end
  end
end
