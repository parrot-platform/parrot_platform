---
marp: true
theme: default
paginate: true
backgroundColor: #fff
---

<!-- _class: lead -->

# Putting the "T" back in OTP

## Building Modern Telecom with Elixir

**2025 ClueCon**

---

# Who Am I?

- Started in VoIP and will die in VoIP...jk (maybe)
- This year marks **10 years** since my first ClueCon
- Live and surf in Oceanside, CA
- Wife and 4 kids 

---

# What Does VoIP Development Look Like?

## The Reality Check 

> It is not for the faint of heart

- **Configuration files** 📄

- **SIP protocol knowledge is mixed with DSLs**

- **Scaling challenges**
  - Adding services to handle load (redis, rabbitmq, NATs, etc.)
  - Complex distributed systems
  - State management across nodes

---

**The Good News**: It can be a lot of fun 

**The Problem**: Important logic trapped in different static files, hard to test, harder to extend

---

# What is Erlang/Elixir/OTP?

## Erlang (1986)
- Created at Ericsson for **telecom switches**
- Designed for:
  - **Fault tolerance** - "Let it crash"
  - **Concurrency** - Millions of lightweight processes
  - **Hot code swapping** - Zero downtime updates
  - **Distribution** - Built-in clustering

```erlang
-module(hello).
-export([greet/1]).

greet(Name) ->
    io:format("Hello, ~s!~n", [Name]).
```
```
```
---

# OTP - Open Telecom Platform

## Battle-Tested Telecom Patterns

- Framework for building distributed, fault-tolerant applications
- Supervision trees for self-healing systems
- gen_server, gen_statem behaviors
- Built by for telecom (see: Erlang: The Movie)

---

# Enter Elixir (2011)

## Modern Language, Built on the Erlang VM (BEAM - Bogdan's Erlang Abstract Machine)

- **Ruby-like syntax** on the Erlang VM
- **Metaprogramming** capabilities
- **Pipe operator** for data transformation
- All the power of OTP with modern tooling

```elixir
defmodule Hello do
  @moduledoc """
  A simple greeter module.
  """

  @doc """
  Greets the given name.

  ## Examples

      iex> Hello.greet("Brandon")
      "Hello, Brandon!"

  """
  def greet(name) when is_binary(name) do
    "Hello, #{name}!"
  end
end
```

---

# Why the BEAM for VoIP?

## It Was Literally Built For This

- **Process isolation**: Each transaction, dialog, or media session can run in its own process state machine
- **Supervisors**: Automatic restart strategies
- **gen_server/gen_statem**: Perfect for SIP state machines
- **Pattern matching**: Ideal for protocol parsing and avoiding huge conditionals
- **Distribution**: Built-in node clustering

**Yet modern SIP stacks in BEAM are scarce!** 🤔

Shoutout: https://github.com/poroh/ersip

---

# Real-World Advantages

- **Hot code reloading** - Update routing without dropping calls
- **Distributed systems** - Scale across nodes seamlessly  
- **Observability** - Built-in tracing with OTP
- **Pattern matching** - Express routing logic clearly

---

# Benefits of This Approach

## Why Elixir Shines

1. **Composability**
   ```elixir
   call |> authenticate() |> route() |> bill() |> connect()
   ```

2. **Testability**
   ```elixir
   test "routes emergency calls correctly" do
     call = create_test_call(to: "911")
     assert {:emergency, _} = MyDialplan.route(call)
   end
   ```

3. Modern Tooling
```bash
mix voip.new my_app --sup  # Generate VoIP app                                               
mix voip.gen.handler       # Create handler                                                  
mix test.sipp             # Run SIPp tests
mix dialplan.visualize    # See call flows
```

---

# The Missing Pieces

## 1. Pure Elixir SIP Stack
- No NIFs or ports to C libraries
- Pattern matching for message parsing
- gen_statem for transaction/dialog state machines

## 2. Media Handling
- RTP/RTCP processing
- Codec transcoding
- Media mixing

## 3. Developer-Friendly APIs
- Elixir-idiomatic interfaces
- Composable handlers

---

# The Missing Pieces

## But, what about media!?

---

# What is Membrane?

## The Media Framework We've Been Waiting For

- **Pure Elixir multimedia framework**
- Pipeline-based architecture
- Extensive codec support
- Real-time media processing

```elixir
defmodule AudioPipeline do
  use Membrane.Pipeline
  
  @impl true
  def handle_init(_opts) do
    spec = [
      child(:source, %RTP.Source{port: 5004})
      |> child(:decoder, %Opus.Decoder{})
      |> child(:mixer, %AudioMixer{})
      |> child(:encoder, %Opus.Encoder{})
      |> child(:sink, %RTP.Sink{port: 5006})
    ]
    
    {[spec: spec], %{}}
  end
end
```

---

# Membrane + SIP = 🚀

## Building a Media Softswitch

With Membrane, we can:
- **Handle RTP streams** natively in Elixir
- **Transcode** between codecs on the fly
- **Mix audio** for conference calls
- **Record** calls with ease
- **Integrate** with AI/ML services

All without leaving the BEAM!

---

# What Would a VoIP Framework Look Like?

## Dream Developer Experience

```elixir
defmodule MyVoIPApp do
  use VoIP.Framework
  
  # Pattern match on SIP methods
  handle_invite %{from: "sip:alice@" <> _domain} = invite do
    invite
    |> accept_call()
    |> play_media("welcome.mp3")
    |> bridge_to("sip:support@company.com")
  end
  
  # Pattern match on specific conditions
  handle_invite %{to: "sip:conference@" <> _} = invite do
    invite
    |> accept_call()
    |> join_conference("main-room")
  end
end
```

---

# SIP-Specific Callbacks

## Making the Complex Simple

```elixir
defmodule CallHandler do
  use VoIP.Handler
  
  # Lifecycle callbacks
  def on_call_start(call), do: {:ok, call}
  def on_call_answer(call), do: {:ok, call}
  def on_call_end(call, reason), do: :ok
  
  # SIP events
  def on_reinvite(call, sdp), do: handle_reinvite(call, sdp)
  def on_dtmf(call, digit), do: handle_dtmf(call, digit)
  
  # Media events  
  def on_media_timeout(call), do: hangup(call)
  def on_silence_detected(call, duration), do: {:ok, call}
end
```

---

# Metaprogramming DSL Router

## Dialplan Meets Elixir

```elixir
defmodule MyDialplan do
  use VoIP.Router
  
  # DSL for routing
  route "1XXX" do
    authenticate()
    |> set_caller_id("+1555123XXXX")
    |> dial("sip:provider.com")
  end
  
  route ~r/^011(\d+)$/, to: :international_handler
  
  route "911", priority: :emergency do
    set_location_header()
    |> dial("sip:emergency@psap.gov", timeout: :infinity)
  end
  
  # Pattern matching on number patterns
  route number when number =~ ~r/^\+1/ do
    process_domestic_call(number)
  end
end
```

---

# The Vision - Core Components

- ✅ Pure Elixir SIP stack with gen_statem
- ✅ Media handling via Membrane
- ✅ DSL for routing and dialplans
- ✅ WebRTC support
- ✅ Clustering and distribution

But, is any of this even within grasp?

---

<!-- _class: lead -->

# Demo Time! 🎉

---

# Questions?


