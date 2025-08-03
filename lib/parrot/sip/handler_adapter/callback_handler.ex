defmodule Parrot.Sip.HandlerAdapter.CallbackHandler do
  @moduledoc """
  Functions for calling user handler callbacks.

  This module provides helper functions for calling the appropriate
  handler function in a user's handler module.
  """

  require Logger

  @doc """
  Calls the appropriate method handler in the user's handler module.

  This function dynamically determines which handler function to call based on the
  SIP method (e.g., INVITE, OPTIONS) and calls it with the request map and user state.

  If the method handler doesn't exist in the user's module, a default 501 Not Implemented
  response is returned.

  ## Parameters

    * `handler_module` - The user's handler module
    * `method_str_or_atom` - The SIP method as a string or atom (e.g., "INVITE", :invite)
    * `request_map` - The request map containing the parsed SIP request
    * `user_handler_state` - The user's handler state to pass to the handler

  ## Returns

  The return value from the user's handler function, or a default 501 response if
  no handler is found.
  """
  def call_method_handler(handler_module, method_str_or_atom, sip_msg, user_handler_state) do
    method_name_lower = String.downcase(to_string(method_str_or_atom))
    handler_fun = String.to_atom("handle_#{method_name_lower}")

    Logger.debug(
      "HandlerAdapter: Attempting to call user handler: #{inspect(handler_module)}.#{handler_fun}/2"
    )

    if function_exported?(handler_module, handler_fun, 2) do
      apply(handler_module, handler_fun, [sip_msg, user_handler_state])
    else
      Logger.warning(
        "HandlerAdapter: User method handler #{handler_fun}/2 not found in #{inspect(handler_module)}. Defaulting."
      )

      # Default response for unhandled methods
      {:respond, 501, "Not Implemented by User Handler", %{}, ""}
    end
  end

  @doc """
  Calls the appropriate transaction state handler in the user's handler module.

  This function dynamically determines which transaction handler to call based on the
  SIP method and transaction state (e.g., handle_transaction_invite_trying).

  If the transaction handler doesn't exist, it falls back to the basic method handler.

  ## Parameters

    * `handler_module` - The user's handler module
    * `method_str_or_atom` - The SIP method as a string or atom (e.g., "INVITE")
    * `trans_state_atom` - The transaction state as an atom (e.g., :trying, :proceeding)
    * `request_map` - The request map containing the parsed SIP request
    * `transaction_obj` - The transaction object to pass to the handler
    * `user_handler_state` - The user's handler state to pass to the handler

  ## Returns

  The return value from the user's transaction handler function, or from the fallback
  method handler if no transaction handler is found.
  """
  def call_transaction_handler(
        handler_module,
        method,
        trans_state_atom,
        # TODO: deprecate request_map
        request_map,
        transaction_obj,
        user_handler_state
      ) do
    method_name_lower = to_string(method)
    trans_state_str = Atom.to_string(trans_state_atom)
    handler_fun = String.to_atom("handle_transaction_#{method_name_lower}_#{trans_state_str}")

    Logger.debug(
      "HandlerAdapter: Attempting to call user transaction handler: #{inspect(handler_module)}.#{handler_fun}/3"
    )

    if function_exported?(handler_module, handler_fun, 3) do
      Logger.debug("HandlerAdapter: User transaction handler #{handler_fun}/3 found. Running it.")
      apply(handler_module, handler_fun, [request_map, transaction_obj, user_handler_state])
    else
      Logger.debug(
        "HandlerAdapter: User transaction handler #{handler_fun}/3 not found. Falling back to method handler."
      )

      # Fall back to the basic method handler if transaction-specific one isn't found
      call_method_handler(handler_module, method, request_map, user_handler_state)
    end
  end

  @doc """
  Calls the appropriate dialog state handler in the user's handler module.

  This function dynamically determines which dialog handler to call based on the
  dialog state (e.g., handle_dialog_early, handle_dialog_confirmed).

  If the dialog handler doesn't exist, it defaults to returning :noreply.

  ## Parameters

    * `handler_module` - The user's handler module
    * `dialog_state_atom` - The dialog state as an atom (e.g., :early, :confirmed)
    * `request_map` - The request map containing the parsed SIP request
    * `dialog_obj` - The dialog object to pass to the handler
    * `user_handler_state` - The user's handler state to pass to the handler

  ## Returns

  The return value from the user's dialog handler function, or :noreply if
  no dialog handler is found.
  """
  def call_dialog_handler(
        handler_module,
        dialog_state_atom,
        request_map,
        dialog_obj,
        user_handler_state
      ) do
    dialog_state_str = Atom.to_string(dialog_state_atom)
    handler_fun = String.to_atom("handle_dialog_#{dialog_state_str}")

    Logger.debug(
      "HandlerAdapter: Attempting to call user dialog handler: #{inspect(handler_module)}.#{handler_fun}/3"
    )

    if function_exported?(handler_module, handler_fun, 3) do
      apply(handler_module, handler_fun, [request_map, dialog_obj, user_handler_state])
    else
      Logger.warning(
        "HandlerAdapter: User dialog handler #{handler_fun}/3 not found. Defaulting to :noreply."
      )

      :noreply
    end
  end
end
