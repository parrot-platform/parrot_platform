defmodule Parrot.Sip.HandlerAdapter.Core do
  @moduledoc """
  Core implementation of the adapter between the user-friendly Handler API and the internal SIP stack.
  Uses gen_statem to manage the lifecycle of SIP transactions and dialogs.
  Each instance of this gen_statem handles a single primary request.
  """
  @behaviour :gen_statem
  @behaviour Parrot.Sip.Handler

  require Logger

  alias Parrot.Sip.HandlerAdapter.{
    ResponseHandler,
    CallbackHandler
  }

  # State data
  defmodule Data do
    defstruct [
      # Module implementing Handler behavior
      :handler_module,
      # State to pass to handler callbacks
      :handler_state,
      # Current transaction (UAS object)
      :transaction,
      # Current dialog (can be nil)
      :dialog,
      # Current request (map format)
      :request,
      # Original SIP message for the current request
      :original_req_sip_msg,
      # Generated response from user handler
      :response,
      # Current gen_statem state name (for logging or internal logic)
      :current_gen_statem_state
    ]
  end

  @doc """
  Creates a new HandlerAdapter instance.

  This function creates a new Handler struct that wraps the user's handler module,
  allowing it to interface with the SIP stack's internal handler system.

  ## Parameters

    * `user_handler_module` - The module that implements the `Parrot.UasHandler` behaviour
    * `user_handler_state` - The initial state to pass to the user handler's callbacks

  ## Returns

  A new Handler struct that can be used with the SIP stack.

  ## Example

      {:ok, handler} = MyApp.UasHandler.start_link([])
      adapter = HandlerAdapter.new(MyApp.UasHandler, handler)
  """
  def new(user_handler_module, user_handler_state) do
    Parrot.Sip.Handler.new(__MODULE__, {user_handler_module, user_handler_state})
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
    %{
      id: __MODULE__,
      start: {__MODULE__, :start_link, [args]},
      type: :worker,
      # or :permanent depending on your needs
      restart: :temporary,
      shutdown: 5000
    }
  end

  @doc """
  Starts a new HandlerAdapter process.

  Initializes a new gen_statem process that will handle a single SIP transaction,
  interfacing between the user's handler module and the internal SIP stack.

  ## Parameters

    * `{user_handler_module, user_handler_state}` - A tuple containing the user's handler module
      and the state that will be passed to its callbacks

  ## Returns

  `{:ok, pid}` if the process was started successfully, or `{:error, reason}` if it failed.

  This function is typically called by the HandlerAdapterSupervisor rather than directly.
  """
  def start_link({user_handler_module, user_handler_state}) do
    :gen_statem.start_link(__MODULE__, {user_handler_module, user_handler_state}, [])
  end

  @doc """
  Initializes the HandlerAdapter gen_statem process.

  Sets up the initial state for the adapter instance. This is called automatically
  when the process is started with `start_link/1`.

  ## Parameters

    * `{user_handler_module, user_handler_state}` - A tuple containing the user's handler module
      and the state that will be passed to its callbacks

  ## Returns

  `{:ok, :idle, data}` where `:idle` is the initial state and `data` is the internal state data.
  """
  @impl :gen_statem
  def init({user_handler_module, user_handler_state}) do
    Logger.debug(
      "HandlerAdapter instance: init with user_handler_module: #{inspect(user_handler_module)}"
    )

    {:ok, :idle,
     %Data{
       handler_module: user_handler_module,
       handler_state: user_handler_state,
       current_gen_statem_state: :idle
     }}
  end

  @doc """
  Defines the callback mode for the gen_statem.

  This adapter uses the `:state_functions` mode, where the gen_statem callbacks
  are implemented as separate functions named after the states.

  ## Returns

  `:state_functions`
  """
  @impl :gen_statem
  def callback_mode, do: :state_functions

  # Parrot.Sip.Handler behaviour callbacks (static functions)

  @doc """
  Handles transport-level SIP requests.

  Called by the transport layer (e.g., TransportUdp) when a new SIP request arrives.
  This adapter always returns `:process_transaction` to have the request processed
  by the transaction layer.

  ## Parameters

    * `_msg` - The SIP message
    * `_args` - Arguments passed by the transport layer (unused)

  ## Returns

  `:process_transaction` - Indicates that the message should be processed by the transaction layer
  """
  @impl Parrot.Sip.Handler
  def transp_request(_msg, _args) do
    :process_transaction
  end

  @doc """
  Handles transaction-level SIP messages.

  Called by the Transaction FSM when it needs to pass control to the UAS layer.
  This adapter always returns `:process_uas` to have the message processed by the UAS layer.

  ## Parameters

    * `trans` - The transaction object
    * `sip_msg` - The SIP message
    * `{user_handler_module, user_handler_state}` - A tuple containing the user's handler module
      and its state

  ## Returns

  `:process_uas` - Indicates that the message should be processed by the UAS layer
  """
  @impl true
  def transaction(_trans, sip_msg, {user_handler_module, _user_handler_state}) do
    Logger.debug(
      "HandlerAdapter [static]: transaction callback for #{sip_msg.method}. User handler: #{inspect(user_handler_module)}"
    )

    :process_uas
  end

  @doc """
  Handles UAS-level SIP requests.

  This is the main entry point for handling incoming SIP requests at the UAS layer.
  It spawns a new HandlerAdapter instance to handle this specific request and delegates
  processing to it.

  The function handles different request types, with special handling for INVITE requests
  which require multiple state transitions in their transaction lifecycle.

  ## Parameters

    * `uas` - The UAS object
    * `req_sip_msg` - The SIP request message
    * `{user_handler_module, user_handler_state}` - A tuple containing the user's handler module
      and its state

  ## Returns

  `:ok` - Always returns `:ok` as the processing is delegated to the spawned instance
  """
  @impl true
  def uas_request(uas, req_sip_msg, {user_handler_module, user_handler_state}) do
    method = req_sip_msg.method
    Logger.debug("HandlerAdapter [static]: uas_request for #{method}. Spawning instance.")

    # Spawn a new HandlerAdapter gen_statem instance for this request
    # The args for start_child are {user_handler_module, user_handler_state}
    {:ok, pid} =
      Parrot.Sip.HandlerAdapter.Supervisor.start_child({user_handler_module, user_handler_state})

    # Send the request details to the new instance.
    # Using a timeout for the call.
    # 5 seconds
    call_timeout = 5000

    call_result =
      :gen_statem.call(pid, {:process_request, uas, req_sip_msg}, call_timeout)

    Logger.debug(
      "HandlerAdapter [static]: uas_request for #{method}, instance #{inspect(pid)} call returned: #{inspect(call_result)}"
    )

    case call_result do
      :invite_processing ->
        Logger.debug(
          "HandlerAdapter [static]: INVITE processing for instance #{inspect(pid)}, casting :progress."
        )

        :gen_statem.cast(pid, :progress)

      :ok ->
        Logger.debug(
          "HandlerAdapter [static]: Non-INVITE request processed by instance #{inspect(pid)}."
        )

      {:error, :timeout} ->
        Logger.error(
          "HandlerAdapter [static]: Timeout calling new instance #{inspect(pid)} for #{method}."
        )

      # UAS.make_reply should be used carefully here, as `uas` might be tied to the instance.
      # This path indicates a failure to initialize/process in the new adapter.
      # A 500 error might be appropriate, sent via the original `uas` if possible, or handled by Transaction timeout.
      # For now, log and let transaction timeout handle it.
      {:error, _reason} = error ->
        Logger.error(
          "HandlerAdapter [static]: Error from instance #{inspect(pid)} for #{method}: #{inspect(error)}"
        )

      # Similar to timeout, a server error occurred in the instance.
      other ->
        Logger.warning(
          "HandlerAdapter [static]: Unexpected result from instance call for #{method}: #{inspect(other)}"
        )
    end

    # The static uas_request's job is to delegate.
    :ok
  end

  @doc """
  Handles transaction termination events.

  Called by the Transaction layer when a transaction is stopping. The HandlerAdapter
  instances are designed to be short-lived and handle their own termination, so
  this function currently does nothing.

  ## Parameters

    * `_trans` - The transaction object
    * `_result` - The termination result
    * `{_user_handler_module, _user_handler_state}` - A tuple containing the user's handler module
      and its state

  ## Returns

  `:ok`
  """
  @impl true
  def transaction_stop(_trans, _result, {_user_handler_module, _user_handler_state}) do
    :ok
  end

  @doc """
  Handles CANCEL requests for a UAS transaction.

  Called when a CANCEL request is received for a UAS transaction. Currently, the
  Transaction layer handles CANCEL requests directly, so this function does nothing.

  ## Parameters

    * `_uas_id` - The ID of the UAS transaction to cancel
    * `{_user_handler_module, _user_handler_state}` - A tuple containing the user's handler module
      and its state

  ## Returns

  `:ok`
  """
  @impl true
  def uas_cancel(_uas_id, {_user_handler_module, _user_handler_state}) do
    :ok
  end

  @doc """
  Handles ACK requests.

  ACK requests are special in SIP as they don't generate responses. This function
  passes ACK requests directly to the user's handler without creating a new adapter
  instance.

  ## Parameters

    * `sip_msg` - The ACK SIP message
    * `{user_handler_module, user_handler_state}` - A tuple containing the user's handler module
      and its state

  ## Returns

  `:ok`
  """
  @impl true
  def process_ack(sip_msg, {user_handler_module, user_handler_state}) do
    # ACKs are typically dialog-related and often don't need a full new adapter state machine.
    # They can be passed directly to the user's handler.
    Logger.debug(
      "HandlerAdapter [static]: process_ack. Calling user handler #{inspect(user_handler_module)}."
    )

    _user_response =
      CallbackHandler.call_method_handler(
        user_handler_module,
        "ACK",
        sip_msg,
        user_handler_state
      )

    # The result of handle_ack (e.g., :noreply) is usually not sent back as a SIP message.
    :ok
  end

  # GenStatem Callbacks (for instances)

  @doc """
  Catches and handles unhandled gen_statem events.

  This is a fallback handler for any gen_statem events that aren't handled by the
  specific state functions. It logs warnings and returns appropriate responses.

  ## Parameters

    * `event_type` - The type of gen_statem event
    * `event_content` - The content of the event
    * `state` - The current state of the gen_statem
    * `data` - The current data of the gen_statem

  ## Returns

  A tuple suitable for the gen_statem behavior, typically keeping the current state
  and responding with an error for call events.
  """
  @impl :gen_statem
  def handle_event(event_type, event_content, state, data) do
    Logger.warning(
      "HandlerAdapter instance: Unhandled gen_statem event: #{inspect(event_type)}, #{inspect(event_content)} in state #{inspect(state)}"
    )

    Logger.warning("HandlerAdapter instance: Data: #{inspect(data)}")

    case event_type do
      {:call, from} ->
        Logger.warning(
          "HandlerAdapter instance: Replying with default 501 Not Implemented from handle_event/4"
        )

        # This instance is likely stuck or received an unexpected call.
        # It should ideally terminate if it's in an unrecoverable state.
        {:keep_state_and_data, [{:reply, from, {:error, :unhandled_event}}]}

      _ ->
        {:keep_state_and_data}
    end
  end

  @doc """
  Handles events in the `:idle` state for the HandlerAdapter Core state machine.

  ## Parameters

    - `event_type` - The type of event (`:call` or `:cast`).
    - `event_content` - The event payload. Supported:
        - `{:process_request, request_map, uas, original_req_sip_msg}` for processing new SIP requests (when `event_type` is `:call`).
        - `{:dialog_ended, dialog_id, reason}` for dialog termination notifications (when `event_type` is `:cast`).
        - `{:dialog_started, dialog_id, invite_msg}` for dialog start notifications (when `event_type` is `:cast`).
    - `data` - The current state data.

  ## Returns

    - For `{:call, from}, {:process_request, ...}`: handles the SIP request and transitions state as needed.
    - For `:cast, {:dialog_ended, dialog_id, reason}`: notifies the handler module of dialog termination by invoking `handle_dialog_end/3` if implemented, and remains in the `:idle` state.
    - For `:cast, {:dialog_started, dialog_id, invite_msg}`: notifies the handler module of dialog start by invoking `handle_dialog_start/3` if implemented, and remains in the `:idle` state.

  ## Example

    Handles both synchronous and asynchronous events in the `:idle` state.
  """
  def idle(
        {:call, from},
        {:process_request, uas, %Parrot.Sip.Message{method: method} = original_req_sip_msg},
        data
      ) do
    Logger.debug(
      "HandlerAdapter instance [#{inspect(self())}] state idle: Processing request for method #{method}"
    )

    new_data = %{
      data
      | transaction: uas,
        original_req_sip_msg: original_req_sip_msg,
        # Will be updated by next_state
        current_gen_statem_state: :idle
    }

    # INVITE
    if method != :invite do
      Logger.debug(
        "HandlerAdapter instance [#{inspect(self())}] state idle: Processing non-INVITE request"
      )

      user_response =
        CallbackHandler.call_method_handler(
          new_data.handler_module,
          method,
          original_req_sip_msg,
          new_data.handler_state
        )

      Logger.debug(
        "HandlerAdapter instance [#{inspect(self())}] state idle: built user_response: #{inspect(user_response)}"
      )

      ResponseHandler.process_user_response(user_response, uas, original_req_sip_msg)
      updated_data = %{new_data | response: user_response, current_gen_statem_state: :completed}

      Logger.debug(
        "HandlerAdapter instance [#{inspect(self())}] state idle: done processing user response. updated_data: #{inspect(updated_data)}"
      )

      # This instance will self-terminate after completion for non-INVITEs.
      {:stop_and_reply, :normal, [{:reply, from, :ok}], updated_data}
    else
      # For INVITE, the transaction layer already sent 100 Trying.
      # We transition to :transaction_trying and await a :progress event (casted by static uas_request).
      Logger.debug(
        "HandlerAdapter instance [#{inspect(self())}] state idle: transitioning to :transaction_trying"
      )

      updated_data = %{new_data | current_gen_statem_state: :transaction_trying}
      {:next_state, :transaction_trying, updated_data, [{:reply, from, :invite_processing}]}
    end
  end

  def idle(:cast, {:dialog_ended, dialog_id, msg}, data) do
    Logger.debug("HandlerAdapter instance [#{inspect(self())}] state idle: dialog ended")
    # Notify the handler module if it implements handle_dialog_end/3
    handler_module = data.handler_module
    handler_state = data.handler_state

    # Call the handler's callback if it exists
    if function_exported?(handler_module, :handle_dialog_end, 3) do
      Logger.debug(
        "HandlerAdapter instance [#{inspect(self())}] state idle: calling handle_dialog_end"
      )

      handler_module.handle_dialog_end(dialog_id, msg, handler_state)
    end

    # Return :keep_state_and_data to stay in idle state
    :keep_state_and_data
  end

  def idle(:cast, {:dialog_started, dialog_id, msg}, data) do
    Logger.debug("HandlerAdapter instance [#{inspect(self())}] state idle: dialog started")
    # Notify the handler module if it implements handle_dialog_end/3
    handler_module = data.handler_module
    handler_state = data.handler_state

    # Call the handler's callback if it exists
    if function_exported?(handler_module, :handle_dialog_start, 3) do
      Logger.debug(
        "HandlerAdapter instance [#{inspect(self())}] state idle: calling handle_dialog_end"
      )

      handler_module.handle_dialog_start(dialog_id, msg, handler_state)
    end

    :keep_state_and_data
  end

  @doc """
  Handles the 'progress' event in the transaction_trying state for INVITE transactions.

  This function processes the INVITE request in the 'trying' phase of the transaction.
  It calls the appropriate user handler function and manages the state transitions
  based on the response.

  ## Parameters

    * `:progress` - The event being processed
    * `data` - The current state data

  ## Returns

  For final responses (>= 200), returns `{:stop, :normal, updated_data}` to terminate.

  For provisional responses (100-199), returns a tuple to transition to
  the :transaction_proceeding state with a timeout to generate the final response later.

  For other responses, stays in the current state.
  """
  def transaction_trying(:state_timeout, :proceed_to_final, data) do
    # Call method handler directly to get final response
    method = Map.get(data.request, :method)

    user_response =
      CallbackHandler.call_method_handler(
        data.handler_module,
        method,
        data.request,
        data.handler_state
      )

    ResponseHandler.process_user_response(
      user_response,
      data.transaction,
      data.request
    )

    updated_data = %{data | response: user_response}

    case user_response do
      {:respond, status, _, _, _} when status >= 200 ->
        {:next_state, :completed, updated_data, []}

      _ ->
        # Stay in trying state if no response or non-final response
        {:keep_state, updated_data}
    end
  end

  def transaction_trying(
        :cast,
        :progress,
        %Parrot.Sip.HandlerAdapter.Core.Data{
          handler_module: _handler_module,
          transaction: %Parrot.Sip.Transaction{request: request}
        } = data
      ) do
    Logger.debug(
      "HandlerAdapter instance [#{inspect(self())}] state transaction_trying: Received :progress event."
    )

    # This is request_map
    method = request.method

    user_response =
      CallbackHandler.call_transaction_handler(
        data.handler_module,
        method,
        :trying,
        data.request,
        # uas object
        data.transaction,
        data.handler_state
      )

    Logger.debug(
      "HandlerAdapter instance [#{inspect(self())}] state transaction_trying: user_response:\n#{inspect(user_response, pretty: true)}\n"
    )

    if user_response != :noreply and match?({:respond, _, _, _, _}, user_response) do
      Logger.debug(
        "HandlerAdapter instance [#{inspect(self())}] state transaction_trying: user trying to respond"
      )

      ResponseHandler.process_user_response(
        user_response,
        data.transaction,
        data.original_req_sip_msg
      )
    end

    case user_response do
      {:respond, status, _, _, _} when status >= 100 and status < 200 ->
        Logger.debug(
          "HandlerAdapter instance [#{inspect(self())}] state transaction_trying: next state :transaction_proceeding "
        )

        updated_data = %{
          data
          | response: user_response,
            current_gen_statem_state: :transaction_proceeding
        }

        Logger.debug(
          "HandlerAdapter instance [#{inspect(self())}] state transaction_trying: next state :transaction_proceeding "
        )

        # Ensure :request is always present in updated_data
        updated_data_with_request =
          Map.put(updated_data, :request, data.request || data.original_req_sip_msg)

        {:next_state, :transaction_proceeding, updated_data_with_request,
         [{:state_timeout, 100, :proceed_to_final}]}

      # Final response from trying handler
      {:respond, status, _, _, _} when status >= 200 ->
        Logger.debug(
          "HandlerAdapter instance [#{inspect(self())}] state transaction_trying: next state :completed "
        )

        updated_data = %{
          data
          | response: user_response,
            current_gen_statem_state: :completed
        }

        {:stop, :normal, updated_data}

      # Stay in trying if :noreply or unhandled (e.g. default handler)
      _ ->
        Logger.debug(
          "HandlerAdapter instance [#{inspect(self())}] state transaction_trying: staying in :transaction_trying "
        )

        updated_data = %{
          data
          | response: user_response,
            current_gen_statem_state: :transaction_trying
        }

        updated_data_with_request =
          Map.put(updated_data, :request, data.request || data.original_req_sip_msg)

        {:next_state, :transaction_trying, updated_data_with_request,
         [{:state_timeout, 100, :proceed_to_final}]}
    end
  end

  @doc """
  Handles the timeout event in the transaction_proceeding state.

  This function is triggered by a timeout to generate the final response for an INVITE
  transaction that has already sent provisional responses. It calls the user's method
  handler to get the final response.

  ## Parameters

    * `:proceed_to_final` - The timeout event
    * `data` - The current state data

  ## Returns

  `{:next_state, :completed, updated_data, []}` - Transitions to the completed state
  with the final user response.
  """
  def transaction_proceeding(:state_timeout, :proceed_to_final, data) do
    # Call method handler directly to get final response
    method = Map.get(data.request, :method)

    user_response =
      CallbackHandler.call_method_handler(
        data.handler_module,
        method,
        data.request,
        data.handler_state
      )

    # Send final response
    ResponseHandler.process_user_response(
      user_response,
      data.transaction,
      data.original_req_sip_msg
    )

    # Transition to completed state
    {:next_state, :completed, %{data | response: user_response}, []}
  end

  # Handles a manual 'complete' call in the transaction_proceeding state.
  #
  # This function is called when another process explicitly asks the transaction
  # to complete by generating a final response. It will either use a previously set
  # final response or call the user's method handler to get a new one.
  #
  # Parameters:
  #   * `{:call, from}` - The gen_statem call information with caller reference
  #   * `:complete` - The completion command
  #   * `data` - The current state data
  #
  # Returns:
  #   `{:stop, :normal, :ok, updated_data, [{:reply, from, user_response}]}` -
  #   Terminates the adapter with a normal reason, responds to the caller with the
  #   user's response, and includes the updated data.
  def transaction_proceeding({:call, from}, :complete, data) do
    Logger.debug(
      "HandlerAdapter instance [#{inspect(self())}] state transaction_proceeding: Received :complete event."
    )

    # This event implies the user handler for 'trying' or 'proceeding' phase is done,
    # and now we need the final response (e.g., 200 OK for INVITE).
    # This is typically triggered after the user handler for provisional responses has finished.
    # The actual final response is generated by calling the main method handler.

    user_response =
      if data.response && elem(data.response, 0) == :respond && elem(data.response, 1) >= 200 do
        # If a final response was already set (e.g. by trying_handler), use it.
        Logger.debug(
          "HandlerAdapter instance [#{inspect(self())}] state transaction_proceeding: final response is being used"
        )

        data.response
      else
        method = Map.get(data.request, :method)

        Logger.debug(
          "HandlerAdapter instance [#{inspect(self())}] state transaction_proceeding: going to call handler for method #{inspect(method)}"
        )

        CallbackHandler.call_method_handler(
          data.handler_module,
          method,
          data.request,
          data.handler_state
        )
      end

    Logger.debug(
      "HandlerAdapter instance [#{inspect(self())}] state transaction_proceeding: calling process_user_response with #{inspect(user_response)}"
    )

    ResponseHandler.process_user_response(
      user_response,
      data.transaction,
      data.original_req_sip_msg
    )

    updated_data = %{data | response: user_response, current_gen_statem_state: :completed}

    Logger.debug(
      "HandlerAdapter instance [#{inspect(self())}] state transaction_proceeding: done calling process_user_response. updated_data:#{inspect(updated_data)}"
    )

    # This instance will self-terminate.
    # Reply to :complete caller
    Logger.debug(
      "HandlerAdapter instance [#{inspect(self())}] state transaction_proceeding: terminating with :stop"
    )

    {:stop, :normal, :ok, updated_data, [{:reply, from, user_response}]}
  end

  # Dialog state functions (if used, these would be triggered by Dialog module)
  # These are less likely to be called in the simple test case but are part of the adapter.
  @doc """
  Handles updates to dialogs in the early state.

  This function is called when a dialog in the early state (before being established)
  receives an update. It calls the user's dialog handler for the early state.

  ## Parameters

    * `{:call, from}` - The gen_statem call information with caller reference
    * `{:update, request, dialog_obj}` - The update information
    * `data` - The current state data

  ## Returns

  `{:keep_state, updated_data, [{:reply, from, user_response}]}` -
  Keeps the current state, updates data with the new request, dialog, and response,
  and replies to the caller with the user's response.
  """
  def dialog_early({:call, from}, {:update, request, dialog_obj}, data) do
    Logger.debug(
      "HandlerAdapter instance [#{inspect(self())}] state dialog_early: Received :update."
    )

    user_response =
      CallbackHandler.call_dialog_handler(
        data.handler_module,
        :early,
        # This should be a request_map
        request,
        dialog_obj,
        data.handler_state
      )

    # Responses from dialog handlers might not always be SIP responses to send immediately.
    # This needs clarification based on how dialog updates are meant to work.
    # For now, assume it might return a SIP response to send.
    if user_response != :noreply and match?({:respond, _, _, _, _}, user_response) do
      # Dialog updates might not have an original_req_sip_msg in the same way.
      # This needs careful handling of what `uas` object to use.
      # ResponseHandler.process_user_response(user_response, ???, ???)
      Logger.warning("HandlerAdapter: Sending response from dialog_early not fully implemented.")
    end

    updated_data = %{
      data
      | response: user_response,
        request: request,
        dialog: dialog_obj,
        current_gen_statem_state: :dialog_early
    }

    {:keep_state, updated_data, [{:reply, from, user_response}]}
  end

  @doc """
  Handles updates to dialogs in the confirmed state.

  This function is called when a dialog in the confirmed state (after being established)
  receives an update. It calls the user's dialog handler for the confirmed state.

  ## Parameters

    * `{:call, from}` - The gen_statem call information with caller reference
    * `{:update, request, dialog_obj}` - The update information
    * `data` - The current state data

  ## Returns

  `{:keep_state, updated_data, [{:reply, from, user_response}]}` -
  Keeps the current state, updates data with the new request, dialog, and response,
  and replies to the caller with the user's response.
  """
  def dialog_confirmed({:call, from}, {:update, request, dialog_obj}, data) do
    Logger.debug(
      "HandlerAdapter instance [#{inspect(self())}] state dialog_confirmed: Received :update."
    )

    user_response =
      CallbackHandler.call_dialog_handler(
        data.handler_module,
        :confirmed,
        # request_map
        request,
        dialog_obj,
        data.handler_state
      )

    if user_response != :noreply and match?({:respond, _, _, _, _}, user_response) do
      Logger.warning(
        "HandlerAdapter: Sending response from dialog_confirmed not fully implemented."
      )
    end

    updated_data = %{
      data
      | response: user_response,
        request: request,
        dialog: dialog_obj,
        current_gen_statem_state: :dialog_confirmed
    }

    {:keep_state, updated_data, [{:reply, from, user_response}]}
  end

  @doc """
  Handles events in the completed state.

  This function is called when the adapter is in the completed state and receives events.
  In this state, all events are ignored as the adapter has finished its work and is
  about to terminate.

  ## Parameters

    * `_event_type` - The type of event (ignored)
    * `_event_content` - The content of the event (ignored)
    * `data` - The current state data

  ## Returns

  `{:keep_state_and_data}` - Keeps the current state and data, ignoring the event.
  """
  def completed(_event_type, _event_content, _data) do
    Logger.debug(
      "HandlerAdapter instance [#{inspect(self())}] state completed: Received event, but already completed. Ignoring."
    )

    # This instance should have already stopped or be about to stop.
    # If it receives events here, it's unexpected.
    # Or stop if not already stopped.
    {:keep_state_and_data}
  end

  @doc """
  Handles termination of the HandlerAdapter process.

  This function is called when the adapter is terminating. It logs the reason and
  final state data for debugging purposes.

  ## Parameters

    * `reason` - The reason for termination
    * `_state` - The current state (ignored)
    * `data` - The current state data

  ## Returns

  `:ok`
  """
  @impl :gen_statem
  def terminate(reason, _state, data) do
    Logger.debug(
      "HandlerAdapter instance [#{inspect(self())}] terminating. Reason: #{inspect(reason)}. Final Data: #{inspect(data)}"
    )

    :ok
  end
end
