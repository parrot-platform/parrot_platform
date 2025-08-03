defmodule Parrot.Sip.Headers.Event do
  @moduledoc """
  Module for working with SIP Event headers as defined in RFC 3265 Section 7.2.

  The Event header field indicates the event or class of events that a SUBSCRIBE
  request is requesting notifications for, or that a NOTIFY message is reporting.

  The Event header is a mandatory component of the SIP events framework:
  - Required in all SUBSCRIBE requests to specify the event package
  - Required in all NOTIFY requests to indicate the event being notified
  - Supports event templates with parameters for flexible subscriptions
  - Enables the SIP-specific event notification framework

  Common event packages include:
  - presence: User presence information (RFC 3856)
  - message-summary: Message waiting indication (RFC 3842)
  - dialog: Dialog state events (RFC 4235)
  - reg: Registration state events (RFC 3680)
  - refer: REFER event package (RFC 3515)

  Event parameters allow for more specific subscriptions, such as
  subscribing to a specific dialog with an id parameter.

  References:
  - RFC 3265 Section 7.2: Event Header Field
  - RFC 3265 Section 7.4.1: Subscription Duration
  - RFC 3265: Session Initiation Protocol (SIP)-Specific Event Notification
  - IANA SIP Event Packages Registry
  """

  defstruct [
    :event,
    :parameters
  ]

  @type t :: %__MODULE__{
          event: String.t(),
          parameters: %{String.t() => String.t()}
        }

  @doc """
  Creates a new Event header.

  ## Examples

      iex> Parrot.Sip.Headers.Event.new("presence")
      %Parrot.Sip.Headers.Event{event: "presence", parameters: %{}}
      
      iex> Parrot.Sip.Headers.Event.new("presence", %{"id" => "1234"})
      %Parrot.Sip.Headers.Event{event: "presence", parameters: %{"id" => "1234"}}
  """
  @spec new(String.t(), map()) :: t()
  def new(event, parameters \\ %{}) when is_binary(event) do
    %__MODULE__{
      event: event,
      parameters: parameters
    }
  end

  @doc """
  Parses an Event header string into a struct.

  ## Examples

      iex> Parrot.Sip.Headers.Event.parse("presence")
      %Parrot.Sip.Headers.Event{event: "presence", parameters: %{}}
      
      iex> Parrot.Sip.Headers.Event.parse("presence;id=1234")
      %Parrot.Sip.Headers.Event{event: "presence", parameters: %{"id" => "1234"}}
  """
  @spec parse(String.t()) :: t()
  def parse(string) when is_binary(string) do
    case String.split(string, ";", parts: 2) do
      [event] ->
        %__MODULE__{
          event: event,
          parameters: %{}
        }

      [event, params_string] ->
        parameters =
          params_string
          |> String.split(";")
          |> Enum.map(&String.split(&1, "=", parts: 2))
          |> Enum.map(fn [key, value] -> {key, value} end)
          |> Enum.into(%{})

        %__MODULE__{
          event: event,
          parameters: parameters
        }
    end
  end

  @doc """
  Formats an Event struct as a string.

  ## Examples

      iex> event = %Parrot.Sip.Headers.Event{event: "presence", parameters: %{}}
      iex> Parrot.Sip.Headers.Event.format(event)
      "presence"
      
      iex> event = %Parrot.Sip.Headers.Event{event: "presence", parameters: %{"id" => "1234"}}
      iex> Parrot.Sip.Headers.Event.format(event)
      "presence;id=1234"
  """
  @spec format(t()) :: String.t()
  def format(%__MODULE__{} = event) do
    params_string =
      if Enum.empty?(event.parameters) do
        ""
      else
        ";" <>
          (event.parameters
           |> Enum.map(fn {key, value} -> "#{key}=#{value}" end)
           |> Enum.join(";"))
      end

    "#{event.event}#{params_string}"
  end

  @doc """
  Alias for format/1 for consistency with other header modules.

  ## Examples

      iex> event = %Parrot.Sip.Headers.Event{event: "presence", parameters: %{"id" => "1234"}}
      iex> Parrot.Sip.Headers.Event.to_string(event)
      "presence;id=1234"
  """
  @spec to_string(t()) :: String.t()
  def to_string(%__MODULE__{} = event), do: format(event)

  @doc """
  Gets the value of a parameter from an Event struct.

  ## Examples

      iex> event = %Parrot.Sip.Headers.Event{event: "presence", parameters: %{"id" => "1234"}}
      iex> Parrot.Sip.Headers.Event.get_parameter(event, "id")
      "1234"
      
      iex> event = %Parrot.Sip.Headers.Event{event: "presence", parameters: %{}}
      iex> Parrot.Sip.Headers.Event.get_parameter(event, "id")
      nil
  """
  @spec get_parameter(t(), String.t()) :: String.t() | nil
  def get_parameter(%__MODULE__{} = event, key) when is_binary(key) do
    Map.get(event.parameters, key)
  end

  @doc """
  Sets a parameter in an Event struct.

  ## Examples

      iex> event = %Parrot.Sip.Headers.Event{event: "presence", parameters: %{}}
      iex> Parrot.Sip.Headers.Event.set_parameter(event, "id", "1234")
      %Parrot.Sip.Headers.Event{event: "presence", parameters: %{"id" => "1234"}}
  """
  @spec set_parameter(t(), String.t(), String.t()) :: t()
  def set_parameter(%__MODULE__{} = event, key, value) when is_binary(key) and is_binary(value) do
    %__MODULE__{event | parameters: Map.put(event.parameters, key, value)}
  end
end
