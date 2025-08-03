defmodule Parrot.Sip.Headers.AllowTest do
  use ExUnit.Case

  alias Parrot.Sip.Headers

  describe "parsing Allow headers" do
    test "parses Allow header" do
      header_value = "ACK, BYE, CANCEL, INVITE, OPTIONS"

      allow = Headers.Allow.parse(header_value)

      assert allow == Parrot.Sip.MethodSet.new([:invite, :ack, :cancel, :options, :bye])

      assert Headers.Allow.format(allow) == header_value
    end
  end

  describe "creating Allow headers" do
    test "creates Allow header" do
      expected = Parrot.Sip.MethodSet.new([:invite, :ack, :cancel, :options, :bye])

      allow = Headers.Allow.new([:invite, :ack, :cancel, :options, :bye])

      assert allow == expected

      assert Headers.Allow.format(allow) == "ACK, BYE, CANCEL, INVITE, OPTIONS"
    end
  end
end
