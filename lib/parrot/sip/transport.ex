defmodule Parrot.Sip.Transport do
  require Logger

  @doc """
  Sends a SIP response message using the UDP transport.

  This function expects the response to be a `%Parrot.Sip.Message{}` and the source
  (destination for the response) to be present in the message struct as `:source`
  or passed explicitly as a second argument.

  If you call with only the response, it will try to extract the source from
  `response.source`. If you have the source separately, use the two-argument version.

  ## Examples

      Parrot.Sip.Transport.send_response(response, source)
      Parrot.Sip.Transport.send_response(response) # if response.source is set

  """
  @spec send_response(Parrot.Sip.Message.t()) :: :ok | {:error, term()}
  def send_response(%Parrot.Sip.Message{source: %Parrot.Sip.Source{} = source} = response) do
    send_response(response, source)
  end

  @spec send_response(Parrot.Sip.Message.t(), Parrot.Sip.Source.t()) :: :ok | {:error, term()}
  def send_response(response, source) do
    Parrot.Sip.Transport.Udp.send_response(response, source)
  end

  @moduledoc """
  Transport layer for SIP protocol.

  This module provides functions for handling the transport layer of SIP communication.
  It manages the transport-specific aspects of SIP communication, including:

  - Connection handling for different transport types (UDP, TCP, TLS, WS, WSS)
  - Transport error handling and recovery
  - NAT traversal mechanisms

  The actual serialization and deserialization of SIP messages is handled by
  Parrot.Sip.Serializer and Parrot.Sip.Deserializer respectively.

  This module provides the pure functional implementation of SIP transport.
  For stateful transport management, see Parrot.Sip.Transport.StateMachine.

  References:
  - RFC 3261 Section 18: Transport
  - RFC 3261 Section 18.2.1: Sending Responses
  - RFC 3261 Section 18.2.2: Sending Requests
  - RFC 6223: SIP Transport Extension for WebSocket
  """

  alias Parrot.Sip.Message
  alias Parrot.Sip.Headers.Via
  alias Parrot.Sip.Serializer
  alias Parrot.Sip.Transport.StateMachine, as: TransportSM

  @typedoc """
  Transport types supported by SIP
  """
  @type transport_type :: :udp | :tcp | :tls | :ws | :wss

  @typedoc """
  Transport configuration options
  """
  @type transport_opts :: %{
          type: transport_type(),
          local_host: String.t(),
          local_port: non_neg_integer() | nil,
          remote_host: String.t() | nil,
          remote_port: non_neg_integer() | nil,
          tls_options: keyword() | nil,
          connection_timeout: non_neg_integer(),
          keep_alive_interval: non_neg_integer() | nil
        }

  @typedoc """
  Transport connection
  """
  @type connection :: %{
          type: transport_type(),
          socket: port() | pid() | reference(),
          local_host: String.t(),
          local_port: non_neg_integer(),
          remote_host: String.t() | nil,
          remote_port: non_neg_integer() | nil,
          created_at: DateTime.t()
        }

  @typedoc """
  Transport source information
  """
  @type source :: %{
          type: transport_type(),
          host: String.t(),
          port: non_neg_integer(),
          local_host: String.t(),
          local_port: non_neg_integer()
        }

  @doc """
  Delegates serialization of a SIP message to Parrot.Sip.Serializer.

  ## Examples

      iex> message = Parrot.Sip.Message.new_request(:invite, "sip:bob@example.com")
      iex> binary = Parrot.Sip.Transport.serialize(message)
      iex> String.starts_with?(binary, "INVITE sip:bob@example.com SIP/2.0\\r\\n")
      true
  """
  @spec serialize(Message.t()) :: binary()
  def serialize(message, opts \\ %{}) do
    Serializer.encode(message, opts)
  end

  @doc """
  Delegates deserialization of a binary SIP message to Parrot.Sip.Deserializer.

  This function handles the parsing of raw binary data received from the network
  into a structured SIP message.

  ## Parameters
  - raw_data: The raw binary data
  - source: Transport source information

  ## Examples

      iex> raw_data = "INVITE sip:bob@example.com SIP/2.0\\r\\nVia: SIP/2.0/UDP pc33.atlanta.com;branch=z9hG4bK776asdhds\\r\\nMax-Forwards: 70\\r\\nTo: Bob <sip:bob@biloxi.com>\\r\\nFrom: Alice <sip:alice@atlanta.com>;tag=1928301774\\r\\nCall-ID: a84b4c76e66710@pc33.atlanta.com\\r\\nCSeq: 314159 INVITE\\r\\nContact: <sip:alice@pc33.atlanta.com>\\r\\nContent-Type: application/sdp\\r\\nContent-Length: 0\\r\\n\\r\\n"
      iex> source = %{type: :udp, host: "pc33.atlanta.com", port: 5060, local_host: "server.biloxi.com", local_port: 5060}
      iex> {:ok, message} = Parrot.Sip.Transport.deserialize(raw_data, source)
      iex> message.method
      :invite
  """
  @spec deserialize(binary(), source()) :: {:ok, Message.t()} | {:error, String.t()}
  def deserialize(raw_data, source) when is_binary(raw_data) do
    Serializer.decode(raw_data, source)
  end

  @doc """
  Prepares a message for sending over a specific transport.

  This function makes any necessary transport-specific adjustments to the message
  before serialization, such as:
  - Updating or adding a Via header with the correct transport protocol
  - Setting rport parameter when appropriate
  - Handling Max-Forwards decrementing

  ## Parameters
  - message: The SIP message to prepare
  - transport_opts: Transport configuration options

  ## Examples

      iex> message = Parrot.Sip.Message.new_request(:invite, "sip:bob@example.com")
      iex> opts = %{type: :udp, local_host: "alice.atlanta.com", local_port: 5060}
      iex> prepared = Parrot.Sip.Transport.prepare_message(message, opts)
      iex> via = Parrot.Sip.Message.top_via(prepared)
      iex> via.transport
      :udp
  """
  @spec prepare_message(Message.t(), transport_opts()) :: Message.t()
  def prepare_message(%Message{type: :request} = message, transport_opts) do
    # Create or update the Via header for the request
    via =
      case Message.top_via(message) do
        nil ->
          # Create a new Via header with branch
          Via.new_with_branch(
            transport_opts.local_host,
            transport_type_to_string(transport_opts.type),
            transport_opts.local_port
          )

        existing_via ->
          # Ensure the branch parameter is RFC 3261 compliant
          Via.ensure_rfc3261_branch(existing_via)
      end

    # Add rport parameter for NAT traversal if UDP
    via =
      if transport_opts.type == :udp do
        Via.with_parameter(via, "rport", "")
      else
        via
      end

    # Set Max-Forwards if not present
    headers = message.headers

    headers =
      if not Map.has_key?(headers, "max-forwards") do
        Map.put(headers, "max-forwards", 70)
      else
        headers
      end

    # Update the message with the new Via header and headers
    %{message | headers: Map.put(headers, "via", via)}
  end

  def prepare_message(%Message{type: :response} = message, _transport_opts) do
    # For responses, we don't need to add any headers - we use the
    # existing Via headers in reverse order
    message
  end

  @doc """
  Determines the appropriate connection for sending a SIP message.

  For requests, this function follows the client transport rules in RFC 3261 Section 18.1.1.
  For responses, it follows the server transport rules in RFC 3261 Section 18.2.2.

  ## Parameters
  - message: The SIP message to be sent
  - transport_opts: Transport configuration options

  ## Returns
  - `{:ok, connection_info}` with the connection details
  - `{:error, reason}` if no appropriate connection can be determined

  ## Examples

      iex> message = Parrot.Sip.Message.new_request(:invite, "sip:bob@biloxi.com")
      iex> opts = %{type: :udp, local_host: "alice.atlanta.com", local_port: 5060}
      iex> {:ok, conn} = Parrot.Sip.Transport.determine_connection(message, opts)
      iex> conn.type
      :udp
  """
  @spec determine_connection(Message.t(), transport_opts()) ::
          {:ok, connection()} | {:error, String.t()}
  def determine_connection(%Message{type: :request} = _message, transport_opts) do
    # For requests, we need to determine the next hop based on
    # Route header or Request-URI

    # TODO: Implement full connection resolution logic with DNS SRV records
    # For now, just create a basic connection based on transport options

    connection = %{
      type: transport_opts.type,
      # Will be created when actually connecting
      socket: nil,
      local_host: transport_opts.local_host,
      local_port: transport_opts.local_port || default_port_for_transport(transport_opts.type),
      remote_host: transport_opts.remote_host,
      remote_port: transport_opts.remote_port || default_port_for_transport(transport_opts.type),
      created_at: DateTime.utc_now()
    }

    {:ok, connection}
  end

  def determine_connection(%Message{type: :response} = message, transport_opts) do
    # For responses, use the top Via header to determine where to send the response
    case Message.top_via(message) do
      nil ->
        {:error, "No Via header in response"}

      via ->
        # Extract sent-by address and received/rport parameters
        {host, port} = determine_response_destination(via)

        connection = %{
          type: via_transport_to_type(via.transport),
          # Will be created when actually connecting
          socket: nil,
          local_host: transport_opts.local_host,
          local_port:
            transport_opts.local_port ||
              default_port_for_transport(via_transport_to_type(via.transport)),
          remote_host: host,
          remote_port: port,
          created_at: DateTime.utc_now()
        }

        {:ok, connection}
    end
  end

  @doc """
  Delegates source info creation to Parrot.Sip.Deserializer.

  ## Examples

      iex> Parrot.Sip.Transport.create_source(:udp, "192.168.1.100", 5060, "192.168.1.1", 5060)
      %{type: :udp, host: "192.168.1.100", port: 5060, local_host: "192.168.1.1", local_port: 5060}
  """
  @spec create_source(
          transport_type(),
          String.t(),
          non_neg_integer(),
          String.t(),
          non_neg_integer()
        ) :: source()
  def create_source(type, remote_host, remote_port, local_host, local_port) do
    Serializer.create_source_info(type, remote_host, remote_port, local_host, local_port)
  end

  @doc """
  Sends a SIP request message through the appropriate transport.

  This function:
  1. Serializes the message using the transport-specific options
  2. Determines the appropriate transport to use
  3. Sends the message through that transport

  ## Parameters
  - request: The SIP request message to send

  ## Returns
  - `:ok` if the message was sent successfully
  - `{:error, reason}` if sending failed

  ## Examples

      iex> request = Parrot.Sip.Message.new_request(:invite, "sip:bob@example.com")
      iex> Parrot.Sip.Transport.send_request(request)
      :ok
  """
  @spec send_request(Message.t()) :: :ok | {:error, String.t()}
  def send_request(%Message{} = request) do
    # Extract destination from the request URI
    case extract_destination(request) do
      {:ok, {host, port}} ->
        # Create the outbound request structure expected by UDP transport
        out_req = %{
          destination: {host, port},
          message: request
        }
        
        Parrot.Sip.Transport.Udp.send_request(out_req)
        
      {:error, reason} ->
        Logger.error("Failed to extract destination from request: #{inspect(reason)}")
        {:error, reason}
    end
  end
  
  # Extract host and port from a SIP message's request URI
  defp extract_destination(%Message{request_uri: uri}) when is_binary(uri) do
    case Parrot.Sip.Uri.parse(uri) do
      {:ok, %{host: host, port: port}} when is_binary(host) ->
        # Default SIP port is 5060
        port = port || 5060
        {:ok, {host, port}}
        
      {:ok, %{host: host}} when is_binary(host) ->
        # No port specified, use default
        {:ok, {host, 5060}}
        
      {:error, reason} ->
        {:error, reason}
        
      _ ->
        {:error, :invalid_uri}
    end
  rescue
    _ -> {:error, :uri_parse_error}
  end
  
  defp extract_destination(_), do: {:error, :no_request_uri}

  # Private helper functions

  # Converts a transport type atom to string representation
  @spec transport_type_to_string(transport_type()) :: String.t()
  defp transport_type_to_string(:udp), do: "udp"
  defp transport_type_to_string(:tcp), do: "tcp"
  defp transport_type_to_string(:tls), do: "tls"
  defp transport_type_to_string(:ws), do: "ws"
  defp transport_type_to_string(:wss), do: "wss"

  # Converts a Via transport atom to a transport type
  @spec via_transport_to_type(atom()) :: transport_type()
  defp via_transport_to_type(:udp), do: :udp
  defp via_transport_to_type(:tcp), do: :tcp
  defp via_transport_to_type(:tls), do: :tls
  defp via_transport_to_type(:ws), do: :ws
  defp via_transport_to_type(:wss), do: :wss
  # Default to UDP
  defp via_transport_to_type(_), do: :udp

  # Returns the default port for a transport type
  @spec default_port_for_transport(transport_type()) :: non_neg_integer()
  defp default_port_for_transport(:udp), do: 5060
  defp default_port_for_transport(:tcp), do: 5060
  defp default_port_for_transport(:tls), do: 5061
  defp default_port_for_transport(:ws), do: 80
  defp default_port_for_transport(:wss), do: 443

  @doc """
  Returns a URI for the local transport.
  This is used for Contact headers in requests and responses.

  ## Returns
  - The URI for the local transport

  ## Examples

      iex> uri = Parrot.Sip.Transport.local_uri()
      iex> uri.scheme
      "sip"
  """
  @spec local_uri() :: String.t()
  def local_uri() do
    # For now, return a default local URI
    # In a real implementation, this would be configurable
    "sip:#{local_host()}:#{local_port()}"
  end

  @spec local_host() :: String.t()
  defp local_host() do
    # Get the local hostname or IP
    # For now, use a default
    "localhost"
  end

  @spec local_port() :: non_neg_integer()
  defp local_port() do
    # Get the local port
    # For now, use the default SIP port
    5060
  end

  # Determines the destination for a response based on a Via header
  @spec determine_response_destination(Via.t()) :: {String.t(), non_neg_integer()}
  defp determine_response_destination(via) do
    # Check for 'received' parameter (for NAT handling)
    host =
      case Via.received(via) do
        nil -> via.host
        received -> received
      end

    # Check for 'rport' parameter (for NAT handling)
    port =
      case Via.rport(via) do
        nil ->
          via.port || default_port_for_transport(via_transport_to_type(via.transport))

        "" ->
          via.port || default_port_for_transport(via_transport_to_type(via.transport))

        rport when is_binary(rport) ->
          case Integer.parse(rport) do
            {port_num, _} -> port_num
            :error -> via.port || default_port_for_transport(via_transport_to_type(via.transport))
          end
      end

    {host, port}
  end

  # Facade functions that delegate to the StateMachine implementation

  @doc """
  Start a UDP transport.

  Delegates to the StateMachine implementation.

  ## Parameters
  - udp_start_opts: UDP transport start options

  ## Returns
  - `:ok` if successful
  - `{:error, reason}` if an error occurred
  """
  @spec start_udp(map()) :: :ok | {:error, any()}
  def start_udp(udp_start_opts) do
    TransportSM.start_udp(udp_start_opts)
  end

  @doc """
  Stop the UDP transport.

  Delegates to the StateMachine implementation.

  ## Returns
  - `:ok` if successful
  """
  @spec stop_udp() :: :ok
  def stop_udp() do
    TransportSM.stop_udp()
  end
end
