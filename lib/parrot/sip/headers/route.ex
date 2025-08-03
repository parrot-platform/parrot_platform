defmodule Parrot.Sip.Headers.Route do
  @moduledoc """
  Module for working with SIP Route headers as defined in RFC 3261 Section 20.34.

  The Route header field is used to force routing for a request through a list
  of proxies. Each proxy extracts the first Route header field value from a request
  and uses it to route to the next hop.

  Route headers serve crucial functions in SIP routing:
  - Implementing loose routing (lr parameter) as defined in RFC 3261
  - Forcing requests through specific proxy paths
  - Enabling pre-loaded routes in initial requests
  - Supporting record-route-based dialog routing

  Route headers are typically populated from Record-Route headers received in
  responses, but in reverse order. The presence of the 'lr' (loose routing)
  parameter indicates RFC 3261 compliance, distinguishing from RFC 2543 strict routing.

  References:
  - RFC 3261 Section 8.1.2: Contact and Route Header Fields
  - RFC 3261 Section 12.2.1.1: UAC Behavior - Generating the Request
  - RFC 3261 Section 16.6: Request Forwarding (proxy processing)
  - RFC 3261 Section 19.1.1: Loose Routing
  - RFC 3261 Section 20.34: Route Header Field
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
  Creates a new Route header.

  ## Examples

      iex> Parrot.Sip.Headers.Route.new("sip:proxy.example.com;lr")
      %Parrot.Sip.Headers.Route{display_name: nil, uri: "sip:proxy.example.com;lr", parameters: %{}}
      
      iex> Parrot.Sip.Headers.Route.new("sip:proxy.example.com;lr", "Example Proxy")
      %Parrot.Sip.Headers.Route{display_name: "Example Proxy", uri: "sip:proxy.example.com;lr", parameters: %{}}
  """
  @spec new(String.t() | Uri.t(), String.t() | nil, map()) :: t()
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
  Parses a Route header string into a Route struct.

  ## Examples

      iex> Parrot.Sip.Headers.Route.parse("<sip:proxy.example.com;lr>")
      %Parrot.Sip.Headers.Route{display_name: nil, uri: "sip:proxy.example.com;lr", parameters: %{}}
      
      iex> Parrot.Sip.Headers.Route.parse("Example Proxy <sip:proxy.example.com;lr>")
      %Parrot.Sip.Headers.Route{display_name: "Example Proxy", uri: "sip:proxy.example.com;lr", parameters: %{}}
      
      iex> Parrot.Sip.Headers.Route.parse("\"Complex Name\" <sip:proxy.example.com;lr>;param=value")
      %Parrot.Sip.Headers.Route{display_name: "Complex Name", uri: "sip:proxy.example.com;lr", parameters: %{"param" => "value"}}
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
    {uri_str, params_part} =
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

  @doc """
  Formats a Route header as a string.

  ## Examples

      iex> route = %Parrot.Sip.Headers.Route{display_name: nil, uri: "sip:proxy.example.com;lr", parameters: %{}}
      iex> Parrot.Sip.Headers.Route.format(route)
      "<sip:proxy.example.com;lr>"
      
      iex> route = %Parrot.Sip.Headers.Route{display_name: "Example Proxy", uri: "sip:proxy.example.com;lr", parameters: %{}}
      iex> Parrot.Sip.Headers.Route.format(route)
      "Example Proxy <sip:proxy.example.com;lr>"
      
      iex> route = %Parrot.Sip.Headers.Route{display_name: "Complex Name", uri: "sip:proxy.example.com;lr", parameters: %{"param" => "value"}}
      iex> Parrot.Sip.Headers.Route.format(route)
      "\"Complex Name\" <sip:proxy.example.com;lr>;param=value"
  """
  @spec format(t()) :: String.t()
  def format(route) do
    # Format display name
    display_part =
      cond do
        is_nil(route.display_name) ->
          ""

        String.contains?(route.display_name, [",", "\"", ";", "\\"]) ->
          "\"#{route.display_name}\" "

        true ->
          "#{route.display_name} "
      end

    # Format URI
    uri_part =
      cond do
        is_struct(route.uri, Parrot.Sip.Uri) ->
          uri_string = route.uri.scheme <> ":"

          uri_string =
            if route.uri.user, do: uri_string <> route.uri.user <> "@", else: uri_string

          uri_string = uri_string <> route.uri.host

          uri_string =
            if route.uri.port,
              do: uri_string <> ":" <> Integer.to_string(route.uri.port),
              else: uri_string

          # Add URI parameters if present
          uri_string =
            if route.uri.parameters && map_size(route.uri.parameters) > 0 do
              params_str =
                route.uri.parameters
                |> Enum.map(fn {k, v} -> if v == "", do: k, else: "#{k}=#{v}" end)
                |> Enum.join(";")

              "#{uri_string};#{params_str}"
            else
              uri_string
            end

          "<#{uri_string}>"

        is_binary(route.uri) ->
          "<#{route.uri}>"

        true ->
          "<>"
      end

    # Format parameters
    params_part =
      route.parameters
      |> Enum.map(fn {k, v} ->
        if v == "", do: k, else: "#{k}=#{v}"
      end)
      |> Enum.join(";")

    params_part = if params_part == "", do: "", else: ";#{params_part}"

    display_part <> uri_part <> params_part
  end

  @doc """
  Parses a list of Route headers.

  ## Examples

      iex> Parrot.Sip.Headers.Route.parse_list("<sip:proxy1.example.com;lr>, <sip:proxy2.example.com;lr>")
      [
        %Parrot.Sip.Headers.Route{display_name: nil, uri: "sip:proxy1.example.com;lr", parameters: %{}},
        %Parrot.Sip.Headers.Route{display_name: nil, uri: "sip:proxy2.example.com;lr", parameters: %{}}
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
  Formats a list of Route headers as a string.

  ## Examples

      iex> routes = [
      ...>   %Parrot.Sip.Headers.Route{display_name: nil, uri: "sip:proxy1.example.com;lr", parameters: %{}},
      ...>   %Parrot.Sip.Headers.Route{display_name: nil, uri: "sip:proxy2.example.com;lr", parameters: %{}}
      ...> ]
      iex> Parrot.Sip.Headers.Route.format_list(routes)
      "<sip:proxy1.example.com;lr>, <sip:proxy2.example.com;lr>"
  """
  @spec format_list([t()]) :: String.t()
  def format_list(routes) when is_list(routes) do
    routes
    |> Enum.map(&format/1)
    |> Enum.join(", ")
  end
end
