defmodule Parrot.Media.PipelineHelpersTest do
  use ExUnit.Case, async: true
  
  alias Parrot.Media.PipelineHelpers
  
  describe "parse_ip/1" do
    test "parses valid IPv4 string" do
      assert {:ok, {192, 168, 1, 1}} = PipelineHelpers.parse_ip("192.168.1.1")
      assert {:ok, {127, 0, 0, 1}} = PipelineHelpers.parse_ip("127.0.0.1")
      assert {:ok, {255, 255, 255, 255}} = PipelineHelpers.parse_ip("255.255.255.255")
    end
    
    test "accepts valid IPv4 tuple" do
      assert {:ok, {192, 168, 1, 1}} = PipelineHelpers.parse_ip({192, 168, 1, 1})
      assert {:ok, {0, 0, 0, 0}} = PipelineHelpers.parse_ip({0, 0, 0, 0})
    end
    
    test "rejects invalid IPv4 tuple" do
      assert {:error, {:invalid_ipv4_tuple, {256, 0, 0, 0}}} = 
        PipelineHelpers.parse_ip({256, 0, 0, 0})
      assert {:error, {:invalid_ipv4_tuple, {192, 168, 1, -1}}} = 
        PipelineHelpers.parse_ip({192, 168, 1, -1})
    end
    
    test "parses valid IPv6 string" do
      assert {:ok, {0, 0, 0, 0, 0, 0, 0, 1}} = PipelineHelpers.parse_ip("::1")
      assert {:ok, {8193, 3512, 0, 0, 0, 0, 0, 1}} = 
        PipelineHelpers.parse_ip("2001:db8::1")
    end
    
    test "accepts valid IPv6 tuple" do
      assert {:ok, {0, 0, 0, 0, 0, 0, 0, 1}} = 
        PipelineHelpers.parse_ip({0, 0, 0, 0, 0, 0, 0, 1})
    end
    
    test "rejects invalid IPv6 tuple" do
      assert {:error, {:invalid_ipv6_tuple, {65536, 0, 0, 0, 0, 0, 0, 0}}} = 
        PipelineHelpers.parse_ip({65536, 0, 0, 0, 0, 0, 0, 0})
    end
    
    test "returns error for invalid string" do
      assert {:error, {:invalid_ip_address, "not.an.ip", _}} = 
        PipelineHelpers.parse_ip("not.an.ip")
      assert {:error, {:invalid_ip_address, "999.999.999.999", _}} = 
        PipelineHelpers.parse_ip("999.999.999.999")
    end
    
    test "returns error for invalid format" do
      assert {:error, {:invalid_ip_format, :atom}} = PipelineHelpers.parse_ip(:atom)
      assert {:error, {:invalid_ip_format, 123}} = PipelineHelpers.parse_ip(123)
      assert {:error, {:invalid_ip_format, {1, 2, 3}}} = PipelineHelpers.parse_ip({1, 2, 3})
    end
  end
  
  describe "parse_ip!/1" do
    test "returns IP tuple for valid input" do
      assert {127, 0, 0, 1} = PipelineHelpers.parse_ip!("127.0.0.1")
      assert {192, 168, 1, 1} = PipelineHelpers.parse_ip!({192, 168, 1, 1})
    end
    
    test "raises for invalid input" do
      assert_raise ArgumentError, ~r/Invalid IP address/, fn ->
        PipelineHelpers.parse_ip!("invalid")
      end
      
      assert_raise ArgumentError, ~r/Invalid IP address/, fn ->
        PipelineHelpers.parse_ip!({256, 0, 0, 0})
      end
    end
  end
  
  describe "format_ip/1" do
    test "returns string as-is" do
      assert "192.168.1.1" = PipelineHelpers.format_ip("192.168.1.1")
      assert "::1" = PipelineHelpers.format_ip("::1")
    end
    
    test "formats IPv4 tuple" do
      assert "192.168.1.1" = PipelineHelpers.format_ip({192, 168, 1, 1})
      assert "0.0.0.0" = PipelineHelpers.format_ip({0, 0, 0, 0})
    end
    
    test "formats IPv6 tuple" do
      assert "0:0:0:0:0:0:0:1" = PipelineHelpers.format_ip({0, 0, 0, 0, 0, 0, 0, 1})
      # Elixir's Integer.to_string uses uppercase for hex
      assert "2001:DB8:0:0:0:0:0:1" = PipelineHelpers.format_ip({8193, 3512, 0, 0, 0, 0, 0, 1})
    end
    
    test "uses inspect for unknown format" do
      assert ":atom" = PipelineHelpers.format_ip(:atom)
      assert "123" = PipelineHelpers.format_ip(123)
    end
  end
  
  describe "has_audio_file?/1" do
    test "returns false for :default_audio" do
      refute PipelineHelpers.has_audio_file?(%{audio_file: :default_audio})
    end
    
    test "returns false for nil" do
      refute PipelineHelpers.has_audio_file?(%{audio_file: nil})
    end
    
    test "returns true for file path" do
      assert PipelineHelpers.has_audio_file?(%{audio_file: "/path/to/file.wav"})
      assert PipelineHelpers.has_audio_file?(%{audio_file: "relative/path.wav"})
    end
    
    test "returns false when audio_file key is missing" do
      refute PipelineHelpers.has_audio_file?(%{})
      refute PipelineHelpers.has_audio_file?(%{other_key: "value"})
    end
    
    test "returns false for non-map input" do
      refute PipelineHelpers.has_audio_file?(nil)
      refute PipelineHelpers.has_audio_file?("string")
      refute PipelineHelpers.has_audio_file?([])
    end
  end
  
  describe "build_udp_endpoint_spec/2" do
    test "builds bidirectional endpoint when has_audio? is true" do
      opts = %{
        local_rtp_port: 5060,
        remote_rtp_port: 5061,
        remote_rtp_address: "192.168.1.1"
      }
      
      spec = PipelineHelpers.build_udp_endpoint_spec(opts, true)
      
      # Membrane.ChildrenSpec.child returns a Builder struct, not a tuple
      assert %Membrane.ChildrenSpec.Builder{
        children: [
          {:udp_endpoint, %Membrane.UDP.Endpoint{
            local_port_no: 5060,
            destination_port_no: 5061,
            destination_address: {192, 168, 1, 1}
          }, _}
        ]
      } = spec
    end
    
    test "builds receive-only endpoint when has_audio? is false" do
      opts = %{
        local_rtp_port: 5060,
        remote_rtp_port: 5061,
        remote_rtp_address: "192.168.1.1"
      }
      
      spec = PipelineHelpers.build_udp_endpoint_spec(opts, false)
      
      # Membrane.ChildrenSpec.child returns a Builder struct, not a tuple
      assert %Membrane.ChildrenSpec.Builder{
        children: [
          {:udp_endpoint, %Membrane.UDP.Source{
            local_port_no: 5060
          }, _}
        ]
      } = spec
    end
    
    test "raises for invalid IP address" do
      opts = %{
        local_rtp_port: 5060,
        remote_rtp_port: 5061,
        remote_rtp_address: "invalid.ip"
      }
      
      assert_raise ArgumentError, ~r/Invalid IP address/, fn ->
        PipelineHelpers.build_udp_endpoint_spec(opts, true)
      end
    end
  end
end