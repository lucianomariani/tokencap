# TokenCap

> macOS menu bar app that shows your Claude Code usage in real time.

![macOS 14+](https://img.shields.io/badge/macOS-14%2B-blue)
![License: MIT](https://img.shields.io/github/license/helsky-labs/tokencap)
![Release](https://img.shields.io/github/v/release/helsky-labs/tokencap)

<!-- TODO: Add screenshot -->

## What it shows

- **Session usage** — 5-hour rolling window percentage
- **Weekly usage** — 7-day all-models, Sonnet, and Opus breakdown
- **Extra credits** — dollar amount used vs monthly limit
- **Color-coded levels** — green (<50%), yellow (50–80%), red (>80%)

## Install

### Homebrew

```bash
brew install --cask helsky-labs/tap/tokencap
```

### Direct download

Download the latest `.dmg` from [GitHub Releases](https://github.com/helsky-labs/tokencap/releases).

## Requirements

- macOS 14 (Sonoma) or later
- Claude Code with an active session (`claude login`)

## How it works

TokenCap reads your Claude Code OAuth token from `~/.claude/.credentials.json` and polls Anthropic's usage API every 60 seconds. No account creation, no cloud sync, no telemetry.

## Privacy

- Zero analytics or tracking in the app
- Reads only your local credential file
- Makes HTTPS requests only to `api.anthropic.com`
- Stores nothing to disk
- Fully open source — read every line

## Build from source

```bash
git clone https://github.com/helsky-labs/tokencap.git
cd tokencap
swift build -c release
# Binary at .build/release/TokenCap
```

## Known limitations

- Uses an undocumented Anthropic API endpoint — may break if Anthropic changes it
- OAuth token expires and requires re-authentication via Claude Code
- macOS only (native SwiftUI app)

## License

MIT

## Credits

Built by [Helsky Labs](https://helsky-labs.com). Not affiliated with Anthropic.
