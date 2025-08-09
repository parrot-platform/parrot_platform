---
marp: true
theme: default
paginate: true
backgroundColor: #fff
---

<!-- _class: lead -->

# Putting the "T" back in OTP

## Can we build telecoms with the Erlang Runtime again?

**2025 ClueCon**

---

# Here is the plan...

- Learn about Erlang, Elixir, and the BEAM
- Explore why Elixir is well-suited for modern VoIP systems
- See what an Elixir VoIP development stack could look like 
- Do a demo (*hopefully not too dangerous*)

## How does that sound?

---

# Who Am I?

- Started in VoIP and will die in VoIP...jk (maybe)
- Living and surfing in Oceanside, CA
- Wife and 4 kids 

---

# One more language will fix me...

---

# mod_erlang_event

---
# What is Erlang/Elixir/OTP?

## Erlang (1986)
- Created at Ericsson for **telecom switches**
- Designed for:
  - **Fault tolerance** - "Let it crash"
  - **Concurrency** - Millions of lightweight processes
  - **Hot code swapping** - Zero downtime updates
  - **Distribution** - Built-in clustering

--- 

```erlang
-module(hello).
-export([greet/1]).

greet(Name) ->
    io:format("Hello, ~s!~n", [Name]).
```

---

# Elixir (2011)
- Created by José Valim to modernize Erlang/BEAM development
- Brings to Erlang/BEAM:
  - **Friendly syntax** - Ruby-inspired, readable and expressive
  - **Powerful metaprogramming** - Macros for DSLs and code generation
  - **Mix tool** - Project management, testing, and builds
  - **Phoenix & Nerves** - Robust web and embedded ecosystems
  - **Nx & Bumblebee** - New ML/AI libraries (like Pytorch for Elixir)

---

```elixir
defmodule Hello do
  def greet(name) do
    IO.puts("Hello, #{name}!")
  end
end
```

---

# OTP - Open Telecom Platform

## Battle-Tested Telecom Patterns

- Framework for building distributed, fault-tolerant applications
- Supervision trees for self-healing systems
- gen_server, gen_statem behaviors
- Built by and for telecom (see: Erlang: The Movie)

---

# Concurrency and Distribution Solved Together

```bash
$ iex --sname foo

iex(foo@host)1> pid = spawn(fn ->
...(1)>   receive do
...(1)>     {:ping, from} -> send(from, {:pong, node()})
...(1)>   end
...(1)> end)
#PID<0.108.0>

iex(foo@host)2> :global.register_name(:my_proc, pid)
:yes
```

---

# Concurrency and Distribution Solved Together

```bash
# iex --sname bar

iex(bar@host)1> Node.connect(:'foo@host')
true

iex(bar@host)2> send(:global.whereis_name(:my_proc), {:ping, self()})
{:ping, #PID<0.90.0>}

iex(bar@host)3> receive do
...(3)>   msg -> msg
...(3)> after
...(3)>   1000 -> :timeout
...(3)> end
{:pong, :"foo@host"}
```

---

# Concurrency and Distribution Solved Together

- **The Good**: Whole blocks of problems already solved
- **The Bad**: Can feel like you're bringing a cannon to a gun fight

---

## gen_statem

**gen_statem** is Erlang's state machine behavior that provides:
- State-specific event handling
- Automatic state transitions
- Built-in timers and timeouts

---

# Example flow:

```
Trying → Proceeding → Completed → Confirmed → Terminated
```

Example code
```elixir
def trying(:cast, {:response, %{status: status}}, data) when status < 200 do
  # Probably a 180 or 183
  {:next_state, :proceeding, data}
end

def trying(:cast, {:response, %{status: status}}, data) when status >= 200 do
  {:next_state, :completed, data}
end
```

---

## gen_statem

- **The Good**: Able to handle complex state machines very deterministically
- **The Bad**: Takes getting used to, especially for troubleshooting

---

# So, that's OTP...

## But, what about Elixir?

---
# Why Elixir Shines

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

# Why the Erlang Runtime for VoIP?

## It Was Literally Built For This

- **Process isolation**: Each transaction, dialog, or media session can run in its own process state machine
- **Supervisors**: Automatic restart strategies
- **gen_statem**: Perfect for SIP state machines
- **Pattern matching**: Ideal for protocol parsing and avoiding huge conditionals
- **Distribution and Concurrency**: Solved in the same swing

---

# What we need

## Pure Elixir SIP Stack
- No NIFs or ports to C libraries
- Pattern matching for message parsing
- gen_statem for transaction/dialog state machines

_this part I thought I could figure out_

---

# What we also need

## Pure Elixir Media Stack

_this part I knew I could NOT figure out_

---

# Membrane

https://membrane.stream

> built by Software Mansion

- Elixir multimedia framework
- Pipeline-based architecture
- Extensive codec support
- Real-time media processing

---

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

With Membrane, we can:
- **Handle RTP streams** natively in Elixir
- **Transcode** between codecs on the fly
- **Mix audio** for conference calls
- **Record** calls with ease
- **Integrate** with AI/ML services

All without leaving the the Erlang Runtime!

---

# What Would a VoIP Framework Look Like?

---

```elixir
defmodule MyVoIPApp do
  use VoIP.Framework
  
  handle_invite %{from: "sip:alice@" <> _domain} = invite do
    invite
    |> accept_call()
    |> play_media("welcome.mp3")
    |> bridge_to("sip:support@company.com")
    |> fork_media("wss://ai-service.com", %{customer_name: "alice"})
  end
  
  handle_invite %{to: "sip:conference@" <> _} = invite do
    invite
    |> accept_call()
    |> join_conference("main-room")
  end
end
```

---

# What is currently possible...

---

#### SIP Callbacks

```elixir
  defmodule MyCallHandler do
    use Parrot.UasHandler  # For receiving calls (User Agent Server)

    def handle_transaction_invite_trying(_request, _transaction, _state) do
      Logger.info("[VoipServer] INVITE transaction: trying")
      :noreply
    end

    def handle_transaction_invite_proceeding(request, _transaction, state) do
      Logger.info("[VoipServer] INVITE transaction: proceeding")
      :noreply
    end
    
    # SIP Protocol Callbacks
    def handle_invite(request, state) do
      # Process incoming call
      {:ok, sdp_answer} = MediaSession.process_offer(request.body)
      {:respond, 200, "OK", %{}, sdp_answer}
    end

    def handle_ack(request, state) do
      # Now you'll want to start media session
    end

    def handle_bye(request, state) do
      # Call termination
      {:respond, response(200, "OK"), state}
    end

    def handle_cancel(request, state) do
      # Cancel pending INVITE
      {:respond, response(200, "OK"), state}
    end

    def handle_option(request, state) do
      {:response, 200, "OK", %{}, ""}
    end

    def handle_info(request, state) do
      # In-dialog INFO (DTMF, etc)
      {:respond, response(200, "OK"), state}
    end
  end
```

---

#### Media Callbacks

```elixir
defmodule MyMediaHandler do
  use Parrot.MediaHandler

  # Core lifecycle callbacks
  def handle_session_start(session_id, _opts, state) do
    {:ok, Map.put(state, :session_id, session_id)}
  end

  def handle_stream_start(session_id, _direction, state) do
    # Start playing welcome message
    {{:play, "welcome.wav"}, %{state | playing: :welcome}}
  end

  # SDP negotiation
  def handle_codec_negotiation(offered, supported, state) do
    # Select best codec (prefer opus > pcmu > pcma)
    codec = Enum.find([:opus, :pcmu, :pcma], & &1 in offered and &1 in supported)
    {:ok, codec, state}
  end

  # Playback control
  def handle_play_complete("welcome.wav", state) do
    # Play next file or stop
    {{:play, "menu.wav"}, %{state | playing: :menu}}
  end

  def handle_play_complete("menu.wav", state) do
    {:stop, %{state | playing: :done}}
  end
end
```

---

# Demo Time! 🎉

https://github.com/parrot-platform/parrot_platform

---

# What's the status of parrot_platform?

- it's very new
- the ergonomics still need work
- but, it's been a lot of fun so far

---
# Questions?


