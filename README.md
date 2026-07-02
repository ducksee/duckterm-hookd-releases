# duckterm-hookd releases

Long-running daemon bridging Claude Code / Codex agent hooks to the DuckTerm
mobile app (push notifications, approvals, live tail).

Static single-file binaries — no runtime dependencies.

## Install

### Homebrew (macOS / Linux)

```sh
brew install ducksee/tap/duckterm-hookd
duckterm-hookd pair --token <pairing-token>   # from the DuckTerm app
duckterm-hookd install                        # wire agent hooks (non-destructive)
brew services start duckterm-hookd
```

### Manual (any host)

Download the tarball for your platform from the latest release, verify with
`SHA256SUMS`, then:

```sh
tar -xzf duckterm-hookd_<os>-<arch>.tar.gz
./duckterm-hookd pair --token <pairing-token>
./duckterm-hookd install
./duckterm-hookd serve   # or wire your own launchd/systemd unit
```

## Packages

| asset | platform |
|---|---|
| `duckterm-hookd_darwin-arm64.tar.gz` | macOS Apple Silicon |
| `duckterm-hookd_darwin-amd64.tar.gz` | macOS Intel |
| `duckterm-hookd_linux-amd64.tar.gz` | Linux x86_64 (static, UPX) |
| `duckterm-hookd_linux-arm64.tar.gz` | Linux arm64 (static, UPX) |

Proprietary software — see the LICENSE inside each package.
