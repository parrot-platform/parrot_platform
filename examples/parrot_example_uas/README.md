# Parrot Example UAS

This example demonstrates a UAS (User Agent Server) application that answers incoming SIP calls and plays audio files.

## Features

- 📞 **Answers incoming SIP calls** (INVITE)
- 🎵 **Plays audio files** when calls connect
- 🔄 **Handles call lifecycle** (INVITE → ACK → BYE)
- 📊 **Media handler callbacks** for custom media processing
- 🎛️ **Configurable audio** (welcome, menu, music files)

## Installation

1. Navigate to the example directory:
```bash
cd examples/parrot_example_uas
```

2. Get dependencies:
```bash
mix deps.get
```

3. Compile:
```bash
mix compile
```

## Usage

### Basic Usage

Start the UAS in an IEx session:

```elixir
iex -S mix

# Start the UAS on default port 5060
ParrotExampleUas.start()

# Or start on a custom port
ParrotExampleUas.start(port: 5080)
```

Your SIP server is now running and ready to accept calls!

### Testing with SIP Clients

Connect any SIP client (Linphone, Zoiper, MicroSIP, etc.) and call:
- URI: `sip:service@<your-ip>:5060`
- No authentication required

When you call, the UAS will:
1. Answer automatically (200 OK)
2. Play a welcome message
3. Accept BYE to end the call

### Testing with parrot_example_uac

For the best experience, test with the UAC example:

#### Terminal 1 - Start the UAS:
```bash
cd examples/parrot_example_uas
iex -S mix
iex> ParrotExampleUas.start()
```

#### Terminal 2 - Start the UAC and make a call:
```bash
cd examples/parrot_example_uac
iex -S mix
iex> ParrotExampleUac.start()
iex> ParrotExampleUac.call("sip:service@127.0.0.1:5060")
```

## Configuration

### Audio Files

The example uses audio files from the parrot_platform priv directory. To use custom audio:

```elixir
audio_config = %{
  welcome_file: "/path/to/welcome.wav",
  menu_file: "/path/to/menu.wav",
  music_file: "/path/to/music.wav",
  goodbye_file: "/path/to/goodbye.wav"
}
```

Audio files must be:
- WAV format
- 8000 Hz sample rate
- Mono channel
- PCM encoding

### Logging

Control logging verbosity:

```elixir
handler = Parrot.Sip.Handler.new(
  Parrot.Sip.HandlerAdapter.Core,
  {__MODULE__, %{calls: %{}}},
  log_level: :info,      # :debug, :info, :warning, :error
  sip_trace: true        # Show full SIP messages
)
```

## Architecture

The example implements:
- `Parrot.UasHandler` for SIP protocol handling
- `Parrot.MediaHandler` for media session callbacks
- Transaction state callbacks for INVITE processing
- Media playback using Membrane Framework

### Handler Callbacks

#### UasHandler Callbacks
- `handle_invite/2` - Process incoming calls
- `handle_ack/2` - Start media when ACK received
- `handle_bye/2` - Clean up when call ends
- `handle_options/2` - Report capabilities
- `handle_cancel/2` - Cancel pending calls

#### MediaHandler Callbacks
- `handle_session_start/3` - Media session initialized
- `handle_stream_start/3` - Audio stream started
- `handle_play_complete/2` - Audio file finished playing
- `handle_codec_negotiation/3` - Select audio codec
- `handle_stream_error/3` - Handle media errors

## Extending the Example

This example can be extended to:
- Add authentication/registration
- Implement call routing
- Add DTMF detection
- Support video calls
- Record conversations
- Connect to external systems

## Troubleshooting

### Port Already in Use

If you get "address already in use":
```bash
# Find process using port 5060
lsof -i :5060

# Kill the process
kill -9 <PID>
```

### No Audio

If calls connect but no audio plays:
- Check audio file paths exist
- Verify audio format (8000 Hz, mono, WAV)
- Check RTP port range (16384-32768) in firewall

### SIP Client Issues

Common client configuration:
- Username: anything (e.g., "test")
- Domain: your server IP
- Port: 5060 (or custom port)
- Transport: UDP
- No authentication/password

## Code Structure

```
lib/
└── parrot_example_uas.ex
    ├── SIP Handlers         # handle_invite, handle_bye, etc.
    ├── Transaction States   # INVITE state machine callbacks
    ├── Media Handlers       # Audio playback control
    └── Helper Functions     # SDP processing, media setup
```

## License

This example is part of the Parrot Platform and is licensed under the Apache License 2.0.