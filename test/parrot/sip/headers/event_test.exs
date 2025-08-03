defmodule Parrot.Sip.Headers.EventTest do
  use ExUnit.Case

  alias Parrot.Sip.Headers

  describe "parsing Event headers" do
    test "parses Event header" do
      header_value = "presence"

      event = Headers.Event.parse(header_value)

      assert is_map(event)
      assert event.event == "presence"
      assert event.parameters == %{}

      assert Headers.Event.format(event) == header_value
    end

    test "parses Event header with parameters" do
      header_value = "presence;id=1234"

      event = Headers.Event.parse(header_value)

      assert event.event == "presence"
      assert event.parameters["id"] == "1234"

      assert Headers.Event.format(event) == header_value
    end
  end

  describe "creating Event headers" do
    test "creates Event header" do
      event = Headers.Event.new("presence", %{"id" => "1234"})

      assert event.event == "presence"
      assert event.parameters["id"] == "1234"

      assert Headers.Event.format(event) == "presence;id=1234"
    end
  end
end
