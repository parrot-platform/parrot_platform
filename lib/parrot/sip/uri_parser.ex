defmodule Parrot.Sip.UriParser do
  @moduledoc """
  Common URI parsing functionality for SIP URIs.

  This module provides core URI parsing functions that can be used across
  different SIP header modules to avoid code duplication.
  """

  @doc """
  Parses a SIP URI string into components.

  Returns `{:ok, map}` with URI components or `{:error, reason}`.

  ## Examples

      iex> Parrot.Sip.UriParser.parse("sip:alice@atlanta.com")
      {:ok, %{scheme: "sip", user: "alice", password: nil, host: "atlanta.com", 
              port: nil, parameters: %{}, headers: %{}}}
      
      iex> Parrot.Sip.UriParser.parse("sip:alice@atlanta.com:5060;transport=tcp?subject=meeting")
      {:ok, %{scheme: "sip", user: "alice", password: nil, host: "atlanta.com", 
              port: 5060, parameters: %{"transport" => "tcp"}, 
              headers: %{"subject" => "meeting"}}}
  """
  @spec parse(String.t()) :: {:ok, map()} | {:error, String.t()}
  def parse(uri_string) when is_binary(uri_string) do
    with [scheme, rest] <- String.split(uri_string, ":", parts: 2),
         true <- valid_scheme?(scheme),
         {:ok, components} <-
           parse_uri_parts(rest, %{
             scheme: scheme,
             parameters: %{},
             headers: %{}
           }) do
      {:ok, components}
    else
      [_] -> {:error, "Invalid scheme or URI format"}
      false -> {:error, "Invalid scheme"}
      {:error, reason} -> {:error, reason}
      _ -> {:error, "Invalid URI format"}
    end
  rescue
    e in ArgumentError -> {:error, e.message}
    e -> {:error, "Error parsing URI: #{inspect(e)}"}
  end

  @doc """
  Parses a SIP URI string and raises an exception if it fails.

  ## Examples

      iex> Parrot.Sip.UriParser.parse!("sip:alice@atlanta.com")
      %{scheme: "sip", user: "alice", password: nil, host: "atlanta.com", 
        port: nil, parameters: %{}, headers: %{}}
  """
  @spec parse!(String.t()) :: map()
  def parse!(uri_string) do
    case parse(uri_string) do
      {:ok, components} -> components
      {:error, reason} -> raise ArgumentError, reason
    end
  rescue
    e in ArgumentError -> raise e
    _ -> raise ArgumentError, "Invalid URI format"
  end

  @doc """
  Extracts parameters from a parameter string.

  ## Examples

      iex> Parrot.Sip.UriParser.extract_parameters("transport=tcp;user=phone")
      %{"transport" => "tcp", "user" => "phone"}
      
      iex> Parrot.Sip.UriParser.extract_parameters("lr")
      %{"lr" => ""}
  """
  @spec extract_parameters(String.t()) :: map()
  def extract_parameters(""), do: %{}

  def extract_parameters(params_str) when is_binary(params_str) do
    params_str
    |> String.split(";")
    |> Enum.map(fn param ->
      case String.split(param, "=", parts: 2) do
        [name, value] -> {name, value}
        [name] -> {name, ""}
      end
    end)
    |> Enum.into(%{})
  end

  @doc """
  Extracts headers from a header string.

  ## Examples

      iex> Parrot.Sip.UriParser.extract_headers("subject=project&priority=urgent")
      %{"subject" => "project", "priority" => "urgent"}
  """
  @spec extract_headers(String.t()) :: map()
  def extract_headers(""), do: %{}

  def extract_headers(headers_str) when is_binary(headers_str) do
    headers_str
    |> String.split("&")
    |> Enum.reduce(%{}, fn header, acc ->
      case String.split(header, "=", parts: 2) do
        [name, value] -> Map.put(acc, name, value)
        [name] -> Map.put(acc, name, "")
      end
    end)
  end

  @doc """
  Determines the host type based on the host string.

  ## Examples

      iex> Parrot.Sip.UriParser.determine_host_type("example.com")
      :hostname
      
      iex> Parrot.Sip.UriParser.determine_host_type("192.168.1.1")
      :ipv4
      
      iex> Parrot.Sip.UriParser.determine_host_type("2001:db8::1")
      :ipv6
  """
  @spec determine_host_type(String.t()) :: :hostname | :ipv4 | :ipv6
  def determine_host_type(host) do
    cond do
      # Check for IPv6 address
      String.contains?(host, ":") &&
          match?({:ok, _}, :inet.parse_ipv6strict_address(String.to_charlist(host))) ->
        :ipv6

      # Check for IPv4 address
      match?({:ok, _}, :inet.parse_ipv4strict_address(String.to_charlist(host))) ->
        :ipv4

      # Default to hostname
      true ->
        :hostname
    end
  end

  @doc """
  Parses an address from a string with the format: `user@host:port`.

  ## Examples

      iex> Parrot.Sip.UriParser.parse_address("alice@atlanta.com:5060")
      {:ok, %{user: "alice", host: "atlanta.com", port: 5060, host_type: :hostname}}
      
      iex> Parrot.Sip.UriParser.parse_address("atlanta.com")
      {:ok, %{user: nil, host: "atlanta.com", port: nil, host_type: :hostname}}
  """
  @spec parse_address(String.t()) :: {:ok, map()} | {:error, String.t()}
  def parse_address(address) when is_binary(address) do
    # Check for user part first
    case String.split(address, "@", parts: 2) do
      [hostport] ->
        parse_hostport(hostport, %{user: nil})

      [userinfo, hostport] when hostport != "" ->
        user_map = parse_userinfo(userinfo)
        parse_hostport(hostport, user_map)

      [_, ""] ->
        {:error, "Invalid host: Host cannot be empty"}
    end
  rescue
    e in ArgumentError -> {:error, e.message}
    e -> {:error, "Error parsing address: #{inspect(e)}"}
  end

  # Private functions

  defp valid_scheme?("sip"), do: true
  defp valid_scheme?("sips"), do: true
  defp valid_scheme?(_), do: false

  defp parse_uri_parts(rest, uri) do
    # Split into userinfo@hostport and params?headers
    {main, rest} = split_uri_main_parts(rest)

    # Parse user and host parts
    case parse_userinfo_hostport(main, uri) do
      {:ok, uri} ->
        # Parse parameters and headers
        uri =
          case rest do
            nil -> uri
            rest -> parse_params_headers(rest, uri)
          end

        {:ok, uri}

      {:error, reason} ->
        {:error, reason}
    end
  rescue
    e in ArgumentError -> {:error, e.message}
    e -> {:error, "Error parsing URI: #{inspect(e)}"}
  end

  defp split_uri_main_parts(str) do
    # First split by semicolon to separate the hostport from parameters
    parts = String.split(str, ";", parts: 2)

    case parts do
      [hostport, rest] ->
        # Check if the rest contains a question mark for headers
        if String.contains?(rest, "?") do
          {hostport, rest}
        else
          {hostport, rest}
        end

      [hostport] ->
        # Check if hostport contains a question mark for headers
        case String.split(hostport, "?", parts: 2) do
          [hostport_only, query] ->
            {hostport_only, "?" <> query}

          [hostport_only] ->
            {hostport_only, nil}
        end
    end
  end

  defp parse_userinfo_hostport(str, uri) do
    # Parse userinfo@hostport
    case String.split(str, "@", parts: 2) do
      [hostport] ->
        case parse_hostport(hostport, %{}) do
          {:ok, host_map} -> {:ok, Map.merge(uri, host_map)}
          {:error, reason} -> {:error, reason}
        end

      [userinfo, hostport] when hostport != "" ->
        user_map = parse_userinfo(userinfo)

        case parse_hostport(hostport, user_map) do
          {:ok, address_map} -> {:ok, Map.merge(uri, address_map)}
          {:error, reason} -> {:error, reason}
        end

      [_, ""] ->
        {:error, "Invalid host: Host cannot be empty"}
    end
  end

  defp parse_userinfo(userinfo) do
    case String.split(userinfo, ":", parts: 2) do
      [user] ->
        %{user: user, password: nil}

      [user, password] ->
        %{user: user, password: password}
    end
  end

  defp parse_hostport(hostport, map) do
    if hostport == "" do
      {:error, "Invalid host: Host cannot be empty"}
    else
      # First, check if this is an IPv6 address in brackets
      if String.starts_with?(hostport, "[") do
        # IPv6 addresses need special handling because they contain colons
        case Regex.run(~r/^\[([^\]]+)\](?::(\d+))?$/, hostport) do
          [_, ipv6_host, port_str] when port_str != "" ->
            # Validate IPv6 address
            case :inet.parse_ipv6strict_address(String.to_charlist(ipv6_host)) do
              {:ok, _} ->
                {port, ""} = Integer.parse(port_str)
                {:ok, Map.merge(map, %{host: ipv6_host, port: port, host_type: :ipv6})}

              {:error, _} ->
                {:error, "Invalid IPv6 address"}
            end

          [_, ipv6_host] ->
            # Validate IPv6 address
            case :inet.parse_ipv6strict_address(String.to_charlist(ipv6_host)) do
              {:ok, _} ->
                {:ok, Map.merge(map, %{host: ipv6_host, port: nil, host_type: :ipv6})}

              {:error, _} ->
                {:error, "Invalid IPv6 address"}
            end

          nil ->
            # Malformed IPv6 address
            {:error, "Invalid IPv6 address"}
        end
      else
        # Regular hostname or IPv4 address
        case String.split(hostport, ":", parts: 2) do
          [host] ->
            if host == "" do
              {:error, "Invalid host: Host cannot be empty"}
            else
              host_type = determine_host_type(host)
              {:ok, Map.merge(map, %{host: host, port: nil, host_type: host_type})}
            end

          [host, port_str] ->
            if host == "" do
              {:error, "Invalid host: Host cannot be empty"}
            else
              host_type = determine_host_type(host)

              try do
                {port, ""} = Integer.parse(port_str)
                {:ok, Map.merge(map, %{host: host, port: port, host_type: host_type})}
              rescue
                _ -> {:error, "Invalid port: #{port_str}"}
              end
            end
        end
      end
    end
  end

  defp parse_params_headers(str, uri) do
    if String.starts_with?(str, "?") do
      # Only headers, no parameters
      parse_headers(String.slice(str, 1..-1//1), uri)
    else
      case String.split(str, "?", parts: 2) do
        [params] ->
          parse_parameters(params, uri)

        [params, headers] ->
          uri = parse_parameters(params, uri)
          parse_headers(headers, uri)
      end
    end
  end

  defp parse_parameters("", uri), do: uri

  defp parse_parameters(params_str, uri) do
    params = extract_parameters(params_str)
    Map.put(uri, :parameters, params)
  end

  defp parse_headers(headers_str, uri) do
    headers = extract_headers(headers_str)
    Map.put(uri, :headers, headers)
  end
end
