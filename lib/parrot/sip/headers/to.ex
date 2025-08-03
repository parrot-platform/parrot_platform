defmodule Parrot.Sip.Headers.To do
  @moduledoc """
  Module for working with SIP To headers as defined in RFC 3261 Section 20.39.

  The To header identifies the logical recipient of the request. Like the From header,
  it contains a URI that identifies the target of the request, an optional display name,
  and parameters. The tag parameter, which may be added by the UAS in responses,
  is a critical component for dialog identification.

  The To header serves several key functions:
  - Specifying the recipient of the request
  - Contributing to dialog identification (when tag is present)
  - Allowing recipient identification independent of the Request-URI

  Initially, requests contain a To header without a tag. The UAS adds a tag parameter
  in responses, which then becomes part of the dialog identification as described in
  RFC 3261 Section 12.1.

  References:
  - RFC 3261 Section 8.1.1.2: To
  - RFC 3261 Section 12.1: Creation of a Dialog
  - RFC 3261 Section 19.3: Dialog ID Components
  - RFC 3261 Section 20.39: To Header Field
  """

  alias Parrot.Sip.Uri

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
  Creates a new To header.
  """
  @spec new(String.t(), String.t() | nil, map()) :: t()
  def new(uri, display_name \\ nil, parameters \\ %{}) do
    # Parse URI string if needed
    parsed_uri =
      cond do
        is_binary(uri) ->
          case Parrot.Sip.Uri.parse(uri) do
            {:ok, uri_struct} -> uri_struct
            # Keep as string if parsing fails
            {:error, _reason} -> uri
          end

        true ->
          uri
      end

    %__MODULE__{
      display_name: display_name,
      uri: parsed_uri,
      parameters: parameters
    }
  end

  @doc """
  Creates a new To header with a tag parameter.
  """
  @spec new_with_tag(String.t(), String.t() | nil, String.t()) :: t()
  def new_with_tag(uri, display_name \\ nil, tag) do
    parameters = %{"tag" => tag}
    new(uri, display_name, parameters)
  end

  @doc """
  Converts a To header to a string representation.
  """
  @spec format(t()) :: String.t()
  def format(to) do
    # Format: "Display Name" <sip:user@host>;params
    display_part =
      if to.display_name do
        # Quote display name if it contains spaces or special characters
        if String.contains?(to.display_name, [
             " ",
             ",",
             "\"",
             ";",
             "\\",
             "&",
             "<",
             ">",
             "@",
             ":",
             "/"
           ]) do
          "\"#{to.display_name}\""
        else
          to.display_name
        end
      else
        ""
      end

    uri_part =
      cond do
        is_struct(to.uri, Parrot.Sip.Uri) ->
          uri_string = to.uri.scheme <> ":"
          uri_string = if to.uri.user, do: uri_string <> to.uri.user <> "@", else: uri_string
          uri_string = uri_string <> to.uri.host

          uri_string =
            if to.uri.port,
              do: uri_string <> ":" <> Integer.to_string(to.uri.port),
              else: uri_string

          # Add URI parameters if present
          uri_string =
            if to.uri.parameters && map_size(to.uri.parameters) > 0 do
              params_str =
                to.uri.parameters
                |> Enum.map(fn {k, v} -> if v == "", do: k, else: "#{k}=#{v}" end)
                |> Enum.join(";")

              "#{uri_string};#{params_str}"
            else
              uri_string
            end

          uri_string

        is_binary(to.uri) ->
          to.uri

        true ->
          ""
      end

    uri_with_brackets =
      if String.starts_with?(uri_part, "<") do
        uri_part
      else
        "<#{uri_part}>"
      end

    params_part =
      to.parameters
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
  Adds or updates a parameter in a To header.
  """
  @spec with_parameter(t(), String.t(), String.t()) :: t()
  def with_parameter(to, name, value) do
    parameters = Map.put(to.parameters, name, value)
    %{to | parameters: parameters}
  end

  @doc """
  Adds a tag parameter to a To header if one doesn't exist.
  """
  @spec with_tag(t(), String.t()) :: t()
  def with_tag(to, tag) do
    if Map.has_key?(to.parameters, "tag") do
      to
    else
      with_parameter(to, "tag", tag)
    end
  end

  @doc """
  Gets a parameter from a To header.
  """
  @spec get_parameter(t(), String.t()) :: String.t() | nil
  def get_parameter(to, name) do
    Map.get(to.parameters, name)
  end

  @doc """
  Gets the tag parameter from a To header.
  """
  @spec tag(t()) :: String.t() | nil
  def tag(to) do
    get_parameter(to, "tag")
  end

  @doc """
  Parses a To header string into a To struct.

  ## Examples

      iex> Parrot.Sip.Headers.To.parse("Bob <sip:bob@biloxi.com>;tag=a6c85cf")
      %Parrot.Sip.Headers.To{display_name: "Bob", uri: %Parrot.Sip.Uri{scheme: "sip", user: "bob", host: "biloxi.com"}, parameters: %{"tag" => "a6c85cf"}}
      
      iex> Parrot.Sip.Headers.To.parse("<sip:bob@biloxi.com>")
      %Parrot.Sip.Headers.To{display_name: nil, uri: %Parrot.Sip.Uri{scheme: "sip", user: "bob", host: "biloxi.com"}, parameters: %{}}

  """
  @spec parse(String.t()) :: t()
  def parse(string) when is_binary(string) do
    # Extract display name, URI, and parameters
    {display_name, uri_str, params_str} = parse_address_parts(string)

    # Parse parameters
    parameters =
      if params_str != "" do
        params_str
        |> String.split(";")
        |> Enum.map(fn param ->
          case String.split(param, "=", parts: 2) do
            [name, value] -> {name, value}
            [name] -> {name, ""}
          end
        end)
        |> Enum.into(%{})
      else
        %{}
      end

    # Parse URI string if needed
    parsed_uri =
      cond do
        is_binary(uri_str) ->
          case Parrot.Sip.Uri.parse(uri_str) do
            {:ok, uri_struct} -> uri_struct
            # Keep as string if parsing fails
            {:error, _reason} -> uri_str
          end

        true ->
          uri_str
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
          if Regex.match?(~r/^".*"</, String.trim(string)) do
            # Handle quoted display names with possible escaped quotes
            case Regex.run(~r/^"((?:\\"|[^"])*)"/, string) do
              [_, quoted_name] ->
                # Unescape any escaped quotes
                String.replace(quoted_name, "\\\\\"", "\"")

              nil ->
                nil
            end
          else
            # Handle unquoted display names
            case Regex.run(~r/^([^<]+)</, string) do
              [_, name] -> String.trim(name)
              nil -> nil
            end
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
