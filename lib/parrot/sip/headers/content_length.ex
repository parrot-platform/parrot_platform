defmodule Parrot.Sip.Headers.ContentLength do
  @moduledoc """
  Module for working with SIP Content-Length headers as defined in RFC 3261 Section 20.14.

  The Content-Length header indicates the size of the message body in bytes. It's essential
  for message framing, especially when using stream-based transport protocols like TCP.

  Content-Length serves critical functions in SIP:
  - Enabling correct framing of messages over stream transports
  - Preventing truncated message reception
  - Allowing endpoints to determine when a complete message has been received
  - Supporting pipelining of multiple requests over a single connection

  As specified in RFC 3261 Section 18.3, if no body is present in a message, the
  Content-Length value should be 0. The header is mandatory for messages sent over TCP.

  References:
  - RFC 3261 Section 7.4.1: Header Field Format
  - RFC 3261 Section 18.3: Framing
  - RFC 3261 Section 20.14: Content-Length Header Field
  """

  defstruct [:value]

  @type t :: %__MODULE__{
          value: non_neg_integer()
        }

  @doc """
  Creates a new Content-Length header with the specified value.

  ## Examples

      iex> Parrot.Sip.Headers.ContentLength.new(42)
      %Parrot.Sip.Headers.ContentLength{value: 42}
      
  """
  @spec new(non_neg_integer()) :: t()
  def new(length) when is_integer(length) and length >= 0 do
    %__MODULE__{value: length}
  end

  @doc """
  Parses a Content-Length header value.

  ## Examples

      iex> Parrot.Sip.Headers.ContentLength.parse("42")
      %Parrot.Sip.Headers.ContentLength{value: 42}

  """
  @spec parse(String.t()) :: t()
  def parse(string) when is_binary(string) do
    value =
      string
      |> String.trim()
      |> String.to_integer()

    %__MODULE__{value: value}
  end

  @doc """
  Formats a Content-Length header value.

  ## Examples

      iex> content_length = %Parrot.Sip.Headers.ContentLength{value: 42}
      iex> Parrot.Sip.Headers.ContentLength.format(content_length)
      "42"
      
  """
  @spec format(t()) :: String.t()
  def format(%__MODULE__{} = content_length) do
    Integer.to_string(content_length.value)
  end

  @doc """
  Calculates the Content-Length for a given body.

  ## Examples

      iex> Parrot.Sip.Headers.ContentLength.calculate("Hello, world!")
      13
      
  """
  @spec calculate(String.t() | nil) :: non_neg_integer()
  def calculate(nil), do: 0

  def calculate(body) when is_binary(body) do
    byte_size(body)
  end

  @doc """
  Creates a Content-Length header value for a given body.

  ## Examples

      iex> Parrot.Sip.Headers.ContentLength.create("Hello, world!")
      %Parrot.Sip.Headers.ContentLength{value: 13}
      
  """
  @spec create(String.t() | nil) :: t()
  def create(body) do
    new(calculate(body))
  end
end
