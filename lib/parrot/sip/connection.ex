defmodule Parrot.Sip.Connection do
  @moduledoc """
  SIP Connection module.

  Describes one SIP connection from a source and handles message parsing and processing.
  This module replaces the ERSIP `ersip_conn` module with a pure Elixir implementation.
  """

  alias Parrot.Sip.Serializer
  alias Parrot.Sip.Message
  alias Parrot.Sip.Headers.Via
  alias Parrot.Sip.Source

  @typedoc """
  Represents a SIP connection
  """
  @type t :: %__MODULE__{
          local_addr: {:inet.ip_address(), :inet.port_number()},
          remote_addr: {:inet.ip_address(), :inet.port_number()},
          transport: atom(),
          options: map()
        }

  @typedoc """
  Message outcome represents an action that should be taken based on received data
  """
  @type message_outcome ::
          {:new_request, Message.t()}
          | {:new_response, Via.t(), Message.t()}
          | {:bad_message, binary() | Message.t(), term()}

  defstruct [
    :local_addr,
    :remote_addr,
    :transport,
    :options
  ]

  @doc """
  Creates a new SIP connection.

  ## Parameters
  - `local_addr`: Local IP address
  - `local_port`: Local port number
  - `remote_addr`: Remote IP address
  - `remote_port`: Remote port number
  - `transport`: SIP transport type (e.g., `:udp`, `:tcp`, `:tls`)
  - `options`: Additional options for the connection

  ## Returns
  - `t()`: A new connection struct
  """
  @spec new(
          local_addr :: :inet.ip_address(),
          local_port :: :inet.port_number(),
          remote_addr :: :inet.ip_address(),
          remote_port :: :inet.port_number(),
          transport :: atom(),
          options :: map()
        ) :: t()
  def new(local_addr, local_port, remote_addr, remote_port, transport, options \\ %{}) do
    _is_datagram = is_message_oriented(transport)

    %__MODULE__{
      local_addr: {local_addr, local_port},
      remote_addr: {remote_addr, remote_port},
      transport: transport,
      options: options
    }
  end

  @doc """
  Processes connection data and returns the connection and message outcomes.

  ## Parameters
  - `data`: Binary data received from the connection
  - `conn`: Connection struct

  ## Returns
  - `{t(), [message_outcome()]}`: Updated connection and list of message outcomes
  """
  def conn_data(data, %__MODULE__{transport: :udp} = conn) do
    # Datagram transport (UDP)
    case Serializer.decode(data) do
      {:ok, message} ->
        receive_raw(message, conn)

      {:error, reason} ->
        {conn, {:bad_message, data, reason}}
    end
  end

  def conn_data(data, %__MODULE__{} = conn) do
    # Stream transport (TCP, TLS)
    # Not implemented yet - focus on UDP for now
    {conn, {:bad_message, data, :stream_transport_not_implemented}}
  end

  @doc """
  Creates a source struct from the connection.

  ## Parameters
  - `conn`: Connection struct

  ## Returns
  - `Source.t()`: Source information
  """
  @spec source(t()) :: Source.t()
  def source(%__MODULE__{
        local_addr: local,
        remote_addr: remote,
        transport: transport,
        options: opts
      }) do
    source_id = Map.get(opts, :source_id)
    Source.new(local, remote, transport, source_id)
  end

  # Private functions

  # Process a parsed message based on its type (request or response)
  defp receive_raw(message, conn) do
    case message.type do
      :request -> receive_request(message, conn)
      :response -> receive_response(message, conn)
      _ -> {conn, {:bad_message, message, :unknown_message_type}}
    end
  end

  # Process a request message
  @spec receive_request(Message.t(), t()) :: {t(), [message_outcome()]}
  defp receive_request(message, conn) do
    case process_request_via(message, conn) do
      {:ok, new_message} ->
        message_with_source = %{new_message | source: source(conn)}
        {conn, {:new_request, message_with_source}}

      {:error, reason} ->
        {conn, {:bad_message, message, reason}}
    end
  end

  # Process a response message
  @spec receive_response(Message.t(), t()) :: {t(), [message_outcome()]}
  defp receive_response(message, conn) do
    # For now, we'll just pass the response through
    # In a complete implementation, we would take the top Via header
    # and verify it matches our local address
    message_with_source = %{message | source: source(conn)}
    {conn, {:new_response, nil, message_with_source}}
  end

  # Process the Via header in a request
  @spec process_request_via(Message.t(), t()) :: {:ok, Message.t()} | {:error, term()}
  defp process_request_via(message, conn) do
    case Message.get_header(message, "via") do
      nil ->
        {:error, :no_via}

      via ->
        updated_via =
          via
          |> maybe_add_received(conn)
          |> maybe_fill_rport(conn)

        updated_message = Message.set_header(message, "via", updated_via)
        {:ok, updated_message}
    end
  end

  # Add received parameter if necessary
  @spec maybe_add_received(Via.t(), t()) :: Via.t()
  defp maybe_add_received(via, %__MODULE__{remote_addr: {remote_ip, _}}) do
    # Always add received parameter for simplicity
    # A more complete implementation would check the sent-by field
    Via.with_parameter(via, "received", :inet.ntoa(remote_ip) |> List.to_string())
  end

  # Add rport parameter if necessary
  @spec maybe_fill_rport(Via.t(), t()) :: Via.t()
  defp maybe_fill_rport(via, %__MODULE__{remote_addr: {_, remote_port}}) do
    # If rport parameter exists (with or without value), set it to the remote port
    # RFC 3581:
    # When a server compliant to this specification (which can be a proxy
    # or UAS) receives a request, it examines the topmost Via header field
    # value.  If this Via header field value contains an "rport" parameter
    # with no value, it MUST set the value of the parameter to the source
    # port of the request.  This is analogous to the way in which a server
    # will insert the "received" parameter into the topmost Via header
    # field value.  In fact, the server MUST insert a "received" parameter
    # containing the source IP address that the request came from, even if
    # it is identical to the value of the "sent-by" component.  Note that
    # this processing takes place independent of the transport protocol.
    if Via.has_parameter?(via, "rport") do
      Via.with_parameter(via, "rport", Integer.to_string(remote_port))
    else
      via
    end
  end

  # Check if transport is message-oriented (datagram)
  @spec is_message_oriented(atom()) :: boolean()
  defp is_message_oriented(:udp), do: true
  defp is_message_oriented(_), do: false
end
