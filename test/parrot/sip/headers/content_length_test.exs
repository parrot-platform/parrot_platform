defmodule Parrot.Sip.Headers.ContentLengthTest do
  use ExUnit.Case

  alias Parrot.Sip.Headers

  describe "parsing Content-Length headers" do
    test "parses Content-Length header" do
      header_value = "142"

      content_length = Headers.ContentLength.parse(header_value)

      assert content_length.value == 142

      assert Headers.ContentLength.format(content_length) == "142"
    end
  end

  describe "creating Content-Length headers" do
    test "creates Content-Length header" do
      content_length = Headers.ContentLength.new(142)

      assert content_length.value == 142

      assert Headers.ContentLength.format(content_length) == "142"
    end
  end
end
