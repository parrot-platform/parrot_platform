defmodule Parrot.Sip.Transport.StateMachine do
  @moduledoc """
  Parrot SIP Stack Transport State Machine

  This GenServer manages the transport layer for SIP messages, coordinating
  UDP transport instances and providing a unified interface for message
  sending and receiving.
  """

  use GenServer
  require Logger
  alias Parrot.Sip.Transport.Udp

  @type start_opts :: Udp.start_opts()

  defstruct [
    :udp_pid,
    :supervisor_pid,
    :state
  ]

  @type t :: %__MODULE__{
          udp_pid: pid() | nil,
          supervisor_pid: pid() | nil,
          state: :idle | :running
        }

  def child_spec(args) do
    start_args =
      case args do
        [] -> []
        _ when is_list(args) and length(args) == 1 and is_list(hd([args])) -> hd([args])
        _ -> args
      end

    %{
      id: __MODULE__,
      start: {__MODULE__, :start_link, start_args},
      type: :worker,
      restart: :permanent,
      shutdown: 5000
    }
  end

  @spec start_link(list()) :: GenServer.on_start()
  def start_link(args \\ []) do
    GenServer.start_link(__MODULE__, args, name: __MODULE__)
  end

  @spec start_udp(start_opts()) :: :ok | {:error, term()}
  def start_udp(udp_start_opts) do
    GenServer.call(__MODULE__, {:start_udp, udp_start_opts})
  end

  @spec stop_udp() :: :ok
  def stop_udp do
    GenServer.call(__MODULE__, :stop_udp)
  end

  @spec local_uri() :: {:ok, String.t()} | {:error, term()}
  def local_uri do
    GenServer.call(__MODULE__, :local_uri)
  end

  @spec send_request(map()) :: :ok | {:error, term()}
  def send_request(out_req) do
    GenServer.call(__MODULE__, {:send_request, out_req})
  end

  # GenServer callbacks

  @impl true
  def init(args) do
    Logger.debug("Transport.StateMachine starting with args: #{inspect(args)}")

    state = %__MODULE__{
      udp_pid: nil,
      supervisor_pid: nil,
      state: :idle
    }

    {:ok, state}
  end

  @impl true
  def handle_call({:start_udp, udp_opts}, _from, state) do
    Logger.debug("Starting UDP transport with opts: #{inspect(udp_opts)}")

    try do
      case state.udp_pid do
        nil ->
          # Catch the exit when UDP fails to start
          result =
            try do
              Udp.start_link(udp_opts)
            catch
              :exit, {{:error, reason}, _} ->
                # Handle case where Udp.start_link fails during init with {:stop, error}
                # The exit has a tuple format: {{:error, reason}, call_info}
                {:error, reason}

              :exit, {:error, reason} ->
                # Handle simpler error format
                {:error, reason}

              :exit, reason ->
                # Handle other exit reasons
                Logger.debug("Caught exit with reason: #{inspect(reason)}")
                {:error, {:exit, reason}}
            end

          case result do
            {:ok, pid} ->
              Logger.debug("UDP transport started with PID: #{inspect(pid)}")
              new_state = %{state | udp_pid: pid, state: :running}
              {:reply, :ok, new_state}

            {:error, {:already_started, pid}} ->
              Logger.debug("UDP transport already started with PID: #{inspect(pid)}")
              new_state = %{state | udp_pid: pid, state: :running}
              {:reply, {:error, {:already_started, pid}}, new_state}

            {:error, reason} = error ->
              Logger.warning("Failed to start UDP transport: #{inspect(reason)}")
              {:reply, error, state}
          end

        pid when is_pid(pid) ->
          Logger.debug("UDP transport already running with PID: #{inspect(pid)}")
          {:reply, {:error, {:already_started, pid}}, state}
      end
    catch
      kind, reason ->
        Logger.error("Unexpected error in start_udp: #{inspect({kind, reason})}")
        {:reply, {:error, reason}, state}
    end
  end

  @impl true
  def handle_call(:stop_udp, _from, state) do
    Logger.debug("Stopping UDP transport")

    case state.udp_pid do
      nil ->
        Logger.debug("No UDP transport to stop")
        {:reply, :ok, state}

      pid when is_pid(pid) ->
        if Process.alive?(pid) do
          GenServer.stop(pid)
          Logger.debug("UDP transport stopped")
        end

        new_state = %{state | udp_pid: nil, state: :idle}
        {:reply, :ok, new_state}
    end
  end

  @impl true
  def handle_call(:local_uri, _from, state) do
    case state.udp_pid do
      nil ->
        Logger.warning("No UDP transport running")
        {:reply, {:error, :no_transport}, state}

      pid when is_pid(pid) ->
        try do
          uri = Udp.local_uri()
          {:reply, {:ok, uri}, state}
        catch
          :exit, reason ->
            Logger.warning("Failed to get local URI: #{inspect(reason)}")
            {:reply, {:error, reason}, state}
        end
    end
  end

  @impl true
  def handle_call({:send_request, out_req}, _from, state) do
    case state.udp_pid do
      nil ->
        Logger.warning("No UDP transport running")
        {:reply, {:error, :no_transport}, state}

      pid when is_pid(pid) ->
        try do
          result = Udp.send_request(out_req)
          {:reply, result, state}
        catch
          :exit, reason ->
            Logger.warning("Failed to send request: #{inspect(reason)}")
            {:reply, {:error, reason}, state}
        end
    end
  end

  @impl true
  def handle_call(request, _from, state) do
    Logger.warning("Unexpected call: #{inspect(request)}")
    {:reply, {:error, {:unexpected_call, request}}, state}
  end

  @impl true
  def handle_cast(request, state) do
    Logger.warning("Unexpected cast: #{inspect(request)}")
    {:noreply, state}
  end

  @impl true
  def handle_info({:DOWN, _ref, :process, pid, reason}, %{udp_pid: pid} = state) do
    Logger.warning("UDP transport process #{inspect(pid)} terminated: #{inspect(reason)}")
    new_state = %{state | udp_pid: nil, state: :idle}
    {:noreply, new_state}
  end

  @impl true
  def handle_info(msg, state) do
    Logger.warning("Unexpected info: #{inspect(msg)}")
    {:noreply, state}
  end

  @impl true
  def terminate(reason, state) do
    Logger.debug("Transport.StateMachine terminating: #{inspect(reason)}")

    if state.udp_pid && Process.alive?(state.udp_pid) do
      GenServer.stop(state.udp_pid)
    end

    :ok
  end
end
