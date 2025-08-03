defmodule Parrot.Sip.Headers.SubscriptionState do
  @moduledoc """
  Module for working with SIP Subscription-State headers as defined in RFC 3265 Section 7.2.3.

  The Subscription-State header field provides subscription state information.
  It is used in NOTIFY requests to convey the status of a subscription.
  The header field contains a value that indicates the state of the subscription.
  It can also contain parameters that provide additional information about the subscription.

  The Subscription-State header is mandatory in all NOTIFY requests and indicates:
  - active: The subscription is active and notifications will continue
  - pending: The subscription has been received but not yet authorized
  - terminated: The subscription has ended and no more notifications will be sent

  Important parameters include:
  - expires: For active/pending states, indicates remaining subscription time
  - reason: For terminated state, indicates why the subscription ended
  - retry-after: Suggests when to retry after certain termination reasons

  Common termination reasons:
  - deactivated: Subscription terminated by subscriber
  - timeout: Subscription expired
  - probation: Subscription in probation due to failed notifications
  - rejected: Subscription rejected by notifier
  - giveup: Subscription ended due to fatal error
  - noresource: Resource no longer exists

  References:
  - RFC 3265 Section 7.2.3: Subscription-State Header Field
  - RFC 3265 Section 3.2.4: Subscriber NOTIFY Behavior
  - RFC 3265 Section 3.1.6.2: Notifier NOTIFY Behavior
  - RFC 3265 Section 4.2.3: Subscription State Machine
  """

  @states [:active, :pending, :terminated]

  defstruct [
    :state,
    :parameters
  ]

  @type t :: %__MODULE__{
          state: :active | :pending | :terminated,
          parameters: %{String.t() => String.t()}
        }

  @doc """
  Creates a new Subscription-State header.

  ## Examples

      iex> Parrot.Sip.Headers.SubscriptionState.new(:active, %{"expires" => "3600"})
      %Parrot.Sip.Headers.SubscriptionState{state: :active, parameters: %{"expires" => "3600"}}
      
      iex> Parrot.Sip.Headers.SubscriptionState.new(:terminated, %{"reason" => "timeout"})
      %Parrot.Sip.Headers.SubscriptionState{state: :terminated, parameters: %{"reason" => "timeout"}}
  """
  @spec new(atom(), map()) :: t()
  def new(state, parameters \\ %{}) when state in @states do
    %__MODULE__{
      state: state,
      parameters: parameters
    }
  end

  @doc """
  Parses a Subscription-State header string into a struct.

  ## Examples

      iex> Parrot.Sip.Headers.SubscriptionState.parse("active;expires=3600")
      %Parrot.Sip.Headers.SubscriptionState{state: :active, parameters: %{"expires" => "3600"}}
      
      iex> Parrot.Sip.Headers.SubscriptionState.parse("terminated;reason=timeout")
      %Parrot.Sip.Headers.SubscriptionState{state: :terminated, parameters: %{"reason" => "timeout"}}
  """
  @spec parse(String.t()) :: t()
  def parse(string) when is_binary(string) do
    case String.split(string, ";", parts: 2) do
      [state] ->
        %__MODULE__{
          state: String.to_existing_atom(state),
          parameters: %{}
        }

      [state, params_string] ->
        parameters =
          params_string
          |> String.split(";")
          |> Enum.map(&String.split(&1, "=", parts: 2))
          |> Enum.map(fn [key, value] -> {key, value} end)
          |> Enum.into(%{})

        %__MODULE__{
          state: String.to_existing_atom(state),
          parameters: parameters
        }
    end
  end

  @doc """
  Formats a Subscription-State struct as a string.

  ## Examples

      iex> subscription_state = %Parrot.Sip.Headers.SubscriptionState{state: :active, parameters: %{"expires" => "3600"}}
      iex> Parrot.Sip.Headers.SubscriptionState.format(subscription_state)
      "active;expires=3600"
      
      iex> subscription_state = %Parrot.Sip.Headers.SubscriptionState{state: :terminated, parameters: %{"reason" => "timeout"}}
      iex> Parrot.Sip.Headers.SubscriptionState.format(subscription_state)
      "terminated;reason=timeout"
  """
  @spec format(t()) :: String.t()
  def format(%__MODULE__{} = subscription_state) do
    params_string =
      if Enum.empty?(subscription_state.parameters) do
        ""
      else
        ";" <>
          (subscription_state.parameters
           |> Enum.map(fn {key, value} -> "#{key}=#{value}" end)
           |> Enum.join(";"))
      end

    "#{Atom.to_string(subscription_state.state)}#{params_string}"
  end

  @doc """
  Returns a new Subscription-State with a reason parameter added.

  ## Examples

      iex> state = Parrot.Sip.Headers.SubscriptionState.new(:terminated)
      iex> Parrot.Sip.Headers.SubscriptionState.set_reason("noresource", state)
      %Parrot.Sip.Headers.SubscriptionState{state: :terminated, parameters: %{"reason" => "noresource"}}
  """
  @spec set_reason(String.t(), t()) :: t()
  def set_reason(reason, %__MODULE__{} = subscription_state) when is_binary(reason) do
    %__MODULE__{
      subscription_state
      | parameters: Map.put(subscription_state.parameters, "reason", reason)
    }
  end

  @doc """
  Returns a new Subscription-State with an expires parameter added.

  ## Examples

      iex> state = Parrot.Sip.Headers.SubscriptionState.new(:active)
      iex> Parrot.Sip.Headers.SubscriptionState.set_expires("3600", state)
      %Parrot.Sip.Headers.SubscriptionState{state: :active, parameters: %{"expires" => "3600"}}
  """
  @spec set_expires(String.t(), t()) :: t()
  def set_expires(expires, %__MODULE__{} = subscription_state) when is_binary(expires) do
    %__MODULE__{
      subscription_state
      | parameters: Map.put(subscription_state.parameters, "expires", expires)
    }
  end

  @doc """
  Checks if the subscription state is terminated.

  ## Examples

      iex> state = Parrot.Sip.Headers.SubscriptionState.new(:terminated)
      iex> Parrot.Sip.Headers.SubscriptionState.terminated?(state)
      true
      
      iex> state = Parrot.Sip.Headers.SubscriptionState.new(:active)
      iex> Parrot.Sip.Headers.SubscriptionState.terminated?(state)
      false
  """
  @spec terminated?(t()) :: boolean()
  def terminated?(%__MODULE__{state: :terminated}), do: true
  def terminated?(%__MODULE__{}), do: false
end
