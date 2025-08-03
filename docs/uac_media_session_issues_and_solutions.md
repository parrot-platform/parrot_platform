# UAC Media Session Issues and Solutions

## Executive Summary

The current `parrot_example_uac` implementation has two critical issues:

1. **Port Mismatch Issue**: The UAC allocates a random RTP port for the SDP offer but creates the MediaSession with a different port, causing the media pipeline to listen on the wrong port.
2. **Audio Quality Issue**: The audio coming through the UAC speaker is "fuzzy", likely due to improper audio processing or configuration.

## Current Implementation Analysis

### The Port Allocation Problem

In `parrot_example_uac.ex` (lines 227-265), the current flow is:

1. UAC generates a random RTP port: `local_rtp_port = 20000 + :rand.uniform(10000)`
2. This port is included in the SDP offer sent in the INVITE
3. Later, when creating the MediaSession (lines 321-330), it passes this port as `local_rtp_port`
4. **However**, `MediaSession.process_offer/2` ignores the pre-allocated port and allocates a new one (lines 684-691 in media_session.ex)
5. Result: The remote party sends RTP to the port advertised in the INVITE, but the pipeline listens on a different port

### The Audio Quality Problem

The fuzzy audio is likely caused by:

1. **Simple Resampler Issues**: The `SimpleResampler` module uses a basic decimation approach (taking every 6th sample) which can introduce aliasing and distortion. This is acknowledged in the code comments as "not a high-quality resampler but works for testing".
2. **Potential Role Confusion**: The UAC creates the MediaSession with `role: :uas` (line 324), which is incorrect and may affect codec negotiation or pipeline configuration.

## Recommended Solutions

### Solution 1: Use MediaSessionManager (Recommended)

The codebase already includes `MediaSessionManager` which implements the correct pattern:

```elixir
defp do_make_call(uri, input_device, output_device, state) do
  # Generate call parameters
  call_id = "uac-#{:rand.uniform(1000000)}@#{get_local_ip()}"
  local_tag = generate_tag()
  dialog_id = "#{call_id}-#{local_tag}"
  
  # Step 1: Create MediaSession FIRST using MediaSessionManager
  case MediaSessionManager.prepare_uac_session(
    id: "uac-media-#{call_id}",
    dialog_id: dialog_id,
    audio_source: :device,
    audio_sink: :device,
    input_device_id: input_device,
    output_device_id: output_device
  ) do
    {:ok, media_session_pid, sdp_offer} ->
      # Step 2: Create INVITE with the SDP from MediaSession
      headers = build_invite_headers(uri, call_id, local_tag)
      invite = Message.new_request(:invite, uri, headers)
      |> Message.set_body(sdp_offer)
      
      # Step 3: Send INVITE
      callback = create_uac_callback(self())
      {:uac_id, transaction} = UAC.request(invite, callback)
      
      # Store session info for later
      new_state = %{state |
        current_call: uri,
        call_id: call_id,
        local_tag: local_tag,
        media_session: media_session_pid
      }
      
      {:ok, new_state}
      
    {:error, reason} ->
      {:error, reason}
  end
end

defp handle_uac_response({:response, %{status_code: 200} = response}, state) do
  # Extract SDP answer
  sdp_answer = response.body
  
  # Complete UAC setup using MediaSessionManager
  case MediaSessionManager.complete_uac_setup(state.media_session, sdp_answer) do
    :ok ->
      # Send ACK
      send_ack(state, response)
      # Update state...
      
    {:error, reason} ->
      Logger.error("Failed to complete media setup: #{inspect(reason)}")
      # Handle error...
  end
end
```

### Audio Quality Improvements

1. **Replace SimpleResampler**: Use a proper resampling library like `membrane_ffmpeg_swresample_plugin` for better audio quality:

```elixir
# In PortAudioPipeline, replace:
child(:resampler, Parrot.Media.SimpleResampler)

# With:
child(:resampler, %Membrane.FFmpeg.SWResample.Converter{
  output_stream_format: %RawAudio{
    sample_format: :s16le,
    sample_rate: 8000,
    channels: 1
  }
})
```

2. **Add Audio Processing**: Consider adding filters for noise reduction or echo cancellation.

3. **Monitor Network Conditions**: Add jitter buffer and packet loss recovery mechanisms.

## Implementation Steps

1. **Fix Port Allocation** (Critical):
   - Modify `do_make_call/4` to create MediaSession first
   - Use `MediaSession.generate_offer/1` for UAC
   - Remove manual RTP port allocation
   - Fix role to `:uac` instead of `:uas`

2. **Fix Audio Quality** (Important):
   - Replace SimpleResampler with a proper resampling library
   - Verify audio device configuration
   - Add logging for audio pipeline metrics

3. **Testing Requirements**:
   - Ensure `mix test test/sipp/test_scenarios.exs` continues to pass
   - Run `mix test` to ensure no regressions
   - Add unit tests for new MediaSession UAC flow

## Key Principles

1. **MediaSession owns port allocation** - Never allocate RTP ports outside of MediaSession
2. **Create MediaSession before INVITE** - For UAC, the session must exist before generating SDP
3. **Use correct roles** - UAC should use `role: :uac`, not `:uas`
4. **Use proper codec flow** - UAC uses `generate_offer/process_answer`, UAS uses `process_offer/start_media`

## Testing Approach

```bash
# Test basic SIP functionality
mix test test/sipp/test_scenarios.exs

# Run all tests
mix test

# Test the examples
# Terminal 1: Start UAS
cd examples/parrot_example_uas
iex -S mix
ParrotExampleUas.start()

# Terminal 2: Start UAC
cd examples/parrot_example_uac
iex -S mix
ParrotExampleUac.start()
ParrotExampleUac.call("sip:service@127.0.0.1:5060")
```

## Terminology Clarification

- **Media Session**: The overall media handling context including SDP negotiation and pipeline management
- **Media Pipeline**: The Membrane pipeline that processes audio (created by MediaSession)
- **Media Stream**: The actual RTP audio flow between endpoints
- **Starting media**: Initiating the pipeline and beginning RTP packet flow

The correct sequence is:
1. Create media session
2. Negotiate SDP (allocates ports, selects codecs)
3. Start media (creates pipeline, begins streaming)
