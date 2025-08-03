defmodule Parrot.Sip.Headers.AcceptTest do
  use ExUnit.Case

  alias Parrot.Sip.Headers

  describe "parsing Accept headers" do
    test "parses Accept header" do
      header_value = "application/sdp"

      accept = Headers.Accept.parse(header_value)

      assert accept.type == "application"
      assert accept.subtype == "sdp"
      assert accept.parameters == %{}
      assert accept.q_value == nil

      assert Headers.Accept.format(accept) == header_value
    end

    test "parses Accept header with parameters" do
      header_value = "application/sdp;charset=UTF-8;q=0.8"

      accept = Headers.Accept.parse(header_value)

      assert accept.type == "application"
      assert accept.subtype == "sdp"
      assert accept.parameters == %{"charset" => "UTF-8"}
      assert accept.q_value == 0.8

      assert Headers.Accept.format(accept) == header_value
    end

    test "parses Accept header with only q value" do
      header_value = "application/sdp;q=0.5"

      accept = Headers.Accept.parse(header_value)

      assert accept.type == "application"
      assert accept.subtype == "sdp"
      assert accept.parameters == %{}
      assert accept.q_value == 0.5

      assert Headers.Accept.format(accept) == header_value
    end
  end

  describe "creating Accept headers" do
    test "creates Accept header" do
      accept = Headers.Accept.new("application", "sdp")

      assert accept.type == "application"
      assert accept.subtype == "sdp"
      assert accept.parameters == %{}
      assert accept.q_value == nil

      assert Headers.Accept.format(accept) == "application/sdp"
    end

    test "creates Accept header with parameters and q value" do
      accept = Headers.Accept.new("application", "sdp", %{"charset" => "UTF-8"}, 0.8)

      assert accept.type == "application"
      assert accept.subtype == "sdp"
      assert accept.parameters == %{"charset" => "UTF-8"}
      assert accept.q_value == 0.8

      assert Headers.Accept.format(accept) == "application/sdp;charset=UTF-8;q=0.8"
    end

    test "creates SDP Accept header" do
      accept = Headers.Accept.sdp()

      assert accept.type == "application"
      assert accept.subtype == "sdp"
      assert accept.parameters == %{}
      assert accept.q_value == nil

      assert Headers.Accept.format(accept) == "application/sdp"
    end

    test "creates wildcard Accept header" do
      accept = Headers.Accept.all()

      assert accept.type == "*"
      assert accept.subtype == "*"
      assert accept.parameters == %{}
      assert accept.q_value == nil

      assert Headers.Accept.format(accept) == "*/*"
    end
  end

  describe "string conversion" do
    test "to_string is alias for format" do
      accept = Headers.Accept.new("application", "sdp")

      assert Headers.Accept.to_string(accept) == Headers.Accept.format(accept)
      assert Headers.Accept.to_string(accept) == "application/sdp"
    end
  end
end
