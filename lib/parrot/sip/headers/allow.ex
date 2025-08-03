defmodule Parrot.Sip.Headers.Allow do
  @moduledoc """
  Module for working with SIP Allow headers as defined in RFC 3261 Section 20.5.

  The Allow header field lists the set of methods supported by the User Agent
  generating the message. The Allow header field MUST be present in a 405
  (Method Not Allowed) response.

  This module uses `Parrot.Sip.MethodSet` internally for efficient method set operations.

  References:
  - RFC 3261 Section 20.5: Allow Header Field
  """

  alias Parrot.Sip.{Method, MethodSet}

  @doc """
  Creates a new Allow header with the specified methods.

  ## Examples

      iex> Parrot.Sip.Headers.Allow.new([:invite, :ack, :bye])
      %Parrot.Sip.MethodSet{}
  """
  @spec new([Method.t() | String.t()]) :: MethodSet.t()
  def new(methods) when is_list(methods), do: MethodSet.new(methods)

  @doc """
  Creates a standard set of common SIP methods.

  ## Examples

      iex> Parrot.Sip.Headers.Allow.standard()
      #Parrot.Sip.MethodSet<[:ack, :bye, :cancel, :invite, :message, :notify, :options, :register, :subscribe]>
  """
  @spec standard() :: MethodSet.t()
  def standard do
    MethodSet.standard_methods()
  end

  @doc """
  Parses an Allow header string into a method set.

  ## Examples

      iex> Parrot.Sip.Headers.Allow.parse("INVITE, ACK, BYE")
      #Parrot.Sip.MethodSet<[:ack, :bye, :invite]>
      
      iex> Parrot.Sip.Headers.Allow.parse("")
      #Parrot.Sip.MethodSet<[]>
  """
  @spec parse(String.t()) :: MethodSet.t()
  def parse(""), do: MethodSet.new()

  def parse(string) when is_binary(string) do
    MethodSet.from_allow_string(string)
  end

  @doc """
  Formats a method set as a string for the Allow header.

  ## Examples

      iex> set = Parrot.Sip.MethodSet.new([:invite, :ack, :bye])
      iex> Parrot.Sip.Headers.Allow.format(set)
      "INVITE, ACK, BYE"
      
      iex> Parrot.Sip.Headers.Allow.format(Parrot.Sip.MethodSet.new())
      ""
  """
  @spec format(MethodSet.t()) :: String.t()
  def format(%MethodSet{methods: methods}) when map_size(methods) == 0, do: ""

  def format(%MethodSet{} = method_set) do
    MethodSet.to_allow_string(method_set)
  end

  # For backward compatibility
  def format([]), do: ""

  def format(methods) when is_list(methods) do
    MethodSet.new(methods) |> format()
  end

  @doc """
  Adds a method to the Allow header.

  ## Examples

      iex> set = Parrot.Sip.MethodSet.new([:invite, :ack])
      iex> Parrot.Sip.Headers.Allow.add(set, :bye)
      #Parrot.Sip.MethodSet<[:ack, :bye, :invite]>
      
      iex> set = Parrot.Sip.MethodSet.new([:invite, :ack, :bye])
      iex> Parrot.Sip.Headers.Allow.add(set, :invite)
      #Parrot.Sip.MethodSet<[:ack, :bye, :invite]>
  """
  @spec add(MethodSet.t(), Method.t() | String.t()) :: MethodSet.t()
  def add(%MethodSet{} = method_set, method) do
    MethodSet.put(method_set, method)
  end

  # For backward compatibility
  def add(methods, method) when is_list(methods) do
    MethodSet.new(methods) |> add(method)
  end

  @doc """
  Removes a method from the Allow header.

  ## Examples

      iex> set = Parrot.Sip.MethodSet.new([:invite, :ack, :bye])
      iex> Parrot.Sip.Headers.Allow.remove(set, :invite)
      #Parrot.Sip.MethodSet<[:ack, :bye]>
      
      iex> set = Parrot.Sip.MethodSet.new([:invite, :ack])
      iex> Parrot.Sip.Headers.Allow.remove(set, :bye)
      #Parrot.Sip.MethodSet<[:ack, :invite]>
  """
  @spec remove(MethodSet.t(), Method.t() | String.t()) :: MethodSet.t()
  def remove(%MethodSet{} = method_set, method) do
    MethodSet.delete(method_set, method)
  end

  # For backward compatibility
  def remove(methods, method) when is_list(methods) do
    MethodSet.new(methods) |> remove(method)
  end

  @doc """
  Checks if a specific method is allowed.

  ## Examples

      iex> set = Parrot.Sip.MethodSet.new([:invite, :ack, :bye])
      iex> Parrot.Sip.Headers.Allow.allows?(set, :invite)
      true
      
      iex> set = Parrot.Sip.MethodSet.new([:invite, :ack])
      iex> Parrot.Sip.Headers.Allow.allows?(set, :bye)
      false
  """
  @spec allows?(MethodSet.t(), Method.t() | String.t()) :: boolean()
  def allows?(%MethodSet{} = method_set, method) do
    MethodSet.member?(method_set, method)
  end

  # For backward compatibility
  def allows?(methods, method) when is_list(methods) do
    MethodSet.new(methods) |> allows?(method)
  end
end
