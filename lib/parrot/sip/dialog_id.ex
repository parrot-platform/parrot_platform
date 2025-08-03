defmodule Parrot.Sip.DialogId do
  @moduledoc """
  Module for working with SIP dialog identifiers as defined in RFC 3261.

  A dialog ID uniquely identifies a dialog between two user agents.
  As per RFC 3261 Section 12, a dialog is identified by:
  - Call-ID
  - Local tag (From tag for the UAC, To tag for the UAS)
  - Remote tag (To tag for the UAC, From tag for the UAS)

  This module provides functions for creating and handling dialog IDs,
  which are essential for tracking and managing SIP dialogs.

  References:
  - RFC 3261 Section 12: Dialogs
  - RFC 3261 Section 12.1.1: Dialog ID
  - RFC 3261 Section 19.3: Dialog ID Components
  """

  alias Parrot.Sip.Headers.{From, To}
  alias Parrot.Sip.Message

  defstruct [
    # Call-ID header value
    :call_id,
    # Local tag (From tag for UAC, To tag for UAS)
    :local_tag,
    # Remote tag (To tag for UAC, From tag for UAS)
    :remote_tag,
    # :uac or :uas
    :direction
  ]

  @type t :: %__MODULE__{
          call_id: String.t(),
          local_tag: String.t(),
          remote_tag: String.t() | nil,
          direction: :uac | :uas
        }

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
      iex> Parrot.Sip.DialogId.from_message(request)
      %Parrot.Sip.DialogId{
        call_id: "abc@example.com",
        local_tag: "123",
        remote_tag: nil,
        direction: :uas
      }
  """
  @spec from_message(Message.t()) :: t()
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
        %__MODULE__{
          call_id: call_id,
          local_tag: from_tag,
          remote_tag: to_tag,
          direction: dialog_direction
        }

      :response ->
        %__MODULE__{
          call_id: call_id,
          local_tag: to_tag,
          remote_tag: from_tag,
          direction: dialog_direction
        }

      _ ->
        # Default to request behavior for messages with nil or unknown type
        %__MODULE__{
          call_id: call_id,
          local_tag: from_tag,
          remote_tag: to_tag,
          direction: dialog_direction
        }
    end
  end

  @doc """
  Creates a dialog ID with explicit components.

  ## Examples

      iex> Parrot.Sip.DialogId.new("abc@example.com", "123", "456", :uac)
      %Parrot.Sip.DialogId{
        call_id: "abc@example.com",
        local_tag: "123",
        remote_tag: "456",
        direction: :uac
      }
  """
  @spec new(String.t(), String.t(), String.t() | nil, :uac | :uas) :: t()
  def new(call_id, local_tag, remote_tag \\ nil, direction \\ :uac) do
    %__MODULE__{
      call_id: call_id,
      local_tag: local_tag,
      remote_tag: remote_tag,
      direction: direction
    }
  end

  @doc """
  Checks if a dialog ID is complete (has both local and remote tags).

  ## Examples

      iex> dialog_id = %Parrot.Sip.DialogId{call_id: "abc", local_tag: "123", remote_tag: "456"}
      iex> Parrot.Sip.DialogId.is_complete?(dialog_id)
      true

      iex> dialog_id = %Parrot.Sip.DialogId{call_id: "abc", local_tag: "123", remote_tag: nil}
      iex> Parrot.Sip.DialogId.is_complete?(dialog_id)
      false
  """
  @spec is_complete?(t()) :: boolean()
  def is_complete?(%__MODULE__{local_tag: local_tag, remote_tag: remote_tag}) do
    not is_nil(local_tag) and not is_nil(remote_tag)
  end

  @doc """
  Creates a peer dialog ID by swapping local and remote tags.
  This is useful for matching dialog IDs from different endpoints.

  ## Examples

      iex> dialog_id = %Parrot.Sip.DialogId{
      ...>   call_id: "abc@example.com",
      ...>   local_tag: "123",
      ...>   remote_tag: "456",
      ...>   direction: :uac
      ...> }
      iex> Parrot.Sip.DialogId.peer_dialog_id(dialog_id)
      %Parrot.Sip.DialogId{
        call_id: "abc@example.com",
        local_tag: "456",
        remote_tag: "123",
        direction: :uas
      }
  """
  @spec peer_dialog_id(t()) :: t()
  def peer_dialog_id(%__MODULE__{} = dialog_id) do
    peer_direction =
      case dialog_id.direction do
        :uac -> :uas
        :uas -> :uac
      end

    %__MODULE__{
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

      iex> dialog_id1 = %Parrot.Sip.DialogId{call_id: "abc", local_tag: "123", remote_tag: "456"}
      iex> dialog_id2 = %Parrot.Sip.DialogId{call_id: "abc", local_tag: "123", remote_tag: "456"}
      iex> Parrot.Sip.DialogId.match?(dialog_id1, dialog_id2)
      true

      iex> dialog_id1 = %Parrot.Sip.DialogId{call_id: "abc", local_tag: "123", remote_tag: "456", direction: :uac}
      iex> dialog_id2 = %Parrot.Sip.DialogId{call_id: "abc", local_tag: "456", remote_tag: "123", direction: :uas}
      iex> Parrot.Sip.DialogId.match?(dialog_id1, dialog_id2)
      true
  """
  @spec match?(t(), t()) :: boolean()
  def match?(%__MODULE__{} = dialog_id1, %__MODULE__{} = dialog_id2) do
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

      iex> dialog_id = %Parrot.Sip.DialogId{call_id: "abc", local_tag: "123", remote_tag: nil}
      iex> Parrot.Sip.DialogId.with_remote_tag(dialog_id, "456")
      %Parrot.Sip.DialogId{call_id: "abc", local_tag: "123", remote_tag: "456"}
  """
  @spec with_remote_tag(t(), String.t()) :: t()
  def with_remote_tag(%__MODULE__{} = dialog_id, remote_tag) when is_binary(remote_tag) do
    %{dialog_id | remote_tag: remote_tag}
  end

  @doc """
  Converts a dialog ID to a string representation.

  ## Examples

      iex> dialog_id = %Parrot.Sip.DialogId{call_id: "abc", local_tag: "123", remote_tag: "456", direction: :uac}
      iex> Parrot.Sip.DialogId.to_string(dialog_id)
      "abc;local=123;remote=456;uac"
  """
  @spec to_string(t()) :: String.t()
  def to_string(%__MODULE__{} = dialog_id) do
    remote_part = if dialog_id.remote_tag, do: ";remote=#{dialog_id.remote_tag}", else: ""
    "#{dialog_id.call_id};local=#{dialog_id.local_tag}#{remote_part};#{dialog_id.direction}"
  end
end
