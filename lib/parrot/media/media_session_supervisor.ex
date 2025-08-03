defmodule Parrot.Media.MediaSessionSupervisor do
  @moduledoc """
  Supervisor for MediaSession processes.

  This supervisor manages all active media sessions using a simple_one_for_one
  strategy, allowing dynamic creation of media sessions as needed.
  """

  use DynamicSupervisor

  require Logger

  @doc """
  Starts the MediaSession supervisor.
  """
  @spec start_link(keyword()) :: Supervisor.on_start()
  def start_link(opts \\ []) do
    DynamicSupervisor.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  Starts a new MediaSession under this supervisor.

  ## Options

  - `:id` - Session ID (required)
  - `:dialog_id` - Dialog ID this session belongs to (required)
  - `:role` - `:uac` or `:uas` (required)
  - `:owner` - Owner process PID (optional, defaults to caller)
  - `:audio_file` - Path to audio file to play (optional)
  """
  @spec start_session(keyword()) :: DynamicSupervisor.on_start_child()
  def start_session(opts) do
    case validate_opts(opts) do
      :ok ->
        spec = {Parrot.Media.MediaSession, opts}
        DynamicSupervisor.start_child(__MODULE__, spec)

      {:error, reason} ->
        {:error, {:invalid_opts, reason}}
    end
  end

  @doc """
  Stops a MediaSession.
  """
  @spec stop_session(pid()) :: :ok | {:error, :not_found}
  def stop_session(pid) when is_pid(pid) do
    DynamicSupervisor.terminate_child(__MODULE__, pid)
  end

  @doc """
  Lists all active MediaSession processes.
  """
  @spec list_sessions() :: [pid()]
  def list_sessions do
    children = DynamicSupervisor.which_children(__MODULE__)

    for {_, pid, :worker, _} <- children, is_pid(pid) do
      pid
    end
  end

  @doc """
  Counts the number of active MediaSession processes.
  """
  @spec count_sessions() :: non_neg_integer()
  def count_sessions do
    DynamicSupervisor.count_children(__MODULE__).active
  end

  @doc """
  Finds a MediaSession by its ID.
  """
  @spec find_session(String.t()) :: {:ok, pid()} | {:error, :not_found}
  def find_session(session_id) when is_binary(session_id) do
    case Registry.lookup(Parrot.Registry, {:media_session, session_id}) do
      [{pid, _}] -> {:ok, pid}
      [] -> {:error, :not_found}
    end
  end

  # Callbacks

  @impl true
  def init(_opts) do
    Logger.info("MediaSessionSupervisor starting")
    DynamicSupervisor.init(strategy: :one_for_one)
  end

  # Private functions

  defp validate_opts(opts) do
    with :ok <- validate_required(opts, :id),
         :ok <- validate_required(opts, :dialog_id),
         :ok <- validate_role(opts) do
      :ok
    end
  end

  defp validate_required(opts, key) do
    if Keyword.has_key?(opts, key) do
      :ok
    else
      {:error, {:missing_required_option, key}}
    end
  end

  defp validate_role(opts) do
    case Keyword.get(opts, :role) do
      :uac -> :ok
      :uas -> :ok
      nil -> {:error, {:missing_required_option, :role}}
      other -> {:error, {:invalid_role, other}}
    end
  end
end
