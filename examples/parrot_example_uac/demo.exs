#!/usr/bin/env elixir

# Demo script for ParrotExampleUac
# 
# This script demonstrates making a call with audio devices.
# Make sure parrot_example_uas is running on port 5060 first!

IO.puts("""
🦜 Parrot Example UAC Demo
========================

This demo will:
1. List available audio devices
2. Start the UAC
3. Make a call to the local UAS
4. Use your microphone and speakers for bidirectional audio

Make sure parrot_example_uas is running first!
Press Enter to continue...
""")

IO.gets("")

# Start the UAC
{:ok, _pid} = ParrotExampleUac.start()

# List audio devices
IO.puts("\n📱 Available Audio Devices:")
ParrotExampleUac.list_audio_devices()

IO.puts("\nPress Enter to make a call to sip:service@127.0.0.1:5060")
IO.gets("")

# Make the call
case ParrotExampleUac.call("sip:service@127.0.0.1:5060") do
  :ok ->
    IO.puts("\n🎤 Call in progress...")
    IO.puts("You can speak into your microphone and hear audio through your speakers.")
    IO.puts("\nThe call will automatically hang up when you press Enter in the call window.")
    
  {:error, reason} ->
    IO.puts("\n❌ Failed to make call: #{inspect(reason)}")
end

# Keep the script running
IO.puts("\nPress Ctrl+C to exit the demo")
:timer.sleep(:infinity)