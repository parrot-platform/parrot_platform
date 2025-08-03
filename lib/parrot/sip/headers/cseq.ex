defmodule Parrot.Sip.Headers.CSeq do
  @moduledoc """
  Module for working with SIP CSeq headers as defined in RFC 3261 Section 20.16.

  The CSeq (Command Sequence) header field serves as a way to identify and order
  transactions within a dialog. It consists of a sequence number and a method name.

  The CSeq serves several critical functions in SIP:
  - Uniquely identifying transactions within dialogs
  - Distinguishing between new requests and retransmissions
  - Ensuring proper message ordering
  - Matching responses to requests

  Each new request within a dialog increments the CSeq number. 
  ACK and CANCEL requests use the same CSeq number as the request they reference
  but with different methods, as described in RFC 3261 Sections 17.1.1.3 and 9.1.

  References:
  - RFC 3261 Section 8.1.1.5: CSeq
  - RFC 3261 Section 12.2.1.1: UAC Behavior - Generating the Request (CSeq in dialogs)
  - RFC 3261 Section 17.1.1.3: CSeq for CANCEL
  - RFC 3261 Section 20.16: CSeq Header Field
  """

  defstruct [
    # Integer sequence number
    :number,
    # Atom representing the method (:invite, :ack, etc.)
    :method
  ]

  @type t :: %__MODULE__{
          number: integer(),
          method: atom()
        }

  @doc """
  Creates a new CSeq header.
  """
  @spec new(integer(), atom()) :: t()
  def new(number, method) when is_integer(number) and is_atom(method) do
    %__MODULE__{
      number: number,
      method: method
    }
  end

  @doc """
  Converts a CSeq header to a string representation.
  """
  @spec format(t()) :: String.t()
  def format(cseq) do
    method_str = cseq.method |> Atom.to_string() |> String.upcase()
    "#{cseq.number} #{method_str}"
  end

  @doc """
  Increments the sequence number of a CSeq header.
  """
  @spec increment(t()) :: t()
  def increment(cseq) do
    %{cseq | number: cseq.number + 1}
  end

  @doc """
  Creates a new CSeq header with the same sequence number but a different method.
  """
  @spec with_method(t(), atom()) :: t()
  def with_method(cseq, method) when is_atom(method) do
    %{cseq | method: method}
  end

  @doc """
  Parses a CSeq header string into a CSeq struct.

  ## Examples

      iex> Parrot.Sip.Headers.CSeq.parse("314159 INVITE")
      %Parrot.Sip.Headers.CSeq{number: 314159, method: :invite}
      
      iex> Parrot.Sip.Headers.CSeq.parse("1 ACK")
      %Parrot.Sip.Headers.CSeq{number: 1, method: :ack}

  """
  @spec parse(String.t()) :: t()
  def parse(string) when is_binary(string) do
    # Split into number and method
    [number_str, method_str] = String.split(string, " ", parts: 2)

    # Parse the number
    {number, _} = Integer.parse(number_str)

    # Parse the method (convert to lowercase atom)
    method = method_str |> String.downcase() |> String.to_atom()

    %__MODULE__{
      number: number,
      method: method
    }
  end
end
