defmodule Parrot.Sip.Branch do
  @moduledoc """
  Module for generating and working with SIP branch parameters for Via headers.

  The branch parameter is a unique identifier used in the Via header of SIP messages
  to identify transactions. As specified in RFC 3261, the branch parameter in SIP
  requests must start with the magic cookie "z9hG4bK" to be compliant with RFC 3261.

  The branch parameter is crucial for:
  - Transaction identification and matching
  - Loop detection in SIP networks
  - Stateless processing of SIP messages

  References:
  - RFC 3261 Section 8.1.1.7: Via
  - RFC 3261 Section 17.2.3: Matching Requests to Server Transactions
  - RFC 3261 Section 20.40: Via Header Field
  """

  @magic_cookie "z9hG4bK"

  @type t :: String.t()

  @doc """
  Generates a unique branch parameter for a Via header.
  The branch parameter will start with the RFC 3261 magic cookie "z9hG4bK".

  ## Examples

      iex> branch = Parrot.Sip.Branch.generate()
      iex> String.starts_with?(branch, "z9hG4bK")
      true
  """
  @spec generate() :: t()
  def generate do
    # Generate a random branch parameter starting with the magic cookie
    random_part = :crypto.strong_rand_bytes(16) |> Base.encode16(case: :lower)
    @magic_cookie <> random_part
  end

  @doc """
  Generates a unique branch parameter for a Via header based on 
  the given SIP message properties for loop detection.

  This function creates a deterministic branch parameter based on key message properties,
  which helps with loop detection as described in RFC 3261 Section 16.6.

  ## Parameters
  - method: The SIP method (atom) of the request
  - request_uri: The request URI as a string
  - from_tag: The tag parameter from the From header
  - to_tag: The tag parameter from the To header (may be nil)
  - call_id: The Call-ID header value

  ## Examples

      iex> Parrot.Sip.Branch.generate_for_message(:invite, "sip:alice@example.com", "123", nil, "abc@example.com")
      "z9hG4bK" <> _rest
  """
  @spec generate_for_message(atom(), String.t(), String.t(), String.t() | nil, String.t()) :: t()
  def generate_for_message(method, request_uri, from_tag, to_tag, call_id) do
    # Create a deterministic branch based on message properties
    to_tag_part = if to_tag, do: to_tag, else: ""

    key_parts = [
      Atom.to_string(method) |> String.upcase(),
      request_uri,
      from_tag,
      to_tag_part,
      call_id
    ]

    hash_input = Enum.join(key_parts, "|")
    hash = :crypto.hash(:sha256, hash_input) |> Base.encode16(case: :lower)

    # Use first 32 chars of hash
    @magic_cookie <> binary_part(hash, 0, 32)
  end

  @doc """
  Checks if a branch parameter is RFC 3261 compliant.

  ## Examples

      iex> Parrot.Sip.Branch.is_rfc3261_compliant?("z9hG4bKabc123")
      true

      iex> Parrot.Sip.Branch.is_rfc3261_compliant?("123456")
      false
  """
  @spec is_rfc3261_compliant?(String.t()) :: boolean()
  def is_rfc3261_compliant?(branch) when is_binary(branch) do
    String.starts_with?(branch, @magic_cookie)
  end

  def is_rfc3261_compliant?(_), do: false

  @doc """
  Ensures a branch parameter is RFC 3261 compliant by adding 
  the magic cookie if it's missing.

  ## Examples

      iex> Parrot.Sip.Branch.ensure_rfc3261_compliance("abc123")
      "z9hG4bKabc123"

      iex> Parrot.Sip.Branch.ensure_rfc3261_compliance("z9hG4bKabc123")
      "z9hG4bKabc123"
  """
  @spec ensure_rfc3261_compliance(String.t()) :: t()
  def ensure_rfc3261_compliance(branch) when is_binary(branch) do
    if is_rfc3261_compliant?(branch) do
      branch
    else
      @magic_cookie <> branch
    end
  end

  @doc """
  Extracts the transaction identifier part from a branch parameter.
  This is the part after the magic cookie.

  ## Examples

      iex> Parrot.Sip.Branch.transaction_id("z9hG4bKabc123")
      "abc123"

      iex> Parrot.Sip.Branch.transaction_id("abc123")
      "abc123"
  """
  @spec transaction_id(String.t()) :: String.t()
  def transaction_id(branch) when is_binary(branch) do
    if is_rfc3261_compliant?(branch) do
      String.replace_prefix(branch, @magic_cookie, "")
    else
      branch
    end
  end

  @doc """
  Checks if two branch parameters refer to the same transaction.

  ## Examples

      iex> Parrot.Sip.Branch.same_transaction?("z9hG4bKabc123", "z9hG4bKabc123")
      true

      iex> Parrot.Sip.Branch.same_transaction?("z9hG4bKabc123", "abc123")
      true

      iex> Parrot.Sip.Branch.same_transaction?("z9hG4bKabc123", "z9hG4bKdef456")
      false
  """
  @spec same_transaction?(String.t(), String.t()) :: boolean()
  def same_transaction?(branch1, branch2) when is_binary(branch1) and is_binary(branch2) do
    transaction_id(branch1) == transaction_id(branch2)
  end

  def same_transaction?(_, _), do: false
end
