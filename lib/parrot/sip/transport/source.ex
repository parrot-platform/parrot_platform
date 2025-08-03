defmodule Parrot.Sip.Transport.Source do
  @moduledoc """
  Parrot SIP Stack
  SIP message source
  """

  require Logger

  alias Parrot.Sip.Message
  alias Parrot.Sip.Headers.Via

  @type source_id :: {:psip_source, module(), options()}
  @type options :: term()

  @callback send_response(Message.t(), options()) :: any()

  @doc """
  Creates a source identifier from a module and options.
  """
  @spec make_source_id(module(), options()) :: source_id()
  def make_source_id(module, args) do
    {:psip_source, module, args}
  end

  @doc """
  Sends a response through the appropriate source module based on the request's source.
  """
  @spec send_response(Message.t(), Message.t()) :: :ok | :error
  def send_response(%Message{} = resp, %Message{} = req) do
    try do
      # Extract source from the request
      case req.source do
        nil ->
          # No source in message, try to extract from Via header
          extract_source_from_via(req, resp)

        %Parrot.Sip.Source{} = source ->
          # Use the source to send the response
          Parrot.Sip.Transport.send_response(resp, source)

        {:psip_source, module, args} ->
          # Legacy source format
          module.send_response(resp, args)

        _ ->
          Logger.error("Unknown source format: #{inspect(req.source)}")
          :error
      end
    rescue
      error ->
        Logger.error("Failed to send response: #{inspect(error)}")
        :error
    end
  end

  # Extract destination from Via header for responses
  defp extract_source_from_via(%Message{} = req, %Message{} = resp) do
    case Message.get_header(req, "via") do
      nil ->
        Logger.error("No Via header in request for response")
        :error

      %Via{} = via ->
        send_via_response(via, resp)

      [%Via{} = via | _] ->
        send_via_response(via, resp)

      _ ->
        Logger.error("Invalid Via header format")
        :error
    end
  end

  defp send_via_response(%Via{} = via, %Message{} = resp) do
    # Extract host and port from Via header
    host = via.host
    port = via.port || default_port_for_transport(via.transport)

    # Check for received and rport parameters (NAT handling)
    host = Map.get(via.parameters, "received", host)

    port =
      case Map.get(via.parameters, "rport") do
        nil ->
          port

        "" ->
          port

        rport_str when is_binary(rport_str) ->
          case Integer.parse(rport_str) do
            {rport_val, _} -> rport_val
            :error -> port
          end
      end

    # Create a source and send the response
    # Convert host to IP tuple if it's an IP address
    remote_addr = parse_host_address(host)

    source = %Parrot.Sip.Source{
      # Will be filled by transport layer
      local: {nil, nil},
      remote: {remote_addr, port},
      transport: transport_to_atom(via.transport),
      source_id: nil
    }

    Parrot.Sip.Transport.send_response(resp, source)
  end

  defp default_port_for_transport(:udp), do: 5060
  defp default_port_for_transport(:tcp), do: 5060
  defp default_port_for_transport(:tls), do: 5061
  defp default_port_for_transport(:ws), do: 80
  defp default_port_for_transport(:wss), do: 443
  defp default_port_for_transport(_), do: 5060

  defp transport_to_atom("UDP"), do: :udp
  defp transport_to_atom("TCP"), do: :tcp
  defp transport_to_atom("TLS"), do: :tls
  defp transport_to_atom("WS"), do: :ws
  defp transport_to_atom("WSS"), do: :wss
  defp transport_to_atom(:udp), do: :udp
  defp transport_to_atom(:tcp), do: :tcp
  defp transport_to_atom(:tls), do: :tls
  defp transport_to_atom(:ws), do: :ws
  defp transport_to_atom(:wss), do: :wss
  defp transport_to_atom(_), do: :udp

  defp parse_host_address(host) when is_binary(host) do
    # Try to parse as IPv4 address
    case :inet.parse_ipv4_address(String.to_charlist(host)) do
      {:ok, ip} ->
        ip

      {:error, _} ->
        # Try to parse as IPv6 address
        case :inet.parse_ipv6_address(String.to_charlist(host)) do
          {:ok, ip} ->
            ip

          {:error, _} ->
            # It's a hostname, return as is
            host
        end
    end
  end

  defp parse_host_address(host), do: host
end
