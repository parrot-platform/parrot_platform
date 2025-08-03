defmodule Parrot.Sip.Headers.ReferTo do
  @moduledoc """
  Module for working with SIP Refer-To headers as defined in RFC 3515.

  The Refer-To header field is used in a REFER request to provide
  the URI to which the recipient should refer. It can include
  parameters and headers that provide additional information.

  A Refer-To header can contain a Replaces parameter in the URI, which
  is used to replace an existing dialog. This is commonly used in
  attended transfer scenarios where one call is replaced by another.

  References:
  - RFC 3515: The Session Initiation Protocol (SIP) Refer Method
  - RFC 3891: The Session Initiation Protocol (SIP) "Replaces" Header
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
  Creates a new Refer-To header.

  ## Examples

      iex> Parrot.Sip.Headers.ReferTo.new("sip:alice@example.com")
      %Parrot.Sip.Headers.ReferTo{display_name: nil, uri: "sip:alice@example.com", parameters: %{}}
      
      iex> Parrot.Sip.Headers.ReferTo.new("sip:alice@example.com", "Alice")
      %Parrot.Sip.Headers.ReferTo{display_name: "Alice", uri: "sip:alice@example.com", parameters: %{}}
  """
  @spec new(String.t() | Uri.t(), String.t() | nil, map()) :: t()
  def new(uri, display_name \\ nil, parameters \\ %{}) do
    %__MODULE__{
      display_name: display_name,
      uri: uri,
      parameters: parameters
    }
  end

  @doc """
  Parses a Refer-To header string into a ReferTo struct.

  ## Examples

      iex> Parrot.Sip.Headers.ReferTo.parse("<sip:alice@example.com>")
      %Parrot.Sip.Headers.ReferTo{display_name: nil, uri: %Parrot.Sip.Uri{scheme: "sip", user: "alice", host: "example.com"}, parameters: %{}}
      
      iex> Parrot.Sip.Headers.ReferTo.parse("Alice <sip:alice@example.com>")
      %Parrot.Sip.Headers.ReferTo{display_name: "Alice", uri: %Parrot.Sip.Uri{scheme: "sip", user: "alice", host: "example.com"}, parameters: %{}}
      
      iex> Parrot.Sip.Headers.ReferTo.parse("<sip:alice@example.com?Replaces=12345%40example.com%3Bto-tag%3D12345%3Bfrom-tag%3D54321>")
      %Parrot.Sip.Headers.ReferTo{display_name: nil, uri: %Parrot.Sip.Uri{scheme: "sip", user: "alice", host: "example.com", headers: %{"Replaces" => "12345%40example.com%3Bto-tag%3D12345%3Bfrom-tag%3D54321"}}, parameters: %{}}
  """
  @spec parse(String.t()) :: t()
  def parse(string) when is_binary(string) do
    # Pattern 1: "Display Name" <uri>;params
    # Pattern 2: <uri>;params
    # Extract display name if present
    {display_name, remainder} =
      cond do
        # Check for quoted display name first: "Display Name" <uri>
        Regex.match?(~r/^"[^"]+"\s*</, string) ->
          [quoted] = Regex.run(~r/^"([^"]+)"\s*</, string, capture: :all_but_first)
          {quoted, String.replace(string, ~r/^"[^"]+"\s*/, "")}

        # Check for unquoted display name: Display Name <uri>
        Regex.match?(~r/^[^<]+</, string) ->
          name = Regex.run(~r/^([^<]+)</, string, capture: :all_but_first) |> List.first()
          {String.trim(name), String.replace(string, ~r/^[^<]+/, "")}

        # No display name: <uri> or uri
        true ->
          {nil, string}
      end

    # Extract URI
    {uri_str, params_part} =
      case Regex.run(~r/<([^>]+)>(.*)/, remainder) do
        [_, uri_str, rest] -> {uri_str, rest}
        nil -> {remainder, ""}
      end

    # Parse the URI
    uri =
      case Parrot.Sip.Uri.parse(uri_str) do
        {:ok, parsed_uri} -> parsed_uri
        {:error, _} -> uri_str
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

    %__MODULE__{
      display_name: display_name,
      uri: uri,
      parameters: parameters
    }
  end

  @doc """
  Formats a Refer-To header as a string.

  ## Examples

      iex> refer_to = %Parrot.Sip.Headers.ReferTo{display_name: nil, uri: %Parrot.Sip.Uri{scheme: "sip", user: "alice", host: "example.com"}, parameters: %{}}
      iex> Parrot.Sip.Headers.ReferTo.format(refer_to)
      "<sip:alice@example.com>"
      
      iex> refer_to = %Parrot.Sip.Headers.ReferTo{display_name: "Alice", uri: %Parrot.Sip.Uri{scheme: "sip", user: "alice", host: "example.com"}, parameters: %{}}
      iex> Parrot.Sip.Headers.ReferTo.format(refer_to)
      "Alice <sip:alice@example.com>"
      
      iex> refer_to = %Parrot.Sip.Headers.ReferTo{display_name: "Alice", uri: %Parrot.Sip.Uri{scheme: "sip", user: "alice", host: "example.com"}, parameters: %{"method" => "INVITE"}}
      iex> Parrot.Sip.Headers.ReferTo.format(refer_to)
      "Alice <sip:alice@example.com>;method=INVITE"
  """
  @spec format(t()) :: String.t()
  def format(refer_to) do
    # Format display name
    display_part =
      cond do
        is_nil(refer_to.display_name) ->
          ""

        String.contains?(refer_to.display_name, ["\"", ",", ";", "\\"]) ->
          "\"#{refer_to.display_name}\" "

        true ->
          "#{refer_to.display_name} "
      end

    # Format URI
    uri_part =
      cond do
        is_struct(refer_to.uri, Parrot.Sip.Uri) ->
          # Ensure parameters and headers are initialized
          uri_with_defaults = %{
            refer_to.uri
            | parameters: refer_to.uri.parameters || %{},
              headers: refer_to.uri.headers || %{}
          }

          "<#{Parrot.Sip.Uri.to_string(uri_with_defaults)}>"

        is_binary(refer_to.uri) ->
          if String.starts_with?(refer_to.uri, "<") and String.ends_with?(refer_to.uri, ">") do
            refer_to.uri
          else
            "<#{refer_to.uri}>"
          end

        true ->
          "<#{inspect(refer_to.uri)}>"
      end

    # Format parameters
    params_part =
      (refer_to.parameters || %{})
      |> Enum.map(fn {k, v} ->
        if v == "", do: k, else: "#{k}=#{v}"
      end)
      |> Enum.join(";")

    params_part = if params_part == "", do: "", else: ";#{params_part}"

    display_part <> uri_part <> params_part
  end

  @doc """
  Extracts URI parameters from a Refer-To header.
  Returns a map of URI parameters.

  ## Examples

      iex> refer_to = %Parrot.Sip.Headers.ReferTo{uri: %Parrot.Sip.Uri{scheme: "sip", user: "alice", host: "example.com", parameters: %{"transport" => "tcp"}}}
      iex> Parrot.Sip.Headers.ReferTo.uri_parameters(refer_to)
      %{"transport" => "tcp"}
      
      iex> refer_to = %Parrot.Sip.Headers.ReferTo{uri: %Parrot.Sip.Uri{scheme: "sip", user: "alice", host: "example.com"}}
      iex> Parrot.Sip.Headers.ReferTo.uri_parameters(refer_to)
      %{}
  """
  @spec uri_parameters(t()) :: map()
  def uri_parameters(refer_to) do
    cond do
      is_struct(refer_to.uri, Parrot.Sip.Uri) ->
        refer_to.uri.parameters || %{}

      is_binary(refer_to.uri) ->
        case String.split(refer_to.uri, ";", parts: 2) do
          [_, params_str] ->
            params_str
            |> String.split(";")
            |> Enum.map(fn param ->
              case String.split(param, "=", parts: 2) do
                [name, value] -> {name, value}
                [name] -> {name, ""}
              end
            end)
            |> Enum.into(%{})

          [_] ->
            %{}
        end

      true ->
        %{}
    end
  end

  @doc """
  Extracts URI headers from a Refer-To header.
  Returns a map of URI headers.

  ## Examples

      iex> refer_to = %Parrot.Sip.Headers.ReferTo{uri: %Parrot.Sip.Uri{scheme: "sip", user: "alice", host: "example.com", headers: %{"Replaces" => "12345%40example.com%3Bto-tag%3D12345%3Bfrom-tag%3D54321"}}}
      iex> Parrot.Sip.Headers.ReferTo.uri_headers(refer_to)
      %{"Replaces" => "12345%40example.com%3Bto-tag%3D12345%3Bfrom-tag%3D54321"}
      
      iex> refer_to = %Parrot.Sip.Headers.ReferTo{uri: %Parrot.Sip.Uri{scheme: "sip", user: "alice", host: "example.com"}}
      iex> Parrot.Sip.Headers.ReferTo.uri_headers(refer_to)
      %{}
  """
  @spec uri_headers(t()) :: map()
  def uri_headers(refer_to) do
    cond do
      is_struct(refer_to.uri, Parrot.Sip.Uri) ->
        refer_to.uri.headers || %{}

      is_binary(refer_to.uri) ->
        case String.split(refer_to.uri, "?", parts: 2) do
          [_, headers_str] ->
            headers_str
            |> String.split("&")
            |> Enum.map(fn header ->
              case String.split(header, "=", parts: 2) do
                [name, value] -> {name, value}
                [name] -> {name, ""}
              end
            end)
            |> Enum.into(%{})

          [_] ->
            %{}
        end

      true ->
        %{}
    end
  end

  @doc """
  Gets the Replaces parameter from the URI headers if present.
  Returns the decoded Replaces value, or nil if not present.

  ## Examples

      iex> refer_to = %Parrot.Sip.Headers.ReferTo{uri: %Parrot.Sip.Uri{scheme: "sip", user: "alice", host: "example.com", headers: %{"Replaces" => "12345%40example.com%3Bto-tag%3D12345%3Bfrom-tag%3D54321"}}}
      iex> Parrot.Sip.Headers.ReferTo.replaces(refer_to)
      "12345@example.com;to-tag=12345;from-tag=54321"
      
      iex> refer_to = %Parrot.Sip.Headers.ReferTo{uri: %Parrot.Sip.Uri{scheme: "sip", user: "alice", host: "example.com"}}
      iex> Parrot.Sip.Headers.ReferTo.replaces(refer_to)
      nil
  """
  @spec replaces(t()) :: String.t() | nil
  def replaces(refer_to) do
    headers = uri_headers(refer_to)

    case Map.get(headers, "Replaces") do
      nil -> nil
      value -> URI.decode(value)
    end
  end

  @doc """
  Parses the Replaces parameter into its components: call-id, to-tag, and from-tag.
  Returns a map with the components, or nil if Replaces is not present.

  ## Examples

      iex> refer_to = %Parrot.Sip.Headers.ReferTo{uri: %Parrot.Sip.Uri{scheme: "sip", user: "alice", host: "example.com", headers: %{"Replaces" => "12345%40example.com%3Bto-tag%3D12345%3Bfrom-tag%3D54321"}}}
      iex> Parrot.Sip.Headers.ReferTo.parse_replaces(refer_to)
      %{"call_id" => "12345@example.com", "to_tag" => "12345", "from_tag" => "54321"}
      
      iex> refer_to = %Parrot.Sip.Headers.ReferTo{uri: %Parrot.Sip.Uri{scheme: "sip", user: "alice", host: "example.com"}}
      iex> Parrot.Sip.Headers.ReferTo.parse_replaces(refer_to)
      nil
  """
  @spec parse_replaces(t()) :: map() | nil
  def parse_replaces(refer_to) do
    case replaces(refer_to) do
      nil ->
        nil

      replaces_str ->
        [call_id | params] = String.split(replaces_str, ";")

        params_map =
          params
          |> Enum.map(fn param ->
            case String.split(param, "=", parts: 2) do
              [name, value] -> {name, value}
              [name] -> {name, ""}
            end
          end)
          |> Enum.into(%{})

        %{
          "call_id" => call_id,
          "to_tag" => Map.get(params_map, "to-tag"),
          "from_tag" => Map.get(params_map, "from-tag")
        }
    end
  end

  @doc """
  Creates a new Refer-To header with a Replaces parameter.

  ## Examples

      iex> Parrot.Sip.Headers.ReferTo.new_with_replaces("sip:bob@example.com", nil, "call123@example.com", "to-tag-123", "from-tag-456")
      %Parrot.Sip.Headers.ReferTo{display_name: nil, uri: %Parrot.Sip.Uri{scheme: "sip", user: "bob", host: "example.com", headers: %{"Replaces" => "call123%40example.com%3Bto-tag%3Dto-tag-123%3Bfrom-tag%3Dfrom-tag-456"}}, parameters: %{}}
  """
  @spec new_with_replaces(String.t(), String.t() | nil, String.t(), String.t(), String.t(), map()) ::
          t()
  def new_with_replaces(
        uri_str,
        display_name \\ nil,
        call_id,
        to_tag,
        from_tag,
        parameters \\ %{}
      ) do
    {:ok, base_uri} = Parrot.Sip.Uri.parse(uri_str)

    # Construct the Replaces parameter
    replaces_value = "#{call_id};to-tag=#{to_tag};from-tag=#{from_tag}"

    # URL encode the Replaces value
    encoded_replaces = URI.encode(replaces_value)

    # Add the Replaces parameter to the URI headers
    uri = %{base_uri | headers: Map.put(base_uri.headers || %{}, "Replaces", encoded_replaces)}

    # Create the ReferTo header
    %__MODULE__{
      display_name: display_name,
      uri: uri,
      parameters: parameters
    }
  end
end
