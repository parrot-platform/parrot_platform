defmodule Parrot.Sip.Headers.ContentTypeTest do
  use ExUnit.Case

  alias Parrot.Sip.Headers

  describe "parsing Content-Type headers" do
    test "parses Content-Type header" do
      header_value = "application/sdp"

      content_type = Headers.ContentType.parse(header_value)

      assert content_type.type == "application"
      assert content_type.subtype == "sdp"
      assert content_type.parameters == %{}

      assert Headers.ContentType.format(content_type) == header_value
    end

    test "parses Content-Type header with parameters" do
      header_value = "multipart/mixed; boundary=boundary42"

      content_type = Headers.ContentType.parse(header_value)

      assert content_type.type == "multipart"
      assert content_type.subtype == "mixed"
      assert content_type.parameters["boundary"] == "boundary42"

      assert Headers.ContentType.format(content_type) == header_value
    end
  end

  describe "creating Content-Type headers" do
    test "creates Content-Type header" do
      content_type = Headers.ContentType.new("application", "sdp")

      assert content_type.type == "application"
      assert content_type.subtype == "sdp"

      assert Headers.ContentType.format(content_type) == "application/sdp"
    end
  end
end
