defmodule Parrot.Sip.Headers.Via do
  @moduledoc """
  Module for working with SIP Via headers as defined in RFC 3261 Section 20.42.

  The Via header is used to record the route taken by a SIP request and
  to route responses back along the same path. Each SIP element (proxy or UAC)
  that sends a request adds a Via header with its own address, while responses
  follow the Via headers in reverse order.

  The Via header contains:
  - Protocol and version (e.g., "SIP/2.0")
  - Transport protocol (e.g., UDP, TCP, TLS)
  - Sent-by address (hostname or IP address and optional port)
  - Branch parameter (a unique transaction identifier)
  - Optional parameters (e.g., received, rport, maddr)

  Via headers are critical for:
  - Loop detection (using the branch parameter)
  - Response routing (following the Via chain backwards)
  - NAT traversal (using received/rport parameters)

  The branch parameter starting with "z9hG4bK" indicates compliance with RFC 3261
  (Section 8.1.1.7) and forms part of the transaction identifier.

  This module supports both IPv4 and IPv6 addresses. IPv6 addresses in Via headers
  must be enclosed in square brackets as specified in RFC 3261 Section 25.1.

  References:
  - RFC 3261 Section 8.1.1.7: Transaction Identifier
  - RFC 3261 Section 18.2.1: Sending Responses
  - RFC 3261 Section 20.42: Via Header Field
  - RFC 3261 Section 25.1: IPv6 References
  - RFC 3581: Symmetric Response Routing (rport parameter)
  """

  alias Parrot.Sip.Branch

  defstruct [
    # String like "SIP"
    :protocol,
    # String like "2.0"
    :version,
    # Atom :udp, :tcp, :tls, :ws, :wss
    :transport,
    # String
    :host,
    # Integer (optional)
    :port,
    # Atom: :hostname, :ipv4, or :ipv6
    :host_type,
    # Map of parameters including :branch
    :parameters
  ]

  @type t :: %__MODULE__{
          protocol: String.t(),
          version: String.t(),
          transport: atom(),
          host: String.t(),
          port: integer() | nil,
          host_type: :hostname | :ipv4 | :ipv6,
          parameters: map()
        }

  @doc """
  Creates a new Via header.

  ## Examples

      iex> Parrot.Sip.Headers.Via.new("example.com")
      %Parrot.Sip.Headers.Via{
        protocol: "SIP",
        version: "2.0",
        transport: :udp,
        host: "example.com",
        port: nil,
        host_type: :hostname,
        parameters: %{}
      }
  """
  @spec new(String.t(), atom() | String.t(), integer() | nil, map()) :: t()
  def new(host, transport \\ "udp", port \\ nil, parameters \\ %{}) do
    transport_atom =
      if is_binary(transport), do: String.downcase(transport) |> String.to_atom(), else: transport

    host_type = determine_host_type(host)

    %__MODULE__{
      protocol: "SIP",
      version: "2.0",
      transport: transport_atom,
      host: normalize_host(host, host_type),
      port: port,
      host_type: host_type,
      parameters: parameters
    }
  end

  @spec determine_host_type(String.t()) :: :hostname | :ipv4 | :ipv6
  defp determine_host_type(host) do
    # Remove brackets for IPv6 detection
    clean_host = host |> String.trim_leading("[") |> String.trim_trailing("]")

    case :inet.parse_address(String.to_charlist(clean_host)) do
      {:ok, address} ->
        cond do
          :inet.is_ipv6_address(address) ->
            :ipv6

          :inet.is_ipv4_address(address) ->
            :ipv4
        end

      {:error, _reason} ->
        :hostname
    end
  end

  @spec normalize_host(String.t(), :hostname | :ipv4 | :ipv6) :: String.t()
  defp normalize_host(host, :ipv6) do
    # If it's already in brackets, return as is
    if String.starts_with?(host, "[") && String.ends_with?(host, "]") do
      host
    else
      # Otherwise, add brackets
      "[#{host}]"
    end
  end

  defp normalize_host(host, _) do
    # For IPv4 and hostname, return as is
    host
  end

  @doc """
  Generates a unique branch parameter for a Via header.

  Delegates to `Parrot.Sip.Branch.generate/0`.

  ## Examples

      iex> Parrot.Sip.Headers.Via.generate_branch()
      "z9hG4bK..."  # output will vary
  """
  @spec generate_branch() :: String.t()
  def generate_branch do
    Branch.generate()
  end

  @doc """
  Creates a new Via header with a randomly generated branch parameter.

  ## Examples

      iex> via = Parrot.Sip.Headers.Via.new_with_branch("example.com")
      iex> Parrot.Sip.Headers.Via.branch(via) |> String.starts_with?("z9hG4bK")
      true
  """
  @spec new_with_branch(String.t(), String.t(), integer() | nil, map()) :: t()
  def new_with_branch(host, transport \\ "udp", port \\ nil, parameters \\ %{}) do
    parameters = Map.put(parameters, "branch", generate_branch())
    new(host, transport, port, parameters)
  end

  @doc """
  Converts a Via header to a string representation.

  ## Examples

      iex> via = Parrot.Sip.Headers.Via.new("example.com", :udp, 5060, %{"branch" => "z9hG4bKabc"})
      iex> Parrot.Sip.Headers.Via.format(via)
      "SIP/2.0/UDP example.com:5060;branch=z9hG4bKabc"
  """
  @spec format(t()) :: String.t()
  def format(via) do
    # Format: SIP/2.0/UDP host:port;params
    transport_str = via.transport |> Atom.to_string() |> String.upcase()
    transport_part = "#{via.protocol}/#{via.version}/#{transport_str}"

    # For IPv6, the port comes after the closing bracket
    host_part =
      cond do
        via.host_type == :ipv6 && via.port != nil ->
          # The host should already have brackets from normalize_host
          "#{via.host}:#{via.port}"

        true ->
          if via.port, do: "#{via.host}:#{via.port}", else: via.host
      end

    params_part =
      via.parameters
      |> Enum.map(fn {k, v} ->
        if v == "", do: k, else: "#{k}=#{v}"
      end)
      |> Enum.join(";")

    if params_part == "" do
      "#{transport_part} #{host_part}"
    else
      "#{transport_part} #{host_part};#{params_part}"
    end
  end

  @doc """
  Formats a list of Via headers for SIP message serialization.
  
  Multiple Via headers are formatted on separate lines in SIP messages.
  
  ## Examples
  
      iex> via1 = Parrot.Sip.Headers.Via.new("proxy1.com", :udp, 5060)
      iex> via2 = Parrot.Sip.Headers.Via.new("proxy2.com", :tcp, 5061)
      iex> Parrot.Sip.Headers.Via.format_list([via1, via2])
      "SIP/2.0/UDP proxy1.com:5060, SIP/2.0/TCP proxy2.com:5061"
  """
  @spec format_list([t()]) :: String.t()
  def format_list(via_list) when is_list(via_list) do
    via_list
    |> Enum.map(&format/1)
    |> Enum.join(", ")
  end
  
  @doc """
  Adds or updates a parameter in a Via header.

  ## Examples

      iex> via = Parrot.Sip.Headers.Via.new("example.com")
      iex> Parrot.Sip.Headers.Via.with_parameter(via, "received", "192.0.2.1")
      %Parrot.Sip.Headers.Via{parameters: %{"received" => "192.0.2.1"}, ...}
  """
  @spec with_parameter(t(), String.t(), String.t()) :: t()
  def with_parameter(via, name, value) do
    parameters = Map.put(via.parameters, name, value)
    %{via | parameters: parameters}
  end

  @doc """
  Gets a parameter from a Via header.

  ## Examples

      iex> via = Parrot.Sip.Headers.Via.new("example.com", "udp", nil, %{"rport" => "5060"})
      iex> Parrot.Sip.Headers.Via.get_parameter(via, "rport")
      "5060"
  """
  @spec get_parameter(t(), String.t()) :: String.t() | nil
  def get_parameter(via, name) do
    Map.get(via.parameters, name)
  end

  @doc """
  Checks if a parameter exists in the Via header.

  ## Examples

      iex> via = Parrot.Sip.Headers.Via.new("example.com")
      iex> via = Parrot.Sip.Headers.Via.with_parameter(via, "branch", "z9hG4bKabc")
      iex> Parrot.Sip.Headers.Via.has_parameter?(via, "branch")
      true

      iex> Parrot.Sip.Headers.Via.has_parameter?(via, "received")
      false
  """
  @spec has_parameter?(t(), String.t()) :: boolean()
  def has_parameter?(%__MODULE__{parameters: params}, name) do
    Map.has_key?(params, name)
  end

  @doc """
  Gets the branch parameter from a Via header.

  Returns the branch parameter value or nil if not present.

  ## Examples

      iex> via = Parrot.Sip.Headers.Via.new("example.com", "udp", nil, %{"branch" => "z9hG4bKabc"})
      iex> Parrot.Sip.Headers.Via.branch(via)
      "z9hG4bKabc"
  """
  def branch(via) do
    get_parameter(via, "branch")
  end

  @doc """
  Checks if the branch parameter in a Via header is RFC 3261 compliant.

  A branch parameter is RFC 3261 compliant if it starts with the magic cookie "z9hG4bK".

  ## Examples

      iex> via = Parrot.Sip.Headers.Via.new("example.com")
      iex> via = Parrot.Sip.Headers.Via.with_parameter(via, "branch", "z9hG4bKabc123")
      iex> Parrot.Sip.Headers.Via.rfc3261_compliant_branch?(via)
      true

      iex> via = Parrot.Sip.Headers.Via.new("example.com")
      iex> via = Parrot.Sip.Headers.Via.with_parameter(via, "branch", "abc123")
      iex> Parrot.Sip.Headers.Via.rfc3261_compliant_branch?(via)
      false
  """
  @spec rfc3261_compliant_branch?(t()) :: boolean()
  def rfc3261_compliant_branch?(via) do
    case branch(via) do
      nil -> false
      branch -> Branch.is_rfc3261_compliant?(branch)
    end
  end

  @doc """
  Ensures that the branch parameter in a Via header is RFC 3261 compliant.

  If the branch parameter is already compliant, returns the Via header unchanged.
  If not, adds the magic cookie "z9hG4bK" to the beginning of the branch.
  If no branch is present, generates a new one.

  ## Examples

      iex> via = Parrot.Sip.Headers.Via.new("example.com")
      iex> via = Parrot.Sip.Headers.Via.with_parameter(via, "branch", "abc123")
      iex> via = Parrot.Sip.Headers.Via.ensure_rfc3261_branch(via)
      iex> Parrot.Sip.Headers.Via.branch(via)
      "z9hG4bKabc123"
  """
  @spec ensure_rfc3261_branch(t()) :: t()
  def ensure_rfc3261_branch(via) do
    case branch(via) do
      nil ->
        with_parameter(via, "branch", generate_branch())

      branch ->
        with_parameter(via, "branch", Branch.ensure_rfc3261_compliance(branch))
    end
  end

  @doc """
  Gets the received parameter from a Via header.

  ## Examples

      iex> via = Parrot.Sip.Headers.Via.new("example.com", "udp", nil, %{"received" => "203.0.113.1"})
      iex> Parrot.Sip.Headers.Via.received(via)
      "203.0.113.1"
  """
  @spec received(t()) :: String.t() | nil
  def received(via) do
    get_parameter(via, "received")
  end

  @doc """
  Gets the rport parameter from a Via header.

  ## Examples

      iex> via = Parrot.Sip.Headers.Via.new("example.com", "udp", nil, %{"rport" => "5060"})
      iex> Parrot.Sip.Headers.Via.rport(via)
      "5060"
  """
  @spec rport(t()) :: String.t() | nil
  def rport(via) do
    get_parameter(via, "rport")
  end

  @doc """
  Parses a Via header string into a Via struct.

  ## Examples

      iex> Parrot.Sip.Headers.Via.parse("SIP/2.0/UDP server10.biloxi.com:5060;branch=z9hG4bKnashds8")
      %Parrot.Sip.Headers.Via{protocol: "SIP", version: "2.0", transport: :udp, host: "server10.biloxi.com", port: 5060, host_type: :hostname, parameters: %{"branch" => "z9hG4bKnashds8"}}

      iex> Parrot.Sip.Headers.Via.parse("SIP/2.0/UDP [2001:db8::1]:5060;branch=z9hG4bK776asdhds")
      %Parrot.Sip.Headers.Via{protocol: "SIP", version: "2.0", transport: :udp, host: "[2001:db8::1]", port: 5060, host_type: :ipv6, parameters: %{"branch" => "z9hG4bK776asdhds"}}

  """
  @spec parse(String.t()) :: t()
  def parse(string) when is_binary(string) do
    # Split the Via header into the protocol/version/transport part and the rest
    [protocol_transport, rest] = String.split(string, " ", parts: 2)

    # Parse protocol, version, and transport
    [protocol, version, transport_str] = String.split(protocol_transport, "/")

    transport = String.downcase(transport_str) |> String.to_atom()

    # Parse host, port, and parameters
    {host_port, params_str} =
      case String.split(rest, ";", parts: 2) do
        [host_port, params] -> {host_port, params}
        [host_port] -> {host_port, ""}
      end

    # Parse host and port, handling IPv6 addresses
    {host, port} = parse_host_port(host_port)
    host_type = determine_host_type(host)

    # Parse parameters
    parameters =
      if params_str != "" do
        params_str
        |> String.split(";")
        |> Enum.map(fn param ->
          case String.split(param, "=", parts: 2) do
            [name, value] -> {name, value}
            [name] -> {name, ""}
          end
        end)
        |> Enum.into(%{})
      else
        %{}
      end

    %__MODULE__{
      protocol: protocol,
      version: version,
      transport: transport,
      host: host,
      port: port,
      host_type: host_type,
      parameters: parameters
    }
  end

  @spec parse_host_port(String.t()) :: {String.t(), integer() | nil}
  defp parse_host_port(host_port) do
    cond do
      # IPv6 address with port: [2001:db8::1]:5060
      String.contains?(host_port, "]:") ->
        [_, port_str] = String.split(host_port, "]:")
        {port, _} = Integer.parse(port_str)
        # Extract the IPv6 address with brackets
        host = Regex.run(~r/(\[[^\]]+\])/, host_port) |> List.first()
        {host, port}

      # IPv6 address without port: [2001:db8::1]
      String.starts_with?(host_port, "[") && String.ends_with?(host_port, "]") ->
        {host_port, nil}

      # IPv4 address or hostname with port: 192.168.1.1:5060 or example.com:5060
      String.contains?(host_port, ":") ->
        [host, port_str] = String.split(host_port, ":", parts: 2)
        {port, _} = Integer.parse(port_str)
        {host, port}

      # IPv4 address or hostname without port
      true ->
        {host_port, nil}
    end
  end

  @doc """
  Returns the topmost (first) Via header from a SIP message struct.

  ## Examples

      iex> Parrot.Sip.Headers.Via.topmost(message)
      %Parrot.Sip.Headers.Via{host: "host1", ...}
  """
  @spec topmost(map()) :: t() | nil
  def topmost(%{headers: %{"via" => vias}}) when is_list(vias), do: List.first(vias)
  def topmost(%{headers: %{"via" => via}}), do: via
  def topmost(_), do: nil

  @doc """
  Returns a tuple `{topmost, rest}` where `topmost` is the first Via header and `rest` is the remaining Via structs (or nil if only one) from a SIP message struct.

  ## Examples

      iex> Parrot.Sip.Headers.Via.take_topmost(message)
      {%Parrot.Sip.Headers.Via{host: "host1", ...}, [rest...]}

  """
  @spec take_topmost(map()) :: {t(), [t()] | nil} | {t(), nil} | {nil, nil}
  def take_topmost(%{headers: %{"via" => [first | rest]}}),
    do: {first, (rest == [] && nil) || rest}

  def take_topmost(%{headers: %{"via" => via}}) when not is_list(via), do: {via, nil}
  def take_topmost(_), do: {nil, nil}
end
