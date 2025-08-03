defmodule Parrot.Sip.MessageHelper do
  @moduledoc """
  Helper functions for manipulating SIP messages.

  This module provides a set of utility functions for common SIP message operations
  that aren't directly related to serialization or deserialization. These include:

  - Via header manipulation for NAT traversal
  - Route set management
  - Dialog-related header handling
  - Multipart body handling

  References:
  - RFC 3261 Section 18.2.1: Sending Responses
  - RFC 3261 Section 18.2.2: Sending Requests
  - RFC 3261 Section 12: Dialogs
  - RFC 3581: An Extension to SIP for Symmetric Response Routing
  """

  alias Parrot.Sip.Message

  @doc """
  Adds or updates the 'received' parameter in the top Via header.

  This is used for NAT traversal as described in RFC 3261 Section 18.2.1,
  where a server receiving a request through a NAT should record the source
  IP address in the 'received' parameter of the top Via header.

  ## Parameters
    * `message` - A Parrot.Sip.Message struct
    * `ip_address` - IP address to set as the 'received' parameter

  ## Returns
    * The updated message with the 'received' parameter in the top Via

  ## Examples

      iex> message = Parrot.Sip.Message.new_request(:invite, "sip:bob@example.com")
      iex> message = Parrot.Sip.Message.set_header(message, "via", "SIP/2.0/UDP client.atlanta.com:5060;branch=z9hG4bK74bf9")
      iex> updated = Parrot.Sip.MessageHelper.set_received_parameter(message, "192.168.1.1")
      iex> Parrot.Sip.Message.get_header(updated, "via")
      %Parrot.Sip.Headers.Via{
        port: 5060,
        version: "2.0",
        protocol: "SIP",
        host: "client.atlanta.com",
        parameters: %{"branch" => "z9hG4bK74bf9", "received" => "192.168.1.1"},
        transport: :udp,
        host_type: :hostname
      }
  """
  @spec set_received_parameter(Message.t(), String.t()) :: Message.t()
  def set_received_parameter(message, ip_address) do
    case Message.top_via(message) do
      nil ->
        message

      via ->
        # Always treat as a Via struct
        updated_via = Parrot.Sip.Headers.Via.with_parameter(via, "received", ip_address)
        update_top_via(message, updated_via)
    end
  end

  @doc """
  Adds or updates the 'rport' parameter in the top Via header.

  Used for symmetric response routing as described in RFC 3581,
  where a server records the source port in the 'rport' parameter
  of the top Via header when a client includes an empty 'rport'
  parameter in its request.

  ## Parameters
    * `message` - A Parrot.Sip.Message struct
    * `port` - Port number to set as the 'rport' parameter

  ## Returns
    * The updated message with the 'rport' parameter in the top Via

  ## Examples

      iex> message = Parrot.Sip.Message.new_request(:invite, "sip:bob@example.com")
      iex> message = Parrot.Sip.Message.set_header(message, "via", "SIP/2.0/UDP client.atlanta.com:5060;branch=z9hG4bK74bf9;rport")
      iex> updated = Parrot.Sip.MessageHelper.set_rport_parameter(message, 12345)
      iex> Parrot.Sip.Message.get_header(updated, "via")
      %Parrot.Sip.Headers.Via{
        port: 5060,
        version: "2.0",
        protocol: "SIP",
        host: "client.atlanta.com",
        parameters: %{"branch" => "z9hG4bK74bf9", "rport" => "12345"},
        transport: :udp,
        host_type: :hostname
      }
  """
  @spec set_rport_parameter(Message.t(), non_neg_integer()) :: Message.t()
  def set_rport_parameter(message, port) do
    case Message.top_via(message) do
      nil ->
        message

      via ->
        # Process via as a Via struct
        updated_via = Parrot.Sip.Headers.Via.with_parameter(via, "rport", Integer.to_string(port))
        update_top_via(message, updated_via)
    end
  end

  @doc """
  Removes the top Via header from a message.

  This is used when forwarding responses, as each server
  in the response path removes the top Via header before
  forwarding the response.

  ## Parameters
    * `message` - A Parrot.Sip.Message struct

  ## Returns
    * The updated message with the top Via header removed

  ## Examples

      iex> message = Parrot.Sip.Message.new_response(200, "OK")
      iex> message = Parrot.Sip.Message.set_header(message, "via", ["SIP/2.0/UDP proxy.biloxi.com:5060;branch=z9hG4bK74bf9", "SIP/2.0/UDP client.atlanta.com:5060;branch=z9hG4bK74bf9"])
      iex> updated = Parrot.Sip.MessageHelper.remove_top_via(message)
      iex> Parrot.Sip.Message.get_header(updated, "via")
      [
        %Parrot.Sip.Headers.Via{
          port: 5060,
          version: "2.0",
          protocol: "SIP",
          host: "client.atlanta.com",
          parameters: %{"branch" => "z9hG4bK74bf9"},
          transport: :udp,
          host_type: :hostname
        }
      ]
  """
  @spec remove_top_via(Message.t()) :: Message.t()
  def remove_top_via(message) do
    vias = Message.all_vias(message)

    case vias do
      nil -> message
      [] -> message
      # Remove via header completely if last one
      [_top_via | []] -> Message.set_header(message, "via", nil)
      [_top_via | rest] -> Message.set_header(message, "via", rest)
    end
  end

  @doc """
  Applies NAT traversal handling to a message based on source information.

  This function handles both the 'received' and 'rport' parameters,
  which are used for symmetric response routing through NATs.

  ## Parameters
    * `message` - A Parrot.Sip.Message struct
    * `source_info` - Map containing source information with host and port

  ## Returns
    * The updated message with NAT handling applied

  ## Examples

      iex> message = Parrot.Sip.Message.new_request(:invite, "sip:bob@example.com")
      iex> via = Parrot.Sip.Headers.Via.parse("SIP/2.0/UDP client.atlanta.com:5060;branch=z9hG4bK74bf9;rport")
      iex> message = Parrot.Sip.Message.set_header(message, "via", via)
      iex> source_info = %{host: "192.168.1.100", port: 12345}
      iex> updated = Parrot.Sip.MessageHelper.apply_nat_handling(message, source_info)
      iex> Parrot.Sip.Message.get_header(updated, "via")
      %Parrot.Sip.Headers.Via{
        port: 5060,
        version: "2.0",
        protocol: "SIP",
        host: "client.atlanta.com",
        parameters: %{"branch" => "z9hG4bK74bf9", "received" => "192.168.1.100", "rport" => "12345"},
        transport: :udp,
        host_type: :hostname
      }
  """
  @spec apply_nat_handling(Message.t(), map()) :: Message.t()
  def apply_nat_handling(message, %{host: host, port: port}) do
    via = Message.top_via(message)

    case via do
      nil ->
        message

      _ ->
        # Extract via host and port from header
        via_host = extract_via_host(via)
        via_port = extract_via_port(via)

        # Apply changes sequentially to build the final message
        message =
          if via_host != host do
            # Only add received parameter if the host differs
            set_received_parameter(message, host)
          else
            message
          end

        # Check if rport is present as an empty parameter
        if has_empty_rport_parameter?(via) and via_port != port do
          set_rport_parameter(message, port)
        else
          message
        end
    end
  end

  @doc """
  Ensures a response uses the same path as the request for symmetric routing.

  This implements symmetric response routing according to RFC 3581.
  When generating a response to a request, the response should be
  sent to the source of the request if the topmost Via has a 'received'
  parameter and/or an 'rport' parameter with a value.

  ## Parameters
    * `request` - The original request Message struct
    * `response` - The response Message struct

  ## Returns
    * The updated response with routing information from the request

  ## Examples

      iex> request = Parrot.Sip.Message.new_request(:invite, "sip:bob@example.com")
      iex> request = Parrot.Sip.Message.set_header(request, "via", "SIP/2.0/UDP client.atlanta.com:5060;branch=z9hG4bK74bf9;received=192.168.1.100;rport=12345")
      iex> response = Parrot.Sip.Message.new_response(200, "OK")
      iex> response = Parrot.Sip.MessageHelper.symmetric_response_routing(request, response)
      iex> response.source.host
      "192.168.1.100"
      iex> response.source.port
      12345
  """
  @spec symmetric_response_routing(Message.t(), Message.t()) :: Message.t()
  def symmetric_response_routing(request, response) do
    via = Message.top_via(request)

    case via do
      nil ->
        response

      _ ->
        received = extract_via_parameter(via, "received")
        rport = extract_via_parameter(via, "rport")

        # Get original transport type
        transport = extract_via_transport(via)

        # Determine target host and port
        host = if received && received != "", do: received, else: extract_via_host(via)

        port =
          case rport do
            nil ->
              extract_via_port(via)

            "" ->
              extract_via_port(via)

            value ->
              case Integer.parse(value) do
                {port_num, _} -> port_num
                :error -> extract_via_port(via)
              end
          end

        # Create source for response
        source = %{
          type: transport,
          host: host,
          port: port
        }

        # Update response with routing information
        %{response | source: source}
    end
  end

  @doc """
  Adds a Route header to a message.

  Used when sending requests through a specific path, such as
  when using a route set from a dialog or when routing through
  specific proxies.

  ## Parameters
    * `message` - A Parrot.Sip.Message struct
    * `route_uri` - URI to add as a Route header
    * `prepend` - Whether to add the Route at the beginning or end (default: true)

  ## Returns
    * The updated message with the Route header added

  ## Examples

      iex> message = Parrot.Sip.Message.new_request(:invite, "sip:bob@example.com")
      iex> updated = Parrot.Sip.MessageHelper.add_route_header(message, "<sip:proxy.biloxi.com;lr>")
      iex> Parrot.Sip.Message.get_header(updated, "route")
      ["<sip:proxy.biloxi.com;lr>"]

      iex> message = Parrot.Sip.Message.new_request(:invite, "sip:bob@example.com")
      iex> message = Parrot.Sip.Message.set_header(message, "route", "<sip:proxy1.atlanta.com;lr>")
      iex> updated = Parrot.Sip.MessageHelper.add_route_header(message, "<sip:proxy2.biloxi.com;lr>")
      iex> Parrot.Sip.Message.get_header(updated, "route")
      ["<sip:proxy2.biloxi.com;lr>", "<sip:proxy1.atlanta.com;lr>"]

      iex> message = Parrot.Sip.Message.new_request(:invite, "sip:bob@example.com")
      iex> message = Parrot.Sip.Message.set_header(message, "route", "<sip:proxy1.atlanta.com;lr>")
      iex> updated = Parrot.Sip.MessageHelper.add_route_header(message, "<sip:proxy2.biloxi.com;lr>", false)
      iex> Parrot.Sip.Message.get_header(updated, "route")
      ["<sip:proxy1.atlanta.com;lr>", "<sip:proxy2.biloxi.com;lr>"]
  """
  @spec add_route_header(Message.t(), String.t(), boolean()) :: Message.t()
  def add_route_header(message, route, prepend \\ true) do
    current_routes = Message.get_headers(message, "route")

    updated_routes =
      case length(current_routes) do
        0 ->
          [route]

        _ ->
          if prepend, do: [route | current_routes], else: current_routes ++ [route]
      end

    Message.set_header(message, "route", updated_routes)
  end

  @doc """
  Builds a route set from Record-Route headers in a message.

  This is used in dialog creation to establish the route set
  according to RFC 3261 Section 12.1.1.

  ## Parameters
    * `message` - A Parrot.Sip.Message struct

  ## Returns
    * List of route URIs or nil if no Record-Route headers are present

  ## Parameters

    * `message` - A `Parrot.Sip.Message` struct.
    * `record_route` - A `%Parrot.Sip.Headers.RecordRoute{}` struct to add.

  ## Returns

    * An updated `Parrot.Sip.Message` with the new `Record-Route` header prepended.

  ## Examples

      iex> rr = "<sip:proxy.biloxi.com;lr>"
      iex> message = Parrot.Sip.Message.new_request(:invite, "sip:bob@example.com")
      iex> updated = Parrot.Sip.MessageHelper.add_record_route(message, rr)
      iex> length(Parrot.Sip.Message.get_headers(updated, "record-route"))
  """
  @spec add_record_route(Message.t(), String.t()) :: Message.t()
  def add_record_route(message, record_route) do
    current_record_routes = Message.get_headers(message, "record-route")

    updated_record_routes = [record_route | current_record_routes]

    Message.set_header(message, "record-route", updated_record_routes)
  end

  @doc """
  Extracts a specific part from a multipart message body based on content type.

  ## Parameters
    * `message` - A Parrot.Sip.Message struct with a multipart body
    * `content_type` - The content type to extract, e.g., "application/sdp"

  ## Returns
    * `{:ok, part}` - The extracted part as a map with :headers and :body fields
    * `{:error, reason}` - Error if part not found or message doesn't have multipart parts


  """
  @spec extract_multipart_part(Message.t(), String.t()) :: {:ok, map()} | {:error, String.t()}
  def extract_multipart_part(message, content_type) do
    parts = Map.get(message.headers, "multipart-parts")

    if parts do
      part =
        Enum.find(parts, fn part ->
          part_content_type = Map.get(part.headers, "content-type")
          part_content_type && String.starts_with?(part_content_type, content_type)
        end)

      if part, do: {:ok, part}, else: {:error, "No part with content type: #{content_type}"}
    else
      {:error, "Message does not contain parsed multipart body"}
    end
  end

  # Private helper functions

  # Updates the top Via header in a message
  defp update_top_via(message, updated_via) do
    vias = Message.all_vias(message)

    case vias do
      nil ->
        Message.set_header(message, "via", updated_via)

      [] ->
        Message.set_header(message, "via", updated_via)

      [_top_via | rest] ->
        new_vias = if rest == [], do: updated_via, else: [updated_via | rest]
        Message.set_header(message, "via", new_vias)
    end
  end

  # Extracts the host from a Via header
  defp extract_via_host(via) when is_binary(via) do
    case Regex.run(~r{SIP/2.0/\w+\s+([^:;]+)(?::\d+)?}, via) do
      [_, host] -> host
      _ -> nil
    end
  end

  defp extract_via_host(via) when is_struct(via) do
    if Map.has_key?(via, :host), do: via.host, else: nil
  end

  defp extract_via_host(via) when is_map(via) do
    Map.get(via, :host)
  end

  # Extracts the port from a Via header
  defp extract_via_port(via) when is_binary(via) do
    case Regex.run(~r{SIP/2.0/\w+\s+[^:;]+:(\d+)}, via) do
      [_, port_str] ->
        {port, _} = Integer.parse(port_str)
        port

      _ ->
        # Default ports by transport
        if String.contains?(via, "SIP/2.0/TLS"), do: 5061, else: 5060
    end
  end

  defp extract_via_port(via) when is_struct(via) do
    if Map.has_key?(via, :port), do: via.port, else: nil
  end

  defp extract_via_port(via) when is_map(via) do
    Map.get(via, :port)
  end

  # Extracts the transport from a Via header
  defp extract_via_transport(via) when is_binary(via) do
    case Regex.run(~r{SIP/2.0/(\w+)}, via) do
      [_, transport] -> transport
      # Default to UDP if not found
      _ -> "UDP"
    end
  end

  defp extract_via_transport(via) when is_struct(via) do
    if Map.has_key?(via, :transport), do: via.transport, else: nil
  end

  defp extract_via_transport(via) when is_map(via) do
    Map.get(via, :transport)
  end

  # Extracts a parameter value from a Via header
  defp extract_via_parameter(via, param_name) when is_binary(via) do
    pattern = ";#{param_name}(?:=([^;]*))?(?:;|$)"

    case Regex.run(~r{#{pattern}}, via) do
      [_, value] -> value
      # Parameter exists but has no value
      [_] -> ""
      # Parameter doesn't exist
      nil -> nil
    end
  end

  defp extract_via_parameter(via, param_name) when is_struct(via) do
    if Map.has_key?(via, :parameters) do
      Map.get(via.parameters, param_name)
    else
      nil
    end
  end

  defp extract_via_parameter(via, param_name) when is_map(via) do
    if Map.has_key?(via, :parameters) do
      Map.get(via.parameters, param_name)
    else
      nil
    end
  end

  # Checks if a Via header has an empty rport parameter
  defp has_empty_rport_parameter?(via) when is_binary(via) do
    !!Regex.run(~r/;rport(?=;|$)/, via)
  end

  defp has_empty_rport_parameter?(via) when is_struct(via) do
    if Map.has_key?(via, :parameters) do
      case Map.get(via.parameters, "rport") do
        nil -> false
        "" -> true
        # If it has a value, it's not empty
        _ -> false
      end
    else
      false
    end
  end

  defp has_empty_rport_parameter?(via) when is_map(via) do
    if Map.has_key?(via, :parameters) do
      case Map.get(via.parameters, "rport") do
        nil -> false
        "" -> true
        # If it has a value, it's not empty
        _ -> false
      end
    else
      false
    end
  end
end
