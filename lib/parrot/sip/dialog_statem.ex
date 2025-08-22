defmodule Parrot.Sip.DialogStatem do
  @moduledoc """
  SIP Dialog State Machine

  States:
  - :early       - Initial state for early dialogs
  - :confirmed   - State for established dialogs
  - :terminated  - Terminal state

  Events:
  - {:uas_request, sip_msg}     - Process UAS request
  - {:uas_response, resp, req}  - Process UAS response
  - {:uac_request, sip_msg}     - Process UAC request
  - {:uac_trans_result, result} - Process UAC transaction result
  - {:set_owner, pid}           - Set dialog owner
  """
  @behaviour :gen_statem

  require Logger

  alias Parrot.Sip.{Dialog, Message, Branch}
  alias Parrot.Sip.Headers.{Contact, Via}

  @type trans :: {:trans, pid()}
  @type trans_result :: {:message, any()} | {:stop, any()}
  @type dialog_handle :: pid()
  @type dialog_type :: :invite | :notify
  @type start_link_ret :: {:ok, pid()} | {:error, {:already_started, pid()}} | {:error, term()}

  defmodule Data do
    @moduledoc false
    defstruct [
      # Dialog ID
      :id,
      # Dialog state
      :dialog,
      # Local contact
      :local_contact,
      # Early branch for forked responses
      :early_branch,
      # Log ID for logging
      :log_id,
      # Dialog type (:invite or :notify)
      :dialog_type,
      need_cleanup: true,
      # Owner process monitor
      owner_mon: nil
    ]

    @type t :: %__MODULE__{
            id: String.t() | nil,
            dialog: Dialog.t() | nil,
            local_contact: Contact.t() | nil,
            early_branch: String.t() | nil,
            log_id: String.t() | nil,
            dialog_type: :invite | :notify | nil,
            need_cleanup: boolean(),
            owner_mon: reference() | nil
          }
  end

  # API

  def child_spec(args) do
    %{
      id: __MODULE__,
      start: {__MODULE__, :start_link, [args]},
      type: :worker,
      restart: :temporary,
      shutdown: 5000
    }
  end

  @spec start_link(term()) :: start_link_ret()
  def start_link(args) do
    :gen_statem.start_link(
      {:via, Registry, {Parrot.Registry, via_tuple(args)}},
      __MODULE__,
      args,
      []
    )
  end

  @impl :gen_statem
  def callback_mode, do: :state_functions

  @impl :gen_statem
  def init({:uas, resp_sip_msg, req_sip_msg}) do
    Logger.debug(
      "dialog: init called with UAS args: #{inspect(resp_sip_msg)}, #{inspect(req_sip_msg)}"
    )

    # Create dialog from UAS perspective
    {:ok, dialog} = Dialog.uas_create(req_sip_msg, resp_sip_msg)
    dialog_id = dialog.id

    Logger.info("dialog: initializing with ID #{inspect(dialog_id)}")
    case Registry.register(Parrot.Registry, dialog_id, nil) do
      {:ok, _} -> 
        Logger.info("dialog: successfully registered with ID #{inspect(dialog_id)}")
      {:error, {:already_registered, _}} ->
        Logger.warning("dialog: already registered with ID #{inspect(dialog_id)}")
    end

    data = %Data{
      id: dialog_id,
      dialog: dialog,
      local_contact: Message.get_header(req_sip_msg, "contact"),
      log_id: uas_log_id(resp_sip_msg),
      dialog_type: dialog_type(req_sip_msg)
    }

    # Set a timer for NOTIFY dialogs
    actions =
      if data.dialog_type == :notify do
        # Get expiration from Expires header or default to 3600 seconds
        expires = get_expires(req_sip_msg, 3600)

        Logger.info(
          "dialog #{inspect(data.id)}: setting subscription timeout for #{expires} seconds"
        )

        [{:state_timeout, expires * 1000, :subscription_expired}]
      else
        []
      end

    initial_state = if Dialog.is_early?(dialog), do: :early, else: :confirmed
    Logger.info("dialog #{inspect(data.id)}: starting in #{inspect(initial_state)} state")

    req_method = req_sip_msg.method
    res_method = resp_sip_msg.method
    call_id = Message.get_header(req_sip_msg, "call-id")

    Logger.metadata(
      dialog_id: data.id,
      dialog_type: data.dialog_type,
      req_method: req_method,
      res_method: res_method,
      call_id: call_id
    )

    {:ok, initial_state, data, actions}
  end

  def init({:uac, out_req, resp_sip_msg}) do
    # Create dialog from UAC perspective
    # Dialog.uac_create always returns {:ok, dialog}
    {:ok, dialog} = Dialog.uac_create(out_req, resp_sip_msg)
    dialog_id = dialog.id

    # Handle early branch for provisional responses
    early_branch =
      if resp_sip_msg.status_code >= 100 and resp_sip_msg.status_code < 200 do
        branch = get_branch_from_request(out_req)
        branch_key = "branch:" <> branch
        Logger.debug("dialog: early branch #{inspect(branch_key)}")
        Registry.register(Parrot.Registry, branch_key, nil)
        branch
      else
        nil
      end

    Logger.debug("dialog: init #{inspect(dialog_id)}")
    Logger.debug("dialog: early branch #{inspect(early_branch)}")
    Registry.register(Parrot.Registry, dialog_id, nil)

    data = %Data{
      id: dialog_id,
      dialog: dialog,
      local_contact: Message.get_header(out_req, "contact"),
      early_branch: early_branch,
      log_id: uac_log_id(resp_sip_msg),
      dialog_type: dialog_type(out_req)
    }

    Logger.debug("dialog: data #{inspect(data)}")
    initial_state = if Dialog.is_early?(dialog), do: :early, else: :confirmed
    Logger.info("dialog #{inspect(dialog_id)}: starting in #{inspect(initial_state)} state")
    {:ok, initial_state, data}
  end

  @spec uas_find(Message.t()) :: {:ok, dialog_handle()} | :not_found
  def uas_find(%Message{} = req_sip_msg) do
    # Try to extract dialog ID from the message
    dialog_id = Dialog.from_message(req_sip_msg)
    
    if Dialog.is_complete?(dialog_id) do
      dialog_id_str = Dialog.to_string(dialog_id)
      Logger.info("uas_find: looking for dialog with ID #{inspect(dialog_id_str)}")
      result = find_dialog(dialog_id_str)
      case result do
        {:ok, pid} -> 
          Logger.info("uas_find: found dialog #{inspect(dialog_id_str)} at PID #{inspect(pid)}")
          {:ok, pid}
        {:error, :no_dialog} -> 
          Logger.warning("uas_find: dialog #{inspect(dialog_id_str)} not found in registry")
          :not_found
      end
    else
      Logger.debug("uas_find: incomplete dialog ID, not searching")
      :not_found
    end
  end

  @spec uas_request(Message.t()) :: :process | {:reply, Message.t()}
  def uas_request(%Message{} = sip_msg) do
    Logger.debug("dialog: uas_request #{inspect(sip_msg)}")

    # Check if this message has a complete dialog ID
    dialog_id = Dialog.from_message(sip_msg)

    if Dialog.is_complete?(dialog_id) do
      dialog_id_str = Dialog.to_string(dialog_id)
      Logger.debug("dialog: found dialog id #{inspect(dialog_id_str)} in request")

      case find_dialog(dialog_id_str) do
        {:error, :no_dialog} ->
          Logger.debug("dialog #{uas_log_id(sip_msg)}: dialog not found (dialog tracking not yet implemented)")
          resp = Message.reply(sip_msg, 481, "Call/Transaction Does Not Exist")
          {:reply, resp}

        {:ok, dialog_pid} ->
          Logger.debug("dialog #{inspect(dialog_pid)}: found dialog")

          try do
            :gen_statem.call(dialog_pid, {:uas_request, sip_msg})
          catch
            :exit, {reason, _} when reason in [:normal, :noproc] ->
              resp = Message.reply(sip_msg, 481, "Call/Transaction Does Not Exist")
              {:reply, resp}
          end
      end
    else
      Logger.debug("dialog: no complete dialog id in request")
      uas_validate_request(sip_msg)
    end
  end

  @spec uas_response(Message.t(), Message.t()) :: Message.t()
  def uas_response(%Message{} = resp_sip_msg, %Message{} = req_sip_msg) do
    Logger.debug("dialog: uas_response #{inspect(resp_sip_msg)}")

    # Check if response creates or continues a dialog
    dialog_id = Dialog.from_message(resp_sip_msg)

    if Dialog.is_complete?(dialog_id) do
      dialog_id_str = Dialog.to_string(dialog_id)
      Logger.debug("dialog: dialog id #{inspect(dialog_id_str)} in response")

      case find_dialog(dialog_id_str) do
        {:error, :no_dialog} ->
          Logger.debug("dialog #{uas_log_id(resp_sip_msg)}: dialog not found (dialog tracking not yet implemented)")
          uas_maybe_create_dialog(resp_sip_msg, req_sip_msg)

        {:ok, dialog_pid} ->
          Logger.debug("dialog #{inspect(dialog_pid)}: found dialog")
          uas_pass_response(dialog_pid, resp_sip_msg, req_sip_msg)
      end
    else
      Logger.debug("dialog: no complete dialog id in response")
      resp_sip_msg
    end
  end

  @spec uac_request(String.t(), Message.t()) ::
          {:ok, Message.t()} | {:error, :no_dialog}
  def uac_request(dialog_id, sip_msg) do
    case find_dialog(dialog_id) do
      {:ok, dialog_pid} ->
        :gen_statem.call(dialog_pid, {:uac_request, sip_msg})

      {:error, reason} ->
        {:error, reason}
    end
  end

  @spec uac_result(Message.t(), trans_result()) :: :ok
  def uac_result(%Message{} = out_req, trans_result) do
    # Extract dialog ID from the request
    dialog_id = Dialog.from_message(out_req)

    if Dialog.is_complete?(dialog_id) do
      dialog_id_str = Dialog.to_string(dialog_id)

      case find_dialog(dialog_id_str) do
        {:error, :no_dialog} ->
          Logger.warning(
            "dialog: #{uac_log_id(out_req)} is not found for request #{out_req.method}"
          )

          :ok

        {:ok, dialog_pid} ->
          uac_trans_result(dialog_pid, trans_result)
      end
    else
      uac_no_dialog_result(out_req, trans_result)
    end
  end

  @spec set_owner(pid(), String.t()) :: :ok
  def set_owner(pid, dialog_id) when is_pid(pid) do
    case find_dialog(dialog_id) do
      {:ok, dialog_pid} ->
        :gen_statem.cast(dialog_pid, {:set_owner, pid})

      {:error, :no_dialog} ->
        :ok
    end
  end

  @spec count() :: non_neg_integer()
  def count do
    Parrot.Sip.Dialog.Supervisor.num_active()
  end

  @spec find_dialog(String.t()) :: {:ok, pid()} | {:error, :no_dialog}
  def find_dialog(dialog_id) do
    Logger.debug("find_dialog: searching for #{inspect(dialog_id)}")
    case Registry.lookup(Parrot.Registry, dialog_id) do
      [{pid, _}] -> 
        Logger.debug("find_dialog: found PID #{inspect(pid)} for #{inspect(dialog_id)}")
        {:ok, pid}
      [] -> 
        Logger.debug("find_dialog: no PID found for #{inspect(dialog_id)}")
        {:error, :no_dialog}
    end
  end

  # State Functions

  # Early state
  def early({:call, from}, {:uas_request, req_sip_msg}, data) do
    process_uas_request(:early, req_sip_msg, data, from)
  end

  def early(:cast, {:uas_response, resp_sip_msg, req_sip_msg}, data) do
    process_uas_response(:early, resp_sip_msg, req_sip_msg, data)
  end

  def early(:cast, {:uac_trans_result, trans_result}, data) do
    process_uac_trans_result(:early, trans_result, data)
  end

  def early({:call, from}, {:uac_request, req_sip_msg}, data) do
    process_uac_request(:early, req_sip_msg, data, from)
  end

  def early(:cast, {:set_owner, pid}, data) do
    process_set_owner(:early, pid, data)
  end

  def early(:info, {:DOWN, _ref, :process, _pid, _reason}, data) do
    Logger.info("dialog #{inspect(data.id)}: owner process terminated")
    {:stop, :normal}
  end

  def early(event_type, event_content, data) do
    handle_event(event_type, event_content, data)
  end

  # Confirmed state
  def confirmed({:call, from}, {:uas_request, req_sip_msg}, data) do
    process_uas_request(:confirmed, req_sip_msg, data, from)
  end

  def confirmed(:cast, {:uas_response, resp_sip_msg, req_sip_msg}, data) do
    process_uas_response(:confirmed, resp_sip_msg, req_sip_msg, data)
  end

  def confirmed(:cast, {:uac_trans_result, trans_result}, data) do
    process_uac_trans_result(:confirmed, trans_result, data)
  end

  def confirmed({:call, from}, {:uac_request, req_sip_msg}, data) do
    process_uac_request(:confirmed, req_sip_msg, data, from)
  end

  def confirmed(:cast, {:set_owner, pid}, data) do
    process_set_owner(:confirmed, pid, data)
  end

  def confirmed(:state_timeout, :subscription_expired, data) do
    Logger.info("dialog #{inspect(data.id)}: subscription expired")
    {:stop, :normal}
  end

  def confirmed(:info, {:DOWN, _ref, :process, _pid, _reason}, data) do
    Logger.info("dialog #{inspect(data.id)}: owner process terminated")
    {:stop, :normal}
  end

  def confirmed(event_type, event_content, data) do
    handle_event(event_type, event_content, data)
  end

  # Terminated state
  def terminated(_, _, _data) do
    {:stop, :normal}
  end

  # Private Functions

  defp process_uas_request(state, req_sip_msg, data, from) do
    # Process the request in the dialog
    # Dialog.uas_process always returns {:ok, updated_dialog}
    {:ok, updated_dialog} = Dialog.uas_process(req_sip_msg, data.dialog)
    updated_data = %{data | dialog: updated_dialog}

    # Check if dialog should transition states
    new_state = if updated_dialog.state == :terminated, do: :terminated, else: state

    {:next_state, new_state, updated_data, [{:reply, from, :process}]}
  end

  defp process_uas_response(:early, %Message{status_code: status_code}, _req_sip_msg, data)
       when status_code >= 200 and status_code < 300 do
    {:next_state, :confirmed, data}
  end

  defp process_uas_response(state, _resp_sip_msg, _req_sip_msg, data) do
    {:next_state, state, data}
  end

  defp process_uac_trans_result(state, {:message, resp_sip_msg}, data) do
    # Process response in dialog context
    # Dialog.uac_response always returns {:ok, updated_dialog}
    {:ok, updated_dialog} = Dialog.uac_response(resp_sip_msg, data.dialog)
    updated_data = %{data | dialog: updated_dialog}

    # Check state transitions
    new_state = determine_new_state(state, updated_dialog.state)
    {:next_state, new_state, updated_data}
  end

  defp process_uac_trans_result(_state, {:stop, _reason}, _data) do
    {:stop, :normal}
  end

  defp determine_new_state(_current, :terminated), do: :terminated
  defp determine_new_state(:early, :confirmed), do: :confirmed
  defp determine_new_state(current, _), do: current

  defp process_uac_request(_state, req_sip_msg, data, from) do
    # Create in-dialog request
    # Dialog.uac_request always returns {:ok, request, updated_dialog}
    {:ok, request, updated_dialog} = Dialog.uac_request(req_sip_msg.method, data.dialog)
    updated_data = %{data | dialog: updated_dialog}
    {:keep_state, updated_data, [{:reply, from, {:ok, request}}]}
  end

  defp process_set_owner(_state, pid, data) do
    # Monitor the owner process
    if data.owner_mon do
      Process.demonitor(data.owner_mon)
    end

    mon = Process.monitor(pid)
    updated_data = %{data | owner_mon: mon}

    {:keep_state, updated_data}
  end

  defp handle_event(:enter, _old_state, _data) do
    :keep_state_and_data
  end

  defp handle_event({:call, from}, event_content, data) do
    Logger.warning("dialog #{inspect(data.id)}: unexpected call: #{inspect(event_content)}")
    # Reply with an error for unexpected calls
    {:keep_state_and_data, [{:reply, from, {:error, :unexpected_call}}]}
  end

  defp handle_event(event_type, event_content, data) do
    Logger.warning(
      "dialog #{inspect(data.id)}: unexpected event #{inspect(event_type)}: #{inspect(event_content)}"
    )

    :keep_state_and_data
  end

  # Helper functions

  defp via_tuple({:uas, resp_sip_msg, _req_sip_msg}) do
    dialog_id = Dialog.from_message(resp_sip_msg)
    {:dialog, Dialog.to_string(dialog_id)}
  end

  defp via_tuple({:uac, _out_req, resp_sip_msg}) do
    dialog_id = Dialog.from_message(resp_sip_msg)
    {:dialog, Dialog.to_string(dialog_id)}
  end

  defp dialog_type(%Message{method: :notify}), do: :notify
  defp dialog_type(%Message{method: :subscribe}), do: :notify
  defp dialog_type(%Message{method: _}), do: :invite

  defp uas_log_id(%Message{} = msg) do
    call_id = Message.get_header(msg, "call-id")
    method = msg.method
    "#{method} #{call_id}"
  end

  defp uac_log_id(%Message{} = msg) do
    call_id = Message.get_header(msg, "call-id")
    method = if msg.type == :request, do: msg.method, else: "response"
    "#{method} #{call_id}"
  end

  defp get_expires(%Message{} = msg, default) do
    case Message.get_header(msg, "expires") do
      nil -> default
      expires when is_integer(expires) -> expires
      expires when is_binary(expires) -> parse_expires_string(expires, default)
      _ -> default
    end
  end

  defp parse_expires_string(expires, default) do
    case Integer.parse(expires) do
      {val, _} -> val
      :error -> default
    end
  end

  defp get_branch_from_request(%Message{} = request) do
    case Message.get_header(request, "via") do
      %Via{parameters: %{"branch" => branch}} ->
        branch

      [%Via{parameters: %{"branch" => branch}} | _] ->
        branch

      _ ->
        Branch.generate()
    end
  end

  defp uas_validate_request(%Message{} = _sip_msg) do
    # For now, just allow processing
    # In a real implementation, this would validate the request
    :process
  end

  defp uas_maybe_create_dialog(%Message{} = resp_sip_msg, %Message{} = req_sip_msg) do
    # Check if this response creates a dialog
    if should_create_dialog?(resp_sip_msg, req_sip_msg) do
      Logger.info("Creating dialog for #{req_sip_msg.method} response #{resp_sip_msg.status_code}")
      # Start a new dialog
      case Parrot.Sip.Dialog.Supervisor.start_child({:uas, resp_sip_msg, req_sip_msg}) do
        {:ok, pid} ->
          Logger.info("Dialog created successfully with PID: #{inspect(pid)}")
          resp_sip_msg

        {:error, reason} ->
          Logger.error("Failed to create dialog: #{inspect(reason)}")
          resp_sip_msg
      end
    else
      Logger.debug("Not creating dialog for #{req_sip_msg.method} response #{resp_sip_msg.status_code}")
      resp_sip_msg
    end
  end

  defp should_create_dialog?(%Message{status_code: status_code}, %Message{method: method})
       when status_code >= 200 and status_code < 300 do
    # Dialogs are created by 2xx responses to INVITE or SUBSCRIBE
    # Convert to atom if it's a string
    method_atom = if is_binary(method), do: String.to_atom(String.downcase(method)), else: method
    result = method_atom in [:invite, :subscribe]
    Logger.debug("should_create_dialog? method=#{inspect(method)} (#{inspect(method_atom)}), status=#{status_code}, result=#{result}")
    result
  end

  defp should_create_dialog?(resp, req) do
    Logger.debug("should_create_dialog? not 2xx: resp status=#{inspect(resp.status_code)}, req method=#{inspect(req.method)}")
    false
  end

  defp uas_pass_response(dialog_pid, resp_sip_msg, req_sip_msg) do
    :gen_statem.cast(dialog_pid, {:uas_response, resp_sip_msg, req_sip_msg})
    resp_sip_msg
  end

  defp uac_no_dialog_result(%Message{} = out_req, {:message, resp_sip_msg}) do
    # Check if this response creates a dialog
    if should_create_dialog?(resp_sip_msg, out_req) do
      start_uac_dialog(out_req, resp_sip_msg)
    end

    :ok
  end

  defp uac_no_dialog_result(_out_req, {:stop, _reason}), do: :ok

  defp start_uac_dialog(out_req, resp_sip_msg) do
    case Parrot.Sip.Dialog.Supervisor.start_child({:uac, out_req, resp_sip_msg}) do
      {:ok, _pid} ->
        :ok

      {:error, reason} ->
        Logger.warning("Failed to create dialog: #{inspect(reason)}")
        :ok
    end
  end

  defp uac_trans_result(dialog_pid, trans_result) do
    :gen_statem.cast(dialog_pid, {:uac_trans_result, trans_result})
    :ok
  end
end
