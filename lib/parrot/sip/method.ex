defmodule Parrot.Sip.Method do
  @moduledoc """
  Module for working with SIP methods as defined in RFC 3261 and extensions.

  SIP methods indicate the purpose of a SIP request. This module provides
  functions for handling standard SIP methods and custom method names.

  References:
  - RFC 3261 Section 7.1: SIP Methods
  - RFC 3261 Section 8.1: UAC Behavior
  - RFC 3261 Section 20.1: Method Parameter
  - RFC 6665: SIP-Specific Event Notification (SUBSCRIBE, NOTIFY)
  - RFC 3515: The SIP Refer Method
  - RFC 3311: The SIP UPDATE Method
  - RFC 3903: SIP Extension for Event State Publication (PUBLISH)
  - RFC 3428: SIP Extension for Instant Messaging (MESSAGE)
  - RFC 4028: Session Timers in SIP (INFO)
  """

  @standard_methods [
    :ack,
    :bye,
    :cancel,
    :info,
    :invite,
    :message,
    :notify,
    :options,
    :prack,
    :publish,
    :refer,
    :register,
    :subscribe,
    :update
  ]

  @type t :: atom()

  @doc """
  Returns a list of all standard SIP methods.

  ## Examples

      iex> Parrot.Sip.Method.standard_methods()
      [:ack, :bye, :cancel, :info, :invite, :message, :notify, :options, :prack, :publish, :refer, :register, :subscribe, :update]
  """
  @spec standard_methods() :: [atom()]
  def standard_methods, do: @standard_methods

  @doc """
  Checks if a method is a standard SIP method.

  ## Examples

      iex> Parrot.Sip.Method.is_standard?(:invite)
      true

      iex> Parrot.Sip.Method.is_standard?(:custom)
      false
  """
  @spec is_standard?(atom()) :: boolean()
  def is_standard?(method) when is_atom(method), do: method in @standard_methods
  def is_standard?(_), do: false

  @doc """
  Converts a string to a method atom. For standard methods, returns a
  lowercase atom. For custom methods, returns an uppercase atom.

  ## Examples

      iex> Parrot.Sip.Method.parse("INVITE")
      {:ok, :invite}

      iex> Parrot.Sip.Method.parse("CUSTOM")
      {:ok, :CUSTOM}

      iex> Parrot.Sip.Method.parse(123)
      {:error, :invalid_method}
  """
  @spec parse(String.t()) :: {:ok, atom()} | {:error, atom()}
  def parse(method_str) when is_binary(method_str) do
    method_atom =
      method_str
      |> String.downcase()
      |> String.to_atom()

    if is_standard?(method_atom) do
      {:ok, method_atom}
    else
      # Custom method - preserve as uppercase atom
      {:ok, String.to_atom(method_str)}
    end
  end

  def parse(_), do: {:error, :invalid_method}

  @doc """
  Same as `parse/1` but raises an error for invalid methods.

  ## Examples

      iex> Parrot.Sip.Method.parse!("INVITE")
      :invite

      iex> Parrot.Sip.Method.parse!("CUSTOM")
      :CUSTOM
  """
  @spec parse!(String.t()) :: atom()
  def parse!(method_str) do
    case parse(method_str) do
      {:ok, method} ->
        method

      {:error, reason} ->
        raise ArgumentError, "Invalid method: #{inspect(method_str)}, reason: #{reason}"
    end
  end

  @doc """
  Converts a method to its string representation.

  ## Examples

      iex> Parrot.Sip.Method.to_string(:invite)
      "INVITE"

      iex> Parrot.Sip.Method.to_string(:CUSTOM)
      "CUSTOM"
  """
  @spec to_string(atom()) :: String.t()
  def to_string(method) when is_atom(method) do
    if is_standard?(method) do
      method
      |> Atom.to_string()
      |> String.upcase()
    else
      Atom.to_string(method)
    end
  end

  @doc """
  Checks if a method is allowed to have a body.

  ## Examples

      iex> Parrot.Sip.Method.allows_body?(:invite)
      true

      iex> Parrot.Sip.Method.allows_body?(:ack)
      true
  """
  @spec allows_body?(atom()) :: boolean()
  def allows_body?(method) when is_atom(method) do
    # According to RFC 3261, only REGISTER, OPTIONS, and ACK don't typically contain bodies,
    # but they're technically allowed to have them.
    true
  end

  @doc """
  Checks if a method establishes a dialog.

  ## Examples

      iex> Parrot.Sip.Method.creates_dialog?(:invite)
      true

      iex> Parrot.Sip.Method.creates_dialog?(:register)
      false
  """
  @spec creates_dialog?(atom()) :: boolean()
  def creates_dialog?(:invite), do: true
  def creates_dialog?(:subscribe), do: true
  def creates_dialog?(:refer), do: true
  def creates_dialog?(_), do: false

  @doc """
  Checks if a method requires Contact header.

  ## Examples

      iex> Parrot.Sip.Method.requires_contact?(:invite)
      true

      iex> Parrot.Sip.Method.requires_contact?(:options)
      false
  """
  @spec requires_contact?(atom()) :: boolean()
  def requires_contact?(:invite), do: true
  def requires_contact?(:register), do: true
  def requires_contact?(:subscribe), do: true
  def requires_contact?(:notify), do: true
  def requires_contact?(:refer), do: true
  def requires_contact?(_), do: false

  @doc """
  Checks if a method can be canceled.

  ## Examples

      iex> Parrot.Sip.Method.can_cancel?(:invite)
      true

      iex> Parrot.Sip.Method.can_cancel?(:ack)
      false
  """
  @spec can_cancel?(atom()) :: boolean()
  def can_cancel?(:invite), do: true
  def can_cancel?(:subscribe), do: true
  def can_cancel?(:notify), do: true
  def can_cancel?(:register), do: true
  def can_cancel?(:update), do: true
  def can_cancel?(:publish), do: true
  def can_cancel?(:message), do: true
  def can_cancel?(:info), do: true
  def can_cancel?(_), do: false
end
