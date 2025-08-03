defmodule Parrot.Sip.Headers.Supported do
  @moduledoc """
  Module for working with SIP Supported headers as defined in RFC 3261 Section 20.37.

  The Supported header field enumerates all the extensions supported
  by the User Agent Client (UAC) or User Agent Server (UAS). The Supported
  header field contains a list of option tags, described in Section 19.2 of RFC 3261.

  The Supported header plays a key role in SIP capability negotiation:
  - Declaring optional extensions that the UA understands
  - Enabling feature negotiation between endpoints
  - Working with Require and Proxy-Require headers for mandatory features
  - Facilitating backward compatibility and protocol extensibility

  Common option tags include:
  - 100rel: Reliable provisional responses (RFC 3262)
  - timer: Session timers (RFC 4028)
  - replaces: Call transfer (RFC 3891)
  - path: Path extension for registrations (RFC 3327)
  - gruu: Globally Routable User Agent URIs (RFC 5627)

  References:
  - RFC 3261 Section 19.2: Option Tags
  - RFC 3261 Section 20.32: Require Header Field
  - RFC 3261 Section 20.37: Supported Header Field
  - RFC 3261 Section 20.40: Unsupported Header Field
  - IANA SIP Option Tags Registry
  """

  @doc """
  Creates a new Supported header with the specified options.

  ## Examples

      iex> Parrot.Sip.Headers.Supported.new(["path", "100rel"])
      ["path", "100rel"]
  """
  @spec new([String.t()]) :: [String.t()]
  def new(options) when is_list(options), do: options

  @doc """
  Parses a Supported header string into a list of option tags.

  ## Examples

      iex> Parrot.Sip.Headers.Supported.parse("path, 100rel")
      ["path", "100rel"]
      
      iex> Parrot.Sip.Headers.Supported.parse("")
      []
  """
  @spec parse(String.t()) :: [String.t()]
  def parse(""), do: []

  def parse(string) when is_binary(string) do
    string
    |> String.split(",")
    |> Enum.map(&String.trim/1)
    |> Enum.filter(&(&1 != ""))
  end

  @doc """
  Formats a list of Supported options as a string.

  ## Examples

      iex> Parrot.Sip.Headers.Supported.format(["path", "100rel"])
      "path, 100rel"
      
      iex> Parrot.Sip.Headers.Supported.format([])
      ""
  """
  @spec format([String.t()]) :: String.t()
  def format([]), do: ""

  def format(options) when is_list(options) do
    Enum.join(options, ", ")
  end

  @doc """
  Adds an option to the Supported header.

  ## Examples

      iex> Parrot.Sip.Headers.Supported.add(["path"], "100rel")
      ["path", "100rel"]
      
      iex> Parrot.Sip.Headers.Supported.add(["path", "100rel"], "path")
      ["path", "100rel"]
  """
  @spec add([String.t()], String.t()) :: [String.t()]
  def add(options, option) when is_list(options) and is_binary(option) do
    if option in options do
      options
    else
      options ++ [option]
    end
  end

  @doc """
  Removes an option from the Supported header.

  ## Examples

      iex> Parrot.Sip.Headers.Supported.remove(["path", "100rel"], "path")
      ["100rel"]
      
      iex> Parrot.Sip.Headers.Supported.remove(["path"], "100rel")
      ["path"]
  """
  @spec remove([String.t()], String.t()) :: [String.t()]
  def remove(options, option) when is_list(options) and is_binary(option) do
    Enum.filter(options, &(&1 != option))
  end

  @doc """
  Checks if a specific option is supported.

  ## Examples

      iex> Parrot.Sip.Headers.Supported.supports?(["path", "100rel"], "path")
      true
      
      iex> Parrot.Sip.Headers.Supported.supports?(["path"], "100rel")
      false
  """
  @spec supports?([String.t()], String.t()) :: boolean()
  def supports?(options, option) when is_list(options) and is_binary(option) do
    option in options
  end
end
