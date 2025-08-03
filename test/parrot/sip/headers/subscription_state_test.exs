defmodule Parrot.Sip.Headers.SubscriptionStateTest do
  use ExUnit.Case

  alias Parrot.Sip.Headers

  describe "parsing Subscription-State headers" do
    test "parses Subscription-State header" do
      header_value = "active;expires=3600"

      subscription_state = Headers.SubscriptionState.parse(header_value)

      assert subscription_state.state == :active
      assert subscription_state.parameters["expires"] == "3600"

      assert Headers.SubscriptionState.format(subscription_state) == header_value
    end

    test "parses Subscription-State header with reason" do
      header_value = "terminated;reason=timeout"

      subscription_state = Headers.SubscriptionState.parse(header_value)

      assert subscription_state.state == :terminated
      assert subscription_state.parameters["reason"] == "timeout"

      assert Headers.SubscriptionState.format(subscription_state) == header_value
    end
  end

  describe "creating Subscription-State headers" do
    test "creates Subscription-State header" do
      subscription_state = Headers.SubscriptionState.new(:active, %{"expires" => "3600"})

      assert is_map(subscription_state)
      assert subscription_state.state == :active
      assert subscription_state.parameters["expires"] == "3600"

      assert Headers.SubscriptionState.format(subscription_state) == "active;expires=3600"
    end
  end
end
