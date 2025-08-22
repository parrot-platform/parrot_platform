defmodule Parrot.Sip.Transport.Udp do
  @moduledoc """
  Parrot SIP Stack
  UDP Transport
  """

  use GenServer
  require Logger

  alias Parrot.Sip.TransactionStatem
  alias Parrot.Sip.Handler
  alias Parrot.Sip.Transport.{Source, Inet}

  @behaviour Source

  @server __MODULE__

  defmodule State do
    @moduledoc false
    defstruct [
      # :inet.ip_address()
      :local_ip,
      # :inet.port_number()
      :local_port,
      # :gen_udp.socket()
      :socket,
      # Handler.handler() | nil
      :handler,
      # boolean()
      :sip_trace,
      # non_neg_integer()
      :max_burst
    ]

    @type t :: %__MODULE__{
            local_ip: :inet.ip_address() | nil,
            local_port: :inet.port_number() | nil,
            socket: :gen_udp.socket() | nil,
            handler: Handler.handler() | nil,
            sip_trace: boolean() | nil,
            max_burst: non_neg_integer()
          }
  end

  @type start_opts :: %{
          optional(:listen_addr) => :inet.ip_address(),
          optional(:listen_port) => :inet.port_number(),
          optional(:exposed_addr) => :inet.ip_address(),
          optional(:exposed_port) => :inet.port_number(),
          optional(:handler) => Handler.handler(),
          optional(:sip_trace) => boolean(),
          optional(:max_burst) => non_neg_integer()
        }

  @type source_options :: {:inet.ip_address(), :inet.port_number()}

  # API

  @spec start_link(start_opts()) :: GenServer.on_start()
  def start_link(start_opts) do
    # Check if already running
    case Process.whereis(@server) do
      nil ->
        GenServer.start_link(__MODULE__, start_opts, name: @server)

      pid ->
        {:error, {:already_started, pid}}
    end
  end

  @spec stop() :: :ok
  def stop, do: GenServer.stop(@server)

  @spec set_handler(Handler.handler()) :: :ok
  def set_handler(handler), do: GenServer.call(@server, {:set_handler, handler})

  @spec local_uri() :: String.t()
  def local_uri, do: GenServer.call(@server, :local_uri)

  @spec send_request(map()) :: :ok
  def send_request(out_req) do
    GenServer.call(@server, {:send_request, out_req})
  end

  # Source callbacks

  @impl Source
  @spec send_response(Parrot.Sip.Message.t(), Parrot.Sip.Source.t()) :: :ok
  def send_response(sip_msg, %Parrot.Sip.Source{remote: {remote_addr, remote_port}} = _source) do
    GenServer.call(@server, {:send_response, sip_msg, {remote_addr, remote_port}})
  end

  # GenServer callbacks

  @impl true
  def init(start_opts) do
    # ip_address =
    #   Map.get(start_opts, :listen_addr, Inet.first_non_loopack_address())
    ip_address =
      Map.get(start_opts, :listen_addr, Inet.first_ipv4_address())

    port = Map.get(start_opts, :listen_port, 5060)
    Logger.notice("udp port: starting at #{:inet.ntoa(ip_address)}:#{port}")

    exposed_ip = Map.get(start_opts, :exposed_addr, ip_address)
    exposed_port = Map.get(start_opts, :exposed_port, port)
    handler = Map.get(start_opts, :handler)
    max_burst = Map.get(start_opts, :max_burst, 10)

    Logger.notice("udp port: using #{:inet.ntoa(exposed_ip)}:#{exposed_port} as external address")

    case :gen_udp.open(port, [:binary, {:ip, ip_address}, {:active, max_burst}]) do
      {:error, _} = error ->
        Logger.error("udp port: failed to open port: #{inspect(error)}")
        {:stop, error}

      {:ok, socket} ->
        # Get sip_trace from handler config if available, otherwise from start_opts
        sip_trace =
          case handler do
            %{sip_trace: true} -> true
            %{sip_trace: false} -> false
            _ -> Map.get(start_opts, :sip_trace, false)
          end

        state = %State{
          local_ip: exposed_ip,
          local_port: exposed_port,
          socket: socket,
          handler: handler,
          sip_trace: sip_trace,
          max_burst: max_burst
        }

        {:ok, state}
    end
  end

  @impl true
  def handle_call({:set_handler, handler}, _from, state) do
    {:reply, :ok, %State{state | handler: handler}}
  end

  def handle_call(:local_uri, _from, %State{local_ip: local_ip, local_port: local_port} = state) do
    uri = "sip:#{:inet.ntoa(local_ip)}:#{local_port}"
    {:reply, uri, state}
  end

  def handle_call({:send_request, out_req}, _from, state) do
    result = do_send_request(out_req, state)
    {:reply, result, state}
  end

  def handle_call({:send_response, sip_msg, {remote_addr, remote_port}}, _from, state) do
    result = do_send_response(sip_msg, {remote_addr, remote_port}, state)
    {:reply, result, state}
  end

  def handle_call(:send_opts, _from, state) do
    send_opts = %{
      exposed_addr: state.local_ip,
      exposed_port: state.local_port,
      sip_trace: state.sip_trace,
      socket: state.socket
    }

    {:reply, send_opts, state}
  end

  def handle_call(request, _from, state) do
    Logger.warning("udp port: unexpected call: #{inspect(request)}")
    {:reply, {:error, {:unexpected_call, request}}, state}
  end

  @impl true
  def handle_cast(request, state) do
    Logger.warning("udp port: unexpected cast: #{inspect(request)}")
    {:noreply, state}
  end

  @impl true
  def handle_info({:udp, socket, ip, port, msg}, %State{socket: socket} = state) do
    if state.sip_trace do
      Logger.info("[SIP TRACE] udp port: recv: #{:inet.ntoa(ip)}:#{port}\n#{msg}")
    end

    recv_message(ip, port, msg, state)
    {:noreply, state}
  end

  def handle_info({:udp_passive, socket}, %State{socket: socket} = state) do
    :ok = :inet.setopts(socket, [{:active, state.max_burst}])
    {:noreply, state}
  end

  def handle_info(msg, state) do
    Logger.warning("udp port: unexpected info: #{inspect(msg)}")
    {:noreply, state}
  end

  @impl true
  def terminate(:normal, %State{socket: socket}) do
    Logger.notice("udp port: stopped")
    :gen_udp.close(socket)
  end

  def terminate(reason, %State{socket: socket}) do
    Logger.error("udp port: stopped with reason #{inspect(reason)}")
    :gen_udp.close(socket)
  end

  @impl true
  def code_change(_old_vsn, state, _extra), do: {:ok, state}

  # Internal implementation

  # Helper to log with appropriate level
  # The handler's log_level acts as a minimum threshold, not an override
  defp log(_state, level, message) do
    # Use the intended level - handler's log_level is handled by Logger configuration
    Logger.log(level, message)
  end

  @spec recv_message(:inet.ip_address(), :inet.port_number(), binary(), State.t()) :: :ok
  defp recv_message(remote_ip, remote_port, message, state) do
    source_opts = make_source_options(remote_ip, remote_port)
    source_id = Source.make_source_id(__MODULE__, source_opts)

    conn =
      Parrot.Sip.Connection.new(
        state.local_ip,
        state.local_port,
        remote_ip,
        remote_port,
        :udp,
        %{source_id: source_id}
      )

    {_, result} = Parrot.Sip.Connection.conn_data(message, conn)

    # Connection.conn_data returns a message_outcome directly
    handle_message_outcome(result, state)

    :ok
  end

  @spec handle_message_outcome(term(), State.t()) :: :ok
  defp handle_message_outcome({:bad_message, data, error}, _state) when is_binary(data) do
    Logger.warning("udp port: bad message received: #{inspect(error)}\n#{data}")
    :ok
  end

  defp handle_message_outcome({:bad_message, data, error}, _state) do
    Logger.warning("udp port: bad message received: #{inspect(error)}\n#{inspect(data)}")
    :ok
  end

  defp handle_message_outcome({:new_request, %Parrot.Sip.Message{} = msg}, state) do
    unless state.sip_trace do
      log(state, :debug, "udp port: recv request: #{msg.method} #{msg.request_uri}")
    end

    case state.handler do
      nil ->
        log(state, :warning, "udp port: no handlers defined for requests")
        # Send 503, expect that handler will appear
        unavailable_resp(msg)
        :ok

      handler ->
        log(state, :debug, "we have a handler for this request")

        case Handler.transp_request(msg, handler) do
          :noreply ->
            log(state, :debug, "Handler.transp_request returned :noreply")
            :ok

          :process_transaction ->
            log(state, :debug, "Handler.transp_request returned :process_transaction")
            log(state, :debug, "spawning Transaction.server_process in new Task process")

            Task.start(fn ->
              TransactionStatem.server_process(msg, handler)
            end)
        end
    end
  end

  defp handle_message_outcome({:new_response, _via, %Parrot.Sip.Message{} = msg}, state) do
    log(state, :debug, "udp port: recv response: #{msg.status_code} #{msg.reason_phrase}")

    # Extract the topmost Via header to route to the correct transaction
    via =
      case msg.headers["via"] do
        [v | _] when is_map(v) -> v
        v when is_map(v) -> v
        _ -> nil
      end

    if via do
      # Route the response to the transaction state machine
      TransactionStatem.client_response(via, Parrot.Sip.Message.to_binary(msg))
    else
      log(state, :warning, "Response has no Via header, cannot route to transaction")
    end

    # Also call the handler's transp_response if it exists
    case state.handler do
      %{module: mod, args: args} when not is_nil(mod) ->
        if function_exported?(mod, :transp_response, 2) do
          mod.transp_response(msg, args)
        end

      _ ->
        :ok
    end

    :ok
  end

  defp handle_message_outcome(other, _state) do
    Logger.debug("udp port: unhandled message outcome: #{inspect(other)}")
    :ok
  end

  @spec make_source_options(:inet.ip_address(), :inet.port_number()) :: source_options()
  defp make_source_options(ip_addr, port), do: {ip_addr, port}

  @spec unavailable_resp(Parrot.Sip.Message.t()) :: :ok
  defp unavailable_resp(_msg) do
    # Create a 503 Service Unavailable response
    Logger.debug("Sending 503 Service Unavailable response")
    :ok
  end

  @spec do_send_request(map(), State.t()) :: :ok
  defp do_send_request(out_req, state) do
    # Extract destination from the outbound request
    case Map.get(out_req, :destination) do
      {host, port} when is_binary(host) and is_integer(port) ->
        # Parse host to IP if needed
        {remote_addr, remote_port} = resolve_destination(host, port)

        # Get the message to send
        message = Map.get(out_req, :message)
        raw_message = Parrot.Sip.Message.to_binary(message)

        if state.sip_trace do
          # Log at info level with special metadata
          Logger.info(
            "[SIP TRACE] udp port: sent: #{:inet.ntoa(remote_addr)}:#{remote_port}\n#{raw_message}",
            sip_trace: true
          )
        end

        # Send the UDP packet
        case :gen_udp.send(state.socket, remote_addr, remote_port, raw_message) do
          :ok ->
            # Regular logging handled by sip_trace above
            :ok

          {:error, reason} ->
            Logger.warning("udp port: failed to send request: #{inspect(reason)}")
            :ok
        end

      _ ->
        Logger.warning("udp port: invalid destination in outbound request")
        {:error, :invalid_destination}
    end
  end

  @spec do_send_response(Parrot.Sip.Message.t(), source_options(), State.t()) :: :ok
  defp do_send_response(sip_msg, {remote_addr, remote_port}, state) do
    raw_message = Parrot.Sip.Message.to_binary(sip_msg)

    if state.sip_trace do
      # Log at info level with special metadata
      Logger.info(
        "[SIP TRACE] udp port: sent: #{:inet.ntoa(remote_addr)}:#{remote_port}\n#{raw_message}",
        sip_trace: true
      )
    end

    case :gen_udp.send(state.socket, remote_addr, remote_port, raw_message) do
      :ok ->
        # Regular logging handled by sip_trace above
        :ok

      {:error, reason} ->
        Logger.warning("udp port: failed to send response: #{inspect(reason)}")
        :ok
    end
  end

  @spec resolve_destination(String.t(), integer()) :: {:inet.ip_address(), integer()}
  defp resolve_destination(host, port) do
    case :inet.parse_address(String.to_charlist(host)) do
      {:ok, ip} ->
        {ip, port}

      {:error, _} ->
        # Try DNS resolution
        case :inet.gethostbyname(String.to_charlist(host)) do
          {:ok, {:hostent, _name, _aliases, :inet, _length, [ip | _]}} ->
            {ip, port}

          _ ->
            Logger.warning("DNS lookup failed for #{host}, using localhost")
            {{127, 0, 0, 1}, port}
        end
    end
  end
end
