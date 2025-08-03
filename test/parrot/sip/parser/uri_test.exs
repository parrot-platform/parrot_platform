defmodule Parrot.Sip.Parser.UriTest do
  use ExUnit.Case

  alias Parrot.Sip.Uri

  describe "parsing SIP URIs" do
    test "parses basic SIP URI" do
      uri_string = "sip:alice@atlanta.com"

      uri = Uri.parse!(uri_string)

      assert uri.scheme == "sip"
      assert uri.user == "alice"
      assert uri.host == "atlanta.com"
      assert uri.port == nil
      assert uri.parameters == %{}
      assert uri.headers == %{}

      assert Uri.to_string(uri) == uri_string
    end

    test "parses SIP URI with port" do
      uri_string = "sip:alice@atlanta.com:5060"

      uri = Uri.parse!(uri_string)

      assert uri.scheme == "sip"
      assert uri.user == "alice"
      assert uri.host == "atlanta.com"
      assert uri.port == 5060
      assert uri.parameters == %{}
      assert uri.headers == %{}

      assert Uri.to_string(uri) == uri_string
    end

    test "parses SIP URI with parameters" do
      uri_string = "sip:alice@atlanta.com;transport=tcp;user=phone"

      uri = Uri.parse!(uri_string)

      assert uri.scheme == "sip"
      assert uri.user == "alice"
      assert uri.host == "atlanta.com"
      assert uri.port == nil
      assert uri.parameters == %{"transport" => "tcp", "user" => "phone"}
      assert uri.headers == %{}

      assert Uri.to_string(uri) == uri_string
    end

    test "parses SIP URI with headers" do
      uri_string = "sip:alice@atlanta.com?subject=project%20x&priority=urgent"

      uri = Uri.parse!(uri_string)

      assert uri.scheme == "sip"
      assert uri.user == "alice"
      assert uri.host == "atlanta.com"
      assert uri.port == nil
      assert uri.parameters == %{}
      assert uri.headers == %{"subject" => "project%20x", "priority" => "urgent"}

      assert Uri.to_string(uri) == uri_string
    end

    test "parses SIP URI with parameters and headers" do
      uri_string =
        "sip:alice@atlanta.com:5060;transport=tcp;user=phone?subject=project%20x&priority=urgent"

      uri = Uri.parse!(uri_string)

      assert uri.scheme == "sip"
      assert uri.user == "alice"
      assert uri.host == "atlanta.com"
      assert uri.port == 5060
      assert uri.parameters == %{"transport" => "tcp", "user" => "phone"}
      assert uri.headers == %{"subject" => "project%20x", "priority" => "urgent"}

      assert Uri.to_string(uri) == uri_string
    end

    test "parses SIPS URI" do
      uri_string = "sips:alice@atlanta.com"

      uri = Uri.parse!(uri_string)

      assert uri.scheme == "sips"
      assert uri.user == "alice"
      assert uri.host == "atlanta.com"

      assert Uri.to_string(uri) == uri_string
    end

    test "parses SIP URI with password" do
      uri_string = "sip:alice:secretword@atlanta.com"

      uri = Uri.parse!(uri_string)

      assert uri.scheme == "sip"
      assert uri.user == "alice"
      assert uri.password == "secretword"
      assert uri.host == "atlanta.com"

      assert Uri.to_string(uri) == uri_string
    end

    test "parses SIP URI with IPv4 address" do
      uri_string = "sip:user@192.168.1.1"

      uri = Uri.parse!(uri_string)

      assert uri.scheme == "sip"
      assert uri.user == "user"
      assert uri.host == "192.168.1.1"
      assert uri.host_type == :ipv4

      assert Uri.to_string(uri) == uri_string
    end

    test "parses SIP URI with IPv6 address" do
      uri_string = "sip:user@[2001:db8::1]"

      uri = Uri.parse!(uri_string)

      assert uri.scheme == "sip"
      assert uri.user == "user"
      # Note: brackets removed
      assert uri.host == "2001:db8::1"
      assert uri.host_type == :ipv6

      assert Uri.to_string(uri) == uri_string
    end

    test "parses SIP URI with escaped characters" do
      uri_string = "sip:alice%20smith@atlanta.com"

      uri = Uri.parse!(uri_string)

      assert uri.scheme == "sip"
      assert uri.user == "alice%20smith"
      assert uri.host == "atlanta.com"

      assert Uri.to_string(uri) == uri_string
      assert Uri.decoded_user(uri) == "alice smith"
    end
  end

  describe "comparing SIP URIs" do
    test "equal URIs match" do
      uri1 = Uri.parse!("sip:alice@atlanta.com")
      uri2 = Uri.parse!("sip:alice@atlanta.com")

      assert Uri.equal?(uri1, uri2)
    end

    test "URIs with different schemes don't match" do
      uri1 = Uri.parse!("sip:alice@atlanta.com")
      uri2 = Uri.parse!("sips:alice@atlanta.com")

      refute Uri.equal?(uri1, uri2)
    end

    test "URIs with different users don't match" do
      uri1 = Uri.parse!("sip:alice@atlanta.com")
      uri2 = Uri.parse!("sip:bob@atlanta.com")

      refute Uri.equal?(uri1, uri2)
    end

    test "URIs with different hosts don't match" do
      uri1 = Uri.parse!("sip:alice@atlanta.com")
      uri2 = Uri.parse!("sip:alice@biloxi.com")

      refute Uri.equal?(uri1, uri2)
    end

    test "URIs with different ports don't match" do
      uri1 = Uri.parse!("sip:alice@atlanta.com")
      uri2 = Uri.parse!("sip:alice@atlanta.com:5080")

      refute Uri.equal?(uri1, uri2)
    end

    test "URIs with different transport parameters don't match" do
      uri1 = Uri.parse!("sip:alice@atlanta.com;transport=tcp")
      uri2 = Uri.parse!("sip:alice@atlanta.com;transport=udp")

      refute Uri.equal?(uri1, uri2)
    end

    test "URIs with different user parameters don't match" do
      uri1 = Uri.parse!("sip:alice@atlanta.com;user=phone")
      uri2 = Uri.parse!("sip:alice@atlanta.com")

      refute Uri.equal?(uri1, uri2)
    end

    test "URIs with different headers match (headers ignored in comparison)" do
      uri1 = Uri.parse!("sip:alice@atlanta.com?subject=hello")
      uri2 = Uri.parse!("sip:alice@atlanta.com?subject=goodbye")

      assert Uri.equal?(uri1, uri2)
    end

    test "URIs with case differences in host match" do
      uri1 = Uri.parse!("sip:alice@AtLanta.CoM")
      uri2 = Uri.parse!("sip:alice@atlanta.com")

      assert Uri.equal?(uri1, uri2)
    end
  end

  describe "handling malformed URIs" do
    test "returns error for missing scheme" do
      uri_string = "alice@atlanta.com"

      assert {:error, reason} = Uri.parse(uri_string)
      assert reason =~ "Invalid scheme"
    end

    test "returns error for invalid scheme" do
      uri_string = "invalid:alice@atlanta.com"

      assert {:error, reason} = Uri.parse(uri_string)
      assert reason =~ "Invalid scheme"
    end

    test "returns error for missing host" do
      uri_string = "sip:alice@"

      assert {:error, reason} = Uri.parse(uri_string)
      assert reason =~ "Invalid host"
    end

    test "returns error for invalid IPv6 address" do
      uri_string = "sip:alice@[1::invalid]"

      assert {:error, reason} = Uri.parse(uri_string)
      assert reason =~ "Invalid IPv6"
    end

    test "returns error for invalid port" do
      uri_string = "sip:alice@atlanta.com:abcd"

      assert {:error, reason} = Uri.parse(uri_string)
      assert reason =~ "Invalid port"
    end
  end

  describe "URI utility functions" do
    test "URI.new creates a valid URI" do
      uri = Uri.new("sip", "alice", "atlanta.com")

      assert uri.scheme == "sip"
      assert uri.user == "alice"
      assert uri.host == "atlanta.com"
      assert Uri.to_string(uri) == "sip:alice@atlanta.com"
    end

    test "URI.new with all options creates a complete URI" do
      uri =
        Uri.new("sip", "alice", "atlanta.com", 5060, %{"transport" => "tcp"}, %{
          "subject" => "test"
        })

      assert uri.scheme == "sip"
      assert uri.user == "alice"
      assert uri.host == "atlanta.com"
      assert uri.port == 5060
      assert uri.parameters == %{"transport" => "tcp"}
      assert uri.headers == %{"subject" => "test"}

      assert Uri.to_string(uri) == "sip:alice@atlanta.com:5060;transport=tcp?subject=test"
    end

    test "URI.with_port adds port to URI" do
      uri = Uri.parse!("sip:alice@atlanta.com")
      updated_uri = Uri.with_port(uri, 5060)

      assert updated_uri.port == 5060
      assert Uri.to_string(updated_uri) == "sip:alice@atlanta.com:5060"
    end

    test "URI.with_parameter adds parameter to URI" do
      uri = Uri.parse!("sip:alice@atlanta.com")
      updated_uri = Uri.with_parameter(uri, "transport", "tcp")

      assert updated_uri.parameters == %{"transport" => "tcp"}
      assert Uri.to_string(updated_uri) == "sip:alice@atlanta.com;transport=tcp"
    end

    test "URI.with_parameters replaces all parameters" do
      uri = Uri.parse!("sip:alice@atlanta.com;user=phone")
      updated_uri = Uri.with_parameters(uri, %{"transport" => "tcp"})

      assert updated_uri.parameters == %{"transport" => "tcp"}
      assert Uri.to_string(updated_uri) == "sip:alice@atlanta.com;transport=tcp"
    end

    test "URI.is_sips? detects SIPS URIs" do
      sip_uri = Uri.parse!("sip:alice@atlanta.com")
      sips_uri = Uri.parse!("sips:alice@atlanta.com")

      refute Uri.is_sips?(sip_uri)
      assert Uri.is_sips?(sips_uri)
    end
  end
end
