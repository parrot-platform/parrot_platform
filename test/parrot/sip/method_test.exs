defmodule Parrot.Sip.MethodTest do
  use ExUnit.Case, async: true

  alias Parrot.Sip.Method

  describe "standard_methods/0" do
    test "returns all standard SIP methods" do
      methods = Method.standard_methods()
      assert is_list(methods)
      assert Enum.member?(methods, :invite)
      assert Enum.member?(methods, :ack)
      assert Enum.member?(methods, :bye)
      assert Enum.member?(methods, :cancel)
      assert Enum.member?(methods, :register)
      assert Enum.member?(methods, :options)
      assert Enum.member?(methods, :subscribe)
      assert Enum.member?(methods, :notify)
      assert Enum.member?(methods, :publish)
      assert Enum.member?(methods, :message)
    end
  end

  describe "is_standard?/1" do
    test "returns true for standard methods" do
      assert Method.is_standard?(:invite)
      assert Method.is_standard?(:ack)
      assert Method.is_standard?(:bye)
      assert Method.is_standard?(:cancel)
    end

    test "returns false for non-standard methods" do
      assert not Method.is_standard?(:custom)
      assert not Method.is_standard?(:CUSTOM)
      assert not Method.is_standard?(123)
      assert not Method.is_standard?(nil)
    end
  end

  describe "parse/1" do
    test "correctly parses standard methods" do
      assert {:ok, :invite} = Method.parse("INVITE")
      assert {:ok, :ack} = Method.parse("ACK")
      assert {:ok, :register} = Method.parse("REGISTER")
      assert {:ok, :subscribe} = Method.parse("subscribe")
    end

    test "parses custom methods as uppercase atoms" do
      assert {:ok, :CUSTOM} = Method.parse("CUSTOM")
      assert {:ok, :"X-CUSTOM"} = Method.parse("X-CUSTOM")
    end

    test "returns error for invalid methods" do
      assert {:error, :invalid_method} = Method.parse(123)
      assert {:error, :invalid_method} = Method.parse(nil)
    end
  end

  describe "parse!/1" do
    test "correctly parses standard methods" do
      assert :invite = Method.parse!("INVITE")
      assert :ack = Method.parse!("ACK")
      assert :register = Method.parse!("REGISTER")
    end

    test "parses custom methods as uppercase atoms" do
      assert :CUSTOM = Method.parse!("CUSTOM")
      assert :"X-CUSTOM" = Method.parse!("X-CUSTOM")
    end

    test "raises error for invalid methods" do
      assert_raise ArgumentError, fn -> Method.parse!(123) end
      assert_raise ArgumentError, fn -> Method.parse!(nil) end
    end
  end

  describe "to_string/1" do
    test "correctly converts standard methods to strings" do
      assert "INVITE" = Method.to_string(:invite)
      assert "ACK" = Method.to_string(:ack)
      assert "REGISTER" = Method.to_string(:register)
    end

    test "preserves custom method capitalization" do
      assert "CUSTOM" = Method.to_string(:CUSTOM)
      assert "X-CUSTOM" = Method.to_string(:"X-CUSTOM")
    end
  end

  describe "method properties" do
    test "allows_body?/1" do
      assert Method.allows_body?(:invite)
      assert Method.allows_body?(:register)
      assert Method.allows_body?(:options)
    end

    test "creates_dialog?/1" do
      assert Method.creates_dialog?(:invite)
      assert Method.creates_dialog?(:subscribe)
      assert Method.creates_dialog?(:refer)
      assert not Method.creates_dialog?(:register)
      assert not Method.creates_dialog?(:options)
    end

    test "requires_contact?/1" do
      assert Method.requires_contact?(:invite)
      assert Method.requires_contact?(:register)
      assert Method.requires_contact?(:subscribe)
      assert not Method.requires_contact?(:options)
      assert not Method.requires_contact?(:ack)
    end

    test "can_cancel?/1" do
      assert Method.can_cancel?(:invite)
      assert Method.can_cancel?(:subscribe)
      assert Method.can_cancel?(:register)
      assert not Method.can_cancel?(:ack)
      assert not Method.can_cancel?(:bye)
      assert not Method.can_cancel?(:cancel)
    end
  end
end
