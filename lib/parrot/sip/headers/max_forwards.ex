defmodule Parrot.Sip.Headers.MaxForwards do
  @moduledoc """
  Module for working with SIP Max-Forwards headers as defined in RFC 3261 Section 20.22.

  The Max-Forwards header is used to limit the number of proxies or gateways 
  that can forward a request. It consists of a single integer value that is 
  decremented by each proxy that forwards the message.

  Max-Forwards serves important purposes in SIP:
  - Preventing infinite loops in proxy networks
  - Detecting forwarding loops caused by misconfiguration
  - Limiting the request scope to a specific number of hops
  - Triggering 483 (Too Many Hops) responses when reaching zero

  Each proxy MUST decrement the Max-Forwards value by one when forwarding
  a request. The recommended initial value is 70, as specified in RFC 3261
  Section 8.1.1.6.

  References:
  - RFC 3261 Section 8.1.1.6: Max-Forwards
  - RFC 3261 Section 16.6: Request Forwarding (proxy behavior)
  - RFC 3261 Section 20.22: Max-Forwards Header Field
  - RFC 3261 Section 21.4.20: 483 Too Many Hops
  """

  @doc """
  Creates a new Max-Forwards header with the specified value.

  ## Examples

      iex> Parrot.Sip.Headers.MaxForwards.new(70)
      70
  """
  @spec new(integer()) :: integer()
  def new(value) when is_integer(value) and value >= 0, do: value

  @doc """
  Creates a new Max-Forwards header with the default value of 70.

  ## Examples

      iex> Parrot.Sip.Headers.MaxForwards.default()
      70
  """
  @spec default() :: integer()
  def default(), do: 70

  @doc """
  Parses a Max-Forwards header string into an integer value.

  ## Examples

      iex> Parrot.Sip.Headers.MaxForwards.parse("70")
      70
      
      iex> Parrot.Sip.Headers.MaxForwards.parse("0")
      0
  """
  @spec parse(String.t()) :: integer()
  def parse(string) when is_binary(string) do
    case Integer.parse(string) do
      {value, ""} when value >= 0 -> value
      _ -> raise ArgumentError, "Invalid Max-Forwards value: #{string}"
    end
  end

  @doc """
  Formats a Max-Forwards value as a string.

  ## Examples

      iex> Parrot.Sip.Headers.MaxForwards.format(70)
      "70"
      
      iex> Parrot.Sip.Headers.MaxForwards.format(0)
      "0"
  """
  @spec format(integer()) :: String.t()
  def format(value) when is_integer(value) and value >= 0, do: Integer.to_string(value)

  @doc """
  Decrements the Max-Forwards value by 1.
  Returns nil if value is already 0.

  ## Examples

      iex> Parrot.Sip.Headers.MaxForwards.decrement(70)
      69
      
      iex> Parrot.Sip.Headers.MaxForwards.decrement(1)
      0
      
      iex> Parrot.Sip.Headers.MaxForwards.decrement(0)
      nil
  """
  @spec decrement(integer()) :: integer() | nil
  def decrement(value) when is_integer(value) and value > 0, do: value - 1
  def decrement(0), do: nil

  @doc """
  Checks if the Max-Forwards value has reached 0.

  ## Examples

      iex> Parrot.Sip.Headers.MaxForwards.zero?(0)
      true
      
      iex> Parrot.Sip.Headers.MaxForwards.zero?(1)
      false
  """
  @spec zero?(integer()) :: boolean()
  def zero?(value) when is_integer(value), do: value == 0
end
