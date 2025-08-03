defmodule Parrot.Sip.MessageTest do
  use ExUnit.Case
  
  alias Parrot.Sip.Message
  alias Parrot.Sip.Headers.{Via, From, To, CSeq, Contact}

  describe "to_binary/1 with header lists" do
    test "serializes message with Via header list" do
      via1 = Via.new("proxy1.example.com", "udp", 5060, %{"branch" => "z9hG4bK111"})
      via2 = Via.new("proxy2.example.com", "tcp", 5061, %{"branch" => "z9hG4bK222"})
      
      message = Message.new_request(:invite, "sip:bob@example.com", %{
        "via" => [via1, via2],
        "from" => From.new("sip:alice@example.com", "Alice", "tag123"),
        "to" => To.new("sip:bob@example.com", "Bob"),
        "cseq" => CSeq.new(1, :invite),
        "call-id" => "call123@example.com",
        "contact" => Contact.new("sip:alice@192.168.1.100:5060")
      })
      
      binary = Message.to_binary(message)
      
      # Check that the message starts with the request line
      assert binary =~ ~r/^INVITE sip:bob@example.com SIP\/2.0\r\n/
      
      # Check that Via header appears first after the request line
      lines = String.split(binary, "\r\n")
      assert Enum.at(lines, 1) =~ ~r/^Via: /
      
      # Check that Via headers are properly formatted
      assert binary =~ "Via: SIP/2.0/UDP proxy1.example.com:5060;branch=z9hG4bK111, SIP/2.0/TCP proxy2.example.com:5061;branch=z9hG4bK222\r\n"
      
      # Check other headers are present and formatted
      assert binary =~ "From: Alice <sip:alice@example.com>;tag=tag123\r\n"
      assert binary =~ "To: Bob <sip:bob@example.com>\r\n"
      assert binary =~ "Cseq: 1 INVITE\r\n"
      assert binary =~ "Call-Id: call123@example.com\r\n"
      assert binary =~ "Contact: <sip:alice@192.168.1.100:5060>\r\n"
    end
    
    test "serializes message with single Via header in list" do
      via = Via.new("proxy.example.com", "udp", 5060, %{"branch" => "z9hG4bK123"})
      
      message = Message.new_request(:register, "sip:registrar.example.com", %{
        "via" => [via],
        "from" => From.new("sip:alice@example.com", nil, "tag456"),
        "to" => To.new("sip:alice@example.com"),
        "cseq" => CSeq.new(1, :register),
        "call-id" => "reg123@example.com"
      })
      
      binary = Message.to_binary(message)
      
      # Via should still be formatted correctly even with single element list
      assert binary =~ "Via: SIP/2.0/UDP proxy.example.com:5060;branch=z9hG4bK123\r\n"
    end
    
    test "serializes message with empty Via header list" do
      message = Message.new_request(:options, "sip:server.example.com", %{
        "via" => [],
        "from" => From.new("sip:alice@example.com", nil, "tag789"),
        "to" => To.new("sip:server.example.com"),
        "cseq" => CSeq.new(1, :options),
        "call-id" => "opt123@example.com"
      })
      
      binary = Message.to_binary(message)
      
      # Empty Via list should result in "Via: \r\n"
      assert binary =~ "Via: \r\n"
    end
    
    test "serializes message with mixed header types" do
      via = Via.new("proxy.example.com", "udp", 5060, %{"branch" => "z9hG4bK999"})
      
      message = Message.new_request(:invite, "sip:bob@example.com", %{
        "via" => [via],
        "from" => From.new("sip:alice@example.com", "Alice", "tagABC"),
        "to" => To.new("sip:bob@example.com"),
        "cseq" => CSeq.new(1, :invite),
        "call-id" => "mixed123@example.com",
        "contact" => Contact.new("sip:alice@host.com"),
        "content-type" => "application/sdp",  # String header
        "max-forwards" => 70,                   # Integer header
        "user-agent" => "Parrot/1.0"          # String header
      })
      
      binary = Message.to_binary(message)
      
      # Check all headers are formatted correctly
      assert binary =~ "Via: SIP/2.0/UDP proxy.example.com:5060;branch=z9hG4bK999\r\n"
      assert binary =~ "From: Alice <sip:alice@example.com>;tag=tagABC\r\n"
      assert binary =~ "Content-Type: application/sdp\r\n"
      assert binary =~ "Max-Forwards: 70\r\n"
      assert binary =~ "User-Agent: Parrot/1.0\r\n"
    end
  end
end