defmodule Parrot.Sip.Headers.ExpiresTest do
  use ExUnit.Case

  alias Parrot.Sip.Headers

  describe "parsing Expires headers" do
    test "parses Expires header" do
      header_value = "3600"

      expires = Headers.Expires.parse(header_value)

      assert expires == 3600

      assert Headers.Expires.format(expires) == header_value
    end
  end

  describe "creating Expires headers" do
    test "creates Expires header" do
      expires = Headers.Expires.new(3600)

      assert expires == 3600

      assert Headers.Expires.format(expires) == "3600"
    end
  end
end
