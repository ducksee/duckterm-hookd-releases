# duckterm-hookd releases

Long-running daemon bridging Claude Code / Codex / Gemini / OpenCode agent
hooks to the DuckTerm mobile app (push notifications, approvals, live tail).

Static single-file binaries — no runtime dependencies.

## Install

Open **DuckTerm on iPhone → Settings → Agent hooks** and long-press the
install snippet — it copies these commands with your pair token + user id
filled in (on a Mac signed into the same Apple ID, just ⌘V — Universal
Clipboard carries it over):

### Homebrew (macOS / Linux)

`ducksee/tap` is a third-party tap maintained by the DuckTerm authors, not
Homebrew. Install the fully-qualified formula — Homebrew adds the tap
automatically and trusts only this formula:

```sh
brew install ducksee/tap/duckterm-hookd
duckterm-hookd pair --token <pair-token> --user <account-id>
duckterm-hookd install                 # wire agent hooks (non-destructive)
brew services start duckterm-hookd
```

Starting the service before pairing is safe — it waits and retries with
backoff until you pair.

Check version, pairing, and installed-hook state anytime:
```sh
duckterm-hookd status
```

Upgrade (Homebrew won't restart a running service for you):
```sh
brew upgrade duckterm-hookd && brew services restart duckterm-hookd
```

Uninstall (removes only DuckTerm's own hook entries, then the binary):
```sh
duckterm-hookd uninstall && brew services stop duckterm-hookd && brew uninstall duckterm-hookd
```

### One-line install (Linux servers / no Homebrew)

```sh
curl -fsSL https://raw.githubusercontent.com/ducksee/duckterm-hookd-releases/main/install.sh \
  | DUCKTERM_PAIR_TOKEN=<pair-token> DUCKTERM_PAIR_USER=<account-id> sh
```

Downloads the right binary, verifies SHA256, pairs, wires agent hooks, and
registers a supervisor (systemd system unit with root/sudo, else a user unit
with linger; launchd on macOS). Omit the env vars to pair later — the
service self-heals once you run `pair`.

### Manual (any host)

Download the tarball for your platform from the latest release, verify with
`SHA256SUMS`, then:

```sh
tar -xzf duckterm-hookd_<os>-<arch>.tar.gz
./duckterm-hookd pair --token <pair-token> --user <account-id>
./duckterm-hookd install
./duckterm-hookd serve   # or wire your own launchd/systemd unit
```

## Verify

Back in the app: **Settings → Agent hooks → Local push / APN push** — both
should arrive on the phone within seconds.

## Packages

| asset | platform |
|---|---|
| `duckterm-hookd_darwin-arm64.tar.gz` | macOS Apple Silicon |
| `duckterm-hookd_darwin-amd64.tar.gz` | macOS Intel |
| `duckterm-hookd_linux-amd64.tar.gz` | Linux x86_64 (static, UPX) |
| `duckterm-hookd_linux-arm64.tar.gz` | Linux arm64 (static, UPX) |

Proprietary software — see the LICENSE inside each package.
