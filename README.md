# TokenCap

> macOS menu bar app that shows your Claude Code (and Codex) usage in real time — across multiple accounts.

> A fork of [helsky-labs/tokencap](https://github.com/helsky-labs/tokencap) with significant changes — see [Changes from upstream](#changes-from-upstream).

![macOS 14+](https://img.shields.io/badge/macOS-14%2B-blue)
![License: MIT](https://img.shields.io/github/license/lucianomariani/tokencap)
![Release](https://img.shields.io/github/v/release/lucianomariani/tokencap)

<!-- TODO: Add screenshot -->

## What it shows

- **Multiple accounts** — monitor e.g. a personal and a work account side by side
- **Multiple providers** — Claude Code and OpenAI Codex
- **Session usage** — 5-hour rolling window percentage
- **Weekly usage** — 7-day all-models, Sonnet, and Opus breakdown (Claude)
- **Extra credits** — dollar amount used vs monthly limit
- **Color-coded levels** — green (<50%), yellow (50–80%), red (>80%)

The menu bar shows a compact segment per account (e.g. `Pe 40% · Wo 80%`), colored by the account closest to its limit. Open the popover for the full per-account breakdown.

## Install

### Direct download

Download the latest `.dmg` from [GitHub Releases](https://github.com/lucianomariani/tokencap/releases).

> Note: the upstream Homebrew tap (`helsky-labs/tap/tokencap`) installs the original build, not this fork. A tap for this fork is not yet published.

## Requirements

- macOS 14 (Sonoma) or later
- Claude Code with an active session (`claude login`), and/or the Codex CLI logged in (`codex login`)

## How it works

TokenCap reads each account's OAuth token locally and polls that provider's usage API every 60 seconds. Each account is polled independently. No account creation, no cloud sync, no telemetry.

- **Claude** — reads the OAuth token from `~/.claude/.credentials.json` (or the macOS Keychain, or a custom config directory) and polls Anthropic's usage API.
- **Codex** — reads the OAuth token from `~/.codex/auth.json` and polls the ChatGPT backend usage endpoint.

## Accounts

Manage accounts in **Settings → ACCOUNTS**. Each row has a label, a provider (Claude or Codex), and a credential source (**Auto**, or a specific config directory via **Browse**). Use **+ Add account** to add more.

**Monitoring two Claude accounts at once** (e.g. personal + work): Claude Code stores one set of credentials per machine (`~/.claude/.credentials.json` or one Keychain entry), so logging out/in just swaps them. To watch both simultaneously, give each account its **own config directory** — for example by running each `claude login` with a different `CLAUDE_CONFIG_DIR` — then point each TokenCap account at its directory with **Browse**.

Codex stores its credentials at `~/.codex/auth.json` (one login per machine), so a single Codex account is the typical setup.

> **Note on Codex:** Codex doesn't publish a usage API. TokenCap reads `~/.codex/auth.json` and calls the same backend endpoint the Codex CLI's `/status` command uses. This is reverse-engineered and may break if OpenAI changes it. Codex token refresh is not automatic — if the session expires, re-run `codex login`.

## Optional: hardware dashboard

You can mirror the numbers onto a [LilyGo T-Display-S3](https://www.lilygo.cc/products/t-display-s3) ESP32 board on your LAN — an always-visible desk display. TokenCap stays in charge of OAuth and polling; after each successful poll it POSTs a small JSON payload to the board over HTTP. The board has no Anthropic credentials and never talks to the cloud.

Firmware and flashing live in the companion repo: **[lucianomariani/tokencap-t-display-s3](https://github.com/lucianomariani/tokencap-t-display-s3)**.

### Setup

1. **Flash the firmware** to the board (PlatformIO — see the firmware repo's README).
2. **Connect the board to WiFi.** On first boot the board comes up as a WiFi access point named `tokencap-setup`. Join it from your phone, pick your home SSID, enter the password, save. The board reboots onto your network and advertises itself over mDNS as `tokencap.local`.
3. **Point TokenCap at the board.** Open the menu bar → **Settings → DEVICES**, type `tokencap.local` in the Hostname field, and press **Enter**. The board updates within a couple of seconds. The reachability dot turns green when the board responds; click **Test connection** to verify on demand.

If `tokencap.local` doesn't resolve from your Mac (mDNS is occasionally flaky), use the board's local IP address instead. You can find it in your router's DHCP client list or by watching the board's serial output (`pio device monitor` from the firmware repo) right after WiFi connects. Reserve a static DHCP lease for the board if you want the IP to stick.

### Configure a board (advanced)

`POST /config` accepts either or both of `hostname` and `tz` and reboots the board.

**Rename a board** — useful when running more than one on the same LAN, or just for preferred naming:

```bash
curl -X POST http://tokencap.local/config \
  -H 'Content-Type: application/json' \
  -d '{"hostname":"tokencap-desk"}'
```

The board reboots and comes back as `tokencap-desk.local`.

**Set the timezone** — a fresh board defaults to UTC, so reset labels (`resets in 3h 45m`) render against UTC time. Send a POSIX TZ string to switch to local time:

```bash
# Europe/Rome
curl -X POST http://tokencap.local/config \
  -H 'Content-Type: application/json' \
  -d '{"tz":"CET-1CEST,M3.5.0,M10.5.0/3"}'

# America/New_York
# -d '{"tz":"EST5EDT,M3.2.0,M11.1.0"}'

# America/Los_Angeles
# -d '{"tz":"PST8PDT,M3.2.0,M11.1.0"}'
```

The board uses NTP for absolute time and applies your TZ when rendering. See the [firmware README's Timezone section](https://github.com/lucianomariani/tokencap-t-display-s3#timezone) for more POSIX TZ examples.

### Multiple boards

Add as many devices as you have boards via **Settings → DEVICES → + Add device**. Each row gets its own reachability dot. The Mac pushes to all configured boards in parallel after every poll; a board that's powered off (red dot) doesn't delay updates to the live ones.

## Privacy

- Reads only your local credential file
- Makes HTTPS requests to `api.anthropic.com` (and to your Umami instance, if you configured one — see below)
- If a hardware device is configured, sends the usage payload over plain HTTP to that device on your LAN — no auth, LAN-only by design
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

- Uses undocumented usage endpoints (Anthropic, and the Codex/ChatGPT backend) — may break if either provider changes them
- OAuth tokens expire and require re-authentication via the provider's CLI (`claude login` / `codex login`); Codex tokens are not refreshed automatically
- Two simultaneous Claude accounts require separate config directories (see [Accounts](#accounts))
- The hardware dashboard push uses the Claude wire schema and is fed by your first Claude account
- macOS only (native SwiftUI app)

## Changes from upstream

This fork diverges from [helsky-labs/tokencap](https://github.com/helsky-labs/tokencap) in the following ways:

- **Multiple accounts** — monitor several accounts at once (e.g. personal + work), each polled independently, with a compact multi-segment menu bar. See [Accounts](#accounts).
- **Multiple providers** — adds OpenAI Codex alongside Claude Code (reverse-engineered usage endpoint).
- **Configurable analytics** — the Umami website ID, endpoint, and origin are no longer hardcoded to the upstream instance. They are read from env vars or `Info.plist` keys, and analytics is disabled entirely if unset. See [Tracking app usage (optional)](#tracking-app-usage-optional).
- **Analytics opt-out by default** — `analyticsEnabled` defaults to `false` (upstream defaulted to `true`).
- **Threshold alert sounds** — threshold notifications can play curated audio clips (e.g. Hero quotes) instead of the default system sound.
- **Test-alert UI** — Settings → Notifications now has a grid of buttons to preview the sound for each threshold.
- **Extended default thresholds** — all supported thresholds enabled by default, not just 50/75/80/90.
- **Upstream branding removed** — the Helsky Labs mark and footer link have been removed from the menu UI.
- **Optional hardware dashboard** — push usage data to a LilyGo T-Display-S3 ESP32 board on your LAN. See [Optional: hardware dashboard](#optional-hardware-dashboard).

## License

MIT — see [LICENSE](LICENSE). Copyright is held by Helsky Labs for the original work and by Luciano Mariani for the fork's modifications.

## Credits

Originally built by [Helsky Labs](https://helsky-labs.com). This fork is maintained by Luciano Mariani. Not affiliated with Anthropic or Helsky Labs.
