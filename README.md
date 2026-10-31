<p align="center">
  <img src="docs/logo.png" width="128" height="128" alt="RouteBar logo">
</p>

<h1 align="center">RouteBar</h1>

<p align="center">
  The quiet way to run <a href="https://github.com/cheaper-inference/OmniRoute">OmniRoute</a> on a Mac.<br>
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
brew trust --cask spilneo/tap/routebar && brew install --cask spilneo/tap/routebar
```

Homebrew only loads casks from third-party taps you trust, so the command trusts RouteBar first.

RouteBar needs macOS 14 Sonoma or later. Homebrew also installs Node.js, which OmniRoute runs on.

## First launch

1. Open RouteBar. The three-arrow icon appears in the menu bar.
2. RouteBar starts OmniRoute on `http://localhost:20128`. If `omniroute` is not installed
   globally, it is fetched with `npx`, so the very first start can take a minute or two.
3. Every AI tool you are already signed in to is connected for you. RouteBar runs each
   local-login importer OmniRoute offers and names what it adds from OmniRoute's own provider
   list, so there are no files to upload and nothing to configure. Today that covers:

   | Tool          | Where the login is found                                   |
   | ------------- | ---------------------------------------------------------- |
   | Claude Code   | the macOS Keychain, or `~/.claude/.credentials.json`       |
   | Codex         | `~/.codex/auth.json`                                       |
   | Grok CLI      | `~/.grok/auth.json`                                        |
   | Cursor        | the Cursor app or `cursor-agent`                           |
   | Kiro          | the Kiro app or CLI                                        |
   | Antigravity   | the Antigravity CLI token                                  |
   | CLIProxyAPI   | every account in `~/.cli-proxy-api`                        |
   | Zed           | the macOS Keychain, only when you ask (see below)          |

   Imports never overwrite a connection. Zed keeps its keys in the Keychain behind a macOS
   prompt, so it is only read when you click the import button in the footer, which
   also catches tools you signed in to after launch. OpenCode is not listed because OmniRoute
   has no importer for its logins yet.
4. Copy the endpoint and paste it into any OpenAI-compatible app.

```sh
curl http://localhost:20128/v1/models
```

## The panel

| Section       | What it shows                                                                                         |
| ------------- | ----------------------------------------------------------------------------------------------------- |
| **Header**    | Whether the endpoint is running and how many requests it is serving right now, the OmniRoute version (with a note when an update is out), a button to the full dashboard, and the on/off switch. |
| **Endpoint**  | The base URL for your apps, with a copy button.                                                       |
| **Usage**     | Tokens and requests over 7 or 30 days. Hover a bar to see that day.                                   |
| **Providers** | Each connected provider with its logo and live subscription limits, such as Claude's 5-hour and weekly windows. Meters turn orange at 80% and red at 95%, and show when each window resets. |
| **Models**    | Only the models your active providers serve. The list unfolds when you click into search or start typing. Click a row to copy it, press Return to copy the top match, or Esc to fold it away. |
| **Footer**    | Icon buttons, each explained on hover: import logins now, automatic import, open at login, show the OmniRoute log, and quit. Toggles are tinted when on. |

The full OmniRoute dashboard is one click away for everything else, such as adding providers,
combos, API keys and routing rules.

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
