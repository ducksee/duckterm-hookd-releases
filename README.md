# duckterm-hookd releases

Long-running daemon bridging Claude Code, Codex, Gemini, OpenCode, and other
coding-agent hooks to the DuckTerm mobile app for push notifications,
approvals, replies, and Live Preview.

Native packages are available for macOS, Windows, Linux, and WSL. Release
archives include the Hookd binary and its bundled local Web UI.

## Install

Install DuckTerm on your phone first. Each quick-start path below installs the
Hookd runtime and bundled Web UI, registers its background service, connects
detected coding agents, and shows one pairing QR code. In DuckTerm, open
**Settings → Agent notifications → Pair by QR** and scan it.

No pair token or account ID needs to be copied into your shell.

### Command model

The similarly named commands operate at different layers:

- The Homebrew, PowerShell, and shell installers place the Hookd runtime and
  bundled Web UI on the machine.
- `duckterm-hookd setup --qr` is guided onboarding and repair: it pairs an
  unpaired machine, reconciles detected agent integrations, starts the managed
  service, and verifies readiness. It is safe to rerun and keeps an existing
  pairing.
- `duckterm-hookd hook install` changes only DuckTerm-owned coding-agent Hook
  entries and wrappers. It does not install the Hookd runtime, pair the machine,
  or manage the service.

### macOS — Homebrew

```sh
brew install ducksee/tap/duckterm-hookd && \
  "$(brew --prefix duckterm-hookd)/bin/duckterm-hookd" setup --qr
```

Supports Apple silicon and Intel. Setup wires detected agents and starts the
Homebrew background service.

### Windows 10 / 11 — native PowerShell

Run in PowerShell 5.1 or newer:

```powershell
irm https://raw.githubusercontent.com/ducksee/duckterm-hookd-releases/main/install.ps1 | iex
```

The installer selects x64 or arm64, verifies the release SHA-256, installs
under `%LOCALAPPDATA%\Programs\duckterm-hookd`, configures the scheduled
background task, and adds `duckterm-hookd` plus the short alias `dhook` to the
user PATH.

Native Windows and WSL are separate hosts. Use this PowerShell installer for
native Windows agents, PowerShell, psmux, and Windows Herdr sessions.

### Linux

```sh
curl -fsSL https://raw.githubusercontent.com/ducksee/duckterm-hookd-releases/main/install.sh \
  | DUCKTERM_PAIR_QR=1 sh
```

The installer selects arm64 or x86_64, verifies the release SHA-256, wires
detected agents, and registers a systemd service.

### Windows Subsystem for Linux

Run this **inside the WSL distribution**, not in PowerShell:

```sh
curl -fsSL https://raw.githubusercontent.com/ducksee/duckterm-hookd-releases/main/install.sh \
  | DUCKTERM_PAIR_QR=1 sh
```

WSL gets its own Linux daemon and host identity. The installer selects the WSL
package and uses systemd when available, with a managed fallback otherwise.

## Verify

```sh
duckterm-hookd status
duckterm-hookd test-push --note "Setup verification"
```

`dhook status` is equivalent on macOS, Windows, and Linux. The status command
checks pairing, service state, cloud connectivity, membership, and installed
agent integrations.

For end-to-end delivery, confirm the test message appears in DuckTerm. Cloud
and APN/FCM delivery is asynchronous.

If a supported coding agent is installed after initial setup, reconcile its
integration without changing pairing or service state:

```sh
duckterm-hookd hook install
```

## LAN Direct and firewalls

Hookd listens on TCP 11434 on all interfaces for authenticated LAN/VPN direct
connections. Do not configure public router port forwarding.

On Windows, setup attempts to add a firewall rule for Private and Domain
networks only. If elevation is required, open PowerShell as Administrator:

```powershell
duckterm-hookd firewall install
duckterm-hookd firewall status
```

## Upgrade

Every official Homebrew, Windows, Linux, and WSL installation can update
through the same ownership-aware command:

```sh
duckterm-hookd update
```

`duckterm-hookd upgrade` is an exact alias. Hookd detects whether the runtime
is Homebrew-owned or an official native install, verifies the matching release,
and restarts the same managed service. Re-running the one-line installer is
only a recovery path for releases too old to provide the native updater.

Upgrade only the independently versioned local Web UI:

```sh
duckterm-hookd ui upgrade
```

## Remove

Choose the scope explicitly:

```sh
# Remove only DuckTerm-owned agent Hooks and wrappers.
duckterm-hookd hook uninstall

# Stop Hookd and remove cloud/account pairing; keep Hooks, settings, and history.
duckterm-hookd unpair --yes

# Remove DuckTerm-owned Hooks, the managed service, and native runtime.
# Local ~/.duckterm data is preserved.
duckterm-hookd service uninstall --yes

# Also delete all local Hookd data.
duckterm-hookd service uninstall --purge --yes
```

`hook uninstall` and `service uninstall` preserve third-party agent Hooks.
For a Homebrew-owned runtime, Homebrew still owns the package files; after the
service cleanup, remove the formula separately:

```sh
brew uninstall duckterm-hookd
```

## Packages

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

Verify manual downloads with the `SHA256SUMS` file attached to each release.

Proprietary software — see the LICENSE inside each package.
