defmodule Parrot.Sip.HandlerAdapter.HeaderHandler do
  @moduledoc """
  Functions for handling SIP message headers.

  This module handles the manipulation of headers in SIP messages,
  including adding, formatting, and parsing headers.
  """

  require Logger

  alias Parrot.Sip.Message
  alias Parrot.Sip.Uri
  alias Parrot.Sip.Headers.{From, To, Contact}

  @doc """
  Adds headers to a SIP message.

  This function takes a SIP message and a map of headers to add, and returns
  a new SIP message with the headers added.

  ## Parameters

    * `sip_msg` - The SIP message to add headers to
    * `headers_map` - A map of header names to values

  ## Returns

  The SIP message with the headers added
  """
  def add_headers(%Message{} = sip_msg, headers_map) when is_map(headers_map) do
    Enum.reduce(headers_map, sip_msg, fn {name, value}, acc_msg ->
      Logger.debug("Adding header: {#{inspect(name)}, #{inspect(value)}}")

      # Normalize header name
      header_name = normalize_header_name(name)

      Logger.debug("Normalized header name: #{header_name}")

      # Process the header value based on its type
      cond do
        # Handle address headers (From, To, Contact) passed as maps
        is_map(value) and header_name in ["from", "to", "contact"] ->
          Logger.debug("Processing address header as map")
          add_address_header(acc_msg, header_name, value)

        # Handle Contact as a list
        is_list(value) and header_name == "contact" ->
          Logger.debug("Processing contact list: #{inspect(value)}")
          contacts = Enum.map(value, &parse_contact_value/1)
          Message.set_header(acc_msg, "contact", contacts)

        # Handle string values
        is_binary(value) ->
          Logger.debug("Processing string header value")
          Message.set_header(acc_msg, header_name, value)

        # Handle already parsed header structs
        true ->
          Logger.debug("Header value is already a parsed structure")
          Message.set_header(acc_msg, header_name, value)
      end
    end)
  end

  @doc """
  Normalizes a header name to lowercase string.

  ## Parameters

    * `name` - The header name as a string or atom

  ## Returns

  The normalized header name as a lowercase string
  """
  def normalize_header_name(name) when is_binary(name) do
    String.downcase(name)
  end

  def normalize_header_name(name) when is_atom(name) do
    name
    |> Atom.to_string()
    |> String.replace("_", "-")
    |> String.downcase()
  end

  @doc """
  Adds an address header (From, To, Contact) to a SIP message.

  ## Parameters

    * `sip_msg` - The SIP message to add the header to
    * `header_name` - The header name as a string
    * `map_value` - A map containing the address header information

  ## Returns

  The SIP message with the header added
  """
  def add_address_header(%Message{} = sip_msg, header_name, map_value) do
    uri_str = Map.get(map_value, :uri) || Map.get(map_value, "uri")
    display_name = Map.get(map_value, :display_name) || Map.get(map_value, "display_name")
    tag = Map.get(map_value, :tag) || Map.get(map_value, "tag")

    if uri_str do
      uri = Uri.parse!(uri_str)

      header =
        case header_name do
          "from" ->
            from = %From{
              display_name: display_name,
              uri: uri,
              parameters: if(tag, do: %{"tag" => tag}, else: %{})
            }

            from

          "to" ->
            to = %To{
              display_name: display_name,
              uri: uri,
              parameters: if(tag, do: %{"tag" => tag}, else: %{})
            }

            to

          "contact" ->
            %Contact{
              display_name: display_name,
              uri: uri,
              parameters: %{}
            }
        end

      Message.set_header(sip_msg, header_name, header)
    else
      # No URI, skip adding the header
      sip_msg
    end
  end

  # Parses a contact value which can be a map or already parsed struct.
  defp parse_contact_value(%Contact{} = contact), do: contact

  defp parse_contact_value(contact_map) when is_map(contact_map) do
    uri_str = Map.get(contact_map, :uri) || Map.get(contact_map, "uri")
    display_name = Map.get(contact_map, :display_name) || Map.get(contact_map, "display_name")

    if uri_str do
      uri = Uri.parse!(uri_str)

      %Contact{
        display_name: display_name,
        uri: uri,
        parameters: %{}
      }
    else
      # Return a wildcard contact if no URI
      %Contact{wildcard: true}
    end
  end

  defp parse_contact_value(uri_str) when is_binary(uri_str) do
    uri = Uri.parse!(uri_str)

    %Contact{
      display_name: nil,
      uri: uri,
      parameters: %{}
    }
  end
end
