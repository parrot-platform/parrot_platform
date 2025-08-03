defmodule Parrot.Sip.Validators do
  @moduledoc """
  Input validation for SIP messages and parameters.

  This module provides comprehensive validation functions for SIP-related data
  to ensure security and correctness of the protocol implementation.
  """

  alias Parrot.Sip.{Message, Uri}

  @doc """
  Validates a SIP URI.

  ## Examples

      iex> Parrot.Sip.Validators.validate_uri("sip:alice@example.com")
      :ok
      
      iex> Parrot.Sip.Validators.validate_uri("invalid-uri")
      {:error, :invalid_uri_format}
  """
  @spec validate_uri(String.t()) :: :ok | {:error, atom()}
  def validate_uri(uri_string) when is_binary(uri_string) do
    case Uri.parse(uri_string) do
      {:ok, %Uri{scheme: scheme, host: host}} when scheme in ["sip", "sips"] and host != nil ->
        :ok

      {:ok, _} ->
        {:error, :invalid_uri_scheme}

      {:error, _} ->
        {:error, :invalid_uri_format}
    end
  end

  def validate_uri(_), do: {:error, :invalid_uri_type}

  @doc """
  Validates SDP content.

  ## Examples

      iex> sdp = "v=0\\r\\no=- 123 456 IN IP4 192.168.1.1\\r\\ns=-\\r\\nc=IN IP4 192.168.1.1\\r\\nt=0 0\\r\\n"
      iex> Parrot.Sip.Validators.validate_sdp(sdp)
      :ok
  """
  @spec validate_sdp(String.t()) :: :ok | {:error, atom()}
  def validate_sdp(sdp) when is_binary(sdp) do
    # Basic SDP validation - check for required fields
    lines = String.split(sdp, "\r\n", trim: true)

    required_prefixes = ["v=", "o=", "s="]

    has_required =
      Enum.all?(required_prefixes, fn prefix ->
        Enum.any?(lines, &String.starts_with?(&1, prefix))
      end)

    if has_required do
      validate_sdp_content(lines)
    else
      {:error, :missing_required_sdp_fields}
    end
  end

  def validate_sdp(_), do: {:error, :invalid_sdp_type}

  @doc """
  Validates a SIP method.

  ## Examples

      iex> Parrot.Sip.Validators.validate_method(:invite)
      :ok
      
      iex> Parrot.Sip.Validators.validate_method(:unknown)
      {:error, :unsupported_method}
  """
  @spec validate_method(atom()) :: :ok | {:error, atom()}
  def validate_method(method) when is_atom(method) do
    allowed_methods = [:invite, :ack, :bye, :cancel, :options, :register, :info, :prack, :update]

    if method in allowed_methods do
      :ok
    else
      {:error, :unsupported_method}
    end
  end

  def validate_method(_), do: {:error, :invalid_method_type}

  @doc """
  Validates a complete SIP message.

  ## Examples

      iex> message = %Parrot.Sip.Message{method: :invite, type: :request, headers: %{"via" => []}}
      iex> Parrot.Sip.Validators.validate_message(message)
      {:error, :missing_required_headers}
  """
  @spec validate_message(Message.t()) :: :ok | {:error, atom()}
  def validate_message(%Message{type: :request} = message) do
    with :ok <- validate_method(message.method),
         :ok <- validate_required_headers(message, [:via, :from, :to, :call_id, :cseq]),
         :ok <- validate_request_uri(message.request_uri) do
      :ok
    end
  end

  def validate_message(%Message{type: :response} = message) do
    with :ok <- validate_status_code(message.status_code),
         :ok <- validate_required_headers(message, [:via, :from, :to, :call_id, :cseq]) do
      :ok
    end
  end

  def validate_message(_), do: {:error, :invalid_message_type}

  @doc """
  Validates a SIP status code.

  ## Examples

      iex> Parrot.Sip.Validators.validate_status_code(200)
      :ok
      
      iex> Parrot.Sip.Validators.validate_status_code(999)
      {:error, :invalid_status_code}
  """
  @spec validate_status_code(integer()) :: :ok | {:error, atom()}
  def validate_status_code(code) when is_integer(code) and code >= 100 and code <= 699 do
    :ok
  end

  def validate_status_code(_), do: {:error, :invalid_status_code}

  # Private functions

  defp validate_sdp_content(lines) do
    # Additional SDP validation can be added here
    # For now, just check that lines are formatted correctly
    valid_format =
      Enum.all?(lines, fn line ->
        String.match?(line, ~r/^[a-z]=.*$/)
      end)

    if valid_format do
      :ok
    else
      {:error, :invalid_sdp_format}
    end
  end

  defp validate_required_headers(message, required_headers) do
    missing =
      Enum.reject(required_headers, fn header ->
        Atom.to_string(header) in Map.keys(message.headers) or
          String.replace(Atom.to_string(header), "_", "-") in Map.keys(message.headers)
      end)

    if Enum.empty?(missing) do
      :ok
    else
      {:error, :missing_required_headers}
    end
  end

  defp validate_request_uri(uri) when is_binary(uri) do
    if String.starts_with?(uri, "sip:") or String.starts_with?(uri, "sips:") do
      :ok
    else
      {:error, :invalid_request_uri}
    end
  end

  defp validate_request_uri(_), do: {:error, :invalid_request_uri}
end
