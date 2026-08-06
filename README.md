<p align="center">
  <img src="./assets/duckterm-mark.svg" width="72" height="72" alt="DuckTerm">
</p>

<h1 align="center">DuckTerm Hookd</h1>

<p align="center">
  <strong>Keep coding agents on your computers. Stay with them from your phone.</strong>
</p>

<p align="center">
  English · <a href="./README.zh-CN.md">简体中文</a>
</p>

<p align="center">
  <a href="https://github.com/ducksee/duckterm-hookd-releases/releases/latest"><img alt="Latest release" src="https://img.shields.io/github/v/release/ducksee/duckterm-hookd-releases?display_name=tag&style=flat-square"></a>
  <img alt="macOS" src="https://img.shields.io/badge/macOS-Apple%20silicon%20%7C%20Intel-111827?style=flat-square&logo=apple">
  <img alt="Windows" src="https://img.shields.io/badge/Windows-x64%20%7C%20arm64-0078D4?style=flat-square&logo=windows11&logoColor=white">
  <img alt="Linux and WSL" src="https://img.shields.io/badge/Linux%20%7C%20WSL-x64%20%7C%20arm64-FCC624?style=flat-square&logo=linux&logoColor=111827">
</p>

Hookd is the small companion service that connects coding agents on your
computers to DuckTerm on iPhone, iPad, and Android. Your agent and terminal keep
running where they already are; DuckTerm becomes the mobile control surface for
notifications, approvals, replies, and Live Preview.

It is built for people who leave long-running agents on a workstation, server,
or Windows machine and do not want to keep watching every terminal. Hookd does
not move the agent into a hosted shell, and it is not a public terminal gateway.

## Start with the mobile app

Install DuckTerm on the phone or tablet you want to carry. Both apps connect to
the same Hookd service and support the same pairing flow.

<p align="center">
  <a href="https://apps.apple.com/app/id6766765739"><img src="./assets/app-store-badge.svg" height="56" alt="Download DuckTerm on the App Store"></a>
  &nbsp;&nbsp;
  <a href="https://play.google.com/store/apps/details?id=com.duck.term.android"><img src="./assets/google-play-badge.svg" height="56" alt="Get DuckTerm on Google Play"></a>
</p>

Then open **Settings → Agent notifications → Pair by QR**. Leave that screen
open while you install Hookd on the computer.

## Three steps, one working loop

1. **Install DuckTerm** on iOS/iPadOS or Android.
2. **Install Hookd** on each computer that runs your coding agents.
3. Run guided setup, scan its QR code, and tap **Verify** in the app.

```text
Coding agents + tmux / psmux / Herdr
                  │
                  ▼
        Hookd on your computer
          ├── authenticated LAN Direct when reachable
          ├── secure relay for push and remote delivery
          └── local Web control center
                  │
                  ▼
       DuckTerm on iOS / iPadOS / Android
```

After pairing, a normal loop looks like this: start work at your desk, leave the
agent running, receive the result or approval request on your phone, inspect the
live terminal when context matters, and reply without rebuilding the session.

## What you get

- **Agent Inbox and notifications** when a turn finishes, fails, or needs you.
- **Approvals and replies** from the phone for agents that expose those hooks.
- **Live Preview** of the exact terminal behind a conversation when its pane can
  be proven safely.
- **Image and text handoff** to supported agent TUIs without turning the phone
  into a separate chat session.
- **Multi-host continuity** across a Mac, Windows workstation, Linux server, and
  WSL distributions under one DuckTerm account.
- **A local control center** for health, integrations, rules, history, and
  upgrades at `http://127.0.0.1:20080` by default.

## Supported environments

| host | architectures | managed service |
|---|---|---|
| macOS | Apple silicon, Intel | Homebrew services or launchd |
| Windows 10 / 11 | x64, arm64 | hidden Task Scheduler task |
| Linux | x86_64, arm64 | systemd |
| WSL1 / WSL2 | x86_64, arm64 | systemd or managed fallback |

Hookd currently recognizes 12 coding-agent integrations: **Claude Code,
Codex, OpenCode, Cursor, Droid, Qoder, Amp, Gemini, Antigravity, Grok Build,
Pi, and Devin**. It also understands persistent terminal contexts from
**tmux, psmux, and Herdr**.

Upstream agents expose different hook contracts. Hookd enables only the events
and actions each agent actually supports, so notification, approval, reply, and
preview coverage can differ by agent version.

## Install Hookd

### macOS — Homebrew (recommended)

```sh
brew install ducksee/tap/duckterm-hookd && \
  "$(brew --prefix duckterm-hookd)/bin/duckterm-hookd" setup --qr
```

Homebrew owns both the package and its background service. Setup detects
installed agents, preserves their existing third-party hooks, starts Hookd, and
shows the pairing QR. It is safe to run again as a repair command.

Without Homebrew, use the Linux/macOS direct installer below.

### Windows 10 / 11 — native PowerShell

Run in PowerShell 5.1 or newer:

```powershell
irm https://raw.githubusercontent.com/ducksee/duckterm-hookd-releases/main/install.ps1 | iex
```

The installer selects x64 or arm64, verifies SHA-256, installs the bundled Web
UI, registers a hidden background task, adds `duckterm-hookd` and `dhook` to the
user `PATH`, and starts QR pairing. Use this native installer for PowerShell,
psmux, Windows Herdr, and native Windows agents.

### Linux

```sh
curl -fsSL https://raw.githubusercontent.com/ducksee/duckterm-hookd-releases/main/install.sh \
  | DUCKTERM_PAIR_QR=1 sh
```

The installer selects x86_64 or arm64, verifies SHA-256, installs the bundled
Web UI, connects detected agents, and registers a systemd service.

### Windows Subsystem for Linux

Run this **inside the WSL distribution**, not in PowerShell:

```sh
curl -fsSL https://raw.githubusercontent.com/ducksee/duckterm-hookd-releases/main/install.sh \
  | DUCKTERM_PAIR_QR=1 sh
```

Native Windows and WSL are separate hosts. A WSL install gets its own identity,
ports, agent integrations, and service. systemd is used when available; WSL1
uses a managed fallback that survives Windows sign-in.

## Verify the connection

```sh
duckterm-hookd status
duckterm-hookd test-push --note "Setup verification"
```

`status` checks pairing, service ownership, cloud connectivity, account
membership, and detected integrations. `dhook status` is the short equivalent
on supported installs. The test push is asynchronous; confirm it arrives in
the DuckTerm Agent Inbox.

If you install another coding agent later, reconnect integrations without
changing the account or service:

```sh
duckterm-hookd hook install
```

## Everyday commands

| command | purpose |
|---|---|
| `duckterm-hookd setup --qr` | pair or repair the host, reconcile agents, start the service, and verify it |
| `duckterm-hookd status [--verbose]` | inspect account, service, cloud, LAN, and integration health |
| `duckterm-hookd test-push --note "…"` | send an end-to-end notification check |
| `duckterm-hookd hook install` | reconnect DuckTerm-owned entries for all detected agents |
| `duckterm-hookd update` | verify and install the latest release, preserving the current owner and configuration |
| `duckterm-hookd ui upgrade` | update only the independently versioned local Web UI |
| `duckterm-hookd firewall status` | inspect LAN Direct listener and firewall readiness |

`upgrade` is an exact alias of `update`.

## Local first, remote when needed

Hookd prefers authenticated LAN Direct when the phone can reach the computer.
Away from that network, the persistent secure connection keeps notifications,
approvals, and replies available. The Web control center stays local-only unless
you explicitly enable LAN access.

```sh
duckterm-hookd config --lan --reload    # trusted LAN / VPN only
duckterm-hookd config --local --reload  # restore localhost-only Web access
```

LAN Direct uses TCP `11434` by default. Do not expose it or the Web control
center through public router port forwarding. On Windows or a restrictive
Linux firewall, inspect the exact rule and listener before changing anything:

```sh
duckterm-hookd firewall status
```

## Privacy and coexistence

- Agent processes, repositories, and terminal sessions stay on your computers.
- Pairing authority and local settings are stored under `~/.duckterm` with
  private file permissions where the platform supports them.
- Hookd marks every integration entry it owns. Setup and uninstall preserve
  unrelated Claude, Codex, and third-party hooks.
- Live Preview and interactive input require an identified agent session and a
  valid terminal target; Hookd fails closed rather than guessing a pane.
- The local Web UI listens on `127.0.0.1:20080` by default.

## Upgrade and remove

Update any official Homebrew, Windows, Linux, or WSL installation with:

```sh
duckterm-hookd update
```

Choose removal scope deliberately:

```sh
duckterm-hookd hook uninstall             # remove only DuckTerm-owned agent hooks
duckterm-hookd unpair --yes               # remove account/host pairing, keep local data
duckterm-hookd service uninstall --yes    # remove hooks, service, and native runtime
duckterm-hookd service uninstall --purge --yes  # also delete Hookd local data
```

For a Homebrew-owned package, run `brew uninstall duckterm-hookd` after service
cleanup when you also want Homebrew to remove the files.

<details>
<summary><strong>Release packages and manual verification</strong></summary>

| asset | platform |
|---|---|
| `duckterm-hookd_darwin-arm64.tar.gz` | macOS Apple silicon |
| `duckterm-hookd_darwin-amd64.tar.gz` | macOS Intel |
| `duckterm-hookd_windows-amd64.zip` | Windows x64 |
| `duckterm-hookd_windows-arm64.zip` | Windows arm64 |
| `duckterm-hookd_linux-amd64.tar.gz` | Linux x86_64 |
| `duckterm-hookd_linux-arm64.tar.gz` | Linux arm64 |
| `duckterm-hookd_linux-amd64-wsl.tar.gz` | WSL x86_64 |
| `duckterm-hookd_linux-arm64-wsl.tar.gz` | WSL arm64 |

Verify manual downloads against the `SHA256SUMS` attached to every release.

</details>

Official release packages are proprietary software; see the `LICENSE` inside
each package.
