defmodule Parrot.Sip.TransactionStatem do
  @moduledoc """
  SIP Transaction State Machine

  States:
  - :trying      - Initial state for non-INVITE transactions
  - :calling     - Initial state for INVITE client transactions
  - :proceeding  - Processing state for INVITE server transactions
  - :completed   - Final response sent/received
  - :confirmed   - Final state for successful transactions
  - :terminated  - Terminal state

  State Transitions:
  - trying -> proceeding -> completed -> terminated
  - calling -> proceeding -> completed -> terminated
  - proceeding -> completed -> confirmed -> terminated

  Events:
  - {:process_se, se}     - Process transaction events
  - {:send, response}     - Send response
  - :cancel              - Cancel transaction
  - {:set_owner, code, pid} - Set transaction owner
  - {:DOWN, ref, :process, pid, _} - Owner process down
  - {:event, timer_event} - Timer events
  """
  @behaviour :gen_statem

  require Logger

  @inspect_opts [pretty: false, limit: :infinity, width: 80, syntax_colors: []]

  alias Parrot.Sip.Headers.Via
  alias Parrot.Sip.Transaction
  alias Parrot.Sip.{Handler, UAS, Message, Parser}

  @type t :: {:trans, pid()}
  @type client_result :: {:stop, term()} | {:message, term()}
  @type client_callback :: (client_result -> any())
  @type handler :: term()

  # State definition for the state machine
  @type state_name :: :proceeding | :calling | :completed | :confirmed | :trying | :terminated
  @type state :: %{
          type: :client | :server,
          trans: term(),
          owner_mon: reference() | nil,
          data: map(),
          log: boolean(),
          logbranch: String.t()
        }

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

  @spec start_link(term()) :: :gen_statem.start_ret()
  def start_link(args) do
    # Expect args to include a %Parrot.Sip.Transaction{} as the first or a named argument.
    transaction =
      case args do
        [%Parrot.Sip.Transaction{} = t | _] -> t
        %{transaction: %Parrot.Sip.Transaction{} = t} -> t
        _ -> raise ArgumentError, "start_link expects a %Parrot.Sip.Transaction{} in args"
      end

    :gen_statem.start_link(
      via_tuple(transaction),
      __MODULE__,
      args,
      []
    )
  end

  def server_process(%Parrot.Sip.Message{method: :ack} = sip_msg, handler) do
    Logger.debug("server_process ack")
    dbg(sip_msg)
    dbg(handler)

    case find_server(sip_msg) do
      {:ok, pid} ->
        Logger.debug("Forward the ACK to the transaction FSM (gen_statem)")
        :gen_statem.cast(pid, {:received, sip_msg})
        :ok

      :error ->
        Logger.debug(
          "If no transaction found, this might be a 2xx ACK (handled by dialog/user handler)"
        )

        handler_module = handler.module
        handler_args = handler.args

        if function_exported?(handler_module, :process_ack, 2) do
          Logger.debug("Calling process_ack/2 in handler")
          handler_module.process_ack(sip_msg, handler_args)
        else
          Logger.warning("No process_ack/2 in handler for stray ACK")
          :ok
        end
    end
  end

  def server_process(%Parrot.Sip.Message{} = sip_msg, handler) do
    case find_server(sip_msg) do
      {:ok, pid} ->
        :gen_statem.cast(pid, {:received, sip_msg})

      :error ->
        case sip_msg do
          # Handle in-dialog requests (both From and To have tags)
          %Message{
            headers: %{
              "from" => %{parameters: %{"tag" => _from_tag}},
              "to" => %{parameters: %{"tag" => _to_tag}}
            }
          } = in_dialog_msg ->
            Logger.debug("Processing in-dialog request: #{in_dialog_msg.method}")
            handle_in_dialog_request(in_dialog_msg, handler)

          # Handle new dialog requests
          _new_dialog_msg ->
            Logger.debug("Creating new transaction for #{sip_msg.method}")

            dbg(Transaction.determine_transaction_type(sip_msg))

            transaction =
              case Transaction.determine_transaction_type(sip_msg) do
                :invite_server ->
                  {:ok, t} = Transaction.create_invite_server(sip_msg)
                  t

                :non_invite_server ->
                  {:ok, t} = Transaction.create_non_invite_server(sip_msg)
                  t

                other ->
                  raise ArgumentError, "Unsupported transaction type: #{inspect(other)}"
              end

            start_transaction([transaction, handler])
        end
    end
  end

  @spec server_response(term(), Parrot.Sip.Transaction.t()) :: :ok
  def server_response(resp, %Parrot.Sip.Transaction{} = transaction) do
    Logger.debug("Sending response: #{inspect(resp)}")
    dbg(via_tuple(transaction))
    :gen_statem.cast(via_tuple(transaction), {:send, resp})
  end

  @spec create_server_response(term(), term()) :: :ok
  def create_server_response(resp_sip_msg, req_sip_msg) do
    trans_id = Transaction.generate_id(req_sip_msg)

    case Registry.lookup(Parrot.Registry, trans_id) do
      [{pid, _}] when is_pid(pid) ->
        :gen_statem.cast(pid, {:send, resp_sip_msg})

      _ ->
        Logger.debug("No transaction found for response, sending directly")
        # TODO: Implement direct response sending with pure Elixir
        # For now, just return :ok
        :ok
    end
  end

  @spec server_cancel(term()) :: {:reply, term()}
  def server_cancel(%Message{} = cancel_sip_msg) do
    # Generate transaction ID for the original INVITE this CANCEL is targeting
    trans_id = generate_cancel_transaction_id(cancel_sip_msg)

    case Registry.lookup(Parrot.Registry, trans_id) do
      [{pid, _}] when is_pid(pid) ->
        Logger.debug("Found transaction to CANCEL: #{inspect(trans_id, @inspect_opts)}")
        :gen_statem.cast(pid, :cancel)
        resp = Message.reply(cancel_sip_msg, 200, "OK")
        {:reply, resp}

      _ ->
        Logger.debug("cannot find transaction to CANCEL: #{inspect(trans_id, @inspect_opts)}")
        resp = Message.reply(cancel_sip_msg, 481, "Call/Transaction Does Not Exist")
        {:reply, resp}
    end
  end

  @spec server_set_owner(integer(), pid(), t()) :: :ok
  def server_set_owner(code, owner_pid, %Parrot.Sip.Transaction{} = transaction)
      when is_pid(owner_pid) and is_integer(code) do
    :gen_statem.cast(via_tuple(transaction), {:set_owner, code, owner_pid})
  end

  @spec client_new(term(), map(), client_callback()) :: t()
  def client_new(transaction, options, callback) do
    # Pass transaction as first element to match init/1 expectations
    args = [transaction, options, callback]

    case Parrot.Sip.Transaction.Supervisor.start_child(args) do
      {:ok, pid} ->
        {:trans, pid}

      {:error, _} = error ->
        Logger.error("client failed to create transaction: #{inspect(error, @inspect_opts)}")
        {:trans, spawn(fn -> :ok end)}
    end
  end

  @spec client_response(term(), binary()) :: :ok
  def client_response(via, msg) when is_binary(msg) do
    case Parser.parse(msg) do
      {:ok, sip_msg} ->
        # Generate transaction ID from branch and method
        branch =
          case via do
            %Via{parameters: %{"branch" => b}} -> b
            _ -> nil
          end

        # For responses, extract method from CSeq header
        method =
          case sip_msg.headers["cseq"] do
            %{method: m} ->
              m

            cseq when is_binary(cseq) ->
              [_, method_str] = String.split(cseq, " ", parts: 2)
              String.trim(method_str) |> String.downcase() |> String.to_atom()

            _ ->
              nil
          end

        trans_id =
          if branch && method do
            "#{branch}:#{method}:client"
          else
            Logger.warning("Cannot generate transaction ID for response")
            nil
          end

        if trans_id do
          case Registry.lookup(Parrot.Registry, trans_id) do
            [{pid, _}] when is_pid(pid) ->
              :gen_statem.cast(pid, {:received, sip_msg})

            _ ->
              Logger.warning(
                "cannot find transaction for request: #{inspect(via, @inspect_opts)}"
              )
          end
        end

      {:error, _} = error ->
        Logger.warning("failed to parse response: #{inspect(error, @inspect_opts)}")
    end
  end

  @spec client_cancel(t()) :: :ok
  def client_cancel({:trans, pid}) do
    :gen_statem.cast(pid, :cancel)
  end

  @spec count() :: non_neg_integer()
  def count do
    Parrot.Sip.Transaction.Supervisor.num_active()
  end

  @impl :gen_statem
  def init([%Parrot.Sip.Transaction{} = transaction | rest]) do
    sip_msg = transaction.request
    method = transaction.method
    request_uri = sip_msg.request_uri
    transaction_id = transaction.id
    branch = transaction.branch
    call_id = sip_msg.headers["call-id"]

    # Register with the full transaction ID, not just the branch
    Registry.register(Parrot.Registry, transaction_id, nil)

    # Determine if this is a client or server transaction based on the transaction type
    transaction_type = transaction.type

    Logger.metadata(
      trans_id: transaction_id,
      method: method,
      call_id: call_id,
      branch: branch
    )

    if transaction_type == :invite_client || transaction_type == :non_invite_client do
      # Client transaction initialization
      {options, callback} =
        case rest do
          [opts, cb] when is_map(opts) and is_function(cb) -> {opts, cb}
          [cb] when is_function(cb) -> {%{}, cb}
          _ -> {%{}, nil}
        end

      state = %{
        type: :client,
        data: %{
          # For client, handler is the callback function
          handler: callback,
          origmsg: sip_msg,
          transaction: transaction,
          options: options,
          # Store original request for client
          outreq: sip_msg,
          cancelled: false
        },
        timers: %{},
        log: Parrot.Config.log_transactions(),
        logbranch: branch
      }

      Logger.debug(
        "trans: client: #{method} #{request_uri}; call-id: #{call_id}; branch: #{branch}"
      )

      # Send the initial request
      Parrot.Sip.Transport.send_request(sip_msg)

      # Start in calling state for client transactions
      {:ok, :calling, state}
    else
      # Server transaction initialization - extract handler from rest like original code
      handler =
        case rest do
          [h | _] -> h
          _ -> nil
        end

      state = %{
        type: :server,
        data: %{
          handler: handler,
          origmsg: sip_msg,
          transaction: transaction,
          auto_resp: 500
        },
        timers: %{},
        log: Parrot.Config.log_transactions(),
        logbranch: branch
      }

      Logger.debug(
        "trans: server: #{method} #{request_uri}; call-id: #{call_id}; branch: #{branch}"
      )

      {:ok, :trying, state,
       [{:next_event, :cast, {:handle_transaction_setup, [:server, sip_msg, method, handler]}}]}
    end
  end

  @impl :gen_statem
  def callback_mode, do: :state_functions

  # Real implementation of process_actions/2 to handle SIP actions and timers.
  defp process_actions([], _data) do
    Logger.debug("[process_actions] No more actions to process.")
    {:keep_state_and_data, []}
  end

  defp process_actions([action | rest], data) do
    Logger.debug(
      "[process_actions] Processing action: #{inspect(action)} with data: #{inspect(data, pretty: false, limit: 10)}"
    )

    case action do
      {:send_response, response} ->
        Logger.debug("[process_actions] Action is :send_response. Response: #{inspect(response)}")
        # Try to get the source from state, transaction, or response
        source = extract_source(data, response)

        if source do
          Logger.debug("[process_actions] Sending response using source: #{inspect(source)}")
          Parrot.Sip.Transport.send_response(response, source)
        else
          require Logger

          Logger.error(
            "[process_actions] No source found for send_response/2; cannot send SIP response!"
          )
        end

        Logger.debug(
          "[process_actions] Finished :send_response action, processing rest: #{inspect(rest)}"
        )

        process_actions(rest, data)

      {:send_request, request} ->
        Logger.debug("[process_actions] Action is :send_request. Request: #{inspect(request)}")
        Parrot.Sip.Transport.send_request(request)

        Logger.debug(
          "[process_actions] Finished :send_request action, processing rest: #{inspect(rest)}"
        )

        process_actions(rest, data)

      {:start_timer, timer_name, timeout} ->
        Logger.debug(
          "[process_actions] Action is :start_timer. Timer: #{inspect(timer_name)}, Timeout: #{inspect(timeout)}"
        )

        data = cancel_named_timer(timer_name, data)
        ref = Process.send_after(self(), {:event, timer_name}, timeout)
        timers = Map.put(data.timers || %{}, timer_name, ref)

        Logger.debug("[process_actions] Timer started. Timers map: #{inspect(timers)}")

        case process_actions(rest, %{data | timers: timers}) do
          {:keep_state_and_data, _} -> {:keep_state, data}
          {:keep_state, _} -> {:keep_state, data}
          :stop -> {:stop, :normal, data}
        end

      {:cancel_timer, timer_name} ->
        Logger.debug("[process_actions] Action is :cancel_timer. Timer: #{inspect(timer_name)}")
        data = cancel_named_timer(timer_name, data)

        Logger.debug("[process_actions] Timer cancelled. Timers map: #{inspect(data.timers)}")

        process_actions(rest, data)

      :terminate_transaction ->
        Logger.debug("[process_actions] Action is :terminate_transaction. Stopping.")
        :stop

      :retransmit_last_response ->
        Logger.debug("[process_actions] Action is :retransmit_last_response.")

        last_response =
          get_in(data, [:transaction, :last_response]) ||
            get_in(data, [:data, :transaction, :last_response])

        if last_response do
          Logger.debug(
            "[process_actions] Retransmitting last response: #{inspect(last_response)}"
          )

          source = extract_source(data, last_response)

          if source do
            Parrot.Sip.Transport.send_response(last_response, source)
          else
            Parrot.Sip.Transport.send_response(last_response)
          end
        else
          Logger.debug("[process_actions] No last response to retransmit.")
        end

        process_actions(rest, data)

      {:notify_user, msg} ->
        Logger.debug("[process_actions] Action is :notify_user. Message: #{inspect(msg)}")
        # Implement user notification if needed
        process_actions(rest, data)

      :ignore ->
        Logger.debug("[process_actions] Action is :ignore. Skipping.")

        process_actions(rest, data)

      _ ->
        Logger.debug("[process_actions] Unknown action: #{inspect(action)}. Skipping.")

        process_actions(rest, data)
    end
  end

  defp cancel_named_timer(timer_name, data) do
    timers = data.timers || %{}

    case Map.pop(timers, timer_name) do
      {nil, _} ->
        data

      {ref, new_timers} ->
        Process.cancel_timer(ref)
        %{data | timers: new_timers}
    end
  end

  defp extract_source(data, response) do
    cond do
      # Check direct source in data
      Map.has_key?(data, :source) and not is_nil(data.source) ->
        Logger.debug("[extract_source] Found source in data.source: #{inspect(data.source)}")
        data.source

      # Check nested data.data.source
      Map.has_key?(data, :data) and Map.has_key?(data.data, :source) and
          not is_nil(data.data.source) ->
        Logger.debug(
          "[extract_source] Found source in data.data.source: #{inspect(data.data.source)}"
        )

        data.data.source

      # Check transaction source
      Map.has_key?(data, :transaction) and Map.has_key?(data.transaction, :source) and
          not is_nil(data.transaction.source) ->
        Logger.debug(
          "[extract_source] Found source in data.transaction.source: #{inspect(data.transaction.source)}"
        )

        data.transaction.source

      # Check nested data.data.transaction.source
      Map.has_key?(data, :data) and Map.has_key?(data.data, :transaction) and
        Map.has_key?(data.data.transaction, :source) and not is_nil(data.data.transaction.source) ->
        Logger.debug("[extract_source] Found source in data.data.transaction.source")
        data.data.transaction.source

      # Check origmsg source
      Map.has_key?(data, :origmsg) and Map.has_key?(data.origmsg, :source) and
          not is_nil(data.origmsg.source) ->
        Logger.debug(
          "[extract_source] Found source in data.origmsg.source: #{inspect(data.origmsg.source)}"
        )

        data.origmsg.source

      # Check nested data.data.origmsg.source
      Map.has_key?(data, :data) and Map.has_key?(data.data, :origmsg) and
        Map.has_key?(data.data.origmsg, :source) and not is_nil(data.data.origmsg.source) ->
        Logger.debug("[extract_source] Found source in data.data.origmsg.source")
        data.data.origmsg.source

      # Try to build from Via header
      Map.has_key?(data, :origmsg) and is_map(data.origmsg) and
        Map.has_key?(data.origmsg, :headers) and Map.has_key?(data.origmsg.headers, "via") ->
        via = data.origmsg.headers["via"]
        Logger.debug("[extract_source] Built source from Via header: #{inspect(via)}")
        %Parrot.Sip.Source{remote: {via.host, via.port}, transport: via.transport}

      # Check response source
      Map.has_key?(response, :source) and not is_nil(response.source) ->
        Logger.debug(
          "[extract_source] Found source in response.source: #{inspect(response.source)}"
        )

        response.source

      true ->
        Logger.debug("[extract_source] No source found in any known location.")
        nil
    end
  end

  def trying(
        :cast,
        {:handle_transaction_setup, [:server, sip_msg, :ack, handler]},
        %{data: %{transaction: transaction}} = _state
      ) do
    Logger.warning(
      "ACK that matches transaction received for transaction ID: #{sip_msg.transaction_id}"
    )

    :process_uas = Handler.transaction(transaction, sip_msg, handler)
    UAS.process_ack(sip_msg, handler)
  end

  def trying(
        :cast,
        {:handle_transaction_setup, [:server, sip_msg, _method, _handler]},
        %{data: %{transaction: transaction, handler: handler}} = state
      ) do
    Logger.debug(":handle_transaction_setup -> Trying transaction setup")

    # Only send 100 Trying for INVITE server transactions (RFC 3261 17.2.1)
    # Non-INVITE server transactions should not automatically send 100 Trying (RFC 3261 17.2.2)
    if sip_msg.method == :invite do
      trying_resp =
        Parrot.Sip.Message.reply(sip_msg, 100, "Trying")
        |> Map.put(:body, "")

      UAS.response(trying_resp, transaction)
    end

    case Handler.transaction(transaction, sip_msg, handler) do
      :ok ->
        Logger.debug("Handler.transaction(transaction, sip_msg, handler) -> :ok")
        :ok

      :process_uas ->
        Logger.debug("Handler.transaction(transaction, sip_msg, handler) -> :process_uas")
        UAS.process(transaction, sip_msg, handler)
    end

    {:keep_state, state}
  end

  def trying(:cast, {:send, response}, %{data: %{transaction: transaction} = data} = state) do
    Logger.debug(
      "trying(:cast, {:send, response}, %{data: %{transaction: transaction} = data} = state)"
    )

    # Handle sending a response in the trying state using actions
    {new_transaction, actions} =
      Parrot.Sip.Transaction.handle_event({:send, response}, transaction)

    new_data = %{data | transaction: new_transaction}
    new_state = %{state | data: new_data}

    process_actions(actions, new_state)
  end

  def trying(:cast, :cancel, %{data: %{handler: handler, transaction: transaction}} = state) do
    Logger.debug("trans: canceling server transaction. state: #{inspect(state, @inspect_opts)}")
    UAS.process_cancel(transaction, handler)
    {:keep_state, state}
  end

  # Handle cancel events for client transactions
  def trying(:cast, :cancel, %{data: %{cancelled: true}} = state) do
    Logger.debug(
      "trans: transaction is already cancelled. state: #{inspect(state, @inspect_opts)}"
    )

    {:keep_state, state}
  end

  def trying(:cast, :cancel, %{data: %{cancelled: false, outreq: out_req} = data} = state) do
    Logger.debug("trans: canceling client transaction. state: #{inspect(state, @inspect_opts)}")
    # Generate CANCEL request from original request
    cancel_req = %{
      method: :cancel,
      request_uri: out_req.request_uri,
      headers: %{
        "call-id" => out_req.headers["call-id"],
        "from" => out_req.headers["from"],
        "to" => out_req.headers["to"],
        "cseq" => %{number: out_req.headers["cseq"].number, method: :cancel},
        "via" => out_req.headers["via"]
      }
    }

    _ = client_new(cancel_req, %{}, fn _ -> :ok end)
    # Schedule cancel timeout
    {:keep_state, %{state | data: %{data | cancelled: true}},
     [{:state_timeout, 32_000, :cancel_timeout}]}
  end

  # Handle set_owner events
  def trying(:cast, {:set_owner, code, pid}, %{owner_mon: ref, data: data} = state) do
    Logger.debug(
      "trans: set owner to: #{inspect(pid)} with code: #{inspect(code)}. state: #{inspect(data)}"
    )

    if ref, do: Process.demonitor(ref, [:flush])
    new_ref = Process.monitor(pid)
    new_inner_data = Map.put(data, :auto_resp, code)
    new_state = %{state | owner_mon: new_ref, data: new_inner_data}
    {:keep_state, new_state}
  end

  def trying(_event_type, _event, state) do
    Logger.warning("TransactionStatem.trying/3: Ignoring unexpected event")
    {:keep_state, state}
  end

  # PROCEEDING STATE
  def proceeding(:cast, event, state), do: handle_common_event(event, state)

  def proceeding(_event_type, _event, state) do
    Logger.warning("TransactionStatem.proceeding/3: Ignoring unexpected event")
    {:keep_state, state}
  end

  # CALLING STATE
  def calling(
        :cast,
        {:received, %{type: :response, status_code: status_code} = response},
        %{type: :client, data: data} = state
      )
      when status_code >= 100 and status_code < 200 do
    Logger.debug(
      "Client transaction received provisional response: #{response.status_code} #{response.reason_phrase}"
    )

    # Call the user callback with the response
    if is_function(data.handler) do
      data.handler.({:response, response})
    end

    # Provisional response - stay in calling state
    {:keep_state, state}
  end

  def calling(
        :cast,
        {:received, %{type: :response, status_code: status_code} = response},
        %{type: :client, data: data} = state
      )
      when status_code >= 200 do
    Logger.debug(
      "Client transaction received final response: #{response.status_code} #{response.reason_phrase}"
    )

    # Call the user callback with the response
    if is_function(data.handler) do
      data.handler.({:response, response})
    end

    # Final response - move to completed state
    {:next_state, :completed, state}
  end

  def calling(:cast, event, state), do: handle_common_event(event, state)

  def calling(_event_type, _event, state) do
    Logger.warning("TransactionStatem.calling/3: Ignoring unexpected event")
    {:keep_state, state}
  end

  # COMPLETED STATE
  # Handle sending responses in completed state for retransmissions
  def completed(:cast, {:send, _response}, %{data: %{transaction: transaction}} = state) do
    Logger.debug(
      "completed state: processing {:send, response} for transaction type: #{transaction.type}"
    )

    # In completed state, we can only retransmit the last response
    if transaction.last_response do
      Logger.debug("Retransmitting last response in completed state")
      Parrot.Sip.Transport.send_response(transaction.last_response, transaction.source)
    end

    {:keep_state, state}
  end

  def completed(:cast, {:received, msg}, %{type: :server} = state) do
    handle_common_event({:received, msg}, state)
  end

  def completed(:cast, {:received, _msg}, %{type: :client} = state) do
    # For client transactions, retransmit last response if available
    if last = get_in(state, [:data, :transaction, :last_response]) do
      source = get_in(state, [:data, :transaction, :source])
      Parrot.Sip.Transport.send_response(last, source)
    end

    {:keep_state, state}
  end

  def completed(:cast, event, state), do: handle_common_event(event, state)

  def completed(_event_type, _event, state) do
    Logger.warning("TransactionStatem.completed/3: Ignoring unexpected event")
    {:keep_state, state}
  end

  # CONFIRMED STATE
  def confirmed(:cast, event, state), do: handle_common_event(event, state)

  def confirmed(_event_type, _event, state) do
    Logger.warning("TransactionStatem.confirmed/3: Ignoring unexpected event")
    {:keep_state, state}
  end

  # TERMINATED STATE
  def terminated(:cast, _event, state) do
    Logger.warning(
      "TransactionStatem.terminated/3: Transaction already terminated, ignoring event"
    )

    {:keep_state, state}
  end

  def terminated(_event_type, _event, state) do
    Logger.warning(
      "TransactionStatem.terminated/3: Transaction already terminated, ignoring event"
    )

    {:keep_state, state}
  end

  # Handle common events across states
  defp handle_common_event({:received, %{type: :response} = sip_msg} = ev, %{data: data} = state) do
    log_response_info(sip_msg, data)
    handle_common_event_impl(ev, state)
  end

  defp handle_common_event({:received, _sip_msg} = ev, state) do
    handle_common_event_impl(ev, state)
  end

  defp handle_common_event(_event, state) do
    {:keep_state, state}
  end

  defp handle_common_event_impl(ev, %{data: %{transaction: transaction} = data} = state) do
    {new_trans, actions} = Parrot.Sip.Transaction.handle_event(ev, transaction)
    new_data = %{data | transaction: new_trans}
    new_state = %{state | data: new_data}

    # Check if the transaction state has changed and we need to transition gen_statem state
    if transaction.state != new_trans.state do
      case process_actions(actions, new_state) do
        {:keep_state_and_data, _} -> {:next_state, new_trans.state, new_state}
        {:keep_state, _} -> {:next_state, new_trans.state, new_state}
        :stop -> {:stop, :normal, new_state}
      end
    else
      case process_actions(actions, new_state) do
        {:keep_state_and_data, _} -> {:keep_state, new_state}
        {:keep_state, _} -> {:keep_state, new_state}
        :stop -> {:stop, :normal, new_state}
      end
    end
  end

  # Add terminate callback
  @impl :gen_statem
  def terminate(reason, _state, data) do
    case reason do
      :normal -> Logger.debug("trans: finished. state: #{inspect(data, @inspect_opts)}")
      _ -> Logger.error("trans: finished with error: #{inspect(reason, @inspect_opts)}")
    end

    :ok
  end

  # Handle info messages
  @impl :gen_statem
  def handle_event(
        :info,
        {:DOWN, ref, :process, pid, _},
        _state,
        %{owner_mon: ref, data: %{transaction: transaction, origmsg: _sip_msg}} = state
      ) do
    if transaction.last_response && transaction.last_response.status_code >= 200 do
      {:keep_state, state}
    else
      handle_owner_down(pid, state)
    end
  end

  def handle_event(
        :info,
        {:event, timer_event},
        _state,
        %{data: %{transaction: transaction} = data} = state
      ) do
    Logger.debug(
      "trans: timer fired #{inspect(timer_event)}. state: #{inspect(state, @inspect_opts)}"
    )

    {new_trans, actions} = Parrot.Sip.Transaction.handle_event({:timer, timer_event}, transaction)
    new_data = %{data | transaction: new_trans}
    new_state = %{state | data: new_data}

    case process_actions(actions, new_state) do
      {:keep_state_and_data, _} -> {:keep_state, new_state}
      {:keep_state, _} -> {:keep_state, new_state}
      :stop -> {:stop, :normal, new_state}
    end
  end

  def handle_event(
        :state_timeout,
        :cancel_timeout,
        _state,
        %{data: %{transaction: transaction, handler: handler}} = state
      ) do
    unless transaction.last_response && transaction.last_response.status_code >= 200 do
      Logger.warning("trans: remote side did not respond after CANCEL request: terminate")

      if is_function(handler) do
        handler.({:stop, :timeout})
      end
    end

    {:stop, :normal, state}
  end

  # Timer expiry for transaction termination (for Timer H/J)
  def handle_event(:state_timeout, :terminate, _state, state) do
    Logger.debug("TransactionStatem: Timer expired, terminating transaction.")
    {:stop, :normal, state}
  end

  # Handle DOWN messages for client transactions
  def handle_event(
        :info,
        {:DOWN, ref, :process, pid, _},
        _state,
        %{owner_mon: ref, data: %{transaction: transaction, outreq: out_req}} = state
      ) do
    request_msg =
      case out_req do
        %{request: msg} -> msg
        %Message{} = msg -> msg
        _ -> nil
      end

    if (request_msg && request_msg.method == :invite) and
         not (transaction.last_response && transaction.last_response.status_code >= 200) do
      Logger.debug(
        "trans: owner is dead: #{inspect(pid)}: cancel transaction. state: #{inspect(state)}"
      )

      {:keep_state, state, [{:next_event, :cast, :cancel}]}
    else
      {:keep_state, state}
    end
  end

  # Handle unexpected messages
  def handle_event(:info, msg, _state, state) do
    Logger.error("trans: unexpected info: #{inspect(msg, @inspect_opts)}")
    {:keep_state, state}
  end

  # Handle unexpected casts
  def handle_event(:cast, msg, _state, state) do
    Logger.error("trans: unexpected cast: #{inspect(msg, @inspect_opts)}")
    {:keep_state, state}
  end

  # Handle unexpected calls
  def handle_event({:call, from}, request, _state, state) do
    Logger.error("trans: unexpected call: #{inspect(request, @inspect_opts)}")
    {:keep_state, state, [{:reply, from, {:error, {:unexpected_call, request}}}]}
  end

  defp log_response_info(sip_msg, data) do
    call_id = sip_msg.headers["call-id"] || "unknown"
    branch = data.logbranch
    method = to_string(sip_msg.method || :unknown)

    Logger.debug(
      "trans: client: response on #{method}: #{sip_msg.status_code} #{sip_msg.reason_phrase}; call-id: #{call_id}; branch: #{branch}"
    )
  end

  defp handle_owner_down(
         pid,
         %{data: %{auto_resp: code, origmsg: origmsg, transaction: transaction} = inner_data} =
           state
       ) do
    Logger.debug(
      "trans: owner is dead: #{inspect(pid)}: auto reply with #{inspect(code)}. state: #{inspect(state)}"
    )

    resp = Message.reply(origmsg, code)
    {new_trans, actions} = Parrot.Sip.Transaction.handle_event({:send, resp}, transaction)
    new_data = %{inner_data | transaction: new_trans}
    new_state = %{state | data: new_data}

    case process_actions(actions, new_state) do
      {:keep_state_and_data, _} -> {:keep_state, new_state}
      {:keep_state, _} -> {:keep_state, new_state}
      :stop -> {:stop, :normal, new_state}
    end
  end

  # Private functions
  defp find_server(sip_msg) do
    Logger.debug("trans: attempting to generate_id")
    trans_id = Transaction.generate_id(sip_msg)
    Logger.debug("#{inspect(trans_id)}")

    case Registry.lookup(Parrot.Registry, trans_id) do
      [{pid, _}] when is_pid(pid) -> {:ok, pid}
      _ -> :error
    end
  end

  # Returns a Registry tuple using the branch parameter from the topmost Via header.
  #
  # This is used for RFC 3261 transaction matching, where the branch parameter uniquely
  # identifies a transaction. See RFC 3261 Section 17.2.3.
  # Accepts a %Parrot.Sip.Transaction{} and extracts the branch or id for Registry.
  defp via_tuple(%Parrot.Sip.Transaction{id: id}) when is_binary(id) do
    Logger.debug("via_tuple: Using transaction ID: #{id}")
    {:via, Registry, {Parrot.Registry, id}}
  end

  defp via_tuple(%Parrot.Sip.Transaction{branch: branch}) when is_binary(branch) do
    Logger.debug("via_tuple: Fallback to branch (no ID): #{branch}")
    {:via, Registry, {Parrot.Registry, branch}}
  end

  # Helper to start a transaction with error handling
  # Helper function to handle in-dialog requests
  defp handle_in_dialog_request(%Message{} = sip_msg, handler) do
    Logger.debug("Handling in-dialog request: #{sip_msg.method}")

    # Create a new transaction for the in-dialog request
    transaction =
      case Transaction.determine_transaction_type(sip_msg) do
        :non_invite_server ->
          {:ok, t} = Transaction.create_non_invite_server(sip_msg)
          t

        :invite_server ->
          {:ok, t} = Transaction.create_invite_server(sip_msg)
          t

        other ->
          raise ArgumentError,
                "Unsupported transaction type for in-dialog request: #{inspect(other)}"
      end

    # Start the transaction which will handle the request through the normal flow
    start_transaction([transaction, handler])
  end

  # Helper function to generate transaction ID for CANCEL requests
  defp generate_cancel_transaction_id(%Message{} = cancel_msg) do
    # CANCEL uses same transaction ID as the INVITE it's cancelling
    # but with INVITE method instead of CANCEL
    invite_cseq = %{Message.cseq(cancel_msg) | method: :invite}

    invite_msg = %{
      cancel_msg
      | method: :invite,
        headers: Map.put(cancel_msg.headers, "cseq", invite_cseq)
    }

    Transaction.generate_id(invite_msg)
  end

  defp start_transaction(args) do
    case Parrot.Sip.Transaction.Supervisor.start_child(args) do
      {:ok, _} ->
        :ok

      {:error, _} = error ->
        Logger.error("server failed to create transaction: #{inspect(error, @inspect_opts)}")
    end
  end
end
