defmodule Parrot do
  @moduledoc """
  Parrot Platform - Putting the "T" back in OTP.

  Parrot Platform provides Elixir libraries and OTP behaviours for building real-time 
  communication applications. It includes a complete SIP protocol stack implementation 
  with integrated media handling capabilities.

  ## Overview

  Parrot provides two main OTP behaviours for building VoIP applications:

  1. **`Parrot.SipHandler`** - For handling SIP protocol events
  2. **`Parrot.MediaHandler`** - For handling media session events

  ## Quick Start

  Here's a minimal example that handles both SIP and media:

      defmodule MyVoIPApp do
        use Parrot.SipHandler
        @behaviour Parrot.MediaHandler
        
        # Handle incoming calls
        @impl true
        def handle_invite(request, state) do
          # Create media session
          {:ok, _pid} = Parrot.Media.MediaSession.start_link(
            id: "call_123",
            role: :uas,
            media_handler: __MODULE__,
            handler_args: %{welcome_file: "welcome.wav"}
          )
          
          # Accept the call
          {:respond, 200, "OK", %{}, sdp_answer}
        end
        
        # Play audio when media starts
        @impl Parrot.MediaHandler
        def handle_stream_start(session_id, :outbound, state) do
          {{:play, state.welcome_file}, state}
        end
      end

  ## Architecture

  Parrot uses Erlang's `gen_statem` behaviour extensively for managing:

  - **Transactions**: SIP transaction state machines (RFC 3261 compliant)
  - **Dialogs**: SIP dialog lifecycle management
  - **Media Sessions**: RTP audio streaming state management

  ## Features

  - Full SIP protocol stack (RFC 3261)
  - G.711 audio codec support (PCMU/PCMA)
  - RTP/RTCP media streaming
  - Extensible handler pattern
  - Built on Membrane multimedia framework
  - Production-ready supervision trees

  ## Components

  - `Parrot.Sip` - SIP protocol implementation
  - `Parrot.Media` - Media handling and RTP streaming
  - `Parrot.SipHandler` - Behaviour for SIP event callbacks
  - `Parrot.MediaHandler` - Behaviour for media event callbacks

  See the [Getting Started](overview.html) guide or 
  [ParrotExampleApp](https://github.com/source/parrot/examples/parrot_example_uas) 
  for complete examples.
  """
end
