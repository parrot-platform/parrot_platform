# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [0.0.1-alpha.1] - 2025-08-03

### Added
- Initial alpha release
- Complete SIP protocol stack implementation (RFC 3261)
- `Parrot.SipHandler` behaviour for handling SIP events
- `Parrot.MediaHandler` behaviour for media session callbacks
- RTP audio streaming with PCMA codec support
- gen_statem-based architecture for transactions and dialogs
- Integration with Membrane multimedia libraries for audio processing
- Example application demonstrating handler usage
- Generators for uac and uas
- Documentation and guides
- SIPp integration test suite

### Known Issues
- Alpha release - Lots of changes coming
- Limited to G.711 codecs (Opus support planned)
- No TLS or TCP transport support yet

[0.0.1-alpha.1]: https://github.com/parrot-platform/parrot_platform/releases/tag/v0.0.1-alpha.1
