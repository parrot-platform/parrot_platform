defmodule Parrot.Sip.Dns.Resolver do
  require Logger

  @doc """
  Resolves a SIP URI host to IP address and port using DNS SRV records.
  Falls back to A record lookup if SRV lookup fails.
  """
  def resolve(host, transport \\ :udp) when is_binary(host) do
    # Convert host to charlist for erlang DNS functions
    host_charlist = String.to_charlist(host)

    # Try SRV lookup first
    case srv_lookup(host_charlist, transport) do
      {:ok, {ip, port}} ->
        {:ok, {ip, port}}

      {:error, _reason} ->
        # Fallback to A record lookup
        case a_record_lookup(host_charlist) do
          {:ok, ip} -> {:ok, {ip, default_port(transport)}}
          {:error, _} = error -> error
        end
    end
  end

  @doc """
  Performs SRV record lookup for SIP services.
  """
  def srv_lookup(host, transport) do
    service = service_prefix(transport)
    srv_record = ~c"_sip._#{service}.#{host}"

    case :inet_res.lookup(srv_record, :in, :srv) do
      [] ->
        {:error, :no_srv_record}

      records when is_list(records) ->
        # Sort by priority and weight
        sorted_records = sort_srv_records(records)

        case select_record(sorted_records) do
          {_priority, _weight, port, target} ->
            case a_record_lookup(target) do
              {:ok, ip} -> {:ok, {ip, port}}
              error -> error
            end

          nil ->
            {:error, :no_valid_srv_record}
        end
    end
  end

  @doc """
  Performs A record lookup.
  """
  def a_record_lookup(host) do
    case :inet_res.lookup(host, :in, :a) do
      [] -> {:error, :no_a_record}
      [ip | _rest] -> {:ok, ip}
    end
  end

  # Private functions

  defp service_prefix(:udp), do: "udp"
  defp service_prefix(:tcp), do: "tcp"
  defp service_prefix(:tls), do: "tls"

  defp default_port(:udp), do: 5060
  defp default_port(:tcp), do: 5060
  defp default_port(:tls), do: 5061

  defp sort_srv_records(records) do
    Enum.sort(records, fn {priority1, weight1, _, _}, {priority2, weight2, _, _} ->
      cond do
        priority1 < priority2 -> true
        priority1 > priority2 -> false
        weight1 >= weight2 -> true
        true -> false
      end
    end)
  end

  defp select_record([]), do: nil
  defp select_record([record | _]), do: record
end
