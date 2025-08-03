defmodule Parrot.Sip.Transport.Inet do
  @moduledoc """
  Parrot SIP Stack
  Inet-related functions
  """

  @type getifaddrs_ifopts :: [
          {:flags, [:up | :broadcast | :loopback | :pointtopoint | :running | :multicast]}
          | {:addr, :inet.ip_address()}
          | {:netmask, :inet.ip_address()}
          | {:broadaddr, :inet.ip_address()}
          | {:dstaddr, :inet.ip_address()}
          | {:hwaddr, [byte()]}
        ]

  @doc """
  Returns the first non-loopback IP address from the system's network interfaces.
  """
  @spec first_non_loopack_address() :: :inet.ip_address()
  def first_non_loopack_address do
    {:ok, if_addrs} = :inet.getifaddrs()

    candidates =
      if_addrs
      |> Enum.map(fn {_if_name, props} ->
        if not is_loopback(props) and has_address(props) do
          :proplists.get_value(:addr, props)
        end
      end)
      |> Enum.reject(&is_nil/1)
      |> Enum.sort()

    [first | _] = candidates
    first
  end

  @doc """
  return first ipv4 address
  """
  @spec first_ipv4_address() :: :inet.ip_address()
  def first_ipv4_address do
    {:ok, if_addrs} = :inet.getifaddrs()

    candidates =
      if_addrs
      |> Enum.map(fn {_if_name, props} ->
        addr = :proplists.get_value(:addr, props)

        if not is_loopback(props) and has_address(props) and is_ipv4(addr) do
          addr
        end
      end)
      |> Enum.reject(&is_nil/1)
      |> Enum.sort()

    case candidates do
      # Fallback to localhost if no IPv4 address found
      [] -> {127, 0, 0, 1}
      [first | _] -> first
    end
  end

  # Internal implementation

  @spec is_loopback(getifaddrs_ifopts()) :: boolean()
  defp is_loopback(props) do
    flags = :proplists.get_value(:flags, props)
    :loopback in flags
  end

  @spec has_address(getifaddrs_ifopts()) :: boolean()
  defp has_address(props) do
    :proplists.get_value(:addr, props) != :undefined
  end

  @spec is_ipv4(:inet.ip_address() | :undefined) :: boolean()
  defp is_ipv4({a, b, c, d})
       when is_integer(a) and is_integer(b) and is_integer(c) and is_integer(d),
       do: true

  defp is_ipv4(_), do: false
end
