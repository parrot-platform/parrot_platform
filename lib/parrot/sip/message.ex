defmodule Parrot.Sip.Message do
  @moduledoc """
  Represents a SIP message (request or response).

  This module provides a struct and functions for working with SIP messages as defined
  in RFC 3261 and related specifications. It provides a pure functional implementation
  that models both SIP requests and responses, along with utility functions for
  manipulation, analysis, and conversion.

  References:
  - RFC 3261 Section 7: SIP Messages
  - RFC 3261 Section 8.1: UAC Behavior
  - RFC 3261 Section 8.2: UAS Behavior
  - RFC 3261 Section 20: Header Fields
  """

  require Logger

  alias Parrot.Sip.DialogId
  alias Parrot.Sip.Headers.{CSeq, From, To, Via, CallId, Contact}
  alias Parrot.Sip.Method

  defstruct [
    # Atom like :invite, :register
    :method,
    # URI for requests
    :request_uri,
    # Integer for responses
    :status_code,
    # String for responses
    :reason_phrase,
    # String, typically "SIP/2.0"
    :version,
    # Map of header name to header struct
    :headers,
    # Binary string
    :body,
    # Source information for transport
    :source,
    # :request or :response
    :type,
    # :incoming or :outgoing
    :direction,
    # transaction_id
    :transaction_id,
    # dialog_id
    :dialog_id
  ]

  @type t :: %__MODULE__{
          method: Method.t() | nil,
          request_uri: String.t() | nil,
          status_code: integer() | nil,
          reason_phrase: String.t() | nil,
          version: String.t(),
          headers: map(),
          body: String.t(),
          source: map() | nil,
          type: :request | :response | nil,
          direction: :incoming | :outgoing | nil,
          transaction_id: String.t() | nil,
          dialog_id: String.t() | nil
        }

  @default_reason_phrases %{
    100 => "Trying",
    180 => "Ringing",
    181 => "Call Is Being Forwarded",
    182 => "Queued",
    183 => "Session Progress",
    199 => "Early Dialog Terminated",
    200 => "OK",
    202 => "Accepted",
    204 => "No Notification",
    300 => "Multiple Choices",
    301 => "Moved Permanently",
    302 => "Moved Temporarily",
    305 => "Use Proxy",
    380 => "Alternative Service",
    400 => "Bad Request",
    401 => "Unauthorized",
    402 => "Payment Required",
    403 => "Forbidden",
    404 => "Not Found",
    405 => "Method Not Allowed",
    406 => "Not Acceptable",
    407 => "Proxy Authentication Required",
    408 => "Request Timeout",
    409 => "Conflict",
    410 => "Gone",
    412 => "Conditional Request Failed",
    413 => "Request Entity Too Large",
    414 => "Request-URI Too Long",
    415 => "Unsupported Media Type",
    416 => "Unsupported URI Scheme",
    417 => "Unknown Resource-Priority",
    420 => "Bad Extension",
    421 => "Extension Required",
    422 => "Session Interval Too Small",
    423 => "Interval Too Brief",
    424 => "Bad Location Information",
    428 => "Use Identity Header",
    429 => "Provide Referrer Identity",
    430 => "Flow Failed",
    433 => "Anonymity Disallowed",
    436 => "Bad Identity-Info",
    437 => "Unsupported Certificate",
    438 => "Invalid Identity Header",
    439 => "First Hop Lacks Outbound Support",
    440 => "Max-Breadth Exceeded",
    470 => "Consent Needed",
    480 => "Temporarily Unavailable",
    481 => "Call/Transaction Does Not Exist",
    482 => "Loop Detected",
    483 => "Too Many Hops",
    484 => "Address Incomplete",
    485 => "Ambiguous",
    486 => "Busy Here",
    487 => "Request Terminated",
    488 => "Not Acceptable Here",
    489 => "Bad Event",
    491 => "Request Pending",
    493 => "Undecipherable",
    494 => "Security Agreement Required",
    500 => "Server Internal Error",
    501 => "Not Implemented",
    502 => "Bad Gateway",
    503 => "Service Unavailable",
    504 => "Server Time-out",
    505 => "Version Not Supported",
    513 => "Message Too Large",
    580 => "Precondition Failure",
    600 => "Busy Everywhere",
    603 => "Decline",
    604 => "Does Not Exist Anywhere",
    606 => "Not Acceptable",
    607 => "Unwanted",
    608 => "Rejected"
  }

  @doc """
  Returns the default reason phrase for a given SIP status code.
  """
  @spec default_reason_phrase(integer()) :: String.t()
  def default_reason_phrase(status_code) do
    Map.get(@default_reason_phrases, status_code, "Unknown")
  end

  @doc """
  Creates a new request message with the specified method, request URI, and headers.

  This function is the main entry point for creating SIP request messages.

  ## Parameters
  - method: The SIP method (atom) for the request
  - request_uri: The request target URI
  - headers: Optional map of initial headers

  ## Examples

      iex> Parrot.Sip.Message.new_request(:invite, "sip:alice@example.com")
      %Parrot.Sip.Message{
        method: :invite,
        request_uri: "sip:alice@example.com",
        version: "SIP/2.0",
        headers: %{},
        body: "",
        type: :request,
        direction: :outgoing
      }
  """
  @spec new_request(Method.t(), String.t(), map(), keyword()) :: t()
  def new_request(method, request_uri, headers \\ %{}, opts \\ []) do
    %__MODULE__{
      method: method,
      request_uri: request_uri,
      version: "SIP/2.0",
      headers: headers,
      body: "",
      type: :request,
      direction: :outgoing,
      dialog_id: Keyword.get(opts, :dialog_id, nil),
      transaction_id: Keyword.get(opts, :transaction_id, nil)
    }
  end

  @doc """
  Creates a new response message with the specified status code, reason phrase, and headers.

  ## Parameters
  - status_code: The SIP response status code (100-699)
  - reason_phrase: The reason phrase for the response
  - headers: Optional map of initial headers

  ## Examples

      iex> Parrot.Sip.Message.new_response(200, "OK")
      %Parrot.Sip.Message{
        status_code: 200,
        reason_phrase: "OK",
        version: "SIP/2.0",
        headers: %{},
        body: "",
        type: :response,
        direction: :outgoing
      }
  """
  @spec new_response(integer(), String.t(), map(), keyword()) :: t()
  def new_response(status_code, reason_phrase, headers, opts) do
    %__MODULE__{
      status_code: status_code,
      reason_phrase: reason_phrase,
      version: "SIP/2.0",
      headers: headers,
      body: "",
      type: :response,
      direction: :outgoing,
      dialog_id: Keyword.get(opts, :dialog_id, nil),
      transaction_id: Keyword.get(opts, :transaction_id, nil)
    }
  end

  @doc """
  Creates a new response message with standard reason phrase based on status code.

  If no reason phrase is provided, a standard one will be used based on the status code.

  ## Examples

      iex> Parrot.Sip.Message.new_response(200)
      %Parrot.Sip.Message{
        status_code: 200,
        reason_phrase: "OK",
        version: "SIP/2.0",
        headers: %{},
        body: "",
        type: :response,
        direction: :outgoing
      }
  """
  @spec new_response(integer()) :: t()
  def new_response(status_code) do
    reason_phrase = Map.get(@default_reason_phrases, status_code, "Unknown")
    new_response(status_code, reason_phrase, %{}, [])
  end

  @spec new_response(integer(), String.t()) :: t()
  def new_response(status_code, reason_phrase) when is_binary(reason_phrase) do
    new_response(status_code, reason_phrase, %{}, [])
  end

  @spec new_response(integer(), keyword()) :: t()
  def new_response(status_code, opts) when is_list(opts) do
    reason_phrase = Map.get(@default_reason_phrases, status_code, "Unknown")
    new_response(status_code, reason_phrase, %{}, opts)
  end

  @spec new_response(integer(), String.t(), map()) :: t()
  def new_response(status_code, reason_phrase, headers) do
    new_response(status_code, reason_phrase, headers, [])
  end

  @doc """
  Creates a response from a request, copying necessary headers and setting
  the status code and reason phrase.

  This function follows the requirements in RFC 3261 Section 8.2.6 for
  copying headers from requests to responses.

  ## Parameters
  - request: The SIP request message
  - status_code: The response status code
  - reason_phrase: The reason phrase for the response

  ## Examples

      iex> request = Parrot.Sip.Message.new_request(:invite, "sip:alice@example.com")
      iex> response = Parrot.Sip.Message.reply(request, 200, "OK")
      iex> response.status_code
      200
  """
  @spec reply(t(), integer(), String.t()) :: t()
  def reply(request, status_code, reason_phrase) when request.type == :request do
    # Copy headers from request to response with proper manipulation
    resp_headers = %{}
    # Add via headers from request
    resp_headers = Map.put(resp_headers, "via", request.headers["via"])
    # Add to/from headers
    resp_headers = Map.put(resp_headers, "to", request.headers["to"])
    resp_headers = Map.put(resp_headers, "from", request.headers["from"])
    # Add call-id
    resp_headers = Map.put(resp_headers, "call-id", request.headers["call-id"])
    # Add CSeq
    resp_headers = Map.put(resp_headers, "cseq", request.headers["cseq"])

    %__MODULE__{
      method: request.method,
      request_uri: request.request_uri,
      status_code: status_code,
      reason_phrase: reason_phrase,
      version: request.version,
      headers: resp_headers,
      body: Map.get(request, :body, ""),
      source: request.source,
      type: :response,
      direction: :outgoing,
      dialog_id: Map.get(request, :dialog_id),
      transaction_id: Map.get(request, :transaction_id)
    }
  end

  @doc """
  Creates a response from a request with standard reason phrase based on status code.

  ## Examples

      iex> request = Parrot.Sip.Message.new_request(:invite, "sip:alice@example.com")
      iex> response = Parrot.Sip.Message.reply(request, 200)
      iex> response.reason_phrase
      "OK"
  """
  @spec reply(t(), integer()) :: t()
  def reply(request, status_code) when request.type == :request do
    reason_phrase = Map.get(@default_reason_phrases, status_code, "Unknown")
    reply(request, status_code, reason_phrase)
  end

  @doc """
  Gets a header from the message by name.

  Header names are case-insensitive as per RFC 3261.
  If the header is a map, it will be converted to the appropriate struct.

  ## Examples

      iex> message = Parrot.Sip.Message.new_request(:invite, "sip:bob@example.com")
      iex> message = Parrot.Sip.Message.set_header(message, "Via", %{protocol: "SIP", version: "2.0", transport: "udp"})
      iex> Parrot.Sip.Message.get_header(message, "via")
      %Parrot.Sip.Headers.Via{protocol: "SIP", version: "2.0", transport: :udp}
  """
  @spec get_header(t(), String.t()) :: any()
  # Get Via header using direct pattern matching
  def get_header(message, "Via"), do: get_via_header(message)
  def get_header(message, "via"), do: get_via_header(message)
  def get_header(message, "v"), do: get_via_header(message)

  # Regular get_header function for other headers
  def get_header(message, name) do
    downcased = String.downcase(name)

    # Resolve compact headers to their full forms using the Serializer's function
    full_name = Parrot.Sip.Serializer.expand_compact_header(downcased)

    # Get the value
    value = Map.get(message.headers, full_name)

    # Return nil if not found
    if is_nil(value) do
      nil
    else
      # Special case for content-type when accessed directly
      if full_name == "content-type" && is_struct(value, Parrot.Sip.Headers.ContentType) &&
           downcased == "content-type" do
        Parrot.Sip.Headers.ContentType.format(value)
      else
        # Return the value as-is (it should already be a proper struct or primitive value)
        value
      end
    end
  end

  @doc """
  Gets all headers of a given name. Returns a list, even if only one header is present.

  Useful for headers that can appear multiple times like Record-Route or Via.
  """
  @spec get_headers(t(), String.t()) :: [any()]
  def get_headers(message, name) do
    downcased = String.downcase(name)
    full_name = Parrot.Sip.Serializer.expand_compact_header(downcased)

    values = Map.get(message.headers, full_name)

    cond do
      is_nil(values) ->
        []

      is_list(values) ->
        Enum.map(values, fn
          v when is_struct(v) ->
            v

          v when is_map(v) ->
            struct_for_header(full_name, v)

          v ->
            v
        end)

      true ->
        [get_header(message, name)]
    end
  end

  # Extracted helper
  # Headers are now parsed as structs during the initial parsing process,
  # so this function is no longer needed. However, we keep it for backward compatibility
  # with any code that might still rely on it.
  defp struct_for_header("record-route", v) when is_map(v) and not is_struct(v),
    do: struct(Parrot.Sip.Headers.RecordRoute, v)

  defp struct_for_header("route", v) when is_map(v) and not is_struct(v),
    do: struct(Parrot.Sip.Headers.Route, v)

  defp struct_for_header("via", v) when is_map(v) and not is_struct(v),
    do: struct(Parrot.Sip.Headers.Via, v)

  defp struct_for_header("contact", v) when is_map(v) and not is_struct(v),
    do: struct(Parrot.Sip.Headers.Contact, v)

  defp struct_for_header(_, v), do: v

  # Helper function to handle Via header logic
  defp get_via_header(message) do
    value = Map.get(message.headers, "via")

    cond do
      is_nil(value) ->
        nil

      is_struct(value) ->
        value

      is_binary(value) ->
        Parrot.Sip.Headers.Via.parse(value)

      is_list(value) && Enum.all?(value, &is_binary/1) ->
        Enum.map(value, &Parrot.Sip.Headers.Via.parse/1)

      is_list(value) && Enum.all?(value, &is_struct/1) ->
        Enum.map(value, fn via_struct ->
          if is_struct(via_struct, Parrot.Sip.Headers.Via) do
            via_struct
          else
            struct(Parrot.Sip.Headers.Via, via_struct)
          end
        end)

      is_list(value) ->
        Enum.map(value, fn via ->
          struct(Parrot.Sip.Headers.Via, via)
        end)

      true ->
        struct(Parrot.Sip.Headers.Via, value)
    end
  end

  @doc """
  Sets a header in the message.

  Header names are converted to lowercase for consistent storage and retrieval.

  ## Examples

      iex> message = Parrot.Sip.Message.new_request(:invite, "sip:bob@example.com")
      iex> from_header = %Parrot.Sip.Headers.From{}
      iex> message = Parrot.Sip.Message.set_header(message, "From", from_header)
      iex> message.headers["from"] == from_header
      true
  """
  @spec set_header(t(), String.t(), any()) :: t()
  def set_header(message, name, value) do
    downcased = String.downcase(name)
    %{message | headers: Map.put(message.headers, downcased, value)}
  end

  @doc """
  Sets the body of the message and updates the Content-Length header.

  This function automatically calculates and sets the Content-Length header
  based on the body's length.

  ## Examples

      iex> message = Parrot.Sip.Message.new_request(:invite, "sip:bob@example.com")
      iex> message = Parrot.Sip.Message.set_body(message, "Hello, world!")
      iex> message.body
      "Hello, world!"
      iex> message.headers["content-length"]
      13
  """
  @spec set_body(t(), String.t()) :: t()
  def set_body(message, body) do
    headers = Map.put(message.headers, "content-length", byte_size(body))
    %{message | body: body, headers: headers}
  end

  @doc """
  Check if a message is a request.
  """
  @spec is_request?(t()) :: boolean()
  def is_request?(message), do: message.type == :request

  @doc """
  Check if a message is a response.
  """
  @spec is_response?(t()) :: boolean()
  def is_response?(message), do: message.type == :response

  @doc """
  Convert the message to a string representation.
  """
  @spec to_s(t()) :: String.t()
  def to_s(message) do
    start_line =
      if is_request?(message) do
        "#{method_to_string(message.method)} #{message.request_uri} #{message.version}\r\n"
      else
        "#{message.version} #{message.status_code} #{message.reason_phrase}\r\n"
      end

    headers_str = headers_to_string(message.headers)

    start_line <> headers_str <> "\r\n" <> (message.body || "")
  end

  defp method_to_string(method) when is_atom(method) do
    Method.to_string(method)
  end

  defp headers_to_string(headers) do
    # RFC 3261 Section 7.3.1: Header Field Order
    # Via headers must appear before all other headers
    # Then: Route, Record-Route, Proxy-Require, Max-Forwards, 
    # Proxy-Authorization, To, From, Contact, etc.
    
    # Define header order priority (lower number = higher priority)
    header_order = %{
      "via" => 1,
      "route" => 2,
      "record-route" => 3,
      "max-forwards" => 4,
      "proxy-require" => 5,
      "proxy-authorization" => 6,
      "from" => 7,
      "to" => 8,
      "call-id" => 9,
      "cseq" => 10,
      "contact" => 11,
      "expires" => 12,
      "content-type" => 13,
      "content-length" => 14
    }
    
    # Default priority for headers not in the list
    default_priority = 100
    
    headers
    |> Enum.sort_by(fn {name, _value} ->
      normalized_name = name |> to_string() |> String.downcase()
      Map.get(header_order, normalized_name, default_priority)
    end)
    |> Enum.map(fn {name, value} -> format_header(name, value) end)
    |> Enum.join("")
  end

  defp format_header(name, value) do
    header_name =
      name
      |> to_string()
      |> String.split("-")
      |> Enum.map(&String.capitalize/1)
      |> Enum.join("-")

    "#{header_name}: #{format_header_value(name, value)}\r\n"
  end

  defp format_header_value(_name, value) when is_binary(value), do: value
  defp format_header_value(_name, value) when is_integer(value), do: Integer.to_string(value)

  defp format_header_value(_name, value) when is_list(value) do
    # For lists, check if all elements are structs with format function
    if Enum.all?(value, &(is_struct(&1) && function_exported?(&1.__struct__, :format, 1))) do
      # Check if the module has a format_list function
      first_struct = List.first(value)
      if first_struct && function_exported?(first_struct.__struct__, :format_list, 1) do
        first_struct.__struct__.format_list(value)
      else
        # Default: format each and join with comma
        value
        |> Enum.map(&(&1.__struct__.format(&1)))
        |> Enum.join(", ")
      end
    else
      inspect(value)
    end
  end

  defp format_header_value(_name, value) do
    # Try to call format function on header module
    if is_struct(value) && function_exported?(value.__struct__, :format, 1) do
      value.__struct__.format(value)
    else
      # Fall back to inspect for unhandled types
      inspect(value)
    end
  end

  @doc """
  Gets the CSeq header from a message.

  ## Examples

      iex> message = Parrot.Sip.Message.new_request(:invite, "sip:bob@example.com")
      iex> cseq = %Parrot.Sip.Headers.CSeq{sequence: 1, method: :invite}
      iex> message = Parrot.Sip.Message.set_header(message, "CSeq", cseq)
      iex> Parrot.Sip.Message.cseq(message)
      %Parrot.Sip.Headers.CSeq{sequence: 1, method: :invite}
  """
  @spec cseq(t()) :: CSeq.t() | nil
  def cseq(message) do
    get_header(message, "cseq")
  end

  @doc """
  Gets the From header from a message.

  ## Examples

      iex> message = Parrot.Sip.Message.new_request(:invite, "sip:bob@example.com")
      iex> from = %Parrot.Sip.Headers.From{uri: "sip:alice@example.com"}
      iex> message = Parrot.Sip.Message.set_header(message, "From", from)
      iex> Parrot.Sip.Message.from(message)
      %Parrot.Sip.Headers.From{uri: "sip:alice@example.com"}
  """
  @spec from(t()) :: From.t() | nil
  def from(message) do
    get_header(message, "from")
  end

  @doc """
  Gets the To header from a message.

  ## Examples

      iex> message = Parrot.Sip.Message.new_request(:invite, "sip:bob@example.com")
      iex> to = %Parrot.Sip.Headers.To{uri: "sip:bob@example.com"}
      iex> message = Parrot.Sip.Message.set_header(message, "To", to)
      iex> Parrot.Sip.Message.to(message)
      %Parrot.Sip.Headers.To{uri: "sip:bob@example.com"}
  """
  @spec to(t()) :: To.t() | nil
  def to(message) do
    get_header(message, "to")
  end

  @doc """
  Gets the Call-ID header from a message.

  ## Examples

      iex> message = Parrot.Sip.Message.new_request(:invite, "sip:bob@example.com")
      iex> message = Parrot.Sip.Message.set_header(message, "Call-ID", "abc123@example.com")
      iex> Parrot.Sip.Message.call_id(message)
      "abc123@example.com"
  """
  @spec call_id(t()) :: String.t() | CallId.t() | nil
  def call_id(message) do
    get_header(message, "call-id")
  end

  @doc """
  Gets the top Via header from a message.

  ## Examples

      iex> message = Parrot.Sip.Message.new_request(:invite, "sip:bob@example.com")
      iex> via = %Parrot.Sip.Headers.Via{host: "example.com", port: 5060}
      iex> message = Parrot.Sip.Message.set_header(message, "Via", via)
      iex> Parrot.Sip.Message.top_via(message)
      %Parrot.Sip.Headers.Via{host: "example.com", port: 5060}
  """
  @spec top_via(t()) :: Via.t() | nil
  def top_via(message) do
    case get_header(message, "via") do
      nil -> nil
      via when is_list(via) -> List.first(via)
      via -> via
    end
  end

  @doc """
  Gets all Via headers from a message.

  ## Examples

      iex> message = Parrot.Sip.Message.new_request(:invite, "sip:bob@example.com")
      iex> via = %Parrot.Sip.Headers.Via{host: "example.com", port: 5060}
      iex> message = Parrot.Sip.Message.set_header(message, "Via", via)
      iex> Parrot.Sip.Message.all_vias(message)
      [%Parrot.Sip.Headers.Via{host: "example.com", port: 5060}]
  """
  @spec all_vias(t()) :: list(Via.t())
  def all_vias(message) do
    case get_header(message, "via") do
      nil -> []
      via when is_list(via) -> via
      via -> [via]
    end
  end

  @doc """
  Gets the Contact header from a message.

  ## Examples

      iex> message = Parrot.Sip.Message.new_request(:invite, "sip:bob@example.com")
      iex> contact = %Parrot.Sip.Headers.Contact{uri: "sip:alice@example.com"}
      iex> message = Parrot.Sip.Message.set_header(message, "Contact", contact)
      iex> Parrot.Sip.Message.contact(message)
      %Parrot.Sip.Headers.Contact{uri: "sip:alice@example.com"}
  """
  @spec contact(t()) :: Contact.t() | nil
  def contact(message) do
    get_header(message, "contact")
  end

  @doc """
  Gets the branch parameter from the top Via header.

  ## Examples

      iex> message = Parrot.Sip.Message.new_request(:invite, "sip:bob@example.com")
      iex> via = %Parrot.Sip.Headers.Via{parameters: %{"branch" => "z9hG4bK123"}}
      iex> message = Parrot.Sip.Message.set_header(message, "Via", via)
      iex> Parrot.Sip.Message.branch(message)
      "z9hG4bK123"
  """
  @spec branch(t()) :: String.t() | nil
  def branch(message) do
    case top_via(message) do
      nil -> nil
      via -> Map.get(via.parameters, "branch")
    end
  end

  @doc """
  Gets a dialog ID from a message.

  ## Examples

      iex> message = Parrot.Sip.Message.new_request(:invite, "sip:bob@example.com")
      iex> from = %Parrot.Sip.Headers.From{parameters: %{"tag" => "123"}}
      iex> to = %Parrot.Sip.Headers.To{parameters: %{"tag" => "456"}}
      iex> message = message |> Parrot.Sip.Message.set_header("From", from)
      iex> message = message |> Parrot.Sip.Message.set_header("To", to)
      iex> message = message |> Parrot.Sip.Message.set_header("Call-ID", "abc@example.com")
      iex> dialog_id = Parrot.Sip.Message.dialog_id(message)
      iex> dialog_id.call_id
      "abc@example.com"
  """
  @spec dialog_id(t()) :: DialogId.t()
  def dialog_id(message) do
    Logger.debug("Getting dialog_id from message")
    DialogId.from_message(message)
  end

  @doc """
  Determines if a message is within a dialog.

  A message is within a dialog if it has a To tag and a From tag.

  ## Examples

      iex> message = Parrot.Sip.Message.new_request(:invite, "sip:bob@example.com")
      iex> from = %Parrot.Sip.Headers.From{parameters: %{"tag" => "123"}}
      iex> to = %Parrot.Sip.Headers.To{parameters: %{"tag" => "456"}}
      iex> message = message |> Parrot.Sip.Message.set_header("From", from)
      iex> message = message |> Parrot.Sip.Message.set_header("To", to)
      iex> Parrot.Sip.Message.in_dialog?(message)
      true
  """
  @spec in_dialog?(t()) :: boolean()
  def in_dialog?(message) do
    from_header = from(message)
    to_header = to(message)

    from_tag = if from_header, do: From.tag(from_header), else: nil
    to_tag = if to_header, do: To.tag(to_header), else: nil

    not is_nil(from_tag) and not is_nil(to_tag)
  end

  @doc """
  Gets the status class of a response message (1xx, 2xx, etc.).

  ## Examples

      iex> message = Parrot.Sip.Message.new_response(200, "OK")
      iex> Parrot.Sip.Message.status_class(message)
      2
  """
  @spec status_class(t()) :: integer() | nil
  def status_class(%__MODULE__{type: :response, status_code: status_code})
      when is_integer(status_code) do
    div(status_code, 100)
  end

  def status_class(_), do: nil

  @doc """
  Checks if a response message is provisional (1xx).

  ## Examples

      iex> message = Parrot.Sip.Message.new_response(180, "Ringing")
      iex> Parrot.Sip.Message.is_provisional?(message)
      true
  """
  @spec is_provisional?(t()) :: boolean()
  def is_provisional?(message) do
    status_class(message) == 1
  end

  @doc """
  Checks if a response message is successful (2xx).

  ## Examples

      iex> message = Parrot.Sip.Message.new_response(200, "OK")
      iex> Parrot.Sip.Message.is_success?(message)
      true
  """
  @spec is_success?(t()) :: boolean()
  def is_success?(message) do
    status_class(message) == 2
  end

  @doc """
  Checks if a response message is a redirection (3xx).

  ## Examples

      iex> message = Parrot.Sip.Message.new_response(302, "Moved Temporarily")
      iex> Parrot.Sip.Message.is_redirect?(message)
      true
  """
  @spec is_redirect?(t()) :: boolean()
  def is_redirect?(message) do
    status_class(message) == 3
  end

  @doc """
  Checks if a response message is a client error (4xx).

  ## Examples

      iex> message = Parrot.Sip.Message.new_response(404, "Not Found")
      iex> Parrot.Sip.Message.is_client_error?(message)
      true
  """
  @spec is_client_error?(t()) :: boolean()
  def is_client_error?(message) do
    status_class(message) == 4
  end

  @doc """
  Checks if a response message is a server error (5xx).

  ## Examples

      iex> message = Parrot.Sip.Message.new_response(500, "Server Internal Error")
      iex> Parrot.Sip.Message.is_server_error?(message)
      true
  """
  @spec is_server_error?(t()) :: boolean()
  def is_server_error?(message) do
    status_class(message) == 5
  end

  @doc """
  Checks if a response message is a global error (6xx).

  ## Examples

      iex> message = Parrot.Sip.Message.new_response(603, "Decline")
      iex> Parrot.Sip.Message.is_global_error?(message)
      true
  """
  @spec is_global_error?(t()) :: boolean()
  def is_global_error?(message) do
    status_class(message) == 6
  end

  @doc """
  Checks if a response message is a failure (4xx, 5xx, or 6xx).

  ## Examples

      iex> message = Parrot.Sip.Message.new_response(404, "Not Found")
      iex> Parrot.Sip.Message.is_failure?(message)
      true
  """
  @spec is_failure?(t()) :: boolean()
  def is_failure?(message) do
    class = status_class(message)
    class in [4, 5, 6]
  end

  @doc """
  Converts a message to binary format for transmission.

  ## Examples

      iex> message = Parrot.Sip.Message.new_request(:invite, "sip:bob@example.com")
      iex> binary = Parrot.Sip.Message.to_binary(message)
      iex> String.starts_with?(binary, "INVITE sip:bob@example.com SIP/2.0")
      true
  """
  @spec to_binary(t()) :: binary()
  def to_binary(message) do
    to_s(message)
  end
end
