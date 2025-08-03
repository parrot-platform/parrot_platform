# Parrot Example UAC with PortAudio

This example demonstrates a UAC (User Agent Client) application that makes outbound SIP calls with bidirectional audio using system microphone and speakers.

## Features

- 🎤 **Microphone Input**: Captures audio from your system microphone
- 🔊 **Speaker Output**: Plays received audio through system speakers
- 📞 **SIP Calling**: Makes outbound calls to any SIP endpoint
- 🔄 **Bidirectional Audio**: Full duplex communication with G.711 codec
- 🎛️ **Device Selection**: Choose specific audio input/output devices
- 📊 **Device Discovery**: List all available audio devices

## Prerequisites

- Elixir 1.14 or later
- PortAudio library installed on your system
- A SIP server to call (like the parrot_example_uas)

### Installing PortAudio

**macOS:**
```bash
brew install portaudio
```

**Ubuntu/Debian:**
```bash
sudo apt-get install portaudio19-dev
```

**Windows:**
Download and install from [PortAudio website](http://www.portaudio.com/)

## Installation

1. Navigate to the example directory:
```bash
cd examples/parrot_example_uac
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

1. Start the UAC in an IEx session:
```elixir
iex -S mix

# Start the UAC application
{:ok, _pid} = ParrotExampleUac.start()

# List available audio devices
ParrotExampleUac.list_audio_devices()

# Make a call to a SIP endpoint
ParrotExampleUac.call("sip:service@127.0.0.1:5060")

# The call will connect and you'll hear/speak through your audio devices
# Press Enter to hang up
```

### Advanced Usage

#### Using Specific Audio Devices

```elixir
# List devices to get their IDs
ParrotExampleUac.list_audio_devices()

# Example output:
# Available Audio Devices:
# ------------------------
# 
# Input Devices:
#   [0] Built-in Microphone (2 channels)
#   [2] USB Headset Microphone (1 channels)
# 
# Output Devices:
#   [1] Built-in Output (2 channels)
#   [3] USB Headset Speakers (2 channels)

# Make a call with specific devices
ParrotExampleUac.call("sip:service@127.0.0.1:5060", 
  input_device: 2,   # USB Headset Microphone
  output_device: 3   # USB Headset Speakers
)
```

#### Starting with Default Devices

```elixir
# Start UAC with specific default devices
{:ok, _pid} = ParrotExampleUac.start(
  input_device: 2,
  output_device: 3
)

# Now all calls will use these devices by default
ParrotExampleUac.call("sip:service@192.168.1.100:5060")
```

### API Functions

- `start(opts \\ [])` - Starts the UAC application
- `call(uri, opts \\ [])` - Makes an outbound call
- `hangup()` - Ends the current call
- `status()` - Gets current call status
- `list_audio_devices()` - Lists all available audio devices

## Testing with parrot_example_uas

The best way to test this UAC is with the UAS example:

### Terminal 1 - Start the UAS:
```bash
cd examples/parrot_example_uas
iex -S mix
iex> ParrotExampleUas.start()
```

### Terminal 2 - Start the UAC and make a call:
```bash
cd examples/parrot_example_uac
iex -S mix
iex> ParrotExampleUac.start()
iex> ParrotExampleUac.call("sip:service@127.0.0.1:5060")
```

You should:
1. See "Ringing..." when the UAS receives the call
2. See "Call connected!" when answered
3. Hear the UAS welcome message through your speakers
4. Be able to speak through your microphone
5. Press Enter to hang up

## Architecture

The example uses:
- `Parrot.Sip.UAC` for low-level SIP operations
- `Parrot.Media.MediaSession` for SDP negotiation
- `Parrot.Media.PortAudioPipeline` for audio device access
- G.711 (PCMU/PCMA) codecs for compatibility

## Troubleshooting

### No Audio Devices Found

If `list_audio_devices()` returns an error:
1. Ensure PortAudio is installed
2. Check audio permissions (especially on macOS)
3. Verify devices are connected and recognized by the OS

### Audio Quality Issues

- Ensure you're using a headset to avoid echo
- Check your microphone levels in system settings
- Use wired connections for better quality
- Select appropriate devices (avoid using laptop speakers with laptop mic)

### Connection Issues

- Verify the SIP server is running and reachable
- Check firewall settings for SIP (5060) and RTP (16384-32768) ports
- Ensure the target URI is correct

## Extending the Example

This example can be extended to:
- Add DTMF support for touch-tone dialing
- Implement call transfer and hold
- Add presence and registration
- Support video calls
- Record conversations
- Add echo cancellation

## Code Structure

```
lib/
└── parrot_example_uac.ex    # Main UAC implementation
    ├── Client API           # Public functions (call, hangup, etc.)
    ├── GenServer callbacks  # State management
    ├── SIP handling        # INVITE, ACK, BYE logic
    ├── Media handling      # Audio device integration
    └── ResponseHandler     # SIP response processing
```

## License

This example is part of the Parrot Platform and is licensed under the Apache License 2.0.