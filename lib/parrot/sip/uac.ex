defmodule Parrot.Sip.UAC do
  @moduledoc """
  Parrot SIP Stack
  UAC (User Agent Client)

  This module provides functionality for the client side of SIP transactions,
  including sending requests and handling responses.
  """

  alias Parrot.Sip.{Transaction, Dialog, Message, Branch, Uri}
  alias Parrot.Sip.Transport.Udp
  alias Parrot.Sip.TransactionStatem
  alias Parrot.Sip.Headers.Via

  @type callback :: (client_trans_result -> any())
  @type client_trans_result :: {:message, any()} | {:stop, any()} | Transaction.client_result()
  @type id :: {:uac_id, Transaction.t()}
  @type options :: %{
          optional(:sip) => map(),
          optional(:owner) => pid()
        }

  @spec request(Message.t(), Uri.t() | String.t(), callback()) :: id()
  def request(%Message{} = sip_msg, _nexthop, uac_callback) do
    # Generate a random branch for this transaction
    branch = Branch.generate()

    # Add the branch to the topmost Via header
    sip_msg = add_branch_to_via(sip_msg, branch)

    # nexthop is passed to transport layer, not stored in message

    # Create the transaction based on method
    {:ok, transaction} = create_client_transaction(sip_msg, branch)

    callback_fun = make_transaction_handler(transaction, uac_callback)
    trans = TransactionStatem.client_new(transaction, %{}, callback_fun)
    {:uac_id, trans}
  end

  @spec request(Message.t(), callback()) :: id()
  def request(%Message{} = sip_msg, uac_callback) do
    # Generate a random branch for this transaction
    branch = Branch.generate()

    # Add the branch to the topmost Via header
    sip_msg = add_branch_to_via(sip_msg, branch)

    # Create the transaction based on method
    {:ok, transaction} = create_client_transaction(sip_msg, branch)

    callback_fun = make_transaction_handler(transaction, uac_callback)
    trans = TransactionStatem.client_new(transaction, %{}, callback_fun)
    {:uac_id, trans}
  end

  @spec request_with_opts(Message.t(), options(), callback()) :: id()
  def request_with_opts(%Message{} = sip_msg, uac_options, uac_callback) do
    # Generate a random branch for this transaction
    branch = Branch.generate()

    # Add the branch to the topmost Via header
    sip_msg = add_branch_to_via(sip_msg, branch)

    # Create the transaction based on method
    {:ok, transaction} = create_client_transaction(sip_msg, branch)

    callback_fun = make_transaction_handler(transaction, uac_callback)
    trans = TransactionStatem.client_new(transaction, uac_options, callback_fun)
    {:uac_id, trans}
  end

  @spec ack_request(Message.t()) :: :ok
  def ack_request(%Message{} = sip_msg) do
    # Generate a random branch for this transaction
    branch = Branch.generate()

    # Add the branch to the topmost Via header
    sip_msg = add_branch_to_via(sip_msg, branch)

    # ACK is sent directly, not through transaction layer
    # Extract destination from request URI
    case extract_destination_from_request_uri(sip_msg.request_uri) do
      {:ok, host, port} ->
        # Create outbound request map for Transport
        out_req = %{
          message: sip_msg,
          destination: {host, port}
        }
        
        Parrot.Sip.Transport.Udp.send_request(out_req)
      
      {:error, reason} ->
        require Logger
        Logger.error("Failed to extract destination from request URI: #{inspect(reason)}")
        :ok
    end
  end

  @spec cancel(id()) :: :ok
  def cancel({:uac_id, trans}) do
    TransactionStatem.client_cancel(trans)
  end

  # Internal Implementation

  @spec make_transaction_handler(Transaction.t(), callback()) :: callback()
  defp make_transaction_handler(transaction, cb) do
    fn
      {:stop, :normal} ->
        :ok

      trans_result ->
        Dialog.uac_result(transaction.request, trans_result)
        cb.(trans_result)
    end
  end

  @spec add_branch_to_via(Message.t(), String.t()) :: Message.t()
  defp add_branch_to_via(%Message{headers: headers} = msg, branch) do
    # Get the Via headers
    via_headers = Map.get(headers, "via", [])

    # Update the topmost Via header with the branch
    updated_via_headers =
      case via_headers do
        [first_via | rest] ->
          # Parse the Via header if it's a string
          via =
            case first_via do
              %Via{} = v -> v
              str when is_binary(str) -> Via.parse(str)
            end

          # Add branch parameter
          updated_via = Via.with_parameter(via, "branch", branch)
          [updated_via | rest]

        [] ->
          # No Via headers, this shouldn't happen for a proper request
          # but we'll handle it gracefully
          []
      end

    # Update the message with the new Via headers
    %{msg | headers: Map.put(headers, "via", updated_via_headers)}
  end

  @spec create_client_transaction(Message.t(), String.t()) :: {:ok, Transaction.t()}
  defp create_client_transaction(%Message{method: method} = request, branch) do
    # Ensure the request has the branch in its Via header
    request_with_branch = add_branch_to_via(request, branch)

    # Create transaction based on method
    case String.upcase(to_string(method)) do
      "INVITE" -> Transaction.create_invite_client(request_with_branch)
      _ -> Transaction.create_non_invite_client(request_with_branch)
    end
  end

  @spec extract_destination_from_request_uri(String.t()) :: {:ok, String.t(), integer()} | {:error, term()}
  defp extract_destination_from_request_uri(request_uri) do
    case Uri.parse(request_uri) do
      {:ok, %Uri{host: host, port: port}} ->
        # Use default SIP port if not specified
        port = port || 5060
        {:ok, host, port}
      error ->
        error
    end
  end
end
