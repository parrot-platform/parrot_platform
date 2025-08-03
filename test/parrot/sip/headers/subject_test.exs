defmodule Parrot.Sip.Headers.SubjectTest do
  use ExUnit.Case

  alias Parrot.Sip.Headers

  describe "parsing Subject headers" do
    test "parses Subject header" do
      header_value = "Project X Discussion"

      subject = Headers.Subject.parse(header_value)

      assert subject.value == "Project X Discussion"

      assert Headers.Subject.format(subject) == header_value
    end
  end

  describe "creating Subject headers" do
    test "creates Subject header" do
      subject = Headers.Subject.new("Project X Discussion")

      assert subject.value == "Project X Discussion"

      assert Headers.Subject.format(subject) == "Project X Discussion"
    end
  end
end
