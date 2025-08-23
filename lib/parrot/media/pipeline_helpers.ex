defmodule Parrot.Media.PipelineHelpers do
  @moduledoc """
  Common helper functions for media pipelines using pattern matching.
  """

  @doc """
  Parse IP address with pattern matching on different formats.
  """
  def parse_ip(ip) when is_binary(ip) do
    case :inet.parse_address(String.to_charlist(ip)) do
      {:ok, ip_tuple} -> {:ok, ip_tuple}
      {:error, reason} -> {:error, {:invalid_ip_address, ip, reason}}
    end
  end

  def parse_ip({_, _, _, _} = ip), do: validate_ipv4(ip)
  def parse_ip({_, _, _, _, _, _, _, _} = ip), do: validate_ipv6(ip)
  def parse_ip(ip), do: {:error, {:invalid_ip_format, ip}}

  @doc """
  Parse IP address and raise on error.
  """
  def parse_ip!(address) do
    case parse_ip(address) do
      {:ok, ip} ->
        ip

      {:error, reason} ->
        raise ArgumentError, "Invalid IP address: #{inspect(address)}, reason: #{inspect(reason)}"
    end
  end

  @doc """
  Format IP address for display.
  """
  def format_ip(ip) when is_binary(ip), do: ip
  def format_ip({a, b, c, d}), do: "#{a}.#{b}.#{c}.#{d}"

  def format_ip({a, b, c, d, e, f, g, h}),
    do:
      "#{Integer.to_string(a, 16)}:#{Integer.to_string(b, 16)}:" <>
        "#{Integer.to_string(c, 16)}:#{Integer.to_string(d, 16)}:" <>
        "#{Integer.to_string(e, 16)}:#{Integer.to_string(f, 16)}:" <>
        "#{Integer.to_string(g, 16)}:#{Integer.to_string(h, 16)}"

  def format_ip(ip), do: inspect(ip)

  @doc """
  Build UDP endpoint spec based on whether we're sending audio.
  """
  def build_udp_endpoint_spec(opts, has_audio?) when has_audio? do
    Membrane.ChildrenSpec.child(:udp_endpoint, %Membrane.UDP.Endpoint{
      local_port_no: opts.local_rtp_port,
      destination_port_no: opts.remote_rtp_port,
      destination_address: parse_ip!(opts.remote_rtp_address)
    })
  end

  def build_udp_endpoint_spec(opts, _has_audio?) do
    Membrane.ChildrenSpec.child(:udp_endpoint, %Membrane.UDP.Source{
      local_port_no: opts.local_rtp_port
    })
  end

  @doc """
  Check if file should be played.
  """
  def has_audio_file?(%{audio_file: :default_audio}), do: false
  def has_audio_file?(%{audio_file: nil}), do: false
  def has_audio_file?(%{audio_file: _}), do: true
  def has_audio_file?(_), do: false

  # Private helpers

  defp validate_ipv4(ip) do
    ip
    |> Tuple.to_list()
    |> Enum.all?(&(&1 >= 0 and &1 <= 255))
    |> case do
      true -> {:ok, ip}
      false -> {:error, {:invalid_ipv4_tuple, ip}}
    end
  end

  defp validate_ipv6(ip) do
    ip
    |> Tuple.to_list()
    |> Enum.all?(&(&1 >= 0 and &1 <= 65535))
    |> case do
      true -> {:ok, ip}
      false -> {:error, {:invalid_ipv6_tuple, ip}}
    end
  end
end
