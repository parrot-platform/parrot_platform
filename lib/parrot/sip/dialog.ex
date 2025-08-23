defmodule Parrot.Sip.Dialog do
  @moduledoc """
  Implementation of SIP dialog management according to RFC 3261 Section 12.

  This module provides the pure functional implementation of SIP dialogs.
  For stateful dialog management, see Parrot.Sip.DialogStatem.

  A dialog represents a peer-to-peer SIP relationship between two user agents
  that persists for some time. Dialogs facilitate sequencing of messages,
  proper routing of requests between participants, and provide context for
  SIP transactions.

  As defined in RFC 3261 Section 12, a dialog is identified by the combination of:
  - Call-ID
  - Local tag (From tag for UAC, To tag for UAS)
  - Remote tag (To tag for UAC, From tag for UAS)

  Dialogs have states:
  - Early: Created by provisional responses (1xx)
  - Confirmed: Created by final responses (2xx)
  - Terminated: Ended by BYE request or other terminating events

  This module provides functionality for:
  - Creating dialogs from SIP messages (Section 12.1.1)
  - Generating dialog IDs (Section 12.1.1)
  - Managing dialog state transitions (Section 12.3)
  - Creating in-dialog requests (Section 12.2.1)
  - Processing in-dialog responses (Section 12.2.1.2)
  - Handling dialog termination (Section 15)

  References:
  - RFC 3261: SIP: Session Initiation Protocol (https://tools.ietf.org/html/rfc3261)
    - Section 12: Dialogs
    - Section 13: Initiating a Session
    - Section 15: Terminating a Session
  """

  alias Parrot.Sip.Message
  alias Parrot.Sip.Headers
  alias Parrot.Sip.Headers.{From, To}
  alias Parrot.Sip.Uri

  defstruct [
    # Dialog ID string
    :id,
    # :early, :confirmed, :terminated
    :state,
    # Call-ID value
    :call_id,
    # Local tag parameter
    :local_tag,
    # Remote tag parameter
    :remote_tag,
    # Local URI as string
    :local_uri,
    # Remote URI as string
    :remote_uri,
    # Remote target URI as string
    :remote_target,
    # Local sequence number
    :local_seq,
    # Remote sequence number
    :remote_seq,
    # List of Route headers
    :route_set,
    # Boolean indicating if dialog is secure
    :secure
  ]

  @type t :: %__MODULE__{
          id: String.t(),
          state: :early | :confirmed | :terminated,
          call_id: String.t(),
          local_tag: String.t(),
          remote_tag: String.t(),
          local_uri: String.t(),
          remote_uri: String.t(),
          remote_target: String.t(),
          local_seq: non_neg_integer(),
          remote_seq: non_neg_integer(),
          route_set: list(),
          secure: boolean()
        }

  @doc """
  Facade function that creates a request within an existing dialog.

  This function currently delegates to the DialogStatem implementation,
  which uses ERSIP. It will gradually be replaced with our pure Elixir implementation.

  RFC 3261 Section 12.2.1
  @doc \"""
  Associates a request with its dialog and passes it to the dialog process.

  ## Parameters

  - `dialog_id`: The dialog ID to associate with the request
  - `request`: The SIP request message

  ## Returns

  - `{:ok, request}`: The updated request with dialog information
  - `{:error, :no_dialog}`: If no matching dialog exists
  """
  @spec find_and_use_dialog(String.t(), Message.t()) ::
          {:ok, Message.t(), t()} | {:error, :no_dialog}
  def find_and_use_dialog(dialog_id, request) do
    case Parrot.Sip.DialogStatem.find_dialog(dialog_id) do
      {:ok, dialog} -> uac_request(request.method, dialog)
      {:error, reason} -> {:error, reason}
    end
  end

  @doc """
  Facade function that processes a transaction result in the UAC context.

  This function currently delegates to the DialogStatem implementation,
  which uses ERSIP. It will gradually be replaced with our pure Elixir implementation.

  RFC 3261 Section 12.2.1.2

  ## Parameters

  - `request`: The original request
  - `transaction_result`: Result from the transaction

  ## Returns

  - `:ok`: Successfully processed
  """
  @spec uac_result(Message.t(), any()) :: :ok
  def uac_result(%Message{} = _request, _transaction_result) do
    # For now, do nothing
    # In a real implementation, this would update dialog state based on transaction results
    :ok
  end

  @doc """
  Facade function that returns the count of active dialogs.

  This function delegates to the DialogStatem implementation and will
  gradually be replaced with our pure Elixir implementation.

  ## Returns

  - The number of active dialogs
  """
  @spec count() :: non_neg_integer()
  def count() do
    # For now, return 0 as we don't have active dialog tracking yet
    # In a real implementation, this would count dialogs in the registry
    0
  end

  @doc """
  Creates a dialog ID with explicit components.

  ## Examples

      iex> Parrot.Sip.Dialog.new("abc@example.com", "123", "456", :uac)
      %{call_id: "abc@example.com", local_tag: "123", remote_tag: "456", direction: :uac}
  """
  @spec new(String.t(), String.t(), String.t() | nil, :uac | :uas) :: map()
  def new(call_id, local_tag, remote_tag \\ nil, direction \\ :uac) do
    %{
      call_id: call_id,
      local_tag: local_tag,
      remote_tag: remote_tag,
      direction: direction
    }
  end

  @doc """
  Creates a peer dialog ID by swapping local and remote tags.
  This is useful for matching dialog IDs from different endpoints.

  ## Examples

      iex> dialog_id = %{call_id: "abc", local_tag: "123", remote_tag: "456", direction: :uac}
      iex> Parrot.Sip.Dialog.peer_dialog_id(dialog_id)
      %{call_id: "abc", local_tag: "456", remote_tag: "123", direction: :uas}
  """
  @spec peer_dialog_id(map()) :: map()
  def peer_dialog_id(%{direction: direction} = dialog_id) do
    peer_direction = if direction == :uac, do: :uas, else: :uac

    %{
      call_id: dialog_id.call_id,
      local_tag: dialog_id.remote_tag,
      remote_tag: dialog_id.local_tag,
      direction: peer_direction
    }
  end

  @doc """
  Compares two dialog IDs to determine if they match.
  Two dialog IDs match if they have the same call-id and tags.

  ## Examples

      iex> dialog_id1 = %{call_id: "abc", local_tag: "123", remote_tag: "456"}
      iex> dialog_id2 = %{call_id: "abc", local_tag: "123", remote_tag: "456"}
      iex> Parrot.Sip.Dialog.match?(dialog_id1, dialog_id2)
      true
  """
  @spec match?(map(), map()) :: boolean()
  def match?(dialog_id1, dialog_id2) do
    same_call_id = dialog_id1.call_id == dialog_id2.call_id

    same_tags =
      (dialog_id1.local_tag == dialog_id2.local_tag and
         dialog_id1.remote_tag == dialog_id2.remote_tag) or
        (dialog_id1.local_tag == dialog_id2.remote_tag and
           dialog_id1.remote_tag == dialog_id2.local_tag)

    same_call_id and same_tags
  end

  @doc """
  Updates a dialog ID with a remote tag, typically used when receiving a response
  that establishes a dialog.

  ## Examples

      iex> dialog_id = %{call_id: "abc", local_tag: "123", remote_tag: nil}
      iex> Parrot.Sip.Dialog.with_remote_tag(dialog_id, "456")
      %{call_id: "abc", local_tag: "123", remote_tag: "456"}
  """
  @spec with_remote_tag(map(), String.t()) :: map()
  def with_remote_tag(dialog_id, remote_tag) when is_binary(remote_tag) do
    %{dialog_id | remote_tag: remote_tag}
  end

  @doc """
  Creates a dialog ID from a SIP message.

  For requests, the dialog ID is created from the From tag, To tag (if present),
  and Call-ID. For responses, the dialog ID is created from the To tag, From tag,
  and Call-ID.

  The direction is determined by the message type. For requests, the direction is
  :uac (User Agent Client). For responses, the direction is :uas (User Agent Server).

  ## Examples

      iex> request = %Parrot.Sip.Message{type: :request, direction: :incoming, headers: %{
      ...>   "from" => %Parrot.Sip.Headers.From{parameters: %{"tag" => "123"}},
      ...>   "to" => %Parrot.Sip.Headers.To{parameters: %{}},
      ...>   "call-id" => "abc@example.com"
      ...> }}
      iex> Parrot.Sip.Dialog.from_message(request)
      %{call_id: "abc@example.com", local_tag: "123", remote_tag: nil, direction: :uas}
  """
  @spec from_message(Message.t()) :: map()
  def from_message(%Message{type: type, direction: flow_direction} = message) do
    call_id = Message.get_header(message, "call-id")
    from_header = Message.get_header(message, "from")
    to_header = Message.get_header(message, "to")

    from_tag = if from_header, do: From.tag(from_header), else: nil
    to_tag = if to_header, do: To.tag(to_header), else: nil

    # Determine dialog direction based on message type and flow direction
    dialog_direction =
      case {type, flow_direction} do
        {:request, :outgoing} -> :uac
        {:request, :incoming} -> :uas
        {:response, :outgoing} -> :uac
        {:response, :incoming} -> :uas
        _ -> :uac
      end

    case type do
      :request ->
        %{
          call_id: call_id,
          local_tag: from_tag,
          remote_tag: to_tag,
          direction: dialog_direction
        }

      :response ->
        %{
          call_id: call_id,
          local_tag: to_tag,
          remote_tag: from_tag,
          direction: dialog_direction
        }

      _ ->
        # Default to request behavior for messages with nil or unknown type
        %{
          call_id: call_id,
          local_tag: from_tag,
          remote_tag: to_tag,
          direction: dialog_direction
        }
    end
  end

  @doc """
  Checks if a dialog ID is complete (has both local and remote tags).

  ## Examples

      iex> dialog_id = %{call_id: "abc", local_tag: "123", remote_tag: "456"}
      iex> Parrot.Sip.Dialog.is_complete?(dialog_id)
      true

      iex> dialog_id = %{call_id: "abc", local_tag: "123", remote_tag: nil}
      iex> Parrot.Sip.Dialog.is_complete?(dialog_id)
      false
  """
  @spec is_complete?(map() | t()) :: boolean()
  def is_complete?(%__MODULE__{local_tag: local_tag, remote_tag: remote_tag}) do
    not is_nil(local_tag) and not is_nil(remote_tag)
  end

  def is_complete?(%{local_tag: local_tag, remote_tag: remote_tag}) do
    not is_nil(local_tag) and not is_nil(remote_tag)
  end

  @doc """
  Converts a dialog ID to a string representation for Registry lookups.

  This unifies the previous DialogId.to_string/1 and Dialog.generate_id/4 functions
  into a single consistent format.

  ## Examples

      iex> dialog = %Parrot.Sip.Dialog{call_id: "abc", local_tag: "123", remote_tag: "456", ...}
      iex> Parrot.Sip.Dialog.to_string(dialog)
      "abc;local=123;remote=456"

      iex> dialog_id = %{call_id: "abc", local_tag: "123", remote_tag: "456", direction: :uac}
      iex> Parrot.Sip.Dialog.to_string(dialog_id)
      "abc;local=123;remote=456;uac"
  """
  @spec to_string(t() | map()) :: String.t()
  def to_string(%__MODULE__{call_id: call_id, local_tag: local_tag, remote_tag: remote_tag}) do
    remote_part = if remote_tag, do: ";remote=#{remote_tag}", else: ""
    "#{call_id};local=#{local_tag}#{remote_part}"
  end

  def to_string(%{call_id: call_id, local_tag: local_tag, remote_tag: remote_tag} = dialog_id) do
    remote_part = if remote_tag, do: ";remote=#{remote_tag}", else: ""

    direction_part =
      if Map.has_key?(dialog_id, :direction), do: ";#{dialog_id.direction}", else: ""

    "#{call_id};local=#{local_tag}#{remote_part}#{direction_part}"
  end

  @doc """
  Creates a dialog from the UAS perspective.

  Takes a SIP request and response and creates a dialog from the
  server perspective.

  ## Parameters

  - `request`: The SIP request that started the dialog (typically INVITE)
  - `response`: The SIP response that established the dialog

  ## Returns

  - `{:ok, dialog}`: A new dialog struct
  """
  @spec uas_create(Message.t(), Message.t()) :: {:ok, t()}
  def uas_create(request, response) do
    # Extract necessary headers
    call_id = request.headers["call-id"]
    remote_tag = request.headers["from"].parameters["tag"]
    local_tag = response.headers["to"].parameters["tag"]

    # Extract URIs
    to_uri = request.headers["to"].uri
    local_uri = if is_binary(to_uri), do: to_uri, else: Uri.to_string(to_uri)

    from_uri = request.headers["from"].uri
    remote_uri = if is_binary(from_uri), do: from_uri, else: Uri.to_string(from_uri)

    # Extract the remote target from the Contact header in the request
    remote_target =
      if Map.has_key?(request.headers, "contact") do
        contact_uri = request.headers["contact"].uri
        if is_binary(contact_uri), do: contact_uri, else: Uri.to_string(contact_uri)
      else
        remote_uri
      end

    # Get sequence numbers from CSeq
    remote_seq = request.headers["cseq"].number
    local_seq = 0

    # Determine if secure based on the request URI scheme
    secure = String.starts_with?(request.request_uri, "sips:")

    # Extract route set (if any)
    route_set = extract_route_set(response)

    # Determine dialog state based on the response status code
    state =
      if response.status_code >= 200 and response.status_code < 300, do: :confirmed, else: :early

    # Create the dialog
    dialog = %__MODULE__{
      id: generate_id(:uas, call_id, local_tag, remote_tag),
      state: state,
      call_id: call_id,
      local_tag: local_tag,
      remote_tag: remote_tag,
      local_uri: local_uri,
      remote_uri: remote_uri,
      remote_target: remote_target,
      local_seq: local_seq,
      remote_seq: remote_seq,
      route_set: route_set,
      secure: secure
    }

    {:ok, dialog}
  end

  @doc """
  Creates a dialog from the UAC perspective.

  Takes a SIP request and response and creates a dialog from the
  client perspective.

  ## Parameters

  - `request`: The SIP request that started the dialog (typically INVITE)
  - `response`: The SIP response that established the dialog

  ## Returns

  - `{:ok, dialog}`: A new dialog struct
  """
  @spec uac_create(Message.t(), Message.t()) :: {:ok, t()}
  def uac_create(request, response) do
    # Extract necessary headers
    call_id = request.headers["call-id"]
    local_tag = request.headers["from"].parameters["tag"]
    remote_tag = response.headers["to"].parameters["tag"]

    # Extract URIs
    from_uri = request.headers["from"].uri
    local_uri = if is_binary(from_uri), do: from_uri, else: Uri.to_string(from_uri)

    to_uri = request.headers["to"].uri
    remote_uri = if is_binary(to_uri), do: to_uri, else: Uri.to_string(to_uri)

    # Get the remote target from the Contact header in the response
    remote_target =
      if Map.has_key?(response.headers, "contact") do
        contact_uri = response.headers["contact"].uri
        if is_binary(contact_uri), do: contact_uri, else: Uri.to_string(contact_uri)
      else
        remote_uri
      end

    # Get sequence numbers from CSeq
    local_seq = request.headers["cseq"].number
    remote_seq = 0

    # Determine if secure based on the request URI scheme
    secure = String.starts_with?(request.request_uri, "sips:")

    # Extract route set (if any)
    route_set = extract_route_set(response)

    # Determine dialog state based on the response status code
    state =
      if response.status_code >= 200 and response.status_code < 300, do: :confirmed, else: :early

    # Create the dialog
    dialog = %__MODULE__{
      id: generate_id(:uac, call_id, local_tag, remote_tag),
      state: state,
      call_id: call_id,
      local_tag: local_tag,
      remote_tag: remote_tag,
      local_uri: local_uri,
      remote_uri: remote_uri,
      remote_target: remote_target,
      local_seq: local_seq,
      remote_seq: remote_seq,
      route_set: route_set,
      secure: secure
    }

    {:ok, dialog}
  end

  @doc """
  Generates a dialog ID based on the dialog parameters.

  This now uses the unified to_string/1 approach for consistency.

  ## Parameters

  - `perspective`: Either `:uac` or `:uas`
  - `call_id`: The Call-ID value
  - `local_tag`: The local tag value
  - `remote_tag`: The remote tag value

  ## Returns

  - A string representing the dialog ID
  """
  @spec generate_id(atom(), String.t(), String.t(), String.t()) :: String.t()
  def generate_id(perspective, call_id, local_tag, remote_tag) do
    # Use the unified to_string/1 function for consistency
    __MODULE__.to_string(%{
      call_id: call_id,
      local_tag: local_tag,
      remote_tag: remote_tag,
      direction: perspective
    })
  end

  @doc """
  Processes an in-dialog request from the UAS perspective.

  Updates the dialog state based on the received request.

  ## Parameters

  - `request`: The SIP request received in the dialog
  - `dialog`: The current dialog state

  ## Returns

  - `{:ok, updated_dialog}`: The updated dialog
  """
  @spec uas_process(Message.t(), t()) :: {:ok, t()}
  def uas_process(request, dialog) do
    # Update remote sequence number
    remote_seq = request.headers["cseq"].number

    # Handle BYE request (terminates the dialog)
    state = if request.method == :bye, do: :terminated, else: dialog.state

    # Update the dialog
    updated_dialog = %{dialog | remote_seq: remote_seq, state: state}

    {:ok, updated_dialog}
  end

  @doc """
  Creates an in-dialog request from the UAC perspective.

  Creates a new request within an existing dialog.

  ## Parameters

  - `method`: The SIP method for the request
  - `dialog`: The current dialog state

  ## Returns

  - `{:ok, request, updated_dialog}`: The new request and updated dialog
  """
  @spec uac_request(atom(), t()) :: {:ok, Message.t(), t()}
  def uac_request(method, dialog) do
    # Increment local sequence number
    new_seq = dialog.local_seq + 1

    # Create basic headers
    from = %Headers.From{
      display_name: nil,
      uri: Uri.parse!(dialog.local_uri),
      parameters: %{"tag" => dialog.local_tag}
    }

    to = %Headers.To{
      display_name: nil,
      uri: Uri.parse!(dialog.remote_uri),
      parameters: %{"tag" => dialog.remote_tag}
    }

    cseq = %Headers.CSeq{
      number: new_seq,
      method: method
    }

    # Create a basic request structure
    request = %Message{
      method: method,
      request_uri: dialog.remote_target,
      type: :request,
      direction: :outgoing,
      version: "SIP/2.0",
      headers: %{
        "via" => %Headers.Via{
          protocol: "SIP",
          version: "2.0",
          transport: :udp,
          # This would typically be configurable
          host: "pc33.atlanta.com",
          parameters: %{"branch" => Headers.generate_branch()}
        },
        "from" => from,
        "to" => to,
        "call-id" => dialog.call_id,
        "cseq" => cseq,
        "max-forwards" => 70
      },
      body: ""
    }

    # Update the dialog with the new sequence number
    updated_dialog = %{dialog | local_seq: new_seq}

    {:ok, request, updated_dialog}
  end

  @doc """
  Processes a response to an in-dialog request from the UAC perspective.

  Updates the dialog state based on the received response.

  ## Parameters

  - `response`: The SIP response received
  - `dialog`: The current dialog state

  ## Returns

  - `{:ok, updated_dialog}`: The updated dialog
  """
  @spec uac_response(Message.t(), t()) :: {:ok, t()}
  def uac_response(response, dialog) do
    cseq = response.headers["cseq"]

    # Handle transitioning from early to confirmed for INVITE responses
    state =
      cond do
        # Dialog becomes confirmed on 2xx to INVITE
        dialog.state == :early && cseq.method == :invite &&
          response.status_code >= 200 && response.status_code < 300 ->
          :confirmed

        # Dialog becomes terminated on BYE response
        cseq.method == :bye && response.status_code >= 200 && response.status_code < 300 ->
          :terminated

        # Keep current state otherwise
        true ->
          dialog.state
      end

    # Update the dialog with the new state
    updated_dialog = %{dialog | state: state}

    {:ok, updated_dialog}
  end

  @doc """
  Checks if a dialog is in the early state.

  ## Parameters

  - `dialog`: The dialog to check

  ## Returns

  - `true` if the dialog is in the early state, `false` otherwise
  """
  @spec is_early?(t()) :: boolean()
  def is_early?(dialog) do
    dialog.state == :early
  end

  @doc """
  Checks if a dialog is secure (using SIPS).

  ## Parameters

  - `dialog`: The dialog to check

  ## Returns

  - `true` if the dialog is secure, `false` otherwise
  """
  @spec is_secure?(t()) :: boolean()
  def is_secure?(dialog) do
    dialog.secure
  end

  # Private helper functions

  # Extract route set from a response
  defp extract_route_set(_response) do
    # In a real implementation, this would extract Record-Route headers
    # from the response and reverse them for the route set
    []
  end
end
