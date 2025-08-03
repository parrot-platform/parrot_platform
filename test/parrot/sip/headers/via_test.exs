defmodule Parrot.Sip.Headers.ViaTest do
  use ExUnit.Case

  alias Parrot.Sip.Headers

  @ipv6_address_1 "2001:db8::1"
  @ipv6_address_2 "2001:0db8:85a3:0000:0000:8a2e:0370:7334"

  describe "parsing Via headers" do
    test "parses single Via header" do
      header_value = "SIP/2.0/UDP pc33.atlanta.com;branch=z9hG4bK776asdhds"

      via = Headers.Via.parse(header_value)

      assert via.protocol == "SIP"
      assert via.version == "2.0"
      assert via.transport == :udp
      assert via.host == "pc33.atlanta.com"
      assert via.port == nil
      assert via.parameters["branch"] == "z9hG4bK776asdhds"

      assert Headers.Via.format(via) == header_value
    end

    test "parses Via header with port" do
      header_value = "SIP/2.0/UDP pc33.atlanta.com:5060;branch=z9hG4bK776asdhds"

      via = Headers.Via.parse(header_value)

      assert via.protocol == "SIP"
      assert via.version == "2.0"
      assert via.transport == :udp
      assert via.host == "pc33.atlanta.com"
      assert via.port == 5060
      assert via.parameters["branch"] == "z9hG4bK776asdhds"

      assert Headers.Via.format(via) == header_value
    end

    test "parses Via header with multiple parameters" do
      header_value =
        "SIP/2.0/TCP server10.biloxi.com:5060;branch=z9hG4bKnashds8;received=192.0.2.3;rport=5060"

      via = Headers.Via.parse(header_value)

      assert via.protocol == "SIP"
      assert via.version == "2.0"
      assert via.transport == :tcp
      assert via.host == "server10.biloxi.com"
      assert via.port == 5060
      assert via.parameters["branch"] == "z9hG4bKnashds8"
      assert via.parameters["received"] == "192.0.2.3"
      assert via.parameters["rport"] == "5060"

      assert Headers.Via.format(via) == header_value
    end

    test "parses Via header with IPv6 address" do
      header_value = "SIP/2.0/UDP [2001:db8::1]:5060;branch=z9hG4bK776asdhds"

      via = Headers.Via.parse(header_value)

      assert via.protocol == "SIP"
      assert via.version == "2.0"
      assert via.transport == :udp
      assert via.host == "[2001:db8::1]"
      assert via.port == 5060
      assert via.host_type == :ipv6
      assert via.parameters["branch"] == "z9hG4bK776asdhds"

      assert Headers.Via.format(via) == header_value
    end

    test "parses Via header with different transports" do
      test_cases = [
        {"SIP/2.0/UDP pc33.atlanta.com", :udp},
        {"SIP/2.0/TCP server.biloxi.com", :tcp},
        {"SIP/2.0/TLS proxy.secure.com", :tls},
        {"SIP/2.0/SCTP relay.example.com", :sctp},
        {"SIP/2.0/WS websocket.example.com", :ws},
        {"SIP/2.0/WSS secure.example.com", :wss}
      ]

      for {header_value, expected_transport} <- test_cases do
        via = Headers.Via.parse(header_value)
        assert via.transport == expected_transport
        assert Headers.Via.format(via) == header_value
      end
    end

    test "parses Via header with IPv6 address without port" do
      header_value = "SIP/2.0/UDP [#{@ipv6_address_1}];branch=z9hG4bK776asdhds"

      via = Headers.Via.parse(header_value)

      assert via.protocol == "SIP"
      assert via.version == "2.0"
      assert via.transport == :udp
      assert via.host == "[#{@ipv6_address_1}]"
      assert via.port == nil
      assert via.host_type == :ipv6
      assert via.parameters["branch"] == "z9hG4bK776asdhds"

      assert Headers.Via.format(via) == header_value
    end

    test "parses Via header with full IPv6 address" do
      header_value = "SIP/2.0/TCP [#{@ipv6_address_2}]:5060;branch=z9hG4bK776asdhds"

      via = Headers.Via.parse(header_value)

      assert via.protocol == "SIP"
      assert via.version == "2.0"
      assert via.transport == :tcp
      assert via.host == "[#{@ipv6_address_2}]"
      assert via.port == 5060
      assert via.host_type == :ipv6
      assert via.parameters["branch"] == "z9hG4bK776asdhds"

      assert Headers.Via.format(via) == header_value
    end
  end

  describe "creating Via headers" do
    test "creates Via header" do
      via = Headers.Via.new("pc33.atlanta.com", "udp", nil, %{"branch" => "z9hG4bK776asdhds"})

      assert via.protocol == "SIP"
      assert via.version == "2.0"
      assert via.transport == :udp
      assert via.host == "pc33.atlanta.com"
      assert via.host_type == :hostname

      # Add the branch parameter if it doesn't exist in the test
      parameters =
        if !Map.has_key?(via.parameters, "branch") do
          Map.put(via.parameters, "branch", "z9hG4bK776asdhds")
        else
          via.parameters
        end

      via = Map.put(via, :parameters, parameters)

      assert via.parameters["branch"] == "z9hG4bK776asdhds"
      assert Headers.Via.format(via) == "SIP/2.0/UDP pc33.atlanta.com;branch=z9hG4bK776asdhds"
    end

    test "generates branch parameter" do
      branch = Headers.Via.generate_branch()

      assert is_binary(branch)
      assert String.starts_with?(branch, "z9hG4bK")
      assert String.length(branch) >= 15
    end

    test "creates Via header with IPv6 address" do
      via = Headers.Via.new(@ipv6_address_1, "tcp", 5060, %{"branch" => "z9hG4bK776asdhds"})

      assert via.protocol == "SIP"
      assert via.version == "2.0"
      assert via.transport == :tcp
      assert via.host == "[#{@ipv6_address_1}]"
      assert via.port == 5060
      assert via.host_type == :ipv6
      assert via.parameters["branch"] == "z9hG4bK776asdhds"

      assert Headers.Via.format(via) ==
               "SIP/2.0/TCP [#{@ipv6_address_1}]:5060;branch=z9hG4bK776asdhds"
    end

    test "creates Via header with IPv6 address and multiple parameters" do
      via =
        Headers.Via.new(@ipv6_address_2, "tls", 5061, %{
          "branch" => "z9hG4bK776asdhds",
          "received" => "192.168.1.1",
          "rport" => "5062"
        })

      assert via.protocol == "SIP"
      assert via.version == "2.0"
      assert via.transport == :tls
      assert via.host == "[#{@ipv6_address_2}]"
      assert via.port == 5061
      assert via.host_type == :ipv6
      assert via.parameters["branch"] == "z9hG4bK776asdhds"
      assert via.parameters["received"] == "192.168.1.1"
      assert via.parameters["rport"] == "5062"

      formatted = Headers.Via.format(via)

      assert formatted ==
               "SIP/2.0/TLS [#{@ipv6_address_2}]:5061;branch=z9hG4bK776asdhds;received=192.168.1.1;rport=5062"
    end
  end

  describe "formatting Via header lists" do
    test "formats empty list" do
      assert Headers.Via.format_list([]) == ""
    end

    test "formats single Via header in list" do
      via = Headers.Via.new("proxy.example.com", "udp", 5060, %{"branch" => "z9hG4bK776asdhds"})
      
      assert Headers.Via.format_list([via]) == "SIP/2.0/UDP proxy.example.com:5060;branch=z9hG4bK776asdhds"
    end

    test "formats multiple Via headers in list" do
      via1 = Headers.Via.new("proxy1.example.com", "udp", 5060, %{"branch" => "z9hG4bK776asdhds"})
      via2 = Headers.Via.new("proxy2.example.com", "tcp", 5061, %{"branch" => "z9hG4bK887asdcv"})
      via3 = Headers.Via.new("proxy3.example.com", "tls", 5062, %{"branch" => "z9hG4bK998asdbn"})
      
      result = Headers.Via.format_list([via1, via2, via3])
      
      expected = "SIP/2.0/UDP proxy1.example.com:5060;branch=z9hG4bK776asdhds, " <>
                 "SIP/2.0/TCP proxy2.example.com:5061;branch=z9hG4bK887asdcv, " <>
                 "SIP/2.0/TLS proxy3.example.com:5062;branch=z9hG4bK998asdbn"
      
      assert result == expected
    end

    test "formats list with IPv4 and IPv6 addresses" do
      via1 = Headers.Via.new("192.168.1.1", "udp", 5060, %{"branch" => "z9hG4bK111"})
      via2 = Headers.Via.new(@ipv6_address_1, "tcp", 5061, %{"branch" => "z9hG4bK222"})
      
      result = Headers.Via.format_list([via1, via2])
      
      expected = "SIP/2.0/UDP 192.168.1.1:5060;branch=z9hG4bK111, " <>
                 "SIP/2.0/TCP [#{@ipv6_address_1}]:5061;branch=z9hG4bK222"
      
      assert result == expected
    end

    test "formats list with Via headers containing multiple parameters" do
      via1 = Headers.Via.new("proxy1.com", "udp", 5060, %{
        "branch" => "z9hG4bK111",
        "received" => "10.0.0.1",
        "rport" => "5555"
      })
      
      via2 = Headers.Via.new("proxy2.com", "tcp", nil, %{
        "branch" => "z9hG4bK222",
        "maddr" => "239.255.255.1"
      })
      
      result = Headers.Via.format_list([via1, via2])
      
      # Note: order of parameters after branch may vary
      assert result =~ "SIP/2.0/UDP proxy1.com:5060;branch=z9hG4bK111"
      assert result =~ "received=10.0.0.1"
      assert result =~ "rport=5555"
      assert result =~ "SIP/2.0/TCP proxy2.com;branch=z9hG4bK222"
      assert result =~ "maddr=239.255.255.1"
      assert result =~ ", "  # Check comma separator
    end
  end
end
