# Production Readiness Guide

This guide covers important considerations for deploying Parrot Framework applications in production environments.

## Error Handling

### Network Error Handling

Always handle network operations that may fail:

```elixir
# Good - explicit error handling
defp parse_ip(ip) when is_binary(ip) do
  case :inet.parse_address(String.to_charlist(ip)) do
    {:ok, ip_tuple} ->
      {:ok, ip_tuple}
    {:error, reason} ->
      {:error, {:invalid_ip_address, ip, reason}}
  end
end

# Bad - silent fallback
defp parse_ip(ip) do
  case :inet.parse_address(String.to_charlist(ip)) do
    {:ok, ip_tuple} -> ip_tuple
    _ -> {127, 0, 0, 1}  # Dangerous!
  end
end
```

### Resource Cleanup

Ensure proper cleanup of media pipelines and processes:

```elixir
defp ensure_pipeline_termination(pipeline_pid) when is_pid(pipeline_pid) do
  ref = Process.monitor(pipeline_pid)
  
  case Membrane.Pipeline.terminate(pipeline_pid) do
    :ok ->
      receive do
        {:DOWN, ^ref, :process, ^pipeline_pid, _reason} ->
          :ok
      after
        5_000 ->
          Logger.error("Pipeline #{inspect(pipeline_pid)} failed to terminate gracefully")
          Process.exit(pipeline_pid, :kill)
      end
    error ->
      Process.demonitor(ref, [:flush])
      error
  end
end
```

## Port Management

### RTP Port Allocation

Configure appropriate RTP port ranges and implement proper port allocation:

```elixir
defp allocate_rtp_port(config \\ %{}) do
  min_port = Map.get(config, :min_rtp_port, 16384)
  max_port = Map.get(config, :max_rtp_port, 32768)
  
  case find_available_port(min_port, max_port) do
    {:ok, port} -> {:ok, port}
    {:error, :no_ports_available} -> {:error, :port_exhaustion}
  end
end
```

## Configuration

### Environment-based Configuration

Use a centralized configuration module:

```elixir
defmodule YourApp.Config do
  def sip_config do
    %{
      port: System.get_env("SIP_PORT", "5060") |> String.to_integer(),
      allowed_methods: [:invite, :ack, :bye, :cancel, :options],
      user_agent: "YourApp/1.0",
      max_forwards: 70
    }
  end

  def media_config do
    %{
      rtp_port_range: {16384, 32768},
      default_codec: :pcmu,
      chunk_duration_ms: 20,
      audio_dir: System.get_env("AUDIO_DIR", "./priv/audio")
    }
  end
end
```

### Runtime Configuration

```elixir
# config/runtime.exs
import Config

if config_env() == :prod do
  config :parrot,
    sip_port: System.get_env("SIP_PORT", "5060") |> String.to_integer(),
    rtp_port_min: System.get_env("RTP_PORT_MIN", "16384") |> String.to_integer(),
    rtp_port_max: System.get_env("RTP_PORT_MAX", "32768") |> String.to_integer()
end
```

## Security

### Input Validation

Always validate external inputs:

```elixir
defmodule YourApp.Validators do
  def validate_sip_uri(uri) do
    case Parrot.Sip.Uri.parse(uri) do
      {:ok, %{scheme: scheme}} when scheme in ["sip", "sips"] ->
        :ok
      _ ->
        {:error, :invalid_uri}
    end
  end

  def validate_port(port) when is_integer(port) and port > 0 and port <= 65535 do
    :ok
  end
  def validate_port(_), do: {:error, :invalid_port}
end
```

### Rate Limiting

Implement rate limiting for incoming SIP requests:

```elixir
defmodule YourApp.RateLimiter do
  use GenServer

  def check_rate(ip_address) do
    GenServer.call(__MODULE__, {:check_rate, ip_address})
  end

  def handle_call({:check_rate, ip}, _from, state) do
    case Map.get(state, ip, 0) do
      count when count < 100 ->
        {:reply, :ok, Map.put(state, ip, count + 1)}
      _ ->
        {:reply, {:error, :rate_limited}, state}
    end
  end
end
```

## Monitoring and Observability

### Telemetry Integration

Add telemetry events for monitoring:

```elixir
defmodule YourApp.Telemetry do
  def setup do
    events = [
      [:parrot, :sip, :request, :received],
      [:parrot, :sip, :response, :sent],
      [:parrot, :media, :session, :started],
      [:parrot, :media, :session, :stopped]
    ]

    :telemetry.attach_many(
      "yourapp-telemetry",
      events,
      &handle_event/4,
      nil
    )
  end

  defp handle_event(event, measurements, metadata, _config) do
    # Log or send to monitoring service
    Logger.info("Event: #{inspect(event)}, Measurements: #{inspect(measurements)}")
  end
end
```

### Health Checks

Implement health check endpoints:

```elixir
defmodule YourApp.HealthCheck do
  def check do
    checks = [
      check_sip_transport(),
      check_database(),
      check_media_services()
    ]

    case Enum.filter(checks, &(&1 != :ok)) do
      [] -> {:ok, "All systems operational"}
      errors -> {:error, errors}
    end
  end

  defp check_sip_transport do
    # Check if SIP transport is running
    case Process.whereis(Parrot.Sip.Transport) do
      nil -> {:error, :sip_transport_down}
      _pid -> :ok
    end
  end
end
```

## Performance Optimization

### Binary Handling

Use iolists for efficient binary operations:

```elixir
# Good - uses iolist
def build_message(parts) do
  [
    "SIP/2.0 200 OK\r\n",
    format_headers(headers),
    "\r\n",
    body
  ] |> IO.iodata_to_binary()
end

# Less efficient - multiple concatenations
def build_message(parts) do
  "SIP/2.0 200 OK\r\n" <> format_headers(headers) <> "\r\n" <> body
end
```

### Process Pool Management

For high-concurrency scenarios, use pooling:

```elixir
# In your supervision tree
children = [
  {Parrot.Sip.UAS, port: 5060, handler: YourApp.Handler},
  {:poolboy, [
    name: {:local, :media_pool},
    worker_module: YourApp.MediaWorker,
    size: 10,
    max_overflow: 20
  ]}
]
```

## Deployment

### Docker Deployment

Example Dockerfile:

```dockerfile
FROM elixir:1.15-alpine AS build

RUN apk add --no-cache build-base git

WORKDIR /app

# Install dependencies
COPY mix.exs mix.lock ./
RUN mix do deps.get, deps.compile

# Compile application
COPY . .
RUN mix do compile, release

# Runtime stage
FROM alpine:3.18

RUN apk add --no-cache openssl ncurses-libs

WORKDIR /app

COPY --from=build /app/_build/prod/rel/yourapp ./

EXPOSE 5060/udp 16384-32768/udp

CMD ["bin/yourapp", "start"]
```

### Kubernetes Deployment

Example deployment manifest:

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: parrot-app
spec:
  replicas: 3
  selector:
    matchLabels:
      app: parrot-app
  template:
    metadata:
      labels:
        app: parrot-app
    spec:
      containers:
      - name: parrot-app
        image: yourapp:latest
        ports:
        - containerPort: 5060
          protocol: UDP
        env:
        - name: SIP_PORT
          value: "5060"
        - name: RTP_PORT_MIN
          value: "16384"
        - name: RTP_PORT_MAX
          value: "32768"
        resources:
          requests:
            memory: "256Mi"
            cpu: "250m"
          limits:
            memory: "512Mi"
            cpu: "500m"
```

## Troubleshooting Production Issues

### Debug Logging

Enable selective debug logging in production:

```elixir
# config/prod.exs
config :logger,
  level: :info,
  metadata: [:call_id, :session_id]

# Enable debug for specific modules
config :logger, :console,
  format: "$time $metadata[$level] $message\n",
  metadata: [:call_id, :session_id],
  compile_time_purge_matching: [
    [application: :parrot, level_lower_than: :debug]
  ]
```

### Common Issues

1. **Port Exhaustion**
   - Monitor RTP port usage
   - Implement proper port recycling
   - Configure appropriate port ranges

2. **Memory Leaks**
   - Monitor process counts
   - Implement process timeouts
   - Use `:erlang.garbage_collect/0` strategically

3. **Network Issues**
   - Implement retry logic with backoff
   - Monitor network timeouts
   - Use connection pooling

## Production Checklist

Before deploying to production:

- [ ] Error handling implemented for all external operations
- [ ] Resource cleanup guaranteed (pipelines, processes, ports)
- [ ] Input validation on all external data
- [ ] Rate limiting configured
- [ ] Monitoring and alerting set up
- [ ] Health checks implemented
- [ ] Load testing completed
- [ ] Security audit performed
- [ ] Backup and recovery procedures documented
- [ ] Deployment rollback plan ready