defmodule Parrot.Sip.TestHandler do
  @moduledoc """
  Test handler module for SIP unit tests.

  This module implements the Parrot.Sip.Handler behavior and provides
  simple implementations that can be used in unit tests without requiring
  complex setup.
  """

  @behaviour Parrot.Sip.Handler

  require Logger

  @doc """
  Creates a new test handler.
  """
  def new do
    %Parrot.Sip.Handler{
      module: __MODULE__,
      args: %{},
      log_level: :warning,
      sip_trace: false
    }
  end

  @impl Parrot.Sip.Handler
  def transp_request(_msg, _args) do
    Logger.debug("TestHandler: transp_request called")
    :process_transaction
  end

  @impl Parrot.Sip.Handler
  def transaction(_trans, sip_msg, _args) do
    method = sip_msg.method
    Logger.debug("TestHandler: transaction called for method: #{method}")

    case method do
      :invite -> :process_uas
      :register -> :process_uas
      :bye -> :process_uas
      :cancel -> :ok
      :ack -> :ok
      _ -> :process_uas
    end
  end

  @impl Parrot.Sip.Handler
  def transaction_stop(_trans, reason, _args) do
    Logger.debug("TestHandler: transaction_stop called with reason: #{inspect(reason)}")
    :ok
  end

  @impl Parrot.Sip.Handler
  def uas_request(_uas, sip_msg, _args) do
    method = sip_msg.method
    Logger.debug("TestHandler: uas_request called for method: #{method}")
    :ok
  end

  @impl Parrot.Sip.Handler
  def uas_cancel(_uas_id, _args) do
    Logger.debug("TestHandler: uas_cancel called")
    :ok
  end

  @impl Parrot.Sip.Handler
  def process_ack(_sip_msg, _args) do
    Logger.debug("TestHandler: process_ack called")
    :ok
  end

  @doc """
  Creates a proper Handler struct for use in tests.

  Uses test configuration from environment variables:
  - LOG_LEVEL: Controls log level (default: info)
  - SIP_TRACE: Enables SIP message tracing (default: false)

  ## Examples

      iex> handler = Parrot.Sip.TestHandler.new()
      iex> handler.module
      Parrot.Sip.TestHandler
  """
  def new(args \\ nil, opts \\ []) do
    # Get test configuration from Application env (set in config/test.exs)
    test_log_level = Application.get_env(:parrot_platform, :test_log_level, :warning)
    test_sip_trace = Application.get_env(:parrot_platform, :test_sip_trace, false)

    # Allow overrides from opts
    log_level = Keyword.get(opts, :log_level, test_log_level)
    sip_trace = Keyword.get(opts, :sip_trace, test_sip_trace)

    Parrot.Sip.Handler.new(__MODULE__, args,
      log_level: log_level,
      sip_trace: sip_trace
    )
  end
end
