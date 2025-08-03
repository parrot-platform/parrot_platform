defmodule Parrot.Supervisor do
  use Supervisor

  alias Parrot.Sip.TransactionSupervisor

  def start_link(_args) do
    Supervisor.start_link(__MODULE__, :ok, name: __MODULE__)
  end

  @impl true
  def init(:ok) do
    children = [
      {Registry, keys: :unique, name: Parrot.Registry},
      TransactionSupervisor
      # Add other supervisors or workers here
    ]

    Supervisor.init(children, strategy: :one_for_one)
  end
end
