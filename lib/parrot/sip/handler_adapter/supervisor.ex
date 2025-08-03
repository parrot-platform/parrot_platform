defmodule Parrot.Sip.HandlerAdapter.Supervisor do
  @moduledoc """
  Supervisor for HandlerAdapter instances.

  This supervisor manages the lifecycle of HandlerAdapter processes, each of which
  handles a single SIP transaction. It uses a DynamicSupervisor to create and
  manage these short-lived processes.
  """
  use DynamicSupervisor

  @doc """
  Starts the HandlerAdapter supervisor.

  ## Parameters

  * `args` - Initialization arguments (typically empty)

  ## Returns

  `{:ok, pid}` if the supervisor starts successfully, or `{:error, reason}` if it fails.
  """
  def start_link(args) do
    DynamicSupervisor.start_link(__MODULE__, args, name: __MODULE__)
  end

  @doc """
  Starts a new HandlerAdapter child process.

  ## Parameters

  * `args` - A tuple containing `{user_handler_module, user_handler_state}`

  ## Returns

  `{:ok, pid}` if the child process starts successfully, or `{:error, reason}` if it fails.
  """
  def start_child(args) do
    # Args will be {user_handler_module, user_handler_state}
    spec = {Parrot.Sip.HandlerAdapter.Core, args}
    DynamicSupervisor.start_child(__MODULE__, spec)
  end

  @impl true
  def init([]) do
    DynamicSupervisor.init(
      # Each adapter instance is independent
      strategy: :one_for_one,
      max_restarts: 5,
      max_seconds: 10
    )
  end
end
