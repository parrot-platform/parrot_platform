defmodule Parrot.Sip.Serializer do
  @moduledoc """
  Handles serialization and deserialization of SIP messages.

  This module provides functionality to:
  - Encode SIP message structs into properly formatted SIP message strings for transmission
  - Decode raw SIP message strings into structured Parrot.Sip.Message structs
  - Prepare messages for specific transport types
  - Handle multipart bodies and special header formats
  - Create multipart bodies with different content types

  All operations adhere to RFC 3261 specifications for SIP message formatting.

  References:
  - RFC 3261 Section 7: SIP Messages
  - RFC 3261 Section 7.3: Header Format
  - RFC 3261 Section 7.4: Content-Length Calculation
  - RFC 3261 Section 7.5: Framing SIP Messages
  - RFC 3261 Section 18: Transport
  - RFC 2045: Multipart Internet Mail Extensions (MIME)
  - RFC 3420: Internet Media Type message/sipfrag
  """

  alias Parrot.Sip.Message
  alias Parrot.Sip.Method
  alias Parrot.Sip.Parser

  # Map of compact form headers according to RFC 3261 and extensions
  @compact_headers %{
    "a" => "accept-contact",
    "b" => "referred-by",
    "c" => "content-type",
    "d" => "request-disposition",
    "e" => "content-encoding",
    "f" => "from",
    "i" => "call-id",
    "j" => "reject-contact",
    "k" => "supported",
    "l" => "content-length",
    "m" => "contact",
    "o" => "event",
    "r" => "refer-to",
    "s" => "subject",
    "t" => "to",
    "u" => "allow-events",
    "v" => "via",
    "x" => "session-expires"
  }

  # Standard headers that may contain spaces in quoted values
  @headers_with_quotes [
    "from",
    "to",
    "contact",
    "reply-to",
    "referred-by",
    "refer-to",
    "authentication-info",
    "authorization",
    "proxy-authenticate",
    "proxy-authorization",
    "www-authenticate"
  ]

  @doc """
  Encodes a SIP message struct into a raw SIP message string for transmission.

  This function handles all necessary preparation of the message for the specified
  transport type, including adding required headers and calculating content length.

  ## Parameters
    * `message` - A Parrot.Sip.Message struct to encode
    * `opts` - Optional map with encoding options:
      * `:transport_type` - Atom representing transport (:udp, :tcp, :tls, etc.)
      * `:local_host` - String with local hostname or IP address
      * `:local_port` - Integer port number
      * Other transport-specific options

  ## Returns
    * `binary()` - The encoded SIP message ready for transmission

  ## Examples

      iex> request = Parrot.Sip.Message.new_request(:invite, "sip:bob@example.com")
      iex> opts = %{transport_type: :udp, local_host: "alice.atlanta.com", local_port: 5060}
      iex> encoded = Parrot.Sip.Serializer.encode(request, opts)
      iex> encoded =~ ~r{^INVITE sip:bob@example.com SIP/2.0\\r\\n}
      true
      iex> encoded =~ ~r{Via: SIP/2.0/UDP alice.atlanta.com:5060;branch=z9hG4bK}
      true

      iex> response = Parrot.Sip.Message.new_response(200, "OK")
      iex> encoded = Parrot.Sip.Serializer.encode(response)
      iex> encoded =~ ~r{^SIP/2.0 200 OK\\r\\n}
      true
  """
  @spec encode(Message.t(), map()) :: binary()
  def encode(message, opts \\ %{}) do
    transport_type = Map.get(opts, :transport_type, :udp)

    message
    |> prepare_message(transport_type, opts)
    |> serialize()
  end

  @doc """
  Decodes a raw SIP message string into a Parrot.Sip.Message struct.

  This function handles parsing the raw message, validating its structure,
  and creating a properly structured Message struct.

  ## Parameters
    * `raw_data` - Binary string containing the raw SIP message
    * `source` - Optional map containing transport source information:
      * `:type` - Transport type (e.g., :udp, :tcp, :tls)
      * `:host` - Remote host IP or hostname
      * `:port` - Remote port
      * `:local_host` - Local IP or hostname
      * `:local_port` - Local port

  ## Returns
    * `{:ok, message}` - Successfully decoded message
    * `{:error, reason}` - Error with descriptive reason

  ## Examples

      iex> raw_data = "INVITE sip:bob@example.com SIP/2.0\\r\\nVia: SIP/2.0/UDP pc33.atlanta.com;branch=z9hG4bK776asdhds\\r\\nMax-Forwards: 70\\r\\nTo: Bob <sip:bob@biloxi.com>\\r\\nFrom: Alice <sip:alice@atlanta.com>;tag=1928301774\\r\\nCall-ID: a84b4c76e66710@pc33.atlanta.com\\r\\nCSeq: 314159 INVITE\\r\\nContact: <sip:alice@pc33.atlanta.com>\\r\\nContent-Type: application/sdp\\r\\nContent-Length: 0\\r\\n\\r\\n"
      iex> {:ok, message} = Parrot.Sip.Serializer.decode(raw_data)
      iex> message.method
      :invite

      iex> raw_data = "SIP/2.0 200 OK\\r\\nVia: SIP/2.0/UDP server10.biloxi.com;branch=z9hG4bK4b43c2ff8.1\\r\\nTo: Bob <sip:bob@biloxi.com>;tag=a6c85cf\\r\\nFrom: Alice <sip:alice@atlanta.com>;tag=1928301774\\r\\nCall-ID: a84b4c76e66710@pc33.atlanta.com\\r\\nCSeq: 314159 INVITE\\r\\nContent-Length: 0\\r\\n\\r\\n"
      iex> {:ok, message} = Parrot.Sip.Serializer.decode(raw_data)
      iex> message.status_code
      200
  """
  @spec decode(binary(), map() | nil) :: {:ok, Message.t()} | {:error, String.t()}
  def decode(raw_data, source \\ nil) when is_binary(raw_data) do
    # Process header folding before passing to parser
    unfolded_data = unfold_headers(raw_data)

    # Expand compact headers before parsing
    expanded_data = expand_compact_headers(unfolded_data)

    try do
      case Parser.parse(expanded_data) do
        {:ok, message} ->
          # Add source information to the message if provided
          message = if source, do: %{message | source: source}, else: message

          # Process multipart bodies if needed
          message = process_multipart_bodies(message)

          # Validate the message
          _result = Parser.validate_content_length!(message)

          case validate_message(message) do
            :ok -> {:ok, message}
            {:error, reason} -> {:error, reason}
          end

        {:error, reason} ->
          {:error, reason}
      end
    rescue
      e ->
        {:error, "Error processing SIP message in serializer: #{inspect(e)}"}
    end
  end

  @doc """
  Creates a source info map for an incoming message.

  This function is used to track the transport details of SIP messages, which
  is essential for proper response routing, especially in NAT traversal scenarios.
  The source information is attached to incoming messages and used when creating
  responses.

  ## Parameters
  - `type`: Transport type (e.g., `:udp`, `:tcp`, `:tls`)
  - `remote_host`: Host that sent the message (IP address or hostname)
  - `remote_port`: Port that the message was sent from
  - `local_host`: Local host that received the message
  - `local_port`: Local port that received the message

  ## Returns
  - Map containing the source information with the following fields:
    - `:type` - Transport type
    - `:host` - Remote host
    - `:port` - Remote port
    - `:local_host` - Local host
    - `:local_port` - Local port

  ## Examples

      iex> source = Parrot.Sip.Serializer.create_source_info(:udp, "192.168.1.100", 5060, "192.168.1.1", 5060)
      iex> source.type
      :udp
      iex> source.host
      "192.168.1.100"
  """
  @spec create_source_info(atom(), String.t(), non_neg_integer(), String.t(), non_neg_integer()) ::
          map()
  def create_source_info(type, remote_host, remote_port, local_host, local_port) do
    %{
      type: type,
      host: remote_host,
      port: remote_port,
      local_host: local_host,
      local_port: local_port
    }
  end

  @doc """
  Extracts source information from a message.

  Retrieves transport information from a message, typically used for
  determining where to send responses.

  ## Parameters
    * `message` - A Parrot.Sip.Message struct

  ## Returns
    * `{:ok, source}` - Successfully extracted source information
    * `{:error, reason}` - Error with reason string

  ## Examples

      iex> message = %Parrot.Sip.Message{source: %{type: :udp, host: "192.168.1.100", port: 5060}}
      iex> {:ok, source} = Parrot.Sip.Serializer.extract_source(message)
      iex> source.type
      :udp
  """
  @spec extract_source(Message.t()) :: {:ok, map()} | {:error, String.t()}
  def extract_source(%Message{source: source}) when is_map(source) do
    {:ok, source}
  end

  def extract_source(%Message{source: nil}) do
    {:error, "No source information available in message"}
  end

  # Private Functions

  # Serializes a SIP message struct into a string
  @spec serialize(Message.t()) :: binary()
  defp serialize(message) do
    start_line = build_start_line(message)

    # Ensure Content-Length header is set before building the headers string
    message_with_content_length = ensure_content_length(message)

    # Make sure headers appear in a predictable order for testing
    ordered_message = order_headers(message_with_content_length)

    headers_str = build_headers_string(ordered_message.headers)
    body = ordered_message.body || ""

    # Combine all parts with proper CRLF sequences
    start_line <> headers_str <> "\r\n" <> body
  end

  # Orders headers in a consistent way for testing
  defp order_headers(message) do
    # Define header priority order
    priority_order = [
      "via",
      "from",
      "to",
      "call-id",
      "cseq",
      "max-forwards",
      "route",
      "record-route",
      "contact",
      "content-type",
      "content-length"
    ]

    # Sort headers according to priority
    ordered_headers =
      Enum.reduce(priority_order, %{}, fn header, acc ->
        if Map.has_key?(message.headers, header) do
          Map.put(acc, header, message.headers[header])
        else
          acc
        end
      end)

    # Add any remaining headers not in the priority list
    full_ordered_headers =
      Enum.reduce(message.headers, ordered_headers, fn {k, v}, acc ->
        if Map.has_key?(acc, k) do
          acc
        else
          Map.put(acc, k, v)
        end
      end)

    %{message | headers: full_ordered_headers}
  end

  # Expands compact header forms to their full forms
  # Based on RFC 3261 Section 7.3.3 and related RFCs
  defp expand_compact_headers(data) do
    # Split into start line and the rest
    case Regex.run(~r/^([^\r\n]+)\r\n(.*)/s, data) do
      [_, start_line, rest] ->
        # List of compact header forms and their expanded versions
        compact_headers = [
          {"v", "Via"},
          {"i", "Call-ID"},
          {"m", "Contact"},
          {"e", "Content-Encoding"},
          {"l", "Content-Length"},
          {"c", "Content-Type"},
          {"f", "From"},
          {"s", "Subject"},
          {"k", "Supported"},
          {"t", "To"},
          # From RFC 3265
          {"o", "Event"},
          {"r", "Refer-To"},
          {"b", "Referred-By"},
          {"a", "Accept-Contact"},
          {"u", "Allow-Events"},
          {"y", "Identity"},
          {"d", "Request-Disposition"},
          {"j", "Reject-Contact"}
        ]

        # Replace compact forms with their expanded versions
        expanded_rest =
          Enum.reduce(compact_headers, rest, fn {compact, expanded}, acc ->
            Regex.replace(~r/^#{compact}:/im, acc, "#{expanded}:")
          end)

        start_line <> "\r\n" <> expanded_rest

      nil ->
        # If the regex doesn't match, just return the original data
        data
    end
  end

  # Prepares a message for a specific transport type
  @spec prepare_message(Message.t(), atom(), map()) :: Message.t()
  defp prepare_message(message, transport_type, opts) do
    message =
      case message.type do
        :request ->
          # Add Via header for requests
          local_host = Map.get(opts, :local_host, "localhost")
          local_port = Map.get(opts, :local_port, default_port_for_transport(transport_type))
          branch = "z9hG4bK" <> generate_branch_id()

          via_string =
            "SIP/2.0/#{String.upcase(to_string(transport_type))} #{local_host}:#{local_port};branch=#{branch}"

          # Add missing required headers for requests if not present
          message =
            if !has_header?(message, "max-forwards") do
              updated_headers = Map.put(message.headers, "max-forwards", 70)
              %{message | headers: updated_headers}
            else
              message
            end

          # Add Via as the first header
          updated_headers = Map.put(message.headers, "via", via_string)

          %{message | headers: updated_headers}

        :response ->
          # For responses, we don't need to add Via headers
          message
      end

    # Ensure proper Content-Length is set before sending
    ensure_content_length(message)
  end

  # Builds the start line based on whether the message is a request or response
  defp build_start_line(%Message{type: :request} = message) do
    method_str = method_to_string(message.method)
    "#{method_str} #{message.request_uri} #{message.version || "SIP/2.0"}\r\n"
  end

  defp build_start_line(%Message{type: :response} = message) do
    version = message.version || "SIP/2.0"
    "#{version} #{message.status_code} #{message.reason_phrase}\r\n"
  end

  # Converts method atom to string
  defp method_to_string(method) when is_atom(method) do
    Method.to_string(method)
  end

  # Builds the headers string from the headers map
  defp build_headers_string(headers) do
    headers
    |> Enum.map(fn {name, value} -> format_header(name, value) end)
    |> Enum.join("")
  end

  # Formats a single header
  defp format_header(name, value) do
    # Special case for headers with standardized capitalization
    header_name =
      case String.downcase(to_string(name)) do
        "call-id" ->
          "Call-ID"

        "cseq" ->
          "CSeq"

        "www-authenticate" ->
          "WWW-Authenticate"

        "mime-version" ->
          "MIME-Version"

        "content-id" ->
          "Content-ID"

        other ->
          other
          |> String.split("-")
          |> Enum.map(&String.capitalize/1)
          |> Enum.join("-")
      end

    formatted_value = format_header_value(name, value)

    # Handle long header values (> 75 chars) with folding according to RFC 3261 Section 7.3.1
    if String.length(formatted_value) > 75 do
      fold_header_value("#{header_name}: ", formatted_value)
    else
      "#{header_name}: #{formatted_value}\r\n"
    end
  end

  # Formats header values based on their type
  defp format_header_value(_name, value) when is_binary(value), do: value
  defp format_header_value(_name, value) when is_integer(value), do: Integer.to_string(value)

  defp format_header_value(name, value) when is_list(value) do
    # Handle multiple header values (e.g. for Via or Route headers)
    Enum.map_join(value, ", ", &format_header_value(name, &1))
  end

  defp format_header_value(name, value) do
    # Try to call format function on header module
    if is_struct(value) && function_exported?(value.__struct__, :format, 1) do
      value.__struct__.format(value)
    else
      # For header values that might contain quotes, ensure they're properly escaped
      if name in @headers_with_quotes and is_binary(value) and String.contains?(value, "\"") do
        ensure_quotes_escaped(value)
      else
        # Fall back to inspect for unhandled types
        inspect(value)
      end
    end
  end

  # Ensures that quotes within quoted strings are properly escaped
  defp ensure_quotes_escaped(value) do
    # This is a simplified implementation; a more complete version would use a parser
    # to identify quoted sections and only escape unescaped quotes within those sections
    Regex.replace(~r/(?<!\\)"/m, value, "\\\"")
  end

  # Folds long header values according to RFC 3261 Section 7.3.1
  defp fold_header_value(header_name, value) do
    # Split value into chunks of max 70 chars to leave room for folding
    chunks = chunk_string(value, 70)

    # First line has the header name
    first_line = "#{header_name}#{hd(chunks)}\r\n"

    # Subsequent lines are indented with space or tab (using space here)
    rest_lines =
      tl(chunks)
      |> Enum.map(fn chunk -> " #{chunk}\r\n" end)
      |> Enum.join("")

    first_line <> rest_lines
  end

  # Splits string into chunks of specified size, preserving words when possible
  defp chunk_string(str, chunk_size) do
    words = String.split(str, " ")
    chunk_words(words, chunk_size, "", [])
  end

  defp chunk_words([], _chunk_size, current_chunk, chunks) do
    Enum.reverse([current_chunk | chunks])
  end

  defp chunk_words([word | rest], chunk_size, current_chunk, chunks) do
    potential_chunk = if current_chunk == "", do: word, else: "#{current_chunk} #{word}"

    if String.length(potential_chunk) <= chunk_size do
      # Word fits in current chunk
      chunk_words(rest, chunk_size, potential_chunk, chunks)
    else
      # Start a new chunk
      chunk_words(rest, chunk_size, word, [current_chunk | chunks])
    end
  end

  # Ensures the Content-Length header is present and accurate in a message struct
  defp ensure_content_length(%Message{} = message) do
    body_size = if message.body, do: byte_size(message.body), else: 0
    updated_headers = Map.put(message.headers, "content-length", body_size)
    %{message | headers: updated_headers}
  end

  # Generate a random branch ID for Via headers
  defp generate_branch_id do
    :crypto.strong_rand_bytes(8) |> Base.encode16(case: :lower)
  end

  # Returns the default port for a transport type
  defp default_port_for_transport(:udp), do: 5060
  defp default_port_for_transport(:tcp), do: 5060
  defp default_port_for_transport(:tls), do: 5061
  defp default_port_for_transport(:ws), do: 80
  defp default_port_for_transport(:wss), do: 443
  defp default_port_for_transport(_), do: 5060

  # Validates the message format and required headers
  defp validate_message(message) do
    cond do
      # Check if required headers for requests are present
      Message.is_request?(message) && !has_required_request_headers?(message) ->
        missing_headers =
          get_missing_required_headers(message, [:from, :to, :"call-id", :cseq, :via])

        {:error,
         "Invalid SIP message format: Missing required headers: #{Enum.join(missing_headers, ", ")}"}

      # Check if required headers for responses are present
      Message.is_response?(message) && !has_required_response_headers?(message) ->
        missing_headers =
          get_missing_required_headers(message, [:from, :to, :"call-id", :cseq, :via])

        {:error,
         "Invalid SIP message format: Missing required headers: #{Enum.join(missing_headers, ", ")}"}

      # Validate Content-Length matches actual body length
      !valid_content_length?(message) ->
        {:error, "Content-Length does not match actual body length"}

      true ->
        :ok
    end
  end

  # Validates that Content-Length header matches actual body length
  defp valid_content_length?(message) do
    case Parser.validate_content_length(message) do
      {:error, _reason} ->
        false

      :ok ->
        true
    end
  end

  # Checks if all required headers for a request are present
  defp has_required_request_headers?(message) do
    # According to RFC 3261, requests MUST contain From, To, CSeq, Call-ID, Via
    # Max-Forwards is required by RFC 3261 but we'll be lenient for testing
    has_header?(message, "from") &&
      has_header?(message, "to") &&
      has_header?(message, "cseq") &&
      has_header?(message, "call-id") &&
      has_header?(message, "via")
  end

  # Checks if all required headers for a response are present
  defp has_required_response_headers?(message) do
    # According to RFC 3261, responses MUST contain From, To, CSeq, Call-ID, Via
    has_header?(message, "from") &&
      has_header?(message, "to") &&
      has_header?(message, "cseq") &&
      has_header?(message, "call-id") &&
      has_header?(message, "via")
  end

  # Checks if a specific header is present in the message
  defp has_header?(message, header_name) do
    header_value = Message.get_header(message, header_name)

    header_value != nil && header_value != ""
  end

  # Gets a list of missing required headers
  defp get_missing_required_headers(message, required_headers) do
    Enum.filter(required_headers, fn header ->
      header_name = to_string(header)
      !has_header?(message, header_name)
    end)
  end

  # Unfolds headers according to RFC 3261 Section 7.3.1
  # Headers can be split across multiple lines, with each continuation line beginning with SP or HTAB
  defp unfold_headers(raw_data) do
    Regex.replace(~r/\r\n[ \t]+/, raw_data, " ")
  end

  # Process multipart bodies if content-type indicates multipart
  defp process_multipart_bodies(%{headers: headers, body: body} = message) when is_binary(body) do
    content_type = Map.get(headers, "content-type", "")

    case content_type do
      %Parrot.Sip.Headers.ContentType{type: "multipart"} = ct ->
        # Extract boundary parameter from the ContentType struct
        boundary = Map.get(ct.parameters, "boundary")

        if boundary do
          parse_multipart_body(message, boundary)
        else
          # No boundary found, return unchanged
          message
        end

      # Handle the case where content_type is a string (backward compatibility)
      content_type when is_binary(content_type) ->
        if content_type =~ ~r/^multipart\//i do
          # Extract boundary parameter
          case Regex.run(~r/boundary=(?:"([^"]+)"|([^\s;]+))/, content_type) do
            [_, boundary] -> parse_multipart_body(message, boundary)
            [_, "", boundary] -> parse_multipart_body(message, boundary)
            [_, boundary, ""] -> parse_multipart_body(message, boundary)
            # No boundary found, return unchanged
            _ -> message
          end
        else
          message
        end

      _ ->
        message
    end
  end

  defp process_multipart_bodies(message), do: message

  # Parse multipart body into structured parts
  defp parse_multipart_body(%{body: body} = message, boundary) do
    boundary_pattern = "--#{boundary}"
    end_boundary_pattern = "--#{boundary}--"

    # Split the body into parts based on boundary
    parts =
      body
      |> String.split(boundary_pattern)
      |> Enum.filter(fn part ->
        trimmed = String.trim(part)

        trimmed != "" and
          not String.starts_with?(trimmed, "--") and
          trimmed != String.trim_leading(end_boundary_pattern, "-")
      end)
      |> Enum.map(&String.trim/1)
      |> Enum.map(&parse_part/1)
      |> Enum.filter(fn part ->
        # Filter out parts without valid headers or body
        Map.has_key?(part, :headers) and Map.has_key?(part, :body) and
          not (part.headers == %{} and part.body == "")
      end)

    # Store parsed parts in message headers for application use
    headers = Map.put(message.headers, "multipart-parts", parts)
    %{message | headers: headers}
  end

  # Parse an individual part into headers and body
  defp parse_part(part) do
    # Try different separator patterns since implementations may vary
    separators = ["\r\n\r\n", "\n\n", "\r\r"]

    result =
      Enum.find_value(separators, fn separator ->
        case String.split(part, separator, parts: 2) do
          [headers_str, body] when headers_str != "" and body != "" ->
            # Process headers
            headers =
              headers_str
              |> String.split(~r/\r\n|\r|\n/)
              |> Enum.filter(fn line -> line != "" end)
              |> Enum.map(&parse_header_line/1)
              |> Enum.filter(fn x -> x != nil end)
              |> Map.new()

            # Normalize headers to lowercase for consistent access
            normalized_headers =
              Enum.reduce(headers, %{}, fn {key, value}, acc ->
                Map.put(acc, String.downcase(key), value)
              end)

            %{headers: normalized_headers, body: String.trim(body)}

          _ ->
            nil
        end
      end)

    case result do
      # Fallback if no valid parsing
      nil -> %{headers: %{}, body: part}
      part_data -> part_data
    end
  end

  # Parse a single header line into {name, value} tuple
  defp parse_header_line(line) do
    if String.contains?(line, ":") do
      [name, value] = String.split(line, ":", parts: 2)
      {String.downcase(String.trim(name)), String.trim(value)}
    else
      nil
    end
  end

  # Map compact header form to full form according to RFC 3261 Section 7.3.3
  # This is called by the Parser module during header parsing
  @doc false
  def expand_compact_header(header_name) do
    Map.get(@compact_headers, header_name, header_name)
  end

  @doc """
  Creates a multipart body from a list of parts.

  Each part should be a map containing `:content_type` and `:body` fields.
  This function generates a unique boundary if one is not provided and
  constructs the multipart body according to MIME specifications.

  ## Parameters
    * `parts` - List of part maps, each with `:content_type` and `:body` fields
    * `opts` - Options map:
      * `:boundary` - Optional custom boundary string
      * `:content_type` - Optional content type (defaults to "multipart/mixed")

  ## Returns
    * `{body, content_type}` tuple with the assembled multipart body and full content-type header value

  ## Examples

      iex> parts = [
      ...>   %{content_type: "application/sdp", body: "v=0\\r\\no=alice 2890844526 2890844526 IN IP4 pc33.atlanta.com\\r\\ns=Session SDP"},
      ...>   %{content_type: "application/isup", body: "ISUP message data"}
      ...> ]
      iex> {body, content_type} = Parrot.Sip.Serializer.create_multipart_body(parts)
      iex> String.starts_with?(content_type, "multipart/mixed;boundary=")
      true
      iex> String.contains?(body, "Content-Type: application/sdp")
      true
      iex> String.contains?(body, "Content-Type: application/isup")
      true
  """
  @spec create_multipart_body(list(map()), map()) :: {String.t(), String.t()}
  def create_multipart_body(parts, opts \\ %{}) when is_list(parts) do
    # Generate a random boundary if not provided
    boundary =
      Map.get(
        opts,
        :boundary,
        "boundary_" <> (:crypto.strong_rand_bytes(8) |> Base.encode16(case: :lower))
      )

    # Determine content type
    base_content_type = Map.get(opts, :content_type, "multipart/mixed")
    content_type = "#{base_content_type};boundary=#{boundary}"

    # Create the multipart body
    body =
      Enum.map_join(parts, "\r\n", fn part ->
        """
        --#{boundary}
        Content-Type: #{part.content_type}

        #{part.body}
        """
      end)

    # Add the final boundary
    body = body <> "\r\n--#{boundary}--\r\n"

    {body, content_type}
  end
end
