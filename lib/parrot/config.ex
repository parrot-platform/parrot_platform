defmodule Parrot.Config do
  @moduledoc """
  Configuration management for Parrot SIP Stack
  """

  require Logger

  def init do
    # Define allowed SIP methods as a simple list
    allowed_methods = [:options, :invite, :ack, :bye, :cancel, :register, :info, :prack, :update]

    Logger.debug("Allowed methods: #{inspect(allowed_methods)}")

    set_allowed_methods(allowed_methods)
    set_uas_options(default_uas_options())
    :ok
  end

  def allowed_methods do
    Application.get_env(:parrot_platform, :allowed_methods, [
      :options,
      :invite,
      :ack,
      :bye,
      :cancel
    ])
  end

  def set_allowed_methods(methods) when is_list(methods) do
    Application.put_env(:parrot_platform, :allowed_methods, methods)
  end

  def uas_options do
    Application.get_env(:parrot_platform, :uas_options, default_uas_options())
  end

  def set_uas_options(uas_options) when is_map(uas_options) do
    Application.put_env(:parrot_platform, :uas_options, uas_options)
  end

  def log_transactions do
    Application.get_env(:parrot_platform, :log_transactions, false)
  end

  defp default_uas_options do
    %{
      check_scheme: &check_scheme/1,
      to_tag: :auto,
      supported: [],
      allowed: allowed_methods(),
      min_se: 90,
      max_forwards: 70
    }
  end

  defp check_scheme("sip"), do: true
  defp check_scheme("sips"), do: true
  defp check_scheme("tel"), do: true
  defp check_scheme(_), do: false
end
