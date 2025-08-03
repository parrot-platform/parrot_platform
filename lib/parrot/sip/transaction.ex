defmodule Parrot.Sip.Transaction do
  @moduledoc """
  Implementation of SIP transaction management according to RFC 3261 Section 17.

  A SIP transaction consists of a single request and any responses to that request,
  which include zero or more provisional responses and one or more final responses.
  Transactions are a fundamental component of the SIP protocol, providing reliability,
  message sequencing, and state management.

  As defined in RFC 3261, there are four types of transactions:
  - INVITE Client Transaction (Section 17.1.1)
  - Non-INVITE Client Transaction (Section 17.1.2)
  - INVITE Server Transaction (Section 17.2.1)
  - Non-INVITE Server Transaction (Section 17.2.2)

  Each transaction type has its own state machine and handling rules.

  This module provides functionality for:
  - Creating client and server transactions
  - Generating transaction IDs and branch parameters
  - Managing transaction state transitions
  - Handling transaction timeouts and retransmissions
  - Correlating responses to requests

  This module provides the pure functional implementation of SIP transactions.
  For stateful transaction management, see Parrot.Sip.TransactionStatem.

  References:
  - RFC 3261: SIP: Session Initiation Protocol (https://tools.ietf.org/html/rfc3261)
    - Section 17: Transactions
    - Section 8.1.1.7: Transaction Identifier
    - Section 17.1: Client Transaction
    - Section 17.2: Server Transaction
  """

  require Logger

  alias Parrot.Sip.Message
  alias Parrot.Sip.Headers

  @type transaction_type ::
          :invite_client | :non_invite_client | :invite_server | :non_invite_server
  @type transaction_state ::
          :init
          | :calling
          | :proceeding
          | :completed
          | :confirmed
          | :terminated
          | :trying
          | :completed

  @doc """
  Facade function for generating a transaction branch parameter.

  This function initially delegates to ERSIP but will gradually be replaced
  with our pure Elixir implementation.

  RFC 3261 Section 8.1.1.7
  """
  @spec generate_branch(Message.t()) :: String.t()
  def generate_branch(_message) do
    Parrot.Sip.Branch.generate()
  end

  @doc """
  Facade function for generating a transaction ID based on the message type.

  RFC 3261 Section 17
  """
  @spec generate_id(Message.t()) :: String.t()
  def generate_id(message) do
    # TODO: Replace with pure Elixir implementation
    # This will combine method, branch, and other relevant parameters
    branch = get_branch(message)
    generate_transaction_id(determine_transaction_type(message), branch, message)
  end

  # Temporary helper function until Message.method is implemented
  defp get_method(%{method: method}) when is_atom(method), do: method
  defp get_method(_), do: :unknown

  @doc """
  Determines the transaction type based on a message.

  RFC 3261 Section 17
  """
  @spec determine_transaction_type(Message.t()) :: transaction_type()
  def determine_transaction_type(message) do
    sip_method = get_method(message)
    is_request = is_request?(message)

    cond do
      is_request && sip_method == :invite -> :invite_server
      is_request && sip_method != :invite -> :non_invite_server
      !is_request && get_cseq_method(message) == :invite -> :invite_client
      true -> :non_invite_client
    end
  end

  # Temporary helper function until Message.is_request? is implemented
  defp is_request?(%Parrot.Sip.Message{type: :request} = _msg) do
    true
  end

  defp is_request?(_msg) do
    false
  end

  # Temporary helper function until Message.cseq is implemented
  defp get_cseq_method(message) do
    cond do
      is_map(message) && Map.get(message, :headers, %{})["cseq"] ->
        cseq = message.headers["cseq"]
        if is_map(cseq), do: cseq.method, else: :unknown

      true ->
        :unknown
    end
  end

  # This function is already defined as a private function below
  # Removing the duplicate implementation

  @doc """
  Facade function for validating a SIP message for transaction processing.

  This function performs validation on the message according to RFC 3261
  requirements for transaction handling.

  RFC 3261 Section 17
  """
  @spec validate_message(Message.t()) :: {:ok, Message.t()} | {:error, String.t()}
  def validate_message(message) do
    # TODO: Implement thorough message validation
    # For now, basic validation checking required headers
    cond do
      !has_header?(message, "via") ->
        {:error, "Missing Via header"}

      !has_header?(message, "cseq") ->
        {:error, "Missing CSeq header"}

      !has_header?(message, "call-id") ->
        {:error, "Missing Call-ID header"}

      true ->
        {:ok, message}
    end
  end

  # Temporary helper function until Message.has_header? is implemented
  defp has_header?(message, header_name) do
    cond do
      is_map(message) && Map.has_key?(message, :headers) ->
        Map.has_key?(message.headers, header_name)

      true ->
        false
    end
  end

  defstruct [
    # Transaction ID
    :id,
    # Type of transaction
    :type,
    # Current state of the transaction
    :state,
    # Original request
    :request,
    # Last received/sent response
    :last_response,
    # Branch parameter from Via header
    :branch,
    # SIP method of the transaction
    :method,
    # INVITE client retransmission timer
    :timer_a,
    # INVITE client transaction timeout timer
    :timer_b,
    # INVITE server provisional response timer
    :timer_c,
    # Wait time for response retransmits
    :timer_d,
    # Non-INVITE client retransmission timer
    :timer_e,
    # Non-INVITE client transaction timeout timer
    :timer_f,
    # INVITE server response retransmission timer
    :timer_g,
    # Wait time for ACK
    :timer_h,
    # Wait time for ACK retransmits
    :timer_i,
    # Wait time for non-INVITE request retransmits
    :timer_j,
    # Wait time for response retransmits
    :timer_k,
    # Timestamp when transaction was created
    :created_at,
    # Transaction role: :uas or :uac
    :role
  ]

  @type t :: %__MODULE__{
          id: String.t(),
          type: transaction_type(),
          state: transaction_state(),
          request: Message.t(),
          last_response: Message.t() | nil,
          branch: String.t(),
          method: atom(),
          timer_a: reference() | nil,
          timer_b: reference() | nil,
          timer_c: reference() | nil,
          timer_d: reference() | nil,
          timer_e: reference() | nil,
          timer_f: reference() | nil,
          timer_g: reference() | nil,
          timer_h: reference() | nil,
          timer_i: reference() | nil,
          timer_j: reference() | nil,
          timer_k: reference() | nil,
          created_at: integer(),
          role: :uas | :uac | nil
        }

  # Timer defaults (in milliseconds) per RFC 3261
  # These will be used once we replace ERSIP with our pure Elixir implementation
  # Default RTT estimate - used in Timer A, E calculations
  # @timer_t1 500
  # Maximum retransmission interval - used in Timer G calculations
  # @timer_t2 4000
  # Maximum duration a message remains in the network - used in Timer K, I calculations
  # @timer_t4 5000

  @doc """
  Creates a new client transaction for an INVITE request.

  ## Parameters

  - `request`: The SIP INVITE request that initiates the transaction

  ## Returns

  - `{:ok, transaction}`: A new transaction struct
  """
  @spec create_invite_client(Message.t()) :: {:ok, t()}
  def create_invite_client(request) do
    # Extract branch parameter from Via header
    branch = get_branch(request)

    # Create transaction ID
    id = generate_transaction_id(:invite_client, branch, request)

    # Create the transaction in initial state
    transaction = %__MODULE__{
      id: id,
      type: :invite_client,
      state: :init,
      request: request,
      last_response: nil,
      branch: branch,
      method: :invite,
      timer_a: nil,
      timer_b: nil,
      timer_c: nil,
      timer_d: nil,
      timer_e: nil,
      timer_f: nil,
      timer_g: nil,
      timer_h: nil,
      timer_i: nil,
      timer_j: nil,
      timer_k: nil,
      created_at: System.system_time(:millisecond),
      role: :uac
    }

    {:ok, transaction}
  end

  @doc """
  Creates a new client transaction for a non-INVITE request.

  ## Parameters

  - `request`: The SIP request that initiates the transaction

  ## Returns

  - `{:ok, transaction}`: A new transaction struct
  """
  @spec create_non_invite_client(Message.t()) :: {:ok, t()}
  def create_non_invite_client(request) do
    # Extract branch parameter from Via header
    branch = get_branch(request)

    # Create transaction ID
    id = generate_transaction_id(:non_invite_client, branch, request)

    # Create the transaction in initial state
    transaction = %__MODULE__{
      id: id,
      type: :non_invite_client,
      state: :init,
      request: request,
      last_response: nil,
      branch: branch,
      method: request.method,
      timer_a: nil,
      timer_b: nil,
      timer_c: nil,
      timer_d: nil,
      timer_e: nil,
      timer_f: nil,
      timer_g: nil,
      timer_h: nil,
      timer_i: nil,
      timer_j: nil,
      timer_k: nil,
      created_at: System.system_time(:millisecond),
      role: :uac
    }

    {:ok, transaction}
  end

  @doc """
  Creates a new server transaction for an INVITE request.

  ## Parameters

  - `request`: The SIP INVITE request received

  ## Returns

  - `{:ok, transaction}`: A new transaction struct
  """
  @spec create_invite_server(Message.t()) :: {:ok, t()}
  def create_invite_server(request) do
    # Extract branch parameter from Via header
    branch = get_branch(request)

    # Create transaction ID
    id = generate_transaction_id(:invite_server, branch, request)

    # Create the transaction in initial state
    transaction = %__MODULE__{
      id: id,
      type: :invite_server,
      state: :trying,
      request: request,
      last_response: nil,
      branch: branch,
      method: :invite,
      timer_a: nil,
      timer_b: nil,
      timer_c: nil,
      timer_d: nil,
      timer_e: nil,
      timer_f: nil,
      timer_g: nil,
      timer_h: nil,
      timer_i: nil,
      timer_j: nil,
      timer_k: nil,
      created_at: System.system_time(:millisecond),
      role: :uas
    }

    {:ok, transaction}
  end

  @doc """
  Creates a new server transaction for a non-INVITE request.

  ## Parameters

  - `request`: The SIP request received

  ## Returns

  - `{:ok, transaction}`: A new transaction struct
  """
  @spec create_non_invite_server(Message.t()) :: {:ok, t()}
  def create_non_invite_server(request) do
    # Extract branch parameter from Via header
    branch = get_branch(request)

    # Create transaction ID
    id = generate_transaction_id(:non_invite_server, branch, request)

    # Create the transaction in trying state (per RFC 3261 17.2.2)
    transaction = %__MODULE__{
      id: id,
      type: :non_invite_server,
      state: :trying,
      request: request,
      last_response: nil,
      branch: branch,
      method: request.method,
      timer_a: nil,
      timer_b: nil,
      timer_c: nil,
      timer_d: nil,
      timer_e: nil,
      timer_f: nil,
      timer_g: nil,
      timer_h: nil,
      timer_i: nil,
      timer_j: nil,
      timer_k: nil,
      created_at: System.system_time(:millisecond),
      role: :uas
    }

    {:ok, transaction}
  end

  @doc """
  Generates a transaction ID based on the transaction parameters.

  ## Parameters

  - `type`: The transaction type
  - `branch`: The branch parameter from the Via header
  - `request`: The SIP request

  ## Returns

  - A string representing the transaction ID
  """
  @spec generate_transaction_id(transaction_type(), String.t(), Message.t()) :: String.t()
  def generate_transaction_id(type, branch, request) do
    # Transaction ID is determined by branch parameter, method, and direction
    # For client transactions, use "branch:method:client"
    # For server transactions, use "branch:method:cseq"
    case type do
      :invite_client -> "#{branch}:invite:client"
      :non_invite_client -> "#{branch}:#{request.method}:client"
      :invite_server -> "#{branch}:#{request.method}:#{request.headers["cseq"].number}"
      :non_invite_server -> "#{branch}:#{request.method}:#{request.headers["cseq"].number}"
    end
  end

  @doc """
  Processes a response within a client transaction.

  Updates the transaction state based on the received response.

  ## Parameters

  - `response`: The SIP response received
  - `transaction`: The current transaction state

  ## Returns

  - `{:ok, updated_transaction}`: The updated transaction
  """
  @spec receive_response(Message.t(), t()) :: {:ok, t()}
  def receive_response(response, transaction) do
    # Get the response status code
    status_code = response.status_code

    # Define new state based on transaction type and current state
    {new_state, actions} =
      case {transaction.type, transaction.state, status_code} do
        # INVITE client transaction state transitions
        {:invite_client, :calling, code} when code >= 100 and code <= 199 ->
          {:proceeding, [:cancel_timer_a, :cancel_timer_b]}

        {:invite_client, :calling, code} when code >= 200 and code <= 299 ->
          {:terminated, [:cancel_timer_a, :cancel_timer_b]}

        {:invite_client, :calling, code} when code >= 300 and code <= 699 ->
          {:completed, [:cancel_timer_a, :cancel_timer_b, :start_timer_d]}

        {:invite_client, :proceeding, code} when code >= 100 and code <= 199 ->
          {:proceeding, []}

        {:invite_client, :proceeding, code} when code >= 200 and code <= 299 ->
          {:terminated, []}

        {:invite_client, :proceeding, code} when code >= 300 and code <= 699 ->
          {:completed, [:start_timer_d]}

        # Non-INVITE client transaction state transitions
        {:non_invite_client, :trying, code} when code >= 100 and code <= 199 ->
          {:proceeding, [:cancel_timer_e, :cancel_timer_f]}

        {:non_invite_client, :trying, code} when code >= 200 and code <= 699 ->
          {:completed, [:cancel_timer_e, :cancel_timer_f, :start_timer_k]}

        {:non_invite_client, :proceeding, code} when code >= 100 and code <= 199 ->
          {:proceeding, []}

        {:non_invite_client, :proceeding, code} when code >= 200 and code <= 699 ->
          {:completed, [:start_timer_k]}

        # Default: keep current state
        _ ->
          {transaction.state, []}
      end

    # Apply the timer actions
    transaction = apply_timer_actions(transaction, actions)

    # Update the transaction with the new state and response
    updated_transaction = %{transaction | state: new_state, last_response: response}

    {:ok, updated_transaction}
  end

  @doc """
  Processes a request within a server transaction.

  Updates the transaction state based on the received request.

  ## Parameters

  - `request`: The SIP request received
  - `transaction`: The current transaction state

  ## Returns

  - `{:ok, updated_transaction}`: The updated transaction
  """
  @spec receive_request(Message.t(), t()) :: {:ok, t()}
  def receive_request(request, transaction) do
    # Define new state based on transaction type, current state, and request method
    {new_state, actions} =
      case {transaction.type, transaction.state, request.method} do
        # INVITE server transaction: ACK in completed state
        {:invite_server, :completed, :ack} ->
          {:confirmed, [:cancel_timer_g, :cancel_timer_h, :start_timer_i]}

        # Non-INVITE server transactions don't typically receive in-transaction requests
        # other than retransmissions, which are handled at the transport layer

        # Default: keep current state
        _ ->
          {transaction.state, []}
      end

    # Apply the timer actions
    transaction = apply_timer_actions(transaction, actions)

    # Update the transaction with the new state
    updated_transaction = %{transaction | state: new_state}

    {:ok, updated_transaction}
  end

  @doc """
  Sends a provisional response (1xx) in a server transaction.

  ## Parameters

  - `response`: The SIP response to send
  - `transaction`: The current transaction state

  ## Returns

  - `{:ok, updated_transaction}`: The updated transaction
  """
  @spec send_provisional_response(Message.t(), t()) :: {:ok, t()}
  def send_provisional_response(response, transaction) do
    # Validate that response is provisional (1xx)
    unless response.status_code >= 100 and response.status_code <= 199 do
      raise ArgumentError, "Response must be provisional (1xx)"
    end

    # Define new state and actions based on transaction type and current state
    {new_state, actions} =
      case {transaction.type, transaction.state} do
        # INVITE server transaction: sending provisional response
        {:invite_server, :init} ->
          {:proceeding, [:start_timer_c]}

        {:invite_server, :proceeding} ->
          {:proceeding, [:start_timer_c]}

        # Default: invalid state transition
        _ ->
          raise ArgumentError, "Invalid state transition"
      end

    # Apply the timer actions
    transaction = apply_timer_actions(transaction, actions)

    # Update the transaction with the new state and response
    updated_transaction = %{transaction | state: new_state, last_response: response}

    {:ok, updated_transaction}
  end

  @doc """
  Sends a final response (2xx-6xx) in a server transaction.

  ## Parameters

  - `response`: The SIP response to send
  - `transaction`: The current transaction state

  ## Returns

  - `{:ok, updated_transaction}`: The updated transaction
  """
  @spec send_final_response(Message.t(), t()) :: {:ok, t()}
  def send_final_response(response, transaction) do
    # Validate that response is final (2xx-6xx)
    unless response.status_code >= 200 and response.status_code <= 699 do
      raise ArgumentError, "Response must be final (2xx-6xx)"
    end

    # Get the response status code
    status_code = response.status_code

    # Define new state and actions based on transaction type, current state, and status code
    {new_state, actions} =
      case {transaction.type, transaction.state, status_code} do
        # INVITE server transaction: sending 2xx response
        {:invite_server, state, code}
        when state in [:init, :proceeding] and code >= 200 and code <= 299 ->
          {:terminated, [:cancel_timer_c]}

        # INVITE server transaction: sending 3xx-6xx response
        {:invite_server, state, code}
        when state in [:init, :proceeding] and code >= 300 and code <= 699 ->
          {:completed, [:cancel_timer_c, :start_timer_g, :start_timer_h]}

        # Non-INVITE server transaction: sending final response
        {:non_invite_server, :trying, _code} ->
          {:completed, [:start_timer_j]}

        {:non_invite_server, :proceeding, _code} ->
          {:completed, [:start_timer_j]}

        # Default: invalid state transition
        _ ->
          raise ArgumentError, "Invalid state transition"
      end

    # Apply the timer actions
    transaction = apply_timer_actions(transaction, actions)

    # Update the transaction with the new state and response
    updated_transaction = %{transaction | state: new_state, last_response: response}

    {:ok, updated_transaction}
  end

  @doc """
  Starts a client transaction by sending the initial request.

  ## Parameters

  - `transaction`: The transaction to start

  ## Returns

  - `{:ok, updated_transaction}`: The updated transaction
  """
  @spec start_client_transaction(t()) :: {:ok, t()}
  def start_client_transaction(transaction) do
    # Define initial state and actions based on transaction type
    {new_state, actions} =
      case transaction.type do
        :invite_client ->
          {:calling, [:start_timer_a, :start_timer_b]}

        :non_invite_client ->
          {:trying, [:start_timer_e, :start_timer_f]}

        _ ->
          raise ArgumentError, "Not a client transaction"
      end

    # Apply the timer actions
    transaction = apply_timer_actions(transaction, actions)

    # Update the transaction with the new state
    updated_transaction = %{transaction | state: new_state}

    {:ok, updated_transaction}
  end

  @doc """
  Starts a server transaction upon receiving an initial request.

  ## Parameters

  - `transaction`: The transaction to start

  ## Returns

  - `{:ok, updated_transaction}`: The updated transaction
  """
  @spec start_server_transaction(t()) :: {:ok, t()}
  def start_server_transaction(transaction) do
    # Define initial state based on transaction type
    new_state =
      case transaction.type do
        :invite_server -> :proceeding
        :non_invite_server -> :trying
        _ -> raise ArgumentError, "Not a server transaction"
      end

    # Update the transaction with the new state
    updated_transaction = %{transaction | state: new_state}

    {:ok, updated_transaction}
  end

  @doc """
  Checks if a transaction matches the given response.

  ## Parameters

  - `transaction`: The transaction to check
  - `response`: The response to match against

  ## Returns

  - `true` if the transaction matches the response, `false` otherwise
  """
  @spec matches_response?(t(), Message.t()) :: boolean()
  def matches_response?(transaction, response) do
    # Extract the top Via header from the response
    via =
      case response.headers["via"] do
        %Headers.Via{} = via -> via
        [via | _] when is_struct(via, Headers.Via) -> via
        _ -> nil
      end

    if via == nil do
      false
    else
      # Get the branch parameter from the Via header
      response_branch = via.parameters["branch"]

      # Match based on branch, method, and CSeq
      response_branch == transaction.branch &&
        response.headers["cseq"].method == transaction.method &&
        is_client_transaction?(transaction)
    end
  end

  @doc """
  Checks if a transaction matches the given request.

  ## Parameters

  - `transaction`: The transaction to check
  - `request`: The request to match against

  ## Returns

  - `true` if the transaction matches the request, `false` otherwise
  """
  @spec matches_request?(t(), Message.t()) :: boolean()
  def matches_request?(transaction, request) do
    # Extract the top Via header from the request
    via =
      case request.headers["via"] do
        %Headers.Via{} = via -> via
        [via | _] when is_struct(via, Headers.Via) -> via
        _ -> nil
      end

    if via == nil do
      false
    else
      # Get the branch parameter from the Via header
      request_branch = via.parameters["branch"]

      # Match based on branch and method (special case for ACK)
      if request.method == :ack && transaction.method == :invite do
        # For ACK, we match against the original INVITE transaction
        request_branch == transaction.branch &&
          is_server_transaction?(transaction)
      else
        # For other requests, we match directly
        request_branch == transaction.branch &&
          request.method == transaction.method &&
          is_server_transaction?(transaction)
      end
    end
  end

  @doc """
  Terminates a transaction, canceling all timers.

  ## Parameters

  - `transaction`: The transaction to terminate

  ## Returns

  - `{:ok, updated_transaction}`: The updated transaction
  """
  @spec terminate(t()) :: {:ok, t()}
  def terminate(transaction) do
    # Cancel all timers
    transaction =
      apply_timer_actions(transaction, [
        :cancel_timer_a,
        :cancel_timer_b,
        :cancel_timer_c,
        :cancel_timer_d,
        :cancel_timer_e,
        :cancel_timer_f,
        :cancel_timer_g,
        :cancel_timer_h,
        :cancel_timer_i,
        :cancel_timer_j,
        :cancel_timer_k
      ])

    # Update the transaction state to terminated
    updated_transaction = %{transaction | state: :terminated}

    {:ok, updated_transaction}
  end

  @doc """
  Checks if a transaction is a client transaction.

  ## Parameters

  - `transaction`: The transaction to check

  ## Returns

  - `true` if the transaction is a client transaction, `false` otherwise
  """
  @spec is_client_transaction?(t()) :: boolean()
  def is_client_transaction?(transaction) do
    transaction.type in [:invite_client, :non_invite_client]
  end

  @doc """
  Checks if a transaction is a server transaction.

  ## Parameters

  - `transaction`: The transaction to check

  ## Returns

  - `true` if the transaction is a server transaction, `false` otherwise
  """
  @spec is_server_transaction?(t()) :: boolean()
  def is_server_transaction?(transaction) do
    transaction.type in [:invite_server, :non_invite_server]
  end

  @doc """
  Checks if a transaction is terminated.

  ## Parameters

  - `transaction`: The transaction to check

  ## Returns

  - `true` if the transaction is terminated, `false` otherwise
  """
  @spec is_terminated?(t()) :: boolean()
  def is_terminated?(transaction) do
    transaction.state == :terminated
  end

  # Private helper functions

  # Get the branch parameter from a request's Via header
  defp get_branch(request) do
    via =
      case request.headers["via"] do
        %Headers.Via{} = via -> via
        [via | _] when is_struct(via, Headers.Via) -> via
        _ -> raise ArgumentError, "Request must have a Via header"
      end

    via.parameters["branch"]
  end

  # Apply timer actions to a transaction
  defp apply_timer_actions(transaction, actions) do
    Enum.reduce(actions, transaction, fn action, acc ->
      case action do
        :start_timer_a -> start_timer_a(acc)
        :start_timer_b -> start_timer_b(acc)
        :start_timer_c -> start_timer_c(acc)
        :start_timer_d -> start_timer_d(acc)
        :start_timer_e -> start_timer_e(acc)
        :start_timer_f -> start_timer_f(acc)
        :start_timer_g -> start_timer_g(acc)
        :start_timer_h -> start_timer_h(acc)
        :start_timer_i -> start_timer_i(acc)
        :start_timer_j -> start_timer_j(acc)
        :start_timer_k -> start_timer_k(acc)
        :cancel_timer_a -> cancel_timer(acc, :timer_a)
        :cancel_timer_b -> cancel_timer(acc, :timer_b)
        :cancel_timer_c -> cancel_timer(acc, :timer_c)
        :cancel_timer_d -> cancel_timer(acc, :timer_d)
        :cancel_timer_e -> cancel_timer(acc, :timer_e)
        :cancel_timer_f -> cancel_timer(acc, :timer_f)
        :cancel_timer_g -> cancel_timer(acc, :timer_g)
        :cancel_timer_h -> cancel_timer(acc, :timer_h)
        :cancel_timer_i -> cancel_timer(acc, :timer_i)
        :cancel_timer_j -> cancel_timer(acc, :timer_j)
        :cancel_timer_k -> cancel_timer(acc, :timer_k)
      end
    end)
  end

  # Timer functions
  # In a real implementation, these would start actual timers
  # For now, we just set a reference to simulate timer creation

  defp start_timer_a(transaction) do
    # Timer A: INVITE request retransmission timer (T1)
    %{transaction | timer_a: make_ref()}
  end

  defp start_timer_b(transaction) do
    # Timer B: INVITE transaction timeout timer (64*T1)
    %{transaction | timer_b: make_ref()}
  end

  defp start_timer_c(transaction) do
    # Timer C: Proxy INVITE transaction timeout (3 min RFC 3261)
    # Cancel existing timer if any
    transaction = cancel_timer(transaction, :timer_c)
    %{transaction | timer_c: make_ref()}
  end

  defp start_timer_d(transaction) do
    # Timer D: Wait time for response retransmits (32s for UDP, 0s for TCP/SCTP)
    %{transaction | timer_d: make_ref()}
  end

  defp start_timer_e(transaction) do
    # Timer E: Non-INVITE request retransmission timer (T1)
    %{transaction | timer_e: make_ref()}
  end

  defp start_timer_f(transaction) do
    # Timer F: Non-INVITE transaction timeout timer (64*T1)
    %{transaction | timer_f: make_ref()}
  end

  defp start_timer_g(transaction) do
    # Timer G: INVITE response retransmission timer (T1)
    %{transaction | timer_g: make_ref()}
  end

  defp start_timer_h(transaction) do
    # Timer H: Wait time for ACK receipt (64*T1)
    %{transaction | timer_h: make_ref()}
  end

  defp start_timer_i(transaction) do
    # Timer I: Wait time for ACK retransmits (@t4 for UDP, 0s for TCP/SCTP)
    %{transaction | timer_i: make_ref()}
  end

  defp start_timer_j(transaction) do
    # Timer J: Wait time for non-INVITE request retransmits (64*T1 for UDP, 0s for TCP/SCTP)
    %{transaction | timer_j: make_ref()}
  end

  defp start_timer_k(transaction) do
    # Timer K: Wait time for response retransmits (@t4 for UDP, 0s for TCP/SCTP)
    %{transaction | timer_k: make_ref()}
  end

  # Stub for cancel_timer/2 to fix undefined function error.
  # In this pure state machine, this can simply return the transaction unchanged,
  # or you can update the struct if you track timer refs in the struct.
  defp cancel_timer(transaction, _timer_key), do: transaction

  @doc """
  Handles SIP transaction state machine events.

  This function processes an event for the given transaction, returning the updated
  transaction struct and a list of actions for the transaction server to execute.

  ## Parameters

    * `event` - The event to process (e.g., `{:send, response}`, `{:received, request}`, `{:timer, :g}`)
    * `transaction` - The `%Parrot.Sip.Transaction{}` struct representing the current transaction state

  ## Returns

    * `{new_transaction, actions}` - The updated transaction and a list of actions (atoms or tuples)

  ## Example

      {new_trans, actions} = Parrot.Sip.Transaction.handle_event({:send, response}, transaction)

  Supported actions include:
    * `{:send_response, response}`
    * `{:send_request, request}`
    * `{:start_timer, timer_name, timeout_ms}`
    * `{:cancel_timer, timer_name}`
    * `:terminate_transaction`
    * `:ignore`
  """
  @spec handle_event(term(), t()) :: {t(), [term()]}
  def handle_event(
        {:send, response},
        %__MODULE__{state: :trying, type: :invite_server} = transaction
      )
      when is_map(response) do
    Logger.debug(
      "[handle_event] ({:send, response}) in :trying/:invite. Transaction: #{inspect(transaction)}, Response: #{inspect(response)}"
    )

    cond do
      is_provisional_response(response) ->
        # Move to proceeding, send provisional response, start timer G
        new_transaction = %{transaction | state: :proceeding, last_response: response}
        actions = [{:send_response, response}, {:start_timer, :g, timer_g_timeout(transaction)}]
        {new_transaction, actions}

      is_final_response(response) ->
        # Move to completed, send final response, start timer H
        new_transaction = %{transaction | state: :completed, last_response: response}
        actions = [{:send_response, response}, {:start_timer, :h, timer_h_timeout(transaction)}]
        {new_transaction, actions}

      true ->
        {transaction, [:ignore]}
    end
  end

  def handle_event(event, %__MODULE__{state: :trying, type: :invite_server} = transaction) do
    Logger.debug(
      "[handle_event] (event) in :trying/:invite_server. Transaction: #{inspect(transaction)}, Event: #{inspect(event)}"
    )

    case event do
      {:received, _request} ->
        # Retransmit last response if any
        actions =
          case transaction.last_response do
            nil -> [:ignore]
            resp -> [{:send_response, resp}]
          end

        {transaction, actions}

      {:timer, timer} ->
        handle_timer_event(timer, transaction)

      _ ->
        {transaction, [:ignore]}
    end
  end

  def handle_event(
        {:send, response},
        %__MODULE__{state: :proceeding, type: :invite_server} = transaction
      )
      when is_map(response) do
    Logger.debug(
      "[handle_event] ({:send, response}) in :proceeding/:invite_server. Transaction: #{inspect(transaction)}, Response: #{inspect(response)}"
    )

    if is_final_response(response) do
      # Move to completed, send final response, start timer H
      new_transaction = %{transaction | state: :completed, last_response: response}
      actions = [{:send_response, response}, {:start_timer, :h, timer_h_timeout(transaction)}]
      {new_transaction, actions}
    else
      # TODO: this is swallowing the 180 after the 100 Trying
      Logger.warning("Unexpected response: #{inspect(response)}")
      {transaction, [:ignore]}
    end
  end

  def handle_event(event, %__MODULE__{state: :proceeding, type: :invite_server} = transaction) do
    Logger.debug(
      "[handle_event] (event) in :proceeding/:invite_server. Transaction: #{inspect(transaction)}, Event: #{inspect(event)}"
    )

    case event do
      {:received, _request} ->
        # Retransmit last response if any
        actions =
          case transaction.last_response do
            nil -> [:ignore]
            resp -> [{:send_response, resp}]
          end

        {transaction, actions}

      {:timer, timer} ->
        handle_timer_event(timer, transaction)

      _ ->
        {transaction, [:ignore]}
    end
  end

  def handle_event(event, %__MODULE__{state: :completed, type: :invite_server} = transaction) do
    Logger.debug(
      "[handle_event] (event) in :completed/:invite_server. Transaction: #{inspect(transaction)}, Event: #{inspect(event)}"
    )

    case event do
      {:received, ack} ->
        if is_ack(ack) do
          # Move to confirmed, stop timer H, start timer I
          new_transaction = %{transaction | state: :confirmed}
          actions = [{:cancel_timer, :h}, {:start_timer, :i, timer_i_timeout(transaction)}]
          {new_transaction, actions}
        else
          # Not an ACK, retransmit last response
          actions =
            case transaction.last_response do
              nil -> [:ignore]
              resp -> [{:send_response, resp}]
            end

          {transaction, actions}
        end

      {:timer, :h} ->
        # Timer H expired, move to terminated
        new_transaction = %{transaction | state: :terminated}
        actions = [:terminate_transaction]
        {new_transaction, actions}

      _ ->
        {transaction, [:ignore]}
    end
  end

  def handle_event(event, %__MODULE__{state: :confirmed, type: :invite_server} = transaction) do
    Logger.debug(
      "[handle_event] (event) in :confirmed/:invite_server. Transaction: #{inspect(transaction)}, Event: #{inspect(event)}"
    )

    case event do
      {:timer, :i} ->
        # Timer I expired, move to terminated
        new_transaction = %{transaction | state: :terminated}
        actions = [:terminate_transaction]
        {new_transaction, actions}

      _ ->
        {transaction, [:ignore]}
    end
  end

  def handle_event(event, %__MODULE__{state: :terminated} = transaction) do
    Logger.debug(
      "[handle_event] (event) in :terminated. Transaction: #{inspect(transaction)}, Event: #{inspect(event)}"
    )

    # No further processing, transaction is done
    {transaction, [:ignore]}
  end

  # Non-INVITE server transaction states
  def handle_event({:send, response}, %__MODULE__{state: :trying, type: type} = transaction)
      when type != :invite and is_map(response) do
    Logger.debug(
      "[handle_event] ({:send, response}) in :trying/#{inspect(type)}. Transaction: #{inspect(transaction)}, Response: #{inspect(response)}"
    )

    cond do
      is_provisional_response(response) ->
        # Move to proceeding, send provisional response
        new_transaction = %{transaction | state: :proceeding, last_response: response}
        actions = [{:send_response, response}]
        {new_transaction, actions}

      is_final_response(response) ->
        # Move to completed, send final response, start timer J
        new_transaction = %{transaction | state: :completed, last_response: response}
        actions = [{:send_response, response}, {:start_timer, :j, timer_j_timeout(transaction)}]
        {new_transaction, actions}

      true ->
        {transaction, [:ignore]}
    end
  end

  def handle_event(event, %__MODULE__{state: :trying, type: type} = transaction)
      when type != :invite do
    Logger.debug(
      "[handle_event] (event) in :trying/#{inspect(type)}. Transaction: #{inspect(transaction)}, Event: #{inspect(event)}"
    )

    case event do
      {:received, _request} ->
        # Retransmit last response if any
        actions =
          case transaction.last_response do
            nil -> [:ignore]
            resp -> [{:send_response, resp}]
          end

        {transaction, actions}

      {:timer, timer} ->
        handle_timer_event(timer, transaction)

      _ ->
        {transaction, [:ignore]}
    end
  end

  def handle_event({:send, response}, %__MODULE__{state: :proceeding, type: type} = transaction)
      when type != :invite and is_map(response) do
    Logger.debug(
      "[handle_event] ({:send, response}) in :proceeding/#{inspect(type)}. Transaction: #{inspect(transaction)}, Response: #{inspect(response)}"
    )

    if is_final_response(response) do
      # Move to completed, send final response, start timer J
      new_transaction = %{transaction | state: :completed, last_response: response}
      actions = [{:send_response, response}, {:start_timer, :j, timer_j_timeout(transaction)}]
      {new_transaction, actions}
    else
      {transaction, [:ignore]}
    end
  end

  def handle_event(event, %__MODULE__{state: :proceeding, type: type} = transaction)
      when type != :invite do
    Logger.debug(
      "[handle_event] (event) in :proceeding/#{inspect(type)}. Transaction: #{inspect(transaction)}, Event: #{inspect(event)}"
    )

    case event do
      {:received, _request} ->
        # Retransmit last response if any
        actions =
          case transaction.last_response do
            nil -> [:ignore]
            resp -> [{:send_response, resp}]
          end

        {transaction, actions}

      {:timer, timer} ->
        handle_timer_event(timer, transaction)

      _ ->
        {transaction, [:ignore]}
    end
  end

  def handle_event(event, %__MODULE__{state: :completed, type: type} = transaction)
      when type != :invite do
    Logger.debug(
      "[handle_event] (event) in :completed/#{inspect(type)}. Transaction: #{inspect(transaction)}, Event: #{inspect(event)}"
    )

    case event do
      {:timer, :j} ->
        # Timer J expired, move to terminated
        new_transaction = %{transaction | state: :terminated}
        actions = [:terminate_transaction]
        {new_transaction, actions}

      {:received, _request} ->
        # Retransmit last response
        actions =
          case transaction.last_response do
            nil -> [:ignore]
            resp -> [{:send_response, resp}]
          end

        {transaction, actions}

      _ ->
        {transaction, [:ignore]}
    end
  end

  # Client transaction states (simplified, expand as needed)
  def handle_event(
        {:received, response},
        %__MODULE__{state: :calling, type: :invite_client} = transaction
      ) do
    Logger.debug(
      "[handle_event] ({:received, response}) in :calling/:invite_client. Transaction: #{inspect(transaction)}, Response: #{inspect(response)}"
    )

    cond do
      is_provisional_response(response) ->
        # Move to proceeding, start timer 100rel if needed
        new_transaction = %{transaction | state: :proceeding, last_response: response}
        actions = [{:start_timer, :rel1xx, timer_rel1xx_timeout(transaction)}]
        {new_transaction, actions}

      is_final_response(response) ->
        # Move to completed, stop timers, notify user
        new_transaction = %{transaction | state: :completed, last_response: response}
        actions = [{:cancel_timer, :a}, {:cancel_timer, :b}, {:notify_user, response}]
        {new_transaction, actions}

      true ->
        {transaction, [:ignore]}
    end
  end

  def handle_event(event, %__MODULE__{state: :calling, type: :invite_client} = transaction) do
    Logger.debug(
      "[handle_event] (event) in :calling/:invite_client. Transaction: #{inspect(transaction)}, Event: #{inspect(event)}"
    )

    case event do
      {:timer, timer} ->
        handle_timer_event(timer, transaction)

      _ ->
        {transaction, [:ignore]}
    end
  end

  def handle_event(
        {:received, response},
        %__MODULE__{state: :proceeding, type: :invite_client} = transaction
      ) do
    Logger.debug(
      "[handle_event] ({:received, response}) in :proceeding/:invite_client. Transaction: #{inspect(transaction)}, Response: #{inspect(response)}"
    )

    if is_final_response(response) do
      # Move to completed, stop timers, notify user
      new_transaction = %{transaction | state: :completed, last_response: response}
      actions = [{:cancel_timer, :a}, {:cancel_timer, :b}, {:notify_user, response}]
      {new_transaction, actions}
    else
      {transaction, [:ignore]}
    end
  end

  def handle_event(event, %__MODULE__{state: :proceeding, type: :invite_client} = transaction) do
    Logger.debug(
      "[handle_event] (event) in :proceeding/:invite_client. Transaction: #{inspect(transaction)}, Event: #{inspect(event)}"
    )

    case event do
      {:timer, timer} ->
        handle_timer_event(timer, transaction)

      _ ->
        {transaction, [:ignore]}
    end
  end

  def handle_event(event, %__MODULE__{state: :completed, type: :invite_client} = transaction) do
    Logger.debug(
      "[handle_event] (event) in :completed/:invite_client. Transaction: #{inspect(transaction)}, Event: #{inspect(event)}"
    )

    case event do
      {:timer, :d} ->
        # Timer D expired, move to terminated
        new_transaction = %{transaction | state: :terminated}
        actions = [:terminate_transaction]
        {new_transaction, actions}

      _ ->
        {transaction, [:ignore]}
    end
  end

  # Fallback for any other state/event
  def handle_event(event, transaction) do
    Logger.debug("[handle_event] (fallback) Any state. Transaction: #{inspect(transaction)}")
    {transaction, [:ignore]}
  end

  # --- Helper functions ---

  defp is_provisional_response(%{status_code: code})
       when is_integer(code) and code >= 100 and code < 200,
       do: true

  defp is_provisional_response(_), do: false

  defp is_final_response(%{status_code: code}) when is_integer(code) and code >= 200, do: true
  defp is_final_response(_), do: false

  defp is_ack(%{method: :ack}), do: true
  defp is_ack(_), do: false

  # ms, example value
  defp timer_g_timeout(_transaction), do: 500
  defp timer_h_timeout(_transaction), do: 64_000
  defp timer_i_timeout(_transaction), do: 5_000
  defp timer_j_timeout(_transaction), do: 5_000
  defp timer_rel1xx_timeout(_transaction), do: 10_000

  defp handle_timer_event(timer, transaction) do
    # Expand this as needed for your timer logic
    case timer do
      :g ->
        {transaction,
         [:retransmit_last_response, {:start_timer, :g, timer_g_timeout(transaction)}]}

      :h ->
        {transaction, [:move_to_terminated]}

      :i ->
        {transaction, [:move_to_terminated]}

      :j ->
        {transaction, [:move_to_terminated]}

      :d ->
        {transaction, [:move_to_terminated]}

      _ ->
        {transaction, [:ignore]}
    end
  end
end
