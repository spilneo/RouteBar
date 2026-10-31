<p align="center">
  <img src="docs/logo.png" width="128" height="128" alt="RouteBar logo">
</p>

<h1 align="center">RouteBar</h1>

<p align="center">
  The quiet way to run <a href="https://github.com/diegosouzapw/OmniRoute">OmniRoute</a> on a Mac.<br>
  One endpoint, your subscriptions, every model. Right in the menu bar.
</p>

<p align="center">
  <picture>
    <source media="(prefers-color-scheme: dark)" srcset="docs/panel-dark.png">
    <img src="docs/panel-light.png" width="340" alt="The RouteBar panel">
  </picture>
</p>

## Why

OmniRoute is a powerful AI gateway, and its dashboard shows every one of those powers at once.
Most days you only need four things: the endpoint, a switch, how much you used, and the exact
name of a model. RouteBar puts exactly that in the menu bar and keeps the full dashboard one
click away.

## Install

```sh
brew tap spilneo/tap
brew trust spilneo/tap
brew install --cask routebar
```

Recent Homebrew versions only load casks from third-party taps you trust, which is what the
second line does.

RouteBar needs macOS 14 Sonoma or later. Homebrew also installs Node.js, which OmniRoute runs on.

## First launch

1. Open RouteBar. The three-arrow icon appears in the menu bar.
2. RouteBar starts OmniRoute on `http://localhost:20128`. If `omniroute` is not installed
   globally, it is fetched with `npx`, so the very first start can take a minute or two.
3. Your existing logins are connected for you:
   - **Claude Code**: read from the macOS Keychain item Claude Code created when you signed in.
   - **Codex**: read from `~/.codex/auth.json`.

   This happens automatically, with no clicks and no files to upload. RouteBar only does it for a
   tool you are signed in to and that OmniRoute does not have yet, and it never overwrites a
   connection. Not signed in yet? Run `claude` or `codex login` once, then choose
   **Import Logins Now** from the `⋯` menu.
4. Copy the endpoint and paste it into any OpenAI-compatible app.

```sh
curl http://localhost:20128/v1/models
```

## The panel

| Section       | What it does                                                                                          |
| ------------- | ----------------------------------------------------------------------------------------------------- |
| **Endpoint**  | Shows the base URL with its status. Copy it with one click, or switch the endpoint off and on.        |
| **Usage**     | Tokens and requests for the last 7 or 30 days. Hover a bar to see that day.                           |
| **Providers** | Every connected provider as a tile with its logo. Dimmed tiles have no working connection.            |
| **Models**    | Only the models your active providers serve. Type to search, click a row to copy, or press Return to copy the top match. |
| **`⋯` menu**  | Open at Login, automatic login import, the OmniRoute log, and Quit.                                    |

**Open Dashboard** takes you to the full OmniRoute dashboard for everything else, such as
adding providers, combos, API keys and routing rules.

## How it works

- **Native.** Swift and SwiftUI with Swift Charts. No web view and no bundled runtime.
- **Local only.** RouteBar talks to OmniRoute on `127.0.0.1` and nowhere else.
- **No passwords.** Management calls use OmniRoute's own machine-bound CLI token, derived the
  same way the `omniroute` CLI does it. RouteBar keeps working after you set a dashboard password.
- **Clean shutdown.** Switching the endpoint off asks OmniRoute to exit, whoever started it.
  Quitting RouteBar stops the copy it launched, so no stray `node` process is left behind.
- **Credentials stay put.** Logins are read only to hand them to your local OmniRoute. RouteBar
  never stores, logs or sends them anywhere else.

OmniRoute's output is written to `~/Library/Logs/RouteBar/omniroute.log`.

## Build from source

```sh
swift test               # unit tests
./scripts/build-app.sh   # universal, ad-hoc signed RouteBar.app
open RouteBar.app
```

`./scripts/build-icon.sh` regenerates the app icon from [`logo.svg`](logo.svg) and needs
`rsvg-convert` (`brew install librsvg`).

## Releasing

1. Bump `CFBundleShortVersionString` in [`Resources/Info.plist`](Resources/Info.plist).
2. Push a matching tag, for example `git tag v1.0.1 && git push origin v1.0.1`.

The [Release](.github/workflows/release.yml) workflow tests, builds and publishes `RouteBar.zip`.
The [tap](https://github.com/spilneo/homebrew-tap) picks up the new version on its next scheduled
run. To update it immediately, add a `HOMEBREW_TAP_TOKEN` secret with write access to the tap.
