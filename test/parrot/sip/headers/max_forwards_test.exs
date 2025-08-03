defmodule Parrot.Sip.Headers.MaxForwardsTest do
  use ExUnit.Case

  alias Parrot.Sip.Headers

  describe "parsing Max-Forwards headers" do
    test "parses Max-Forwards header" do
      header_value = "70"

      max_forwards = Headers.MaxForwards.parse(header_value)

      assert max_forwards == 70

      assert Headers.MaxForwards.format(max_forwards) == "70"
    end
  end

  describe "creating Max-Forwards headers" do
    test "creates Max-Forwards header" do
      max_forwards = Headers.MaxForwards.new(70)

      assert max_forwards == 70

      assert Headers.MaxForwards.format(max_forwards) == "70"
    end
  end
end
