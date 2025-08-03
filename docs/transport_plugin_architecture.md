# Parrot SIP Transport Plugin Architecture

## Overview

This document describes a proposed plugin-based architecture for SIP transports in Parrot. The goal is to create a flexible, extensible system similar to Membrane Framework's plugin approach, making it easy to configure and run multiple transport types (UDP, TCP, TLS) simultaneously.

## Current Architecture Problems

The current transport system has several limitations:

1. **Tight Coupling**: The `Transport.StateMachine` directly manages UDP instances
2. **Single Transport**: Can only run one transport type at a time
3. **Complex Connection Module**: The `Parrot.Sip.Connection` module adds unnecessary abstraction
4. **Limited Configurability**: Transport options are scattered and hard to understand
5. **Difficult Extension**: Adding TCP/TLS requires modifying core modules

## Proposed Architecture

### Core Components

#### 1. Transport Plugin Behavior

All transports must implement this behavior:

```elixir
defmodule Parrot.Sip.Transport.Plugin do
  @callback child_spec(opts :: keyword()) :: Supervisor.child_spec()
  @callback start_link(opts :: keyword()) :: GenServer.on_start()
  @callback send_request(request :: map()) :: :ok | {:error, term()}
  @callback send_response(message :: term(), destination :: term()) :: :ok | {:error, term()}
  @callback local_uri() :: {:ok, String.t()} | {:error, term()}
  @callback info() :: map()
  @callback stop() :: :ok
end
```

#### 2. Configuration Structs

Type-safe configuration for each transport type:

```elixir
defmodule Parrot.Sip.Transport.Config do
  defmodule UDP do
    @enforce_keys [:port]
    defstruct [
      :port,           # Required: port number
      :ip,             # Optional: IP to bind to
      :handler,        # SIP handler
      :sip_trace,      # Enable SIP message tracing
      :max_burst,      # Max UDP packets to process at once
      :name,           # Optional name for registry
      options: %{}     # Additional options
    ]
  end

  defmodule TCP do
    @enforce_keys [:port]
    defstruct [
      :port,
      :ip,
      :handler,
      :sip_trace,
      :accept_pool,    # Number of acceptor processes
      :max_connections,# Maximum concurrent connections
      :name,
      options: %{}
    ]
  end

  defmodule TLS do
    @enforce_keys [:port, :certfile, :keyfile]
    defstruct [
      :port,
      :ip,
      :handler,
      :sip_trace,
      :certfile,       # Path to certificate file
      :keyfile,        # Path to private key file
      :accept_pool,
      :max_connections,
      :name,
      options: %{}
    ]
  end
end
```

#### 3. Transport Manager

A supervisor that manages multiple transports:

```elixir
defmodule Parrot.Sip.Transport.Manager do
  use Supervisor
  
  # Start with configuration structs
  def start_link(transports) when is_list(transports)
  
  # Convenience functions
  def start(port: port, handler: handler)  # Simple UDP
  def start(transports, handler: handler)   # Multiple transports
  
  # Runtime management
  def list_transports()
  def find_transport(type, port)
  def find_transport(name)
end
```

#### 4. Via Processing Module

Extracted from Connection module:

```elixir
defmodule Parrot.Sip.ViaProcessor do
  @spec process_request_via(Message.t(), ip, port) :: {:ok, Message.t()} | {:error, term()}
  
  # Adds 'received' parameter and fills 'rport' if present (RFC 3581)
end
```

### Transport Plugin Implementation

Each transport implements the plugin behavior. Here's the UDP example:

```elixir
defmodule Parrot.Sip.Transport.UdpPlugin do
  use GenServer
  @behaviour Parrot.Sip.Transport.Plugin
  @behaviour Parrot.Sip.Transport.Source
  
  # Plugin callbacks
  def child_spec(%Config.UDP{} = config)
  def start_link(%Config.UDP{} = config)
  def send_request(pid \\ __MODULE__, request)
  def send_response(message, destination)
  def local_uri(pid \\ __MODULE__)
  def info(pid \\ __MODULE__)
  def stop(pid \\ __MODULE__)
  
  # Direct message handling without Connection module
  def handle_info({:udp, socket, ip, port, data}, state) do
    case Parrot.Sip.Serializer.decode(data) do
      {:ok, message} ->
        # Create source information directly
        source = %Source{
          local: {state.local_ip, state.local_port},
          remote: {ip, port},
          transport: :udp
        }
        
        # Process Via headers inline
        message = process_message(message, ip, port)
        
        # Handle based on type
        handle_message(message, state.handler)
        
      {:error, reason} ->
        Logger.warning("Bad SIP message: #{reason}")
    end
  end
end
```

### Registry-Based Discovery

Transports register themselves for easy discovery:

```elixir
# Registration (in transport init)
Registry.register(Parrot.Transport.Registry, {:udp, 5060}, self())
Registry.register(Parrot.Transport.Registry, :main_udp, self())

# Lookup
{:ok, pid} = Manager.find_transport(:udp, 5060)
{:ok, pid} = Manager.find_transport(:main_udp)
```

## Usage Examples

### Simple Configuration

```elixir
# Basic UDP transport
handler = Handler.new(MyApp.SipHandler, %{}, log_level: :info, sip_trace: true)
Manager.start(port: 5060, handler: handler)
```

### Multiple Transports

```elixir
# Multiple transports with shared handler
Manager.start([
  {:udp, port: 5060},
  {:tcp, port: 5060, accept_pool: 10},
  {:tls, port: 5061, certfile: "cert.pem", keyfile: "key.pem"}
], handler: handler)
```

### Advanced Configuration

```elixir
# Different handlers per transport with full control
Manager.start_link([
  %Config.UDP{
    port: 5060,
    ip: {0, 0, 0, 0},
    handler: udp_handler,
    name: :main_udp,
    max_burst: 20
  },
  %Config.TCP{
    port: 5060,
    ip: {0, 0, 0, 0},
    handler: tcp_handler,
    name: :main_tcp,
    accept_pool: 100,
    max_connections: 10_000
  },
  %Config.TLS{
    port: 5061,
    ip: {0, 0, 0, 0},
    handler: tls_handler,
    name: :main_tls,
    certfile: "/path/to/cert.pem",
    keyfile: "/path/to/key.pem"
  }
])
```

### Application Integration

```elixir
defmodule MyApp.Application do
  use Application

  def start(_type, _args) do
    children = [
      {Parrot.Sip.Transport.Manager, transports()},
      # Other children...
    ]

    Supervisor.start_link(children, strategy: :one_for_one)
  end

  defp transports do
    handler = Handler.new(MyApp.SipHandler, %{})
    
    [
      %Config.UDP{
        port: Application.get_env(:my_app, :sip_port, 5060),
        handler: handler,
        sip_trace: Application.get_env(:my_app, :sip_trace, false)
      }
    ]
  end
end
```

### Runtime Management

```elixir
# List all active transports
transports = Manager.list_transports()
# => [
#      {{UdpPlugin, 5060, :main_udp}, #PID<0.123.0>, %{type: :udp, port: 5060, ...}},
#      {{TcpPlugin, 5060, :main_tcp}, #PID<0.124.0>, %{type: :tcp, port: 5060, ...}}
#    ]

# Find specific transport
{:ok, udp_pid} = Manager.find_transport(:udp, 5060)
{:ok, tcp_pid} = Manager.find_transport(:main_tcp)

# Get transport info
info = GenServer.call(udp_pid, :info)
# => %{
#      type: :udp,
#      local_ip: {127, 0, 0, 1},
#      local_port: 5060,
#      handler: %Handler{...},
#      sip_trace: true
#    }
```

## Benefits

### For Users

1. **Clear Configuration**: Structured configs instead of nested maps
2. **Easy Setup**: Simple cases are simple, complex cases are possible
3. **Discoverable**: Type-safe structs with documentation
4. **Flexible**: Run multiple transports with different configurations

### For Developers

1. **Extensible**: New transports just implement the Plugin behavior
2. **Testable**: Each transport can be tested in isolation
3. **Maintainable**: Clear separation of concerns
4. **Type-Safe**: Configuration structs catch errors at compile time

### Architecture Benefits

1. **No Connection Module**: Simpler data flow
2. **Plugin Pattern**: Familiar to Membrane users
3. **Supervision**: Proper fault tolerance
4. **Registry-Based**: Easy runtime discovery
5. **Consistent Interface**: All transports work the same way

## Migration Strategy

### Phase 1: Parallel Implementation
1. Implement `UdpPlugin` alongside existing `Transport.Udp`
2. Create `Transport.Manager` as alternative to `Transport.StateMachine`
3. Test new implementation with example apps

### Phase 2: Gradual Migration
1. Update tests to use new Manager API
2. Migrate examples to new configuration style
3. Document migration path for users

### Phase 3: Cleanup
1. Deprecate old transport modules
2. Remove `Connection` module
3. Remove `Transport.StateMachine`

## Implementation Checklist

- [ ] Create `Transport.Plugin` behavior
- [ ] Create `Transport.Config` module with UDP/TCP/TLS structs
- [ ] Extract Via processing to `ViaProcessor`
- [ ] Implement `UdpPlugin` without Connection module
- [ ] Create `Transport.Manager` supervisor
- [ ] Add Registry for transport discovery
- [ ] Create TCP plugin stub
- [ ] Create TLS plugin stub
- [ ] Write comprehensive tests
- [ ] Update documentation
- [ ] Create migration guide

## Future Enhancements

1. **WebSocket Transport**: For WebRTC signaling
2. **SCTP Transport**: For carrier-grade deployments
3. **Transport Metrics**: Built-in monitoring
4. **Connection Pooling**: For TCP/TLS
5. **Load Balancing**: Distribute across transport instances

## Example Transport Plugin Template

For developers creating custom transports:

```elixir
defmodule MyCustomTransport do
  use GenServer
  @behaviour Parrot.Sip.Transport.Plugin
  
  defmodule Config do
    @enforce_keys [:port]
    defstruct [:port, :handler, :custom_option]
  end
  
  # Implement all Plugin callbacks
  def child_spec(%Config{} = config), do: # ...
  def start_link(%Config{} = config), do: # ...
  def send_request(pid, request), do: # ...
  def send_response(message, destination), do: # ...
  def local_uri(pid), do: # ...
  def info(pid), do: # ...
  def stop(pid), do: # ...
  
  # Implement GenServer callbacks
  def init(config), do: # ...
  def handle_call(...), do: # ...
  def handle_info(...), do: # ...
end
```

## Conclusion

This plugin architecture makes Parrot's transport layer:
- More flexible and extensible
- Easier to understand and configure
- Similar to successful patterns like Membrane
- Ready for future transport types
- Simpler by removing unnecessary abstractions

The architecture follows Elixir/OTP best practices while providing a clean, intuitive API for SIP application developers.