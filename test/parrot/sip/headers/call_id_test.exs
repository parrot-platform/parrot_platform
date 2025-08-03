defmodule Parrot.Sip.Headers.CallIdTest do
  use ExUnit.Case

  alias Parrot.Sip.Headers

  describe "parsing Call-ID headers" do
    test "parses Call-ID header" do
      header_value = "a84b4c76e66710@pc33.atlanta.com"

      call_id = Headers.CallId.parse(header_value)

      assert call_id == "a84b4c76e66710@pc33.atlanta.com"

      assert Headers.CallId.format(call_id) == header_value
    end
  end

  describe "creating Call-ID headers" do
    test "creates Call-ID header" do
      call_id = Headers.CallId.new("a84b4c76e66710@pc33.atlanta.com")

      assert call_id == "a84b4c76e66710@pc33.atlanta.com"

      assert Headers.CallId.format(call_id) == "a84b4c76e66710@pc33.atlanta.com"
    end

    test "generates Call-ID value" do
      call_id = Headers.CallId.generate()

      assert is_binary(call_id)
      assert String.contains?(call_id, "@")
      assert String.length(call_id) >= 10
    end
  end
end
