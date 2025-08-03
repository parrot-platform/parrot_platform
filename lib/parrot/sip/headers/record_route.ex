defmodule Parrot.Sip.Headers.RecordRoute do
  @moduledoc """
  Module for working with SIP Record-Route headers as defined in RFC 3261 Section 20.30.

  The Record-Route header is used by SIP proxies to force future messages in a dialog
  to be routed through the proxy. Each proxy that requires itself to be in the path of
  subsequent requests adds a Record-Route header.

  Record-Route serves critical functions in SIP dialog management:
  - Ensuring proxies remain in the signaling path for the entire dialog
  - Enabling features like accounting, authorization, and call control
  - Supporting NAT traversal and firewall traversal
  - Facilitating mid-dialog request routing

  The UAC copies all Record-Route header field values from responses into Route
  header field values in reverse order for subsequent requests within the dialog.
  The 'lr' (loose routing) parameter MUST be included for RFC 3261 compliance.

  References:
  - RFC 3261 Section 12.1.1: UAC Behavior (Record-Route processing)
  - RFC 3261 Section 16.6: Request Forwarding (proxy adding Record-Route)
  - RFC 3261 Section 16.7: Response Processing (proxy must not modify Record-Route)
  - RFC 3261 Section 20.30: Record-Route Header Field
  - RFC 3261 Section 20.34: Route Header Field (relationship to Record-Route)
  """

  alias Parrot.Sip.Uri

  defstruct [
    # Optional display name
    :display_name,
    # SIP URI
    :uri,
    # Additional parameters
    :parameters
  ]

  @type t :: %__MODULE__{
          display_name: String.t() | nil,
          uri: String.t() | Uri.t(),
          parameters: map()
        }

  @doc """
  Creates a new Record-Route header.

  ## Examples

      iex> Parrot.Sip.Headers.RecordRoute.new("sip:proxy.example.com;lr")
      %Parrot.Sip.Headers.RecordRoute{display_name: nil, uri: "sip:proxy.example.com;lr", parameters: %{}}
      
      iex> Parrot.Sip.Headers.RecordRoute.new("sip:proxy.example.com;lr", "Example Proxy")
      %Parrot.Sip.Headers.RecordRoute{display_name: "Example Proxy", uri: "sip:proxy.example.com;lr", parameters: %{}}
  """
  @spec new(String.t() | Uri.t(), String.t() | nil, map()) :: t()
  def new(uri, display_name \\ nil, parameters \\ %{}) do
    # Create a URI struct with proper parsing of parameters
    parsed_uri =
      if is_binary(uri) do
        uri_str = String.trim(uri)

        # Parse the URI using the common parser
        case Uri.parse(uri_str) do
          {:ok, uri_struct} ->
            uri_struct

          {:error, _} ->
            # If URI doesn't have scheme, add "sip:" prefix and try again
            if !String.contains?(uri_str, ":") do
              case Uri.parse("sip:" <> uri_str) do
                {:ok, uri_struct} -> uri_struct
                # Keep as string if parsing fails
                {:error, _} -> uri_str
              end
            else
              # Keep as string if parsing fails
              uri_str
            end
        end
      else
        uri
      end

    %__MODULE__{
      display_name: display_name,
      uri: parsed_uri,
      parameters: parameters
    }
  end

  @doc """
  Parses a Record-Route header string into a Record-Route struct.

  ## Examples

      iex> Parrot.Sip.Headers.RecordRoute.parse("<sip:proxy.example.com;lr>")
      %Parrot.Sip.Headers.RecordRoute{display_name: nil, uri: "sip:proxy.example.com;lr", parameters: %{}}
      
      iex> Parrot.Sip.Headers.RecordRoute.parse("Example Proxy <sip:proxy.example.com;lr>")
      %Parrot.Sip.Headers.RecordRoute{display_name: "Example Proxy", uri: "sip:proxy.example.com;lr", parameters: %{}}
      
      iex> Parrot.Sip.Headers.RecordRoute.parse("\"Complex Name\" <sip:proxy.example.com;lr>;param=value")
      %Parrot.Sip.Headers.RecordRoute{display_name: "Complex Name", uri: "sip:proxy.example.com;lr", parameters: %{"param" => "value"}}
  """
  @spec parse(String.t()) :: t()
  def parse(string) when is_binary(string) do
    # Pattern 1: "Display Name" <uri>;params
    # Pattern 2: <uri>;params
    # Extract display name if present
    {display_name, remainder} =
      case Regex.run(~r/^(?:"([^"]+)"|([^<]+))\s*</, string, capture: :all_but_first) do
        [quoted, ""] -> {quoted, String.replace(string, ~r/^"[^"]+"\s*/, "")}
        ["", name] -> {String.trim(name), String.replace(string, ~r/^[^<]+/, "")}
        nil -> {nil, string}
      end

    # Extract URI
    {uri, params_part} =
      case Regex.run(~r/<([^>]+)>(.*)/, remainder) do
        [_, uri_str, rest] -> {uri_str, rest}
        nil -> {remainder, ""}
      end

    # Extract parameters
    parameters =
      if String.trim(params_part) != "" do
        params_part
        |> String.trim_leading(";")
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

    # Parse URI 
    parsed_uri =
      cond do
        is_binary(uri) ->
          case Uri.parse(uri) do
            {:ok, uri_struct} ->
              uri_struct

            {:error, _reason} ->
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
  Formats a Record-Route header as a string.

  ## Examples

      iex> record_route = %Parrot.Sip.Headers.RecordRoute{display_name: nil, uri: "sip:proxy.example.com;lr", parameters: %{}}
      iex> Parrot.Sip.Headers.RecordRoute.format(record_route)
      "<sip:proxy.example.com;lr>"
      
      iex> record_route = %Parrot.Sip.Headers.RecordRoute{display_name: "Example Proxy", uri: "sip:proxy.example.com;lr", parameters: %{}}
      iex> Parrot.Sip.Headers.RecordRoute.format(record_route)
      "Example Proxy <sip:proxy.example.com;lr>"
      
      iex> record_route = %Parrot.Sip.Headers.RecordRoute{display_name: "Complex Name", uri: "sip:proxy.example.com;lr", parameters: %{"param" => "value"}}
      iex> Parrot.Sip.Headers.RecordRoute.format(record_route)
      "\"Complex Name\" <sip:proxy.example.com;lr>;param=value"
  """
  @spec format(t()) :: String.t()
  def format(record_route) do
    # Format display name
    display_part =
      cond do
        is_nil(record_route.display_name) ->
          ""

        String.contains?(record_route.display_name, [",", "\"", ";", ":", "\\"]) ->
          "\"#{record_route.display_name}\" "

        true ->
          "#{record_route.display_name} "
      end

    # Format URI
    uri_part =
      cond do
        is_struct(record_route.uri, Parrot.Sip.Uri) ->
          uri_string = record_route.uri.scheme <> ":"

          uri_string =
            if record_route.uri.user,
              do: uri_string <> record_route.uri.user <> "@",
              else: uri_string

          uri_string = uri_string <> record_route.uri.host

          uri_string =
            if record_route.uri.port,
              do: uri_string <> ":" <> Integer.to_string(record_route.uri.port),
              else: uri_string

          # Add URI parameters if present
          uri_string =
            if record_route.uri.parameters && map_size(record_route.uri.parameters) > 0 do
              params_str =
                record_route.uri.parameters
                |> Enum.map(fn {k, v} -> if v == "", do: k, else: "#{k}=#{v}" end)
                |> Enum.join(";")

              "#{uri_string};#{params_str}"
            else
              uri_string
            end

          "<#{uri_string}>"

        is_binary(record_route.uri) ->
          "<#{record_route.uri}>"

        true ->
          "<>"
      end

    # Format parameters
    params_part =
      record_route.parameters
      |> Enum.map(fn {k, v} ->
        if v == "", do: k, else: "#{k}=#{v}"
      end)
      |> Enum.join(";")

    params_part = if params_part == "", do: "", else: ";#{params_part}"

    display_part <> uri_part <> params_part
  end

  @doc """
  Parses a list of Record-Route headers.

  ## Examples

      iex> Parrot.Sip.Headers.RecordRoute.parse_list("<sip:proxy1.example.com;lr>, <sip:proxy2.example.com;lr>")
      [
        %Parrot.Sip.Headers.RecordRoute{display_name: nil, uri: "sip:proxy1.example.com;lr", parameters: %{}},
        %Parrot.Sip.Headers.RecordRoute{display_name: nil, uri: "sip:proxy2.example.com;lr", parameters: %{}}
      ]
  """
  @spec parse_list(String.t()) :: [t()]
  def parse_list(string) when is_binary(string) do
    string
    |> String.split(",")
    |> Enum.map(&String.trim/1)
    |> Enum.map(&parse/1)
  end

  @doc """
  Formats a list of Record-Route headers as a string.

  ## Examples

      iex> record_routes = [
      ...>   %Parrot.Sip.Headers.RecordRoute{display_name: nil, uri: "sip:proxy1.example.com;lr", parameters: %{}},
      ...>   %Parrot.Sip.Headers.RecordRoute{display_name: nil, uri: "sip:proxy2.example.com;lr", parameters: %{}}
      ...> ]
      iex> Parrot.Sip.Headers.RecordRoute.format_list(record_routes)
      "<sip:proxy1.example.com;lr>, <sip:proxy2.example.com;lr>"
  """
  @spec format_list([t()]) :: String.t()
  def format_list(record_routes) when is_list(record_routes) do
    record_routes
    |> Enum.map(&format/1)
    |> Enum.join(", ")
  end

  # Use UriParser.extract_parameters directly where needed
end
