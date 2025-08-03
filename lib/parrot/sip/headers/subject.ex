defmodule Parrot.Sip.Headers.Subject do
  @moduledoc """
  Module for working with SIP Subject headers as defined in RFC 3261 Section 20.36.

  The Subject header field provides a summary or indicates the nature of the call,
  allowing call filtering without having to parse the session description.
  The session description does not have to use the same subject indication as
  the invitation.

  The Subject header serves several purposes:
  - Providing human-readable information about the call or message
  - Enabling call filtering and screening based on subject
  - Supporting automatic call distribution (ACD) systems
  - Facilitating call logging and history display

  The Subject header is similar to the Subject header in email and follows
  similar conventions. It supports UTF-8 encoding for internationalization.

  References:
  - RFC 3261 Section 20.36: Subject Header Field
  - RFC 2047: MIME (Multipurpose Internet Mail Extensions) Part Three
  - RFC 2822: Internet Message Format (Subject header precedent)
  """

  defstruct [:value]

  @type t :: %__MODULE__{
          value: String.t()
        }

  @doc """
  Creates a new Subject header.

  ## Examples

      iex> Parrot.Sip.Headers.Subject.new("Project X Discussion")
      %Parrot.Sip.Headers.Subject{value: "Project X Discussion"}
  """
  @spec new(String.t()) :: t()
  def new(value) when is_binary(value) do
    %__MODULE__{value: value}
  end

  @doc """
  Parses a Subject header string into a struct.

  ## Examples

      iex> Parrot.Sip.Headers.Subject.parse("Project X Discussion")
      %Parrot.Sip.Headers.Subject{value: "Project X Discussion"}
  """
  @spec parse(String.t()) :: t()
  def parse(string) when is_binary(string) do
    %__MODULE__{value: string}
  end

  @doc """
  Formats a Subject struct as a string.

  ## Examples

      iex> subject = %Parrot.Sip.Headers.Subject{value: "Project X Discussion"}
      iex> Parrot.Sip.Headers.Subject.format(subject)
      "Project X Discussion"
  """
  @spec format(t()) :: String.t()
  def format(%__MODULE__{} = subject) do
    subject.value
  end

  @doc """
  Alias for format/1 for consistency with other header modules.

  ## Examples

      iex> subject = %Parrot.Sip.Headers.Subject{value: "Project X Discussion"}
      iex> Parrot.Sip.Headers.Subject.to_string(subject)
      "Project X Discussion"
  """
  @spec to_string(t()) :: String.t()
  def to_string(%__MODULE__{} = subject), do: format(subject)
end
