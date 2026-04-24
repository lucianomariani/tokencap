# TokenCap

> macOS menu bar app that shows your Claude Code usage in real time.

> A fork of [helsky-labs/tokencap](https://github.com/helsky-labs/tokencap) with significant changes — see [Changes from upstream](#changes-from-upstream).

![macOS 14+](https://img.shields.io/badge/macOS-14%2B-blue)
![License: MIT](https://img.shields.io/github/license/lucianomariani/tokencap)
![Release](https://img.shields.io/github/v/release/lucianomariani/tokencap)

<!-- TODO: Add screenshot -->

## What it shows

- **Session usage** — 5-hour rolling window percentage
- **Weekly usage** — 7-day all-models, Sonnet, and Opus breakdown
- **Extra credits** — dollar amount used vs monthly limit
- **Color-coded levels** — green (<50%), yellow (50–80%), red (>80%)

## Install

### Direct download

Download the latest `.dmg` from [GitHub Releases](https://github.com/lucianomariani/tokencap/releases).

> Note: the upstream Homebrew tap (`helsky-labs/tap/tokencap`) installs the original build, not this fork. A tap for this fork is not yet published.

## Requirements

- macOS 14 (Sonoma) or later
- Claude Code with an active session (`claude login`)

## How it works

TokenCap reads your Claude Code OAuth token from `~/.claude/.credentials.json` and polls Anthropic's usage API every 60 seconds. No account creation, no cloud sync, no telemetry.

## Privacy

- Reads only your local credential file
- Makes HTTPS requests to `api.anthropic.com` (and to your Umami instance, if you configured one — see below)
- Stores nothing to disk
- Fully open source — read every line

### Tracking app usage (optional)

TokenCap can send anonymous, privacy-respecting usage events to a self-hosted [Umami](https://umami.is) instance. This is **off by default** and only fires when _both_ of the following are true:

1. Analytics config has been provided at build/run time (see below).
2. The user has opted in via **Settings → General → Share anonymous usage data**.

Nothing is sent otherwise. No tokens, credentials, or PII are ever included in events — just a per-launch session UUID, app version, locale, screen size, and an event name (e.g. `app_launched`, `threshold_alert`, `manual_refresh`). See [`Sources/TokenCap/AnalyticsService.swift`](Sources/TokenCap/AnalyticsService.swift) for the full payload.

#### Configure

Values are resolved in this order: environment variable → `Info.plist` key. Missing any required value disables analytics entirely, regardless of the user toggle.

| Env var                         | `Info.plist` key       | Example                                  |
| ------------------------------- | ---------------------- | ---------------------------------------- |
| `TOKENCAP_ANALYTICS_WEBSITE_ID` | `TCAnalyticsWebsiteID` | `a9b94dba-2442-4c1a-be15-e717a11f9321`   |
| `TOKENCAP_ANALYTICS_ENDPOINT`   | `TCAnalyticsEndpoint`  | `https://analytics.example.com/api/send` |
| `TOKENCAP_ANALYTICS_ORIGIN`     | `TCAnalyticsOrigin`    | `https://tokencap.example.com`           |

For local dev runs:

```bash
TOKENCAP_ANALYTICS_WEBSITE_ID=... \
TOKENCAP_ANALYTICS_ENDPOINT=https://analytics.example.com/api/send \
TOKENCAP_ANALYTICS_ORIGIN=https://tokencap.example.com \
swift run
```

For release builds, add the `TCAnalytics*` keys to [`Info.plist`](Info.plist) so they are baked into the distributed `.app`.

## Build from source

```bash
git clone https://github.com/lucianomariani/tokencap.git
cd tokencap
swift build -c release
# Binary at .build/release/TokenCap
```

## Known limitations

- Uses an undocumented Anthropic API endpoint — may break if Anthropic changes it
- OAuth token expires and requires re-authentication via Claude Code
- macOS only (native SwiftUI app)

## Changes from upstream

This fork diverges from [helsky-labs/tokencap](https://github.com/helsky-labs/tokencap) in the following ways:

- **Configurable analytics** — the Umami website ID, endpoint, and origin are no longer hardcoded to the upstream instance. They are read from env vars or `Info.plist` keys, and analytics is disabled entirely if unset. See [Tracking app usage (optional)](#tracking-app-usage-optional).
- **Analytics opt-out by default** — `analyticsEnabled` defaults to `false` (upstream defaulted to `true`).
- **Threshold alert sounds** — threshold notifications can play curated audio clips (e.g. Hero quotes) instead of the default system sound.
- **Test-alert UI** — Settings → Notifications now has a grid of buttons to preview the sound for each threshold.
- **Extended default thresholds** — all supported thresholds enabled by default, not just 50/75/80/90.
- **Upstream branding removed** — the Helsky Labs mark and footer link have been removed from the menu UI.

## License

MIT — see [LICENSE](LICENSE). Copyright is held by Helsky Labs for the original work and by Luciano Mariani for the fork's modifications.

## Credits

Originally built by [Helsky Labs](https://helsky-labs.com). This fork is maintained by Luciano Mariani. Not affiliated with Anthropic or Helsky Labs.
