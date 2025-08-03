import Config

# Configure logging for tests based on environment variables
# Usage:
#   mix test                        # Default: warnings and errors only
#   LOG_LEVEL=debug mix test        # Show debug logs
#   LOG_LEVEL=info mix test         # Show info and above
#   LOG_LEVEL=error mix test        # Errors only (quietest)
#   SIP_TRACE=true mix test         # Show full SIP messages
#   LOG_LEVEL=error SIP_TRACE=true mix test  # Minimal logs but show SIP messages

# Configure default SIP trace setting for tests
sip_trace = System.get_env("SIP_TRACE", "false") == "true"

# If SIP trace is enabled, we need to allow info level logs to see the traces
# Otherwise use the configured log level
default_level = if sip_trace, do: "info", else: "warning"
log_level = System.get_env("LOG_LEVEL", default_level) |> String.to_existing_atom()
config :logger, level: log_level

config :parrot_platform,
  test_sip_trace: sip_trace,
  test_log_level: log_level
