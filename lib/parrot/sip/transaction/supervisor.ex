defmodule Parrot.Sip.Transaction.Supervisor do
  use DynamicSupervisor

  def start_link(args) do
    DynamicSupervisor.start_link(__MODULE__, args, name: __MODULE__)
  end

  def start_child(args) do
    spec = {Parrot.Sip.TransactionStatem, args}
    DynamicSupervisor.start_child(__MODULE__, spec)
  end

  def num_active do
    DynamicSupervisor.count_children(__MODULE__)[:active]
  end

  @impl true
  def init([]) do
    DynamicSupervisor.init(
      strategy: :one_for_one,
      max_restarts: 1000,
      max_seconds: 1
    )
  end
end
