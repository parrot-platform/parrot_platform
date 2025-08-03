defmodule Parrot.Sip.HandlerAdapter do
  @moduledoc """
  Adapter between the user-friendly Handler API and the internal SIP stack.

  This module serves as the public API for the HandlerAdapter system, allowing
  user code to interface with the SIP stack through a simplified API.

  Under the hood, it uses gen_statem processes to manage the lifecycle of SIP
  transactions and dialogs, with each instance handling a single primary request.
  """

  @doc """
  Creates a new HandlerAdapter instance.

  This function creates a new Handler struct that wraps the user's handler module,
  allowing it to interface with the SIP stack's internal handler system.

  ## Parameters

  * `user_handler_module` - The module that implements the `Parrot.Handler` behaviour
  * `user_handler_state` - The initial state to pass to the user handler's callbacks

  ## Returns

  A new Handler struct that can be used with the SIP stack.

  ## Example

      {:ok, handler} = MyApp.SipHandler.start_link([])
      adapter = HandlerAdapter.new(MyApp.SipHandler, handler)
  """
  def new(user_handler_module, user_handler_state) do
    Parrot.Sip.HandlerAdapter.Core.new(user_handler_module, user_handler_state)
  end

  @doc """
  Returns a child specification for starting this adapter under a supervisor.

  This function conforms to the OTP child specification and is used when the
  HandlerAdapter is added to a supervision tree.

  ## Parameters

  * `args` - Arguments to pass to the `start_link/1` function

  ## Returns

  A child specification map compatible with supervisors.

  ## Example

      Supervisor.start_child(MySupervisor, HandlerAdapter.child_spec(args))
  """
  def child_spec(args) do
    Parrot.Sip.HandlerAdapter.Core.child_spec(args)
  end

  @doc """
  Starts a new HandlerAdapter process.

  Initializes a new gen_statem process that will handle a single SIP transaction,
  interfacing between the user's handler module and the internal SIP stack.

  ## Parameters

  * `args` - A tuple containing the user's handler module and state

  ## Returns

  `{:ok, pid}` if the process was started successfully, or `{:error, reason}` if it failed.

  This function is typically called by the HandlerAdapterSupervisor rather than directly.
  """
  def start_link(args) do
    Parrot.Sip.HandlerAdapter.Core.start_link(args)
  end
end
