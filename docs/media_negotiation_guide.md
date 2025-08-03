# Media Negotiation Guide

This guide explains the proper way to handle media sessions in Parrot Platform to avoid common pitfalls like RTP port mismatches.

## The Problem

The current implementation has a fundamental issue where:
1. UAC generates a random RTP port and puts it in the INVITE
2. MediaSession is created later with that port number
3. But MediaSession.process_offer allocates a NEW port, ignoring the pre-allocated one
4. Result: The pipeline listens on the wrong port and no audio is heard

## The Solution: MediaSession-First Architecture

### Key Principles

1. **MediaSession owns port allocation** - Never allocate RTP ports outside of MediaSession
2. **Create MediaSession before INVITE** - For UAC, create the session first, then get the SDP
3. **Use consistent flow** - UAC uses generate_offer/process_answer, UAS uses process_offer/start_media

### For UAC (User Agent Client)

```elixir
# Step 1: Create MediaSession FIRST
{:ok, media_session} = MediaSession.start_link(
  id: "unique-session-id",
  role: :uac,
  audio_source: :device,
  audio_sink: :device,
  input_device_id: mic_id,
  output_device_id: speaker_id
)

# Step 2: Generate SDP offer (this allocates the RTP port)
{:ok, sdp_offer} = MediaSession.generate_offer(media_session)

# Step 3: Create and send INVITE with the SDP
invite = create_invite_with_sdp(sdp_offer)
{:uac_id, trans} = UAC.request(invite, callback)

# Step 4: When 200 OK arrives, process the answer
# In your callback:
{:response, %{status_code: 200, body: sdp_answer}} ->
  :ok = MediaSession.process_answer(media_session, sdp_answer)
  :ok = MediaSession.start_media(media_session)
  # Send ACK...
```

### For UAS (User Agent Server)

```elixir
# Step 1: When INVITE arrives, create MediaSession
{:ok, media_session} = MediaSession.start_link(
  id: "unique-session-id", 
  role: :uas,
  audio_source: :device,
  audio_sink: :device
)

# Step 2: Process the offer and generate answer
{:ok, sdp_answer} = MediaSession.process_offer(media_session, invite_sdp)

# Step 3: Send 200 OK with the answer
send_200_ok_with_sdp(sdp_answer)

# Step 4: When ACK arrives, start media
:ok = MediaSession.start_media(media_session)
```

## Using MediaSessionManager

The MediaSessionManager provides a cleaner API that handles the common patterns:

### UAC Example

```elixir
# Prepare session and get SDP in one call
{:ok, session, sdp_offer} = MediaSessionManager.prepare_uac_session(
  id: "call-123",
  audio_source: :device,
  audio_sink: :device,
  input_device_id: 1,
  output_device_id: 2
)

# Send INVITE with sdp_offer...

# When 200 OK arrives:
:ok = MediaSessionManager.complete_uac_setup(session, sdp_answer)
```

### UAS Example

```elixir
# When INVITE arrives:
{:ok, session, sdp_answer} = MediaSessionManager.prepare_uas_session(
  id: "call-456",
  sdp_offer: invite_sdp,
  audio_source: :device,
  audio_sink: :device
)

# Send 200 OK with sdp_answer...

# When ACK arrives:
:ok = MediaSessionManager.complete_uas_setup(session)
```

## Common Mistakes to Avoid

1. **Don't allocate RTP ports manually** - Let MediaSession handle it
2. **Don't call process_offer for UAC** - Use process_answer instead
3. **Don't create MediaSession after sending INVITE** - Create it first
4. **Don't forget to call start_media** - This actually starts the audio flow

## Audio Quality Issues

If audio is "fuzzy", check:
- Sample rate matching (should be 8kHz for G.711)
- Proper resampling from mic input (usually 48kHz) to 8kHz
- Network conditions (packet loss, jitter)
- Audio device configuration

## Migration Guide

To update existing code:

1. Move MediaSession creation before INVITE generation
2. Replace manual port allocation with MediaSession.generate_offer
3. For UAC, replace process_offer with process_answer
4. Consider using MediaSessionManager for cleaner code

## Example Files

- `/examples/uac_with_proper_media.exs` - Correct UAC implementation
- `/lib/parrot/media/media_session_manager.ex` - Helper module for common patterns