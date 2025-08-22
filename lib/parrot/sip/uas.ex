defmodule Parrot.Sip.UAS do
  @moduledoc """
  Parrot SIP Stack
  UAS (User Agent Server)

  This module provides functionality for the server side of SIP transactions,
  including handling incoming requests and generating responses.
  """

  alias Parrot.Sip.Transaction
  alias Parrot.Sip.DialogStatem
  alias Parrot.Sip.Handler
  alias Parrot.Sip.TransactionStatem
  alias Parrot.Sip.Message

  require Logger

  @spec process(any(), Message.t(), Handler.handler()) ::
          :ok
  def process(trans, sip_msg0, handler) do
    Logger.debug("UAS: process #{inspect(sip_msg0.method)}")

    process_list = [
      fn sip_msg ->
        # Replace ersip_uas.process_request with pure Elixir validation
        validate_request(sip_msg)
      end,
      fn sip_msg ->
        Logger.debug("UAS: process_request #{inspect(sip_msg.method)}")

        # Check if this is an in-dialog request
        DialogStatem.uas_request(sip_msg)
        Logger.debug("UAS: process_request process #{inspect(sip_msg.method)}")
        {:process, sip_msg}
      end,
      fn sip_msg ->
        case sip_msg.method == :cancel do
          false -> {:process, sip_msg}
          true -> TransactionStatem.server_cancel(sip_msg)
        end
      end,
      fn sip_msg ->
        # Instead of make_uas, use the Transaction struct directly.
        # Handler.uas_request expects a transaction struct with role: :uas
        Handler.uas_request(trans, sip_msg, handler)
      end
    ]

    case do_process(process_list, sip_msg0) do
      {:reply, resp} -> TransactionStatem.server_response(resp, trans)
      _ -> :ok
    end
  end

  @spec process_ack(Message.t(), Handler.handler()) :: :ok
  def process_ack(req_sip_msg, _handler) do
    # Try to find dialog for ACK
    case DialogStatem.uas_find(req_sip_msg) do
      {:ok, _dialog} ->
        Logger.debug("uas: found dialog for ACK")
      :not_found ->
        Logger.debug("uas: cannot find dialog for ACK")
    end
    :ok
  end

  @spec process_cancel(Transaction.t(), Handler.handler()) :: :ok
  def process_cancel(trans, handler) do
    id = {:uas_id, trans}
    # TODO: in-dialog CANCEL?
    Handler.uas_cancel(id, handler)
  end

  @spec response(Message.t(), Transaction.t()) :: :ok
  def response(resp_sip_msg0, %Transaction{request: req_sip_msg} = transaction) do
    Logger.debug("UAS: response #{inspect(resp_sip_msg0.method)}")
    resp_sip_msg = DialogStatem.uas_response(resp_sip_msg0, req_sip_msg)
    TransactionStatem.server_response(resp_sip_msg, transaction)
  end

  @spec response_retransmit(Message.t(), Transaction.t()) :: :ok
  def response_retransmit(resp_sip_msg, transaction) do
    TransactionStatem.server_response(resp_sip_msg, transaction)
  end

  @spec sipmsg(Transaction.t()) :: Message.t()
  def sipmsg(%Transaction{request: req_sip_msg}), do: req_sip_msg

  @spec make_reply(integer(), binary(), Transaction.t(), Message.t()) :: Message.t()
  def make_reply(code, reason_phrase, %Transaction{} = _transaction, req_sip_msg) do
    Logger.debug("UAS: make_reply #{inspect(code)} #{inspect(reason_phrase)}")

    # Create response using Message.reply
    response = Message.reply(req_sip_msg, code, reason_phrase)

    # For dialog-creating responses (2xx to INVITE/SUBSCRIBE), add a To tag if not present
    case {response.headers["to"], code, req_sip_msg.method} do
      {%{parameters: params} = to_header, status_code, method}
      when status_code >= 200 and status_code < 300 and
             method in [:invite, :subscribe] ->
        # Check if tag already exists
        if Map.has_key?(params, "tag") do
          response
        else
          # Generate and add To tag for dialog-creating responses
          tag = generate_tag()
          updated_to = %{to_header | parameters: Map.put(params, "tag", tag)}
          %{response | headers: Map.put(response.headers, "to", updated_to)}
        end

      _ ->
        # Keep response as is (non-dialog creating)
        response
    end
  end

  @spec set_owner(integer(), pid(), Transaction.t()) :: :ok
  def set_owner(auto_resp_code, pid, transaction) do
    TransactionStatem.server_set_owner(auto_resp_code, pid, transaction)
  end

  # Internal implementation

  # Generate a random tag for responses
  @spec generate_tag() :: binary()
  defp generate_tag do
    :crypto.strong_rand_bytes(6)
    |> Base.encode32(case: :lower, padding: false)
  end

  # Validate incoming SIP request - replaces ersip_uas.process_request
  @spec validate_request(Message.t()) :: {:process, Message.t()} | {:reply, Message.t()}
  defp validate_request(%Message{method: method} = sip_msg) do
    allowed_methods = [:invite, :ack, :bye, :cancel, :options, :register]

    case method in allowed_methods do
      true ->
        # Method is allowed, continue processing
        {:process, sip_msg}

      false ->
        # Method not allowed, return 405 Method Not Allowed
        response = make_method_not_allowed_response(sip_msg, allowed_methods)
        {:reply, response}
    end
  end

  # Create 405 Method Not Allowed response
  @spec make_method_not_allowed_response(Message.t(), [atom()]) :: Message.t()
  defp make_method_not_allowed_response(req_msg, allowed_methods) do
    allow_header = Enum.map(allowed_methods, &to_string/1) |> Enum.join(", ")

    response = Message.reply(req_msg, 405, "Method Not Allowed")
    %{response | headers: Map.put(response.headers, "allow", allow_header)}
  end

  @spec do_process(
          [
            (Message.t() ->
               :ok | {:process, Message.t()} | {:reply, Message.t()})
          ],
          Message.t()
        ) :: :ok | {:reply, Message.t()}
  defp do_process([], _), do: :ok

  defp do_process([f | rest], sip_msg) do
    case f.(sip_msg) do
      :ok -> :ok
      {:reply, _} = reply -> reply
      {:process, sip_msg1} -> do_process(rest, sip_msg1)
    end
  end
end
