defmodule Parrot.Sip.Headers.SupportedTest do
  use ExUnit.Case

  alias Parrot.Sip.Headers

  describe "parsing Supported headers" do
    test "parses Supported header" do
      header_value = "path, 100rel, timer"

      supported = Headers.Supported.parse(header_value)

      assert supported == ["path", "100rel", "timer"]

      assert Headers.Supported.format(supported) == header_value
    end
  end

  describe "creating Supported headers" do
    test "creates Supported header" do
      supported = Headers.Supported.new(["path", "100rel", "timer"])

      assert supported == ["path", "100rel", "timer"]

      assert Headers.Supported.format(supported) == "path, 100rel, timer"
    end
  end
end
