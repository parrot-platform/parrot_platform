defmodule Parrot.Sip.Headers.CallId do
  @moduledoc """
  Module for working with SIP Call-ID headers as defined in RFC 3261 Section 20.8.

  The Call-ID header uniquely identifies a specific invitation or
  all registrations of a particular client. It is a globally unique identifier
  for the call and must be the same for all requests and responses in a given dialog.

  Call-ID serves multiple purposes in SIP:
  - Uniquely identifying dialogs (along with From and To tags)
  - Matching requests and responses for stateless proxies
  - Detecting duplicate requests
  - Distinguishing between separate registrations from the same client

  The syntax typically includes a random string followed by @ and a domain name,
  providing a simple mechanism to generate globally unique identifiers without
  centralized coordination.

  References:
  - RFC 3261 Section 8.1.1.4: Call-ID
  - RFC 3261 Section 12.1.1: UAC Behavior (Call-ID role in dialog)
  - RFC 3261 Section 19.3: Dialog Identifiers
  - RFC 3261 Section 20.8: Call-ID Header Field
  """

  @doc """
  Creates a new Call-ID header.

  ## Examples

      iex> Parrot.Sip.Headers.CallId.new("a84b4c76e66710@pc33.atlanta.com")
      "a84b4c76e66710@pc33.atlanta.com"
      
  """
  @spec new(String.t()) :: String.t()
  def new(call_id) when is_binary(call_id) do
    call_id
  end

  @doc """
  Parses a Call-ID header value.

  ## Examples

      iex> Parrot.Sip.Headers.CallId.parse("a84b4c76e66710@pc33.atlanta.com")
      "a84b4c76e66710@pc33.atlanta.com"
      
  """
  @spec parse(String.t()) :: String.t()
  def parse(string) when is_binary(string) do
    String.trim(string)
  end

  @doc """
  Formats a Call-ID header value.

  ## Examples

      iex> Parrot.Sip.Headers.CallId.format("a84b4c76e66710@pc33.atlanta.com")
      "a84b4c76e66710@pc33.atlanta.com"
      
  """
  @spec format(String.t()) :: String.t()
  def format(call_id) when is_binary(call_id) do
    call_id
  end

  @doc """
  Alias for format/1 for consistency with other header modules.

  ## Examples

      iex> Parrot.Sip.Headers.CallId.to_string("a84b4c76e66710@pc33.atlanta.com")
      "a84b4c76e66710@pc33.atlanta.com"
      
  """
  @spec to_string(String.t()) :: String.t()
  def to_string(call_id) when is_binary(call_id), do: format(call_id)

  @doc """
  Generates a unique Call-ID.

  The generated Call-ID consists of a random string, the '@' character,
  and a hostname or IP address.

  ## Examples

      iex> call_id = Parrot.Sip.Headers.CallId.generate("example.com")
      iex> String.contains?(call_id, "@example.com")
      true
      
  """
  @spec generate(String.t()) :: String.t()
  def generate(host) when is_binary(host) do
    random = :crypto.strong_rand_bytes(16) |> Base.encode16(case: :lower)
    "#{random}@#{host}"
  end

  @doc """
  Generates a unique Call-ID with a default hostname.

  ## Examples

      iex> call_id = Parrot.Sip.Headers.CallId.generate()
      iex> String.contains?(call_id, "@")
      true
      
  """
  @spec generate() :: String.t()
  def generate do
    # Use a default hostname or get the local hostname
    host = "localhost"
    generate(host)
  end
end
