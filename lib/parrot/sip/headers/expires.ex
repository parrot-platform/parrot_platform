defmodule Parrot.Sip.Headers.Expires do
  @moduledoc """
  Module for working with SIP Expires headers as defined in RFC 3261 Section 20.19.

  The Expires header field gives the relative time after which the message
  (or content) expires. The unit of time is seconds.

  The Expires header serves several purposes in SIP:
  - In REGISTER requests: indicates how long the registration should be valid
  - In INVITE requests/responses: indicates when the invitation should expire
  - In SUBSCRIBE requests: indicates the desired duration of the subscription
  - In 3xx responses: indicates the validity duration of the Contact URI

  The value is an integer representing time in seconds. A value of 0 has special
  meaning in REGISTER requests, indicating de-registration of the contact.
  For other uses, reasonable defaults depend on the method and context.

  References:
  - RFC 3261 Section 10.2.1.1: Constructing the REGISTER Request
  - RFC 3261 Section 10.3: Processing REGISTER Requests (registrar behavior)
  - RFC 3261 Section 13.3.1: INVITE Transaction Timeouts
  - RFC 3261 Section 20.19: Expires Header Field
  - RFC 3265 Section 3.1.1: SUBSCRIBE Duration
  """

  @doc """
  Creates a new Expires header with the specified value in seconds.

  ## Examples

      iex> Parrot.Sip.Headers.Expires.new(3600)
      3600
  """
  @spec new(integer()) :: integer()
  def new(seconds) when is_integer(seconds) and seconds >= 0, do: seconds

  @doc """
  Creates a default Expires header with a value of 3600 seconds (1 hour).

  ## Examples

      iex> Parrot.Sip.Headers.Expires.default()
      3600
  """
  @spec default() :: integer()
  def default(), do: 3600

  @doc """
  Parses an Expires header string into an integer value.

  ## Examples

      iex> Parrot.Sip.Headers.Expires.parse("3600")
      3600
      
      iex> Parrot.Sip.Headers.Expires.parse("0")
      0
  """
  @spec parse(String.t()) :: integer()
  def parse(string) when is_binary(string) do
    case Integer.parse(string) do
      {value, ""} when value >= 0 -> value
      _ -> raise ArgumentError, "Invalid Expires value: #{string}"
    end
  end

  @doc """
  Formats an Expires value as a string.

  ## Examples

      iex> Parrot.Sip.Headers.Expires.format(3600)
      "3600"
      
      iex> Parrot.Sip.Headers.Expires.format(0)
      "0"
  """
  @spec format(integer()) :: String.t()
  def format(value) when is_integer(value) and value >= 0, do: Integer.to_string(value)

  @doc """
  Alias for format/1 for consistency with other header modules.

  ## Examples

      iex> Parrot.Sip.Headers.Expires.to_string(3600)
      "3600"
      
      iex> Parrot.Sip.Headers.Expires.to_string(0)
      "0"
  """
  @spec to_string(integer()) :: String.t()
  def to_string(value) when is_integer(value) and value >= 0, do: format(value)

  @doc """
  Checks if an Expires value has expired based on a reference time.

  ## Examples

      iex> now = DateTime.utc_now()
      iex> expires_time = DateTime.add(now, 3600, :second)
      iex> Parrot.Sip.Headers.Expires.expired?(expires_time, now)
      false
      
      iex> now = DateTime.utc_now()
      iex> expires_time = DateTime.add(now, -10, :second)  # 10 seconds in the past
      iex> Parrot.Sip.Headers.Expires.expired?(expires_time, now)
      true
  """
  @spec expired?(DateTime.t(), DateTime.t()) :: boolean()
  def expired?(expires_time, reference_time \\ DateTime.utc_now()) do
    DateTime.compare(expires_time, reference_time) == :lt
  end

  @doc """
  Calculates an expiration DateTime from a duration in seconds.

  ## Examples

      iex> now = DateTime.utc_now()
      iex> expires_time = Parrot.Sip.Headers.Expires.calculate_expiry(3600, now)
      iex> DateTime.diff(expires_time, now, :second)
      3600
  """
  @spec calculate_expiry(integer(), DateTime.t()) :: DateTime.t()
  def calculate_expiry(seconds, reference_time \\ DateTime.utc_now()) do
    DateTime.add(reference_time, seconds, :second)
  end

  @doc """
  Calculates the remaining time in seconds until expiration.
  Returns a negative value if already expired.

  ## Examples

      iex> now = DateTime.utc_now()
      iex> expires_time = DateTime.add(now, 3600, :second)
      iex> remaining = Parrot.Sip.Headers.Expires.remaining_seconds(expires_time, now)
      iex> remaining >= 3599 and remaining <= 3600
      true
      
      iex> now = DateTime.utc_now()
      iex> expires_time = DateTime.add(now, -10, :second)
      iex> Parrot.Sip.Headers.Expires.remaining_seconds(expires_time, now)
      -10
  """
  @spec remaining_seconds(DateTime.t(), DateTime.t()) :: integer()
  def remaining_seconds(expires_time, reference_time \\ DateTime.utc_now()) do
    DateTime.diff(expires_time, reference_time, :second)
  end
end
