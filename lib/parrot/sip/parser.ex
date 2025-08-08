defmodule Parrot.Sip.Parser do
  @moduledoc """
  SIP message parser using NimbleParsec.

  This module provides the core functionality for parsing SIP messages
  according to RFC 3261 and related specifications.
  """

  import NimbleParsec

  require Logger

  alias Parrot.Sip.Message
  alias Parrot.Sip.Headers

  # Constants
  @sip_methods [
    :invite,
    :ack,
    :bye,
    :cancel,
    :options,
    :register,
    :prack,
    :subscribe,
    :notify,
    :publish,
    :info,
    :refer,
    :message,
    :update
  ]

  # Common parsers
  whitespace = ascii_string([?\s, ?\t], min: 1)
  optional_whitespace = ascii_string([?\s, ?\t], min: 0)

  crlf = string("\r\n")

  token_char = [
    ?!,
    ?%,
    ?',
    ?*,
    ?+,
    ?-,
    ?.,
    ?0,
    ?1,
    ?2,
    ?3,
    ?4,
    ?5,
    ?6,
    ?7,
    ?8,
    ?9,
    ?A,
    ?B,
    ?C,
    ?D,
    ?E,
    ?F,
    ?G,
    ?H,
    ?I,
    ?J,
    ?K,
    ?L,
    ?M,
    ?N,
    ?O,
    ?P,
    ?Q,
    ?R,
    ?S,
    ?T,
    ?U,
    ?V,
    ?W,
    ?X,
    ?Y,
    ?Z,
    ?_,
    ?`,
    ?a,
    ?b,
    ?c,
    ?d,
    ?e,
    ?f,
    ?g,
    ?h,
    ?i,
    ?j,
    ?k,
    ?l,
    ?m,
    ?n,
    ?o,
    ?p,
    ?q,
    ?r,
    ?s,
    ?t,
    ?u,
    ?v,
    ?w,
    ?x,
    ?y,
    ?z,
    ?~
  ]

  token = ascii_string(token_char, min: 1)

  # Request-Line parsers
  method =
    choice([
      string("INVITE") |> replace(:invite),
      string("ACK") |> replace(:ack),
      string("BYE") |> replace(:bye),
      string("CANCEL") |> replace(:cancel),
      string("OPTIONS") |> replace(:options),
      string("REGISTER") |> replace(:register),
      string("PRACK") |> replace(:prack),
      string("SUBSCRIBE") |> replace(:subscribe),
      string("NOTIFY") |> replace(:notify),
      string("PUBLISH") |> replace(:publish),
      string("INFO") |> replace(:info),
      string("REFER") |> replace(:refer),
      string("MESSAGE") |> replace(:message),
      string("UPDATE") |> replace(:update)
    ])

  sip_uri = ascii_string([not: ?\s], min: 1)

  sip_version = string("SIP/2.0")

  request_line =
    method
    |> ignore(whitespace)
    |> concat(sip_uri)
    |> ignore(whitespace)
    |> concat(sip_version)
    |> ignore(crlf)
    |> tag(:request_line)

  # Status-Line parsers
  status_code = integer(min: 1, max: 3)
  reason_phrase = ascii_string([not: ?\r], min: 0)

  status_line =
    sip_version
    |> ignore(whitespace)
    |> concat(status_code)
    |> ignore(whitespace)
    |> concat(reason_phrase)
    |> ignore(crlf)
    |> tag(:status_line)

  # Header parsers
  header_name =
    token
    |> map({String, :downcase, []})

  # Parse a header value
  header_value =
    ascii_string([not: ?\r], min: 0)
    |> ignore(crlf)

  header =
    header_name
    |> ignore(string(":"))
    |> ignore(optional_whitespace)
    |> concat(header_value)
    |> tag(:header)

  # Body parser
  body =
    ascii_string([], min: 0)
    |> tag(:body)

  # Complete message parser
  defparsec(
    :parse_message,
    choice([request_line, status_line])
    |> times(header, min: 0)
    |> ignore(crlf)
    |> optional(body)
  )

  @doc """
  Parse a SIP message from a binary string.

  Returns `{:ok, message}` or `{:error, reason}`.
  """
  @spec parse(binary()) :: {:ok, Message.t()} | {:error, String.t()}
  def parse(raw_message) when is_binary(raw_message) do
    # Pre-process the raw message to handle folded headers
    processed_message = unfold_headers(raw_message)

    case parse_message(processed_message) do
      {:ok, parsed, "", _, _, _} ->
        process_parsed_message(parsed)

      {:ok, _, _rest, _, _, _} ->
        {:error, "Invalid SIP message: unparsed content remains"}

      {:error, _reason, _rest, _context, _line, _col} ->
        {:error, "Invalid SIP message format"}
    end
  end

  # Unfold header lines that are continued on the next line with whitespace
  defp unfold_headers(message) do
    String.replace(message, ~r/\r\n[ \t]+/, " ")
  end

  # Process the parsed message and convert it to a Message struct
  defp process_parsed_message(parsed) do
    # Extract parts from parsed result
    {type, parts} = extract_message_parts(parsed)

    # Create basic message structure
    base_message =
      case type do
        :request ->
          %Message{
            method: parts.method,
            request_uri: parts.request_uri,
            version: parts.version,
            headers: parts.headers,
            body: parts.body,
            type: :request,
            direction: :incoming
          }

        :response ->
          %Message{
            status_code: parts.status_code,
            reason_phrase: parts.reason_phrase,
            version: parts.version,
            headers: parts.headers,
            body: parts.body,
            type: :response,
            direction: :incoming
          }
      end

    # RFC 3261 Section 17.1.3: Transaction ID is the branch parameter from the top Via header
    transaction_id =
      case Map.get(base_message.headers, "via") do
        nil ->
          nil

        via when is_list(via) ->
          case via do
            [top | _] -> Map.get(top.parameters, "branch")
            _ -> nil
          end

        via ->
          Map.get(via.parameters, "branch")
      end

    # RFC 3261 Section 12.1.1: Dialog ID is Call-ID + tags
    dialog_id =
      try do
        Logger.debug("Getting dialog_id from message")
        Parrot.Sip.DialogId.from_message(base_message)
      rescue
        _ -> nil
      end

    message = %Message{base_message | transaction_id: transaction_id, dialog_id: dialog_id}

    # Validate required headers and content length
    with :ok <- validate_message(message),
         :ok <- validate_content_length(message) do
      {:ok, message}
    else
      {:error, reason} -> {:error, reason}
    end
  rescue
    e -> {:error, "Error processing SIP message in parser: #{inspect(e)}"}
  end

  # Extract components from the parsed message
  defp extract_message_parts(parsed) do
    # Initialize with empty values
    parts = %{
      headers: %{},
      body: ""
    }

    # Process each part
    {type, updated_parts} =
      Enum.reduce(parsed, {nil, parts}, fn
        {:request_line, [method, request_uri, version]}, {_, parts} ->
          {:request,
           Map.merge(parts, %{
             method: method,
             request_uri: request_uri,
             version: version
           })}

        {:status_line, [version, status_code, reason_phrase]}, {_, parts} ->
          {:response,
           Map.merge(parts, %{
             version: version,
             status_code: status_code,
             reason_phrase: reason_phrase
           })}

        {:header, [name, value]}, {type, parts} ->
          # Process headers
          headers = process_header(name, value, parts.headers)
          {type, %{parts | headers: headers}}

        {:body, [body]}, {type, parts} ->
          {type, %{parts | body: body}}

        _, acc ->
          acc
      end)

    {type, updated_parts}
  end

  # Process individual headers
  defp process_header(name, value, headers) do
    # Trim leading/trailing whitespace from value
    value = String.trim(value)

    # Process based on header name
    case name do
      "via" ->
        # Via headers can be repeated
        parsed = Headers.Via.parse(value)

        case Map.get(headers, "via") do
          nil ->
            Map.put(headers, "via", parsed)

          existing ->
            if is_list(existing) do
              Map.put(headers, "via", existing ++ [parsed])
            else
              Map.put(headers, "via", [existing, parsed])
            end
        end

      "accept" ->
        # For Accept headers, we need to keep the first one or create a list
        parsed = Headers.Accept.parse(value)

        case Map.get(headers, "accept") do
          nil ->
            Map.put(headers, "accept", parsed)

          existing ->
            if is_list(existing) do
              Map.put(headers, "accept", existing ++ [parsed])
            else
              Map.put(headers, "accept", [existing, parsed])
            end
        end

      "from" ->
        Map.put(headers, "from", Headers.From.parse(value))

      "to" ->
        Map.put(headers, "to", Headers.To.parse(value))

      "contact" ->
        Map.put(headers, "contact", Headers.Contact.parse(value))

      "call-id" ->
        Map.put(headers, "call-id", Headers.CallId.parse(value))

      "cseq" ->
        Map.put(headers, "cseq", Headers.CSeq.parse(value))

      "content-length" ->
        Map.put(headers, "content-length", Headers.ContentLength.parse(value))

      "max-forwards" ->
        Map.put(headers, "max-forwards", Headers.MaxForwards.parse(value))

      "expires" ->
        Map.put(headers, "expires", Headers.Expires.parse(value))

      "content-type" ->
        Map.put(headers, "content-type", Headers.ContentType.parse(value))

      "refer-to" ->
        Map.put(headers, "refer-to", Headers.ReferTo.parse(value))

      "event" ->
        Map.put(headers, "event", Headers.Event.parse(value))

      "subscription-state" ->
        Map.put(headers, "subscription-state", Headers.SubscriptionState.parse(value))

      "subject" ->
        Map.put(headers, "subject", Headers.Subject.parse(value))

      "allow" ->
        Map.put(headers, "allow", Headers.Allow.parse(value))

      "supported" ->
        Map.put(headers, "supported", Headers.Supported.parse(value))

      # For other headers, just store the raw value
      _ ->
        Map.put(headers, name, value)
    end
  end

  # Validate that Content-Length matches the actual body length
  def validate_content_length(message) do
    if Map.has_key?(message.headers, "content-length") do
      declared_length = message.headers["content-length"].value
      actual_length = byte_size(message.body)

      cond do
        # Reject negative Content-Length values
        declared_length < 0 ->
          {:error, "Content-Length header value cannot be negative (#{declared_length})"}

        actual_length != declared_length ->
          # Be lenient with Content-Length mismatches for UDP
          # Many SIP implementations have minor discrepancies
          # Log a warning but don't reject the message
          require Logger

          Logger.debug(
            "Content-Length mismatch: declared #{declared_length}, actual #{actual_length}"
          )

          :ok

        true ->
          :ok
      end
    else
      # If no Content-Length header, it's valid (though not recommended for TCP)
      :ok
    end
  end

  def validate_content_length!(message) do
    case validate_content_length(message) do
      :ok -> :ok
      {:error, reason} -> raise ArgumentError, reason
    end
  end

  # All header-specific parsing is now handled by their respective Headers modules

  # Validate that the message has all required headers
  defp validate_message(message) do
    required_request_headers = ["via", "to", "from", "call-id", "cseq"]
    required_response_headers = ["via", "to", "from", "call-id", "cseq"]

    required_headers =
      case message.type do
        :request -> required_request_headers
        :response -> required_response_headers
        _ -> required_request_headers
      end

    missing_headers =
      Enum.filter(required_headers, fn header ->
        not Map.has_key?(message.headers, header)
      end)

    cond do
      message.type == :request and not Enum.member?(@sip_methods, message.method) ->
        {:error, "Invalid SIP method: #{message.method}"}

      message.type == :response and (message.status_code < 100 or message.status_code > 699) ->
        {:error, "Invalid SIP message format: Invalid status code: #{message.status_code}"}

      length(missing_headers) > 0 ->
        {:error,
         "Invalid SIP message format: Missing required headers: #{Enum.join(missing_headers, ", ")}"}

      message.type == :request and
        Map.has_key?(message.headers, "cseq") and
          not Enum.member?(@sip_methods, message.headers["cseq"].method) ->
        {:error, "Invalid CSeq method: #{message.headers["cseq"].method}"}

      Map.has_key?(message.headers, "via") and is_binary(message.headers["via"]) ->
        # If Via is still a string, try to parse it properly
        try do
          via = Headers.Via.parse(message.headers["via"])
          # Update the message, but we don't need to use it since we just return :ok
          _updated_message = %{message | headers: Map.put(message.headers, "via", via)}
          :ok
        rescue
          _ -> {:error, "Invalid Via header format"}
        end

      true ->
        :ok
    end
  end
end
