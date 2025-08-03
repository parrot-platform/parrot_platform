defmodule Parrot.Application do
  use Application

  def start(_type, _args) do
    Parrot.Config.init()

    handler_module = ParrotSupport.SipHandler
    handler_state = %{}
    Application.put_env(:parrot, :sip_handler, {handler_module, handler_state})

    children = [
      {Registry, keys: :unique, name: Parrot.Registry},
      Parrot.Sip.Transport.Supervisor,
      Parrot.Sip.Transaction.Supervisor,
      Parrot.Sip.Dialog.Supervisor,
      Parrot.Sip.HandlerAdapter.Supervisor,
      Parrot.Media.MediaSessionSupervisor
    ]

    opts = [strategy: :one_for_one, name: Parrot.Supervisor]
    Supervisor.start_link(children, opts)
  end
end
