defmodule Parrot.Sip.MethodSet do
  @moduledoc """
  A set implementation for SIP methods.

  This module provides functionality for working with sets of SIP methods
  with efficient operations for checking method membership, combining sets,
  and manipulating sets of methods.

  The implementation is based on MapSet for efficiency, with specialized
  handling for SIP methods.

  References:
  - RFC 3261 Section 7.1: SIP Methods
  - RFC 3261 Section 8.2.2: OPTIONS
  - RFC 3261 Section 20.5: Allow Header Field
  """

  alias Parrot.Sip.Method

  defstruct [:methods]

  @type t :: %__MODULE__{
          methods: MapSet.t(Method.t())
        }

  @doc """
  Creates a new empty method set.

  ## Examples

      iex> Parrot.Sip.MethodSet.new()
      #Parrot.Sip.MethodSet<[]>
  """
  @spec new() :: t()
  def new do
    %__MODULE__{methods: MapSet.new()}
  end

  @doc """
  Creates a method set from a list of methods.

  ## Examples

      iex> Parrot.Sip.MethodSet.new([:invite, :ack, :bye])
      #Parrot.Sip.MethodSet<[:ack, :bye, :invite]>
      
      iex> Parrot.Sip.MethodSet.new(["INVITE", "ACK", "BYE"])
      #Parrot.Sip.MethodSet<[:ack, :bye, :invite]>
  """
  @spec new(list(Method.t() | String.t())) :: t()
  def new(methods) do
    methods =
      Enum.map(methods, fn
        method when is_atom(method) ->
          method

        method when is_binary(method) ->
          {:ok, m} = Method.parse(method)
          m
      end)

    %__MODULE__{methods: MapSet.new(methods)}
  end

  @doc """
  Creates a method set containing all standard SIP methods.

  ## Examples

      iex> set = Parrot.Sip.MethodSet.standard_methods()
      iex> Enum.member?(set, :invite)
      true
      iex> Enum.member?(set, :options)
      true
  """
  @spec standard_methods() :: t()
  def standard_methods do
    new(Method.standard_methods())
  end

  @doc """
  Creates a method set containing the basic dialog methods (INVITE, ACK, BYE).

  ## Examples

      iex> set = Parrot.Sip.MethodSet.dialog_methods()
      iex> Parrot.Sip.MethodSet.member?(set, :invite)
      true
      iex> Parrot.Sip.MethodSet.member?(set, :ack)
      true
      iex> Parrot.Sip.MethodSet.member?(set, :bye)
      true
      iex> Parrot.Sip.MethodSet.member?(set, :register)
      false
  """
  @spec dialog_methods() :: t()
  def dialog_methods do
    new([:invite, :ack, :bye])
  end

  @doc """
  Adds a method to the method set.

  ## Examples

      iex> set = Parrot.Sip.MethodSet.new([:invite])
      iex> set = Parrot.Sip.MethodSet.put(set, :ack)
      iex> Parrot.Sip.MethodSet.member?(set, :ack)
      true
      
      iex> set = Parrot.Sip.MethodSet.new()
      iex> set = Parrot.Sip.MethodSet.put(set, "INVITE")
      iex> Parrot.Sip.MethodSet.member?(set, :invite)
      true
  """
  @spec put(t(), Method.t() | String.t()) :: t()
  def put(%__MODULE__{} = set, method) when is_atom(method) do
    %{set | methods: MapSet.put(set.methods, method)}
  end

  def put(%__MODULE__{} = set, method) when is_binary(method) do
    {:ok, m} = Method.parse(method)
    put(set, m)
  end

  @doc """
  Adds multiple methods to the method set.

  ## Examples

      iex> set = Parrot.Sip.MethodSet.new([:invite])
      iex> set = Parrot.Sip.MethodSet.put_all(set, [:ack, :bye])
      iex> Parrot.Sip.MethodSet.member?(set, :ack)
      true
      iex> Parrot.Sip.MethodSet.member?(set, :bye)
      true
  """
  @spec put_all(t(), list(Method.t() | String.t())) :: t()
  def put_all(%__MODULE__{} = set, methods) do
    Enum.reduce(methods, set, fn method, acc ->
      put(acc, method)
    end)
  end

  @doc """
  Removes a method from the method set.

  ## Examples

      iex> set = Parrot.Sip.MethodSet.new([:invite, :ack, :bye])
      iex> set = Parrot.Sip.MethodSet.delete(set, :ack)
      iex> Parrot.Sip.MethodSet.member?(set, :ack)
      false
      
      iex> set = Parrot.Sip.MethodSet.new([:invite, :ack])
      iex> set = Parrot.Sip.MethodSet.delete(set, "INVITE")
      iex> Parrot.Sip.MethodSet.member?(set, :invite)
      false
  """
  @spec delete(t(), Method.t() | String.t()) :: t()
  def delete(%__MODULE__{} = set, method) when is_atom(method) do
    %{set | methods: MapSet.delete(set.methods, method)}
  end

  def delete(%__MODULE__{} = set, method) when is_binary(method) do
    {:ok, m} = Method.parse(method)
    delete(set, m)
  end

  @doc """
  Checks if a method is a member of the method set.

  ## Examples

      iex> set = Parrot.Sip.MethodSet.new([:invite, :ack])
      iex> Parrot.Sip.MethodSet.member?(set, :invite)
      true
      iex> Parrot.Sip.MethodSet.member?(set, :bye)
      false
      
      iex> set = Parrot.Sip.MethodSet.new([:invite, :ack])
      iex> Parrot.Sip.MethodSet.member?(set, "INVITE")
      true
  """
  @spec member?(t(), Method.t() | String.t()) :: boolean()
  def member?(%__MODULE__{} = set, method) when is_atom(method) do
    MapSet.member?(set.methods, method)
  end

  def member?(%__MODULE__{} = set, method) when is_binary(method) do
    {:ok, m} = Method.parse(method)
    member?(set, m)
  end

  @doc """
  Returns the union of two method sets.

  ## Examples

      iex> set1 = Parrot.Sip.MethodSet.new([:invite, :ack])
      iex> set2 = Parrot.Sip.MethodSet.new([:bye, :cancel])
      iex> set3 = Parrot.Sip.MethodSet.union(set1, set2)
      iex> Parrot.Sip.MethodSet.to_list(set3)
      [:ack, :bye, :cancel, :invite]
  """
  @spec union(t(), t()) :: t()
  def union(%__MODULE__{} = set1, %__MODULE__{} = set2) do
    %__MODULE__{methods: MapSet.union(set1.methods, set2.methods)}
  end

  @doc """
  Returns the intersection of two method sets.

  ## Examples

      iex> set1 = Parrot.Sip.MethodSet.new([:invite, :ack, :bye])
      iex> set2 = Parrot.Sip.MethodSet.new([:bye, :cancel, :invite])
      iex> set3 = Parrot.Sip.MethodSet.intersection(set1, set2)
      iex> Parrot.Sip.MethodSet.to_list(set3)
      [:bye, :invite]
  """
  @spec intersection(t(), t()) :: t()
  def intersection(%__MODULE__{} = set1, %__MODULE__{} = set2) do
    %__MODULE__{methods: MapSet.intersection(set1.methods, set2.methods)}
  end

  @doc """
  Returns the difference of two method sets.

  ## Examples

      iex> set1 = Parrot.Sip.MethodSet.new([:invite, :ack, :bye])
      iex> set2 = Parrot.Sip.MethodSet.new([:bye, :cancel])
      iex> set3 = Parrot.Sip.MethodSet.difference(set1, set2)
      iex> Parrot.Sip.MethodSet.to_list(set3)
      [:ack, :invite]
  """
  @spec difference(t(), t()) :: t()
  def difference(%__MODULE__{} = set1, %__MODULE__{} = set2) do
    %__MODULE__{methods: MapSet.difference(set1.methods, set2.methods)}
  end

  @doc """
  Converts a method set to a list.

  ## Examples

      iex> set = Parrot.Sip.MethodSet.new([:invite, :ack, :bye])
      iex> Parrot.Sip.MethodSet.to_list(set)
      [:ack, :bye, :invite]
  """
  @spec to_list(t()) :: list(Method.t())
  def to_list(%__MODULE__{} = set) do
    set.methods |> MapSet.to_list() |> Enum.sort()
  end

  @doc """
  Formats a method set as a string for the Allow header.

  ## Examples

      iex> set = Parrot.Sip.MethodSet.new([:invite, :ack, :bye])
      iex> Parrot.Sip.MethodSet.to_allow_string(set)
      "INVITE, ACK, BYE"
  """
  @spec to_allow_string(t()) :: String.t()
  def to_allow_string(%__MODULE__{} = set) do
    set
    |> to_list()
    |> Enum.map(&Method.to_string/1)
    |> Enum.join(", ")
  end

  @doc """
  Creates a method set from an Allow header string.

  ## Examples

      iex> set = Parrot.Sip.MethodSet.from_allow_string("INVITE, ACK, BYE")
      iex> Parrot.Sip.MethodSet.to_list(set)
      [:ack, :bye, :invite]
  """
  @spec from_allow_string(String.t()) :: t()
  def from_allow_string(allow_string) when is_binary(allow_string) do
    methods =
      allow_string
      |> String.split(",", trim: true)
      |> Enum.map(&String.trim/1)

    new(methods)
  end

  @doc """
  Returns the size of the method set.

  ## Examples

      iex> set = Parrot.Sip.MethodSet.new([:invite, :ack, :bye])
      iex> Parrot.Sip.MethodSet.size(set)
      3
  """
  @spec size(t()) :: non_neg_integer()
  def size(%__MODULE__{} = set) do
    MapSet.size(set.methods)
  end

  defimpl Enumerable do
    def count(set), do: {:ok, Parrot.Sip.MethodSet.size(set)}

    def member?(set, method), do: {:ok, Parrot.Sip.MethodSet.member?(set, method)}

    def reduce(set, acc, fun),
      do: Enumerable.List.reduce(Parrot.Sip.MethodSet.to_list(set), acc, fun)

    def slice(_set), do: {:error, __MODULE__}
  end

  defimpl Inspect do
    import Inspect.Algebra

    def inspect(set, opts) do
      concat([
        "#Parrot.Sip.MethodSet<",
        to_doc(Parrot.Sip.MethodSet.to_list(set), opts),
        ">"
      ])
    end
  end
end
