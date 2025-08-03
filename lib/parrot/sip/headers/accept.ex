defmodule Parrot.Sip.Headers.Accept do
  @moduledoc """
  Module for working with SIP Accept headers as defined in RFC 3261 Section 20.1.

  The Accept header field is used to specify certain media types which are
  acceptable for the response. It follows the same format as the Content-Type
  header field.

  The Accept header serves important functions in content negotiation:
  - Specifying acceptable message body formats for responses
  - Supporting quality values (q-values) for preference ordering
  - Enabling content type negotiation between endpoints
  - Working with Content-Type headers to ensure compatible formats

  The header supports MIME media types with optional parameters and quality
  values ranging from 0.0 to 1.0, where higher values indicate higher preference.
  The special value "*/*" indicates that all media types are acceptable.

  If no Accept header field is present, the server SHOULD assume a default value
  of application/sdp, as specified in RFC 3261 Section 20.1.

  References:
  - RFC 3261 Section 7.4.1: Header Field Format
  - RFC 3261 Section 20.1: Accept Header Field
  - RFC 3261 Section 20.15: Content-Type Header Field
  - RFC 2616 Section 14.1: HTTP Accept header (similar semantics)
  - RFC 2046: Multipurpose Internet Mail Extensions (MIME) Part Two
  """

  defstruct [
    :type,
    :subtype,
    :parameters,
    :q_value
  ]

  @type t :: %__MODULE__{
          type: String.t(),
          subtype: String.t(),
          parameters: %{String.t() => String.t()},
          q_value: float() | nil
        }

  @doc """
  Creates a new Accept header.

  ## Examples

      iex> Parrot.Sip.Headers.Accept.new("application", "sdp")
      %Parrot.Sip.Headers.Accept{type: "application", subtype: "sdp", parameters: %{}, q_value: nil}
      
      iex> Parrot.Sip.Headers.Accept.new("application", "sdp", %{"charset" => "UTF-8"}, 0.8)
      %Parrot.Sip.Headers.Accept{type: "application", subtype: "sdp", parameters: %{"charset" => "UTF-8"}, q_value: 0.8}
  """
  @spec new(String.t(), String.t(), map(), float() | nil) :: t()
  def new(type, subtype, parameters \\ %{}, q_value \\ nil)
      when is_binary(type) and is_binary(subtype) and (is_nil(q_value) or is_float(q_value)) do
    %__MODULE__{
      type: type,
      subtype: subtype,
      parameters: parameters,
      q_value: q_value
    }
  end

  @doc """
  Parses an Accept header string into a struct.

  ## Examples

      iex> Parrot.Sip.Headers.Accept.parse("application/sdp")
      %Parrot.Sip.Headers.Accept{type: "application", subtype: "sdp", parameters: %{}, q_value: nil}
      
      iex> Parrot.Sip.Headers.Accept.parse("application/sdp;charset=UTF-8;q=0.8")
      %Parrot.Sip.Headers.Accept{type: "application", subtype: "sdp", parameters: %{"charset" => "UTF-8"}, q_value: 0.8}
  """
  @spec parse(String.t()) :: t()
  def parse(string) when is_binary(string) do
    # Split into media type and parameters
    [media_type | parameter_parts] = String.split(string, ";")

    # Split media type into type and subtype
    [type, subtype] = String.split(media_type, "/", parts: 2)

    # Parse parameters
    {parameters, q_value} = parse_parameters(parameter_parts)

    %__MODULE__{
      type: type,
      subtype: subtype,
      parameters: parameters,
      q_value: q_value
    }
  end

  defp parse_parameters(parameter_parts) do
    parameter_pairs =
      Enum.map(parameter_parts, fn part ->
        case String.split(part, "=", parts: 2) do
          [key, value] -> {key, value}
          [key] -> {key, ""}
        end
      end)

    # Extract q-value if present
    q_value_pair = Enum.find(parameter_pairs, fn {key, _} -> key == "q" end)

    q_value =
      case q_value_pair do
        {_, value} -> String.to_float(value)
        nil -> nil
      end

    # Build parameters map without q parameter
    parameters =
      parameter_pairs
      |> Enum.reject(fn {key, _} -> key == "q" end)
      |> Enum.into(%{})

    {parameters, q_value}
  end

  @doc """
  Formats an Accept struct as a string.

  ## Examples

      iex> accept = %Parrot.Sip.Headers.Accept{type: "application", subtype: "sdp", parameters: %{}, q_value: nil}
      iex> Parrot.Sip.Headers.Accept.format(accept)
      "application/sdp"
      
      iex> accept = %Parrot.Sip.Headers.Accept{type: "application", subtype: "sdp", parameters: %{"charset" => "UTF-8"}, q_value: 0.8}
      iex> Parrot.Sip.Headers.Accept.format(accept)
      "application/sdp;charset=UTF-8;q=0.8"
  """
  @spec format(t()) :: String.t()
  def format(%__MODULE__{} = accept) do
    # Build media type
    media_type = "#{accept.type}/#{accept.subtype}"

    # Build parameters string
    params_string =
      accept.parameters
      |> Enum.map(fn {key, value} -> "#{key}=#{value}" end)
      |> Enum.join(";")

    # Add q-value if present
    q_string =
      if accept.q_value do
        ";q=#{:erlang.float_to_binary(accept.q_value, decimals: 1)}"
      else
        ""
      end

    # Combine all parts
    if params_string == "" do
      "#{media_type}#{q_string}"
    else
      "#{media_type};#{params_string}#{q_string}"
    end
  end

  @doc """
  Alias for format/1 for consistency with other header modules.

  ## Examples

      iex> accept = %Parrot.Sip.Headers.Accept{type: "application", subtype: "sdp", parameters: %{}, q_value: nil}
      iex> Parrot.Sip.Headers.Accept.to_string(accept)
      "application/sdp"
  """
  @spec to_string(t()) :: String.t()
  def to_string(%__MODULE__{} = accept), do: format(accept)

  @doc """
  Creates a new Accept header for application/sdp.

  ## Examples

      iex> Parrot.Sip.Headers.Accept.sdp()
      %Parrot.Sip.Headers.Accept{type: "application", subtype: "sdp", parameters: %{}, q_value: nil}
  """
  @spec sdp() :: t()
  def sdp() do
    new("application", "sdp")
  end

  @doc """
  Creates a new Accept header for all media types (*/*).

  ## Examples

      iex> Parrot.Sip.Headers.Accept.all()
      %Parrot.Sip.Headers.Accept{type: "*", subtype: "*", parameters: %{}, q_value: nil}
  """
  @spec all() :: t()
  def all() do
    new("*", "*")
  end
end
