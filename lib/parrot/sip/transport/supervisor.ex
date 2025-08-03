defmodule Parrot.Sip.Transport.Supervisor do
  @moduledoc """
  Parrot SIP Stack
  Transport Supervisor
  """

  use Supervisor

  def start_link(args) do
    Supervisor.start_link(__MODULE__, args, name: __MODULE__)
  end

  @impl true
  def init(_args) do
    children = [
      {Parrot.Sip.Transport.StateMachine, []}
    ]

    Supervisor.init(children, strategy: :one_for_one)
  end
end
