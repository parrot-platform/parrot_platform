defmodule Parrot.Sip.Headers.From do
  @moduledoc """
  Module for working with SIP From headers as defined in RFC 3261 Section 20.20.

  The From header identifies the logical initiator of the request. It contains 
  a URI (typically a SIP URI) that identifies the originator of the request,
  an optional display name, and parameters including a mandatory 'tag' parameter
  that serves as a dialog identifier.

  The From header plays a critical role in:
  - Identifying the sender of the message
  - Dialog identification and matching (through the tag parameter)
  - Establishing associations between requests and responses

  The tag parameter is required for all requests and responses, and once assigned,
  it must remain constant throughout the dialog's lifetime as specified in
  RFC 3261 Section 19.3.

  References:
  - RFC 3261 Section 8.1.1.3: From
  - RFC 3261 Section 19.3: Dialog ID Components  
  - RFC 3261 Section 20.20: From Header Field
  """

  alias Parrot.Sip.Uri
  alias Parrot.Sip.UriParser

  defstruct [
    # String (optional)
    :display_name,
    # String URI or Uri struct
    :uri,
    # Map of parameters, especially :tag
    :parameters
  ]

  @type t :: %__MODULE__{
          display_name: String.t() | nil,
          uri: String.t() | Uri.t(),
          parameters: map()
        }

  @doc """
  Creates a new From header.
  """
  @spec new(String.t(), String.t() | nil, map() | String.t()) :: t()
  def new(uri, display_name \\ nil, parameters \\ %{}) do
    # Convert URI string to URI struct
    uri_struct =
      case uri do
        %Uri{} ->
          uri

        uri when is_binary(uri) ->
          case Uri.parse(uri) do
            {:ok, parsed_uri} ->
              parsed_uri

            {:error, _} ->
              # Try adding sip: prefix if missing
              if !String.starts_with?(uri, "sip:") && !String.starts_with?(uri, "sips:") do
                case Uri.parse("sip:" <> uri) do
                  {:ok, uri_struct} -> uri_struct
                  # Keep as string if parsing fails
                  {:error, _} -> uri
                end
              else
                # Keep as string if parsing fails
                uri
              end
          end
      end

    # Handle case where third parameter is a tag string instead of a parameters map
    parameters =
      if is_binary(parameters) do
        %{"tag" => parameters}
      else
        parameters
      end

    %__MODULE__{
      display_name: display_name,
      uri: uri_struct,
      parameters: parameters
    }
  end

  @doc """
  Generates a unique tag parameter for a From header.
  """
  @spec generate_tag() :: String.t()
  def generate_tag do
    # Generate a random tag parameter
    # 24 random hexadecimal characters
    :crypto.strong_rand_bytes(12) |> Base.encode16(case: :lower)
  end

  @doc """
  Creates a new From header with a randomly generated tag parameter.
  """
  @spec new_with_tag(String.t(), String.t() | nil, map() | String.t()) :: t()
  def new_with_tag(uri, display_name \\ nil, parameters_or_tag \\ nil) do
    parameters =
      cond do
        is_nil(parameters_or_tag) ->
          %{"tag" => generate_tag()}

        is_binary(parameters_or_tag) ->
          %{"tag" => parameters_or_tag}

        is_map(parameters_or_tag) ->
          Map.put(parameters_or_tag, "tag", generate_tag())
      end

    new(uri, display_name, parameters)
  end

  @doc """
  Converts a From header to a string representation.
  """
  @spec format(t()) :: String.t()
  def format(from) do
    # Format: "Display Name" <sip:user@host>;params
    display_part =
      if from.display_name do
        # Check if the display name contains special characters
        if String.contains?(from.display_name, [
             " ",
             ",",
             ";",
             ":",
             "\\",
             "&",
             "<",
             ">",
             "@",
             "/",
             "?"
           ]) do
          # Remove any existing quotes as we'll add them properly
          name =
            from.display_name
            |> String.replace_prefix("\"", "")
            |> String.replace_suffix("\"", "")

          "\"#{name}\""
        else
          # If no special characters, keep as is
          from.display_name
        end
      else
        ""
      end

    uri_part =
      cond do
        is_struct(from.uri, Parrot.Sip.Uri) ->
          uri = from.uri
          scheme = uri.scheme
          user_part = if uri.user, do: "#{uri.user}@", else: ""
          port_part = if uri.port, do: ":#{uri.port}", else: ""

          params_part =
            if map_size(uri.parameters) > 0 do
              ";" <>
                (uri.parameters
                 |> Enum.map(fn {k, v} -> if v == "", do: k, else: "#{k}=#{v}" end)
                 |> Enum.join(";"))
            else
              ""
            end

          headers_part =
            if map_size(uri.headers) > 0 do
              "?" <> (uri.headers |> Enum.map(fn {k, v} -> "#{k}=#{v}" end) |> Enum.join("&"))
            else
              ""
            end

          "#{scheme}:#{user_part}#{uri.host}#{port_part}#{params_part}#{headers_part}"

        is_binary(from.uri) ->
          from.uri

        true ->
          inspect(from.uri)
      end

    uri_with_brackets =
      if String.starts_with?(uri_part, "<") do
        uri_part
      else
        "<#{uri_part}>"
      end

    params_part =
      from.parameters
      |> Enum.map(fn {k, v} -> "#{k}=#{v}" end)
      |> Enum.join(";")

    cond do
      display_part != "" && params_part != "" ->
        "#{display_part} #{uri_with_brackets};#{params_part}"

      display_part != "" ->
        "#{display_part} #{uri_with_brackets}"

      params_part != "" ->
        "#{uri_with_brackets};#{params_part}"

      true ->
        uri_with_brackets
    end
  end

  @doc """
  Adds or updates a parameter in a From header.
  """
  @spec with_parameter(t(), String.t(), String.t()) :: t()
  def with_parameter(from, name, value) do
    parameters = Map.put(from.parameters, name, value)
    %{from | parameters: parameters}
  end

  @doc """
  Adds a tag parameter to a From header if one doesn't exist.
  """
  @spec with_tag(t(), String.t() | nil) :: t()
  def with_tag(from, tag \\ nil) do
    if Map.has_key?(from.parameters, "tag") do
      from
    else
      tag = tag || generate_tag()
      with_parameter(from, "tag", tag)
    end
  end

  @doc """
  Gets a parameter from a From header.
  """
  @spec get_parameter(t(), String.t()) :: String.t() | nil
  def get_parameter(from, name) do
    Map.get(from.parameters, name)
  end

  @doc """
  Gets the tag parameter from a From header.
  """
  @spec tag(t()) :: String.t() | nil
  def tag(from) do
    get_parameter(from, "tag")
  end

  @doc """
  Parses a From header string into a From struct.

  ## Examples

      iex> Parrot.Sip.Headers.From.parse("Alice <sip:alice@atlanta.com>;tag=1928301774")
      %Parrot.Sip.Headers.From{display_name: "Alice", uri: "sip:alice@atlanta.com", parameters: %{"tag" => "1928301774"}}
      
      iex> Parrot.Sip.Headers.From.parse("<sip:bob@biloxi.com>")
      %Parrot.Sip.Headers.From{display_name: nil, uri: "sip:bob@biloxi.com", parameters: %{}}

  """
  @spec parse(String.t()) :: t()
  def parse(string) when is_binary(string) do
    # Extract display name, URI, and parameters
    {display_name, uri_str, params_str} = parse_address_parts(string)

    # Parse parameters using the common parser
    parameters =
      if params_str != "" do
        UriParser.extract_parameters(params_str)
      else
        %{}
      end

    # Parse the URI if possible
    parsed_uri =
      case Uri.parse(uri_str) do
        {:ok, uri_struct} -> uri_struct
        # Keep as string if parsing fails
        {:error, _} -> uri_str
      end

    %__MODULE__{
      display_name: display_name,
      uri: parsed_uri,
      parameters: parameters
    }
  end

  # Helper function to parse the address parts (display-name, URI, parameters)
  defp parse_address_parts(string) do
    # Check for angle brackets to determine format
    case Regex.run(~r/<([^>]+)>(.*)?/, string) do
      [_, uri, rest] ->
        # Extract display name if present
        display_name =
          case Regex.run(~r/^([^<]+)</, string) do
            [_, name] -> String.trim(name)
            nil -> nil
          end

        {display_name, uri, String.trim_leading(rest, ";")}

      nil ->
        # No angle brackets, try to split at first semicolon
        case String.split(string, ";", parts: 2) do
          [uri_part, params] -> {nil, uri_part, params}
          [uri_part] -> {nil, uri_part, ""}
        end
    end
  end
end
