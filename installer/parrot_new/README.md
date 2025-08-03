# Parrot New

Generators for creating new Parrot Platform applications.

## Installation

```bash
mix archive.install hex parrot_new
```

Or from GitHub before Hex publication:

```bash
# Clone the repository
git clone https://github.com/byoungdale/parrot.git
cd parrot/installer/parrot_new
mix archive.build
mix archive.install ./parrot_new-0.0.1-alpha.1.ez
```

## Usage

### Generate a UAC (User Agent Client) application:

```bash
mix parrot.gen.uac my_uac_app
cd my_uac_app
mix deps.get
iex -S mix
```

### Generate a UAS (User Agent Server) application:

```bash
mix parrot.gen.uas my_uas_app
cd my_uas_app
mix deps.get
iex -S mix
```

## Options

Both generators support options:

- `--module` - Specify the module name (default: derived from app name)
- `--no-audio` - Skip audio device support (SIP signaling only)

Example:
```bash
mix parrot.gen.uac my_app --module MyCompany.VoiceApp --no-audio
```

## About

These generators create complete Parrot Platform applications with:

- SIP protocol support (UAC or UAS)
- Optional audio device integration
- G.711 A-law codec support
- Example code and documentation
- Test files

For more information about Parrot Platform, visit: https://github.com/byoungdale/parrot
