defmodule Parrot.Sip.Headers.Contact do
  @moduledoc """
  Module for working with SIP Contact headers as defined in RFC 3261 Section 20.10.

  The Contact header provides a URI where the user can be reached for subsequent requests.
  It plays a critical role in dialog establishment, request routing, and registrations.
  Its meaning depends on the type of request or response it appears in:

  - In REGISTER requests: Specifies where the user can be reached
  - In INVITE requests: Indicates where the caller can be reached
  - In 2xx responses to INVITE: Specifies where the callee can be reached
  - In 3xx responses: Provides alternative locations to retry the request

  The Contact header can contain parameters:
  - expires: Indicates how long the URI is valid (seconds)
  - q-value: Indicates preference among multiple contacts
  - methods: Specifies which methods the contact supports
  - * (wildcard): Special form used only in REGISTER requests for removal

  References:
  - RFC 3261 Section 8.1.1.8: Contact
  - RFC 3261 Section 10: Registrations
  - RFC 3261 Section 12.1.1: UAC Behavior
  - RFC 3261 Section 20.10: Contact Header Field
  """

  alias Parrot.Sip.Uri

  defstruct [
    # String (optional)
    :display_name,
    # String URI or Uri struct
    :uri,
    # Map of parameters
    :parameters,
    # Boolean for * Contact
    :wildcard
  ]

  @type t :: %__MODULE__{
          display_name: String.t() | nil,
          uri: String.t() | Uri.t() | nil,
          parameters: map(),
          wildcard: boolean()
        }

  @doc """
  Creates a new Contact header.
  """
  @spec new(String.t(), String.t() | nil, map()) :: t()
  def new(uri, display_name \\ nil, parameters \\ %{}) do
    # Parse URI string if needed
    parsed_uri =
      cond do
        is_binary(uri) ->
          case Uri.parse(uri) do
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
      parameters: parameters,
      wildcard: false
    }
  end

  @doc """
  Creates a new wildcard Contact header.
  """
  @spec wildcard() :: t()
  def wildcard do
    %__MODULE__{
      display_name: nil,
      uri: nil,
      parameters: %{},
      wildcard: true
    }
  end

  @doc """
  Converts a Contact header to a string representation.
  """
  @spec format(t()) :: String.t()
  def format(contact) do
    if contact.wildcard do
      "*"
    else
      # Format: "Display Name" <sip:user@host>;params
      display_part =
        if contact.display_name do
          has_special_chars =
            String.contains?(contact.display_name, " ") ||
              String.contains?(contact.display_name, "\"") ||
              String.contains?(contact.display_name, ",") ||
              String.contains?(contact.display_name, ";") ||
              String.contains?(contact.display_name, ":") ||
              String.contains?(contact.display_name, "\\") ||
              String.contains?(contact.display_name, "&") ||
              String.contains?(contact.display_name, "<") ||
              String.contains?(contact.display_name, ">") ||
              String.contains?(contact.display_name, "@") ||
              String.contains?(contact.display_name, "/")

          if has_special_chars do
            "\"#{contact.display_name}\""
          else
            contact.display_name
          end
        else
          ""
        end

      uri_part =
        cond do
          is_struct(contact.uri, Parrot.Sip.Uri) ->
            uri_string = contact.uri.scheme <> ":"

            uri_string =
              if contact.uri.user, do: uri_string <> contact.uri.user <> "@", else: uri_string

            uri_string = uri_string <> contact.uri.host

            uri_string =
              if contact.uri.port,
                do: uri_string <> ":" <> Integer.to_string(contact.uri.port),
                else: uri_string

            uri_string

          is_binary(contact.uri) ->
            contact.uri

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
        contact.parameters
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
  end

  @doc """
  Adds or updates a parameter in a Contact header.
  """
  @spec with_parameter(t(), String.t(), String.t()) :: t()
  def with_parameter(contact, name, value) do
    parameters = Map.put(contact.parameters, name, value)
    %{contact | parameters: parameters}
  end

  @doc """
  Sets the expires parameter in a Contact header.
  """
  @spec with_expires(t(), integer()) :: t()
  def with_expires(contact, expires) when is_integer(expires) do
    with_parameter(contact, "expires", Integer.to_string(expires))
  end

  @doc """
  Sets the q-value parameter in a Contact header.
  """
  @spec with_q(t(), float()) :: t()
  def with_q(contact, q) when q >= 0.0 and q <= 1.0 do
    q_str = :io_lib.format("~.1f", [q]) |> to_string()
    with_parameter(contact, "q", q_str)
  end

  @doc """
  Gets a parameter from a Contact header.
  """
  @spec get_parameter(t(), String.t()) :: String.t() | nil
  def get_parameter(contact, name) do
    Map.get(contact.parameters, name)
  end

  @doc """
  Gets the expires parameter from a Contact header.
  """
  @spec expires(t()) :: integer() | nil
  def expires(contact) do
    case get_parameter(contact, "expires") do
      nil ->
        nil

      value ->
        {expires, _} = Integer.parse(value)
        expires
    end
  end

  @doc """
  Gets the q-value parameter from a Contact header.
  """
  @spec q(t()) :: float() | nil
  def q(contact) do
    case get_parameter(contact, "q") do
      nil ->
        nil

      value ->
        {q, _} = Float.parse(value)
        q
    end
  end

  @doc """
  Parses a Contact header string into a Contact struct.

  ## Examples

      iex> Parrot.Sip.Headers.Contact.parse("Alice <sip:alice@pc33.atlanta.com>;expires=3600")
      %Parrot.Sip.Headers.Contact{display_name: "Alice", uri: %Parrot.Sip.Uri{scheme: "sip", user: "alice", host: "pc33.atlanta.com"}, parameters: %{"expires" => "3600"}, wildcard: false}
      
      iex> Parrot.Sip.Headers.Contact.parse("*")
      %Parrot.Sip.Headers.Contact{display_name: nil, uri: nil, parameters: %{}, wildcard: true}

  """
  @spec parse(String.t()) :: t()
  def parse(string) when is_binary(string) do
    # Check for wildcard
    if string == "*" do
      wildcard()
    else
      # Extract display name, URI, and parameters
      {display_name, uri_str, params_str} = parse_address_parts(string |> String.trim())

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

      # Parse URI using common parser
      uri =
        if is_binary(uri_str) do
          uri_str = String.trim(uri_str)

          # Try to parse with the URI parser
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
          uri_str
        end

      %__MODULE__{
        display_name: display_name,
        uri: uri,
        parameters: parameters,
        wildcard: false
      }
    end
  end

  # Helper function to parse the address parts (display-name, URI, parameters)
  defp parse_address_parts(string) do
    # Check for angle brackets to determine format
    case Regex.run(~r/<([^>]+)>(.*)?/, string) do
      [_, uri, rest] ->
        # Extract display name if present
        display_name =
          case Regex.run(~r/^(.*?)\s*</, string) do
            [_, name] ->
              # Remove quotes if present
              name = String.trim(name)

              if String.starts_with?(name, "\"") && String.ends_with?(name, "\"") do
                name |> String.slice(1..(String.length(name) - 2))
              else
                name
              end

            nil ->
              nil
          end

        {display_name, uri, String.trim_leading(rest || "", ";")}

      nil ->
        # No angle brackets, try to split at first semicolon
        case String.split(string, ";", parts: 2) do
          [uri_part, params] -> {nil, uri_part, params}
          [uri_part] -> {nil, uri_part, ""}
        end
    end
  end
end
