# Configure logging based on environment variables before starting tests
sip_trace = System.get_env("SIP_TRACE", "false") == "true"

# If SIP trace is enabled, we need to allow info level logs to see the traces
# Otherwise use the configured log level
default_level = if sip_trace, do: "info", else: "warning"
log_level = System.get_env("LOG_LEVEL", default_level) |> String.to_existing_atom()
Logger.configure(level: log_level)

# Also set test configuration
Application.put_env(:parrot, :test_log_level, log_level)
Application.put_env(:parrot, :test_sip_trace, sip_trace)

Code.require_file("support/uas_handler.ex", __DIR__)
Application.ensure_all_started(:parrot)
ExUnit.start()
