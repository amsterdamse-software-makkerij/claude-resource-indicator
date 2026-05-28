# Claude Resource Indicator

A lightweight macOS menu bar app that shows your Claude subscription usage at a
glance — the same numbers you see on the **Usage** page in Claude's settings,
sitting quietly in your menu bar.

It tracks the three rolling limit windows:

- **Current session** — the 5-hour window
- **Weekly (all models)** — the 7-day window
- **Weekly (Opus)** — the 7-day Opus window (appears once Opus usage is reported)

## What it looks like

- **Menu bar:** thick, monochrome rings — one per active window — that fill
  clockwise as you use up each limit. They're rendered as template images, so
  they stay crisp white-on-dark or black-on-light against any wallpaper.
- **Dropdown (click the icon):** an Apple-Watch-style concentric ring hero plus
  familiar labeled bars with exact percentages and reset countdowns. Bars are
  color-coded green / amber / red as you approach each limit.
- Native menu actions below: **Refresh Now**, **Launch at Login**, and **Quit**.

## How it works

The app reads your existing Claude Code login from the macOS keychain
(`Claude Code-credentials`) and polls Anthropic's usage endpoint
(`GET /api/oauth/usage`) — the same one Claude Code's `/usage` command uses.

- **Read-only:** it never writes to or refreshes the shared credential, so it
  can't interfere with your Claude Code session. When the token is expired it
  simply shows a gentle prompt to open Claude Code.
- **Gentle polling:** refreshes every ~60s and when you open the menu; pauses
  while the display is asleep or you're offline; enforces a 1 request/second
  floor; and backs off exponentially (honoring `Retry-After`) if rate limited.
- **Stays calm:** transient network blips or rate limits keep the last-known
  numbers fully visible and only show a small "Waiting for sync…" note once the
  data is genuinely stale.

> **Unofficial.** This app is not affiliated with Anthropic. It relies on a
> private, undocumented endpoint that may change or break at any time, and reads
> a credential created by Claude Code. Use at your own discretion.

## Requirements

- macOS 13 (Ventura) or later
- [Claude Code](https://claude.com/claude-code) installed and signed in with a
  Pro or Max subscription (the app reads its usage via your existing login)
- To build: Xcode Command Line Tools (or full Xcode), Swift 5.9+

## Build & run

This is a Swift Package; a `Makefile` assembles and ad-hoc-signs the `.app`
bundle. No full Xcode required.

```sh
make run        # build, bundle, and launch
make app        # build the .app into ./build (host architecture)
make install    # build and copy to /Applications
make selftest   # headless check of the data pipeline (keychain -> fetch -> parse)
make clean      # remove build artifacts
```

The app lives in the menu bar only (no Dock icon). Enable **Launch at Login**
from its menu to start it automatically.

## Distributing between machines

`make dist` / `make dmg` produce a **universal** (Intel + Apple Silicon) build:

```sh
make dmg        # -> build/ClaudeResourceIndicator.dmg (drag-to-Applications)
make dist       # -> build/ClaudeResourceIndicator.zip
```

The app is ad-hoc signed, not notarized. If you copy it to another Mac via a
download vector (AirDrop, browser, Mail), Gatekeeper will block the first launch.
Clear the quarantine flag once:

```sh
xattr -dr com.apple.quarantine "/Applications/Claude Resource Indicator.app"
```

(or System Settings → Privacy & Security → **Open Anyway**). Each machine also
needs Claude Code installed and signed in.

## Privacy

Everything stays on your machine. The app only talks to `api.anthropic.com`
using your existing Claude Code token, reads the keychain read-only, and sends
no telemetry.

## Project layout

```
Sources/ClaudeResourceIndicator/
  main.swift              App entry (accessory app)
  AppDelegate.swift       Wires up the status item + model
  StatusItemController.swift  Menu bar item, ring icon, native menu
  RingRenderer.swift      Monochrome menu-bar ring drawing (CoreGraphics)
  MenuContentView.swift   Dropdown UI (watch rings + bars), SwiftUI
  Theme.swift             Colors, thresholds, reset/percent formatting
  AppModel.swift          Polling, backoff, sleep/network handling
  UsageService.swift      Endpoint request + JSON parsing
  Keychain.swift          Reads the Claude Code credential
  Models.swift            Data models and load states
  LoginItem.swift         Launch-at-login via SMAppService
Resources/Info.plist      Bundle metadata (LSUIElement, etc.)
Tools/MakeIcon.swift      Generates the app icon (make icon)
Makefile                  Build / bundle / package targets
```

## License

[MIT](LICENSE)
