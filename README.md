<p align="center">
  <img src="assets/logo.svg" alt="Parrot Logo" width="200">
</p>

<p align="center">
  <a href="https://github.com/byoungdale/parrot/actions/workflows/ci.yml">
    <img src="https://github.com/byoungdale/parrot/workflows/CI/badge.svg" alt="Build Status">
  </a>
  <a href="https://hex.pm/packages/parrot_platform">
    <img src="https://img.shields.io/hexpm/v/parrot_platform.svg" alt="Hex Version">
  </a>
  <a href="https://hexdocs.pm/parrot_platform">
    <img src="https://img.shields.io/badge/hex-docs-purple.svg" alt="Hex Docs">
  </a>
</p>

# Parrot Platform

> Putting the "T" back in OTP.

Parrot Platform provides Elixir libraries and OTP behaviours for building real-time communication services using SIP and RTP.

## Key Features

- **SIP Protocol Stack**: Full RFC 3261 compliant SIP implementation
- **Handler Pattern**: Flexible callback system for SIP events
  - `Parrot.UasHandler` for UAS (server) applications
  - `Parrot.UacHandler` for UAC (client) applications
- **RTP Audio**: Built-in support for G.711 (PCMA) audio streaming
- **Audio Devices**: System audio device support via PortAudio plugin
- **gen_statem Architecture**: Robust state machine implementation for transactions and dialogs
- **Media Integration**: Audio processing through Membrane multimedia libraries

## Getting started

Get started with the Parrot Platform by follow the instructions at https://hexdocs.pm/parrot_platform/overview.html#quick-start

### Brandon's Notes

Next steps:
- [ ] Add git push hook check for mix format
- [ ] add OPUS support to uas and uac examples and generators
- [ ] better pattern matching in media modules
- [ ] load test
- [x] create Parrot Platform audio file welcome message for basic sample app generator to use
- [x] update Parrot.SipHandler to Parrot.UasHandler
- [x] figure out if Handler adapter is a good way to handle things
- [x] Control Parrot logging levels from the handler behavior
- [x] update docs to show a pattern matching example of INVITE handling
- [x] build basic app generator (mix parrot.gen.uas creates UAS applications)

## License

This project is licensed under the [GNU General Public License v2.0](./LICENSE).
