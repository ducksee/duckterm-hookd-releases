#!/usr/bin/env sh
# duckterm-hookd — one-line installer.
#
#   curl -fsSL https://raw.githubusercontent.com/ducksee/duckterm-hookd-releases/main/install.sh | sh
#
# With the recommended one-paste QR pairing path:
#
#   curl -fsSL .../install.sh | DUCKTERM_PAIR_QR=1 sh
#
# What it does:
#   1. Detects OS + arch, downloads the matching static binary tarball
#      from the latest release, verifies SHA256.
#   2. Installs to /usr/local/bin (sudo/root) or ~/.local/bin.
#   3. Pairs once (QR by default; legacy token env remains compatible) —
#      before the service starts, so the first connection is authenticated.
#   4. `duckterm-hookd install` — wires agent hooks (append-only).
#   5. Registers a supervisor:
#        macOS → launchd LaunchAgent (per-user)
#        Linux → systemd system unit when root/sudo, else --user unit
#                with loginctl enable-linger (so it survives logout).
#
# Env knobs:
#   DUCKTERM_VERSION=0.1.0      pin a version (default: latest)
#   DUCKTERM_PAIR_QR=1          render a QR for the DuckTerm app to scan
#   DUCKTERM_PAIR_TOKEN=…       legacy pairing bearer
#   DUCKTERM_PAIR_USER=…        tenant/user id paired with legacy bearer
#   DUCKTERM_NO_UI=1            skip the bundled local Web UI snapshot
#   DUCKTERM_NO_SERVICE=1       skip supervisor registration
#   DUCKTERM_TARBALL=/path.tgz  install from a local tarball (offline)
#
# brew users: prefer `brew install ducksee/tap/duckterm-hookd` +
# `brew services start duckterm-hookd` — this script is for hosts
# without Homebrew (typical Linux servers).

set -eu

REPO="ducksee/duckterm-hookd-releases"
BIN_NAME="duckterm-hookd"

say()  { printf '\033[1;36m[hookd]\033[0m %s\n' "$*"; }
die()  { printf '\033[1;31m[hookd]\033[0m %s\n' "$*" >&2; exit 1; }

# A partial pair request used to write an anonymous config and tell the user
# to pair a second time with --user. Fail before downloading or installing
# anything instead: the App always supplies both values in one paste.
if [ "${DUCKTERM_PAIR_QR:-}" = "1" ] && { [ -n "${DUCKTERM_PAIR_TOKEN:-}" ] || [ -n "${DUCKTERM_PAIR_USER:-}" ]; }; then
  die "choose one pairing method: DUCKTERM_PAIR_QR=1 or the legacy token/user pair"
fi
if [ -n "${DUCKTERM_PAIR_TOKEN:-}" ] && [ -z "${DUCKTERM_PAIR_USER:-}" ]; then
  die "DUCKTERM_PAIR_USER is required with DUCKTERM_PAIR_TOKEN; copy the complete command from DuckTerm"
fi
if [ -z "${DUCKTERM_PAIR_TOKEN:-}" ] && [ -n "${DUCKTERM_PAIR_USER:-}" ]; then
  die "DUCKTERM_PAIR_TOKEN is required with DUCKTERM_PAIR_USER; copy the complete command from DuckTerm"
fi

# ---- detect os/arch ------------------------------------------------------
case "$(uname -s)" in
  Darwin) OS=darwin ;;
  Linux)  OS=linux ;;
  *) die "unsupported OS: $(uname -s)" ;;
esac
case "$(uname -m)" in
  arm64|aarch64) ARCH=arm64 ;;
  x86_64|amd64)  ARCH=amd64 ;;
  *) die "unsupported arch: $(uname -m)" ;;
esac
say "platform: $OS-$ARCH"

# ---- download ------------------------------------------------------------
tmp=$(mktemp -d); trap 'rm -rf "$tmp"' EXIT
if [ -n "${DUCKTERM_TARBALL:-}" ]; then
  say "using local tarball $DUCKTERM_TARBALL"
  cp "$DUCKTERM_TARBALL" "$tmp/pkg.tar.gz"
else
  VER="${DUCKTERM_VERSION:-}"
  if [ -z "$VER" ]; then
    # NB: $(pipeline) exits with the LAST command's status — a failed curl
    # still leaves sed exiting 0, so test the value, not the pipeline.
    VER=$(curl -fsSL "https://api.github.com/repos/$REPO/releases/latest" 2>/dev/null \
      | grep -m1 '"tag_name"' | sed -E 's/.*"tag_name": *"v?([^"]+)".*/\1/') || true
    [ -n "$VER" ] || die "could not resolve latest version (set DUCKTERM_VERSION=… or check network/proxy)"
  fi
  ASSET="${BIN_NAME}_${OS}-${ARCH}.tar.gz"
  URL="https://github.com/$REPO/releases/download/v${VER}/${ASSET}"
  say "downloading $ASSET (v$VER)"
  curl -fsSL -o "$tmp/pkg.tar.gz" "$URL" || die "download failed: $URL"
  if curl -fsSL -o "$tmp/SHA256SUMS" "https://github.com/$REPO/releases/download/v${VER}/SHA256SUMS" 2>/dev/null; then
    want=$(grep "$ASSET\$" "$tmp/SHA256SUMS" | awk '{print $1}')
    if [ -n "$want" ]; then
      if command -v sha256sum >/dev/null 2>&1; then got=$(sha256sum "$tmp/pkg.tar.gz" | awk '{print $1}')
      else got=$(shasum -a 256 "$tmp/pkg.tar.gz" | awk '{print $1}'); fi
      [ "$want" = "$got" ] || die "sha256 mismatch (want $want got $got)"
      say "sha256 verified"
    fi
  fi
fi
tar -xzf "$tmp/pkg.tar.gz" -C "$tmp"
[ -x "$tmp/$BIN_NAME" ] || die "tarball missing $BIN_NAME"

# ---- install binary ------------------------------------------------------
IS_ROOT=0; [ "$(id -u)" = "0" ] && IS_ROOT=1
if [ "$IS_ROOT" = 1 ] || [ -w /usr/local/bin ]; then
  BIN_DIR=/usr/local/bin
elif command -v sudo >/dev/null 2>&1 && sudo -n true 2>/dev/null; then
  BIN_DIR=/usr/local/bin; SUDO=sudo
else
  BIN_DIR="$HOME/.local/bin"; mkdir -p "$BIN_DIR"
fi
# Atomic replace: cp onto a RUNNING binary fails with ETXTBSY on Linux.
# Write a temp file beside it and mv over — the running process keeps its
# old inode, the path points at the new binary for the next (re)start.
${SUDO:-} cp "$tmp/$BIN_NAME" "$BIN_DIR/.$BIN_NAME.new"
${SUDO:-} chmod 755 "$BIN_DIR/.$BIN_NAME.new"
${SUDO:-} mv -f "$BIN_DIR/.$BIN_NAME.new" "$BIN_DIR/$BIN_NAME"
BIN="$BIN_DIR/$BIN_NAME"
say "installed $BIN ($("$BIN" version))"
case ":$PATH:" in *":$BIN_DIR:"*) ;; *) say "note: add $BIN_DIR to your PATH";; esac

# ---- bootstrap bundled Web UI -------------------------------------------
# Release archives carry a verified compatibility snapshot so first use does
# not depend on GitHub/DNS/proxy availability. Bootstrap never replaces a
# valid existing UI; `duckterm-hookd ui upgrade` remains independently usable.
if [ "${DUCKTERM_NO_UI:-}" != "1" ] && [ -f "$tmp/duckterm-hookd-web.tar.gz" ]; then
  "$BIN" ui bootstrap "$tmp/duckterm-hookd-web.tar.gz" \
    || say "⚠ bundled Web UI install failed — Hookd will use its emergency page; retry with '$BIN_NAME ui upgrade'"
fi

# ---- pair (before the service starts — first connect is authenticated) ---
if [ "${DUCKTERM_PAIR_QR:-}" = "1" ]; then
  "$BIN" pair --qr
elif [ -n "${DUCKTERM_PAIR_TOKEN:-}" ]; then
  "$BIN" pair --token "$DUCKTERM_PAIR_TOKEN" --user "$DUCKTERM_PAIR_USER"
elif [ -f "$HOME/.duckterm/hookd-config.json" ]; then
  say "already paired — keeping existing ~/.duckterm/hookd-config.json"
else
  say "not paired yet — choose ONE pairing method (do not run both):"
  say "  $BIN_NAME pair --qr                                      (scan once in the DuckTerm app)"
  say "  or: $BIN_NAME pair --token <legacy-pair-token> --user <account-id>"
  say "  (the service self-heals: it picks pairing up on its next retry, no restart needed)"
fi

# ---- wire agent hooks ----------------------------------------------------
"$BIN" install || say "⚠ hook install reported an issue — re-run '$BIN_NAME install' after fixing"

# ---- supervisor ----------------------------------------------------------
[ "${DUCKTERM_NO_SERVICE:-}" = "1" ] && { say "skipping service (DUCKTERM_NO_SERVICE=1). Run: $BIN_NAME serve"; exit 0; }

if [ "$OS" = "darwin" ]; then
  PLIST="$HOME/Library/LaunchAgents/com.duckterm.hookd.plist"
  if [ -e "$PLIST" ]; then
    # Existing agent may carry site-specific args/env (deploy-host.sh adds
    # --enable-web etc.). Keep it; this run is a binary upgrade + restart.
    say "existing $PLIST found — keeping it (binary upgraded), restarting"
    launchctl kickstart -k "gui/$(id -u)/com.duckterm.hookd" 2>/dev/null \
      || { launchctl unload "$PLIST" 2>/dev/null; launchctl load -w "$PLIST"; }
    say "launchd service restarted"
    say "─── done ───"
    say "verify from the DuckTerm app: Settings → Agent notifications → Verify"
    exit 0
  fi
  mkdir -p "$HOME/Library/LaunchAgents" "$HOME/.duckterm"
  cat > "$PLIST" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key><string>com.duckterm.hookd</string>
  <key>ProgramArguments</key>
  <array><string>$BIN</string><string>serve</string></array>
  <key>RunAtLoad</key><true/>
  <key>KeepAlive</key><true/>
  <key>StandardOutPath</key><string>$HOME/.duckterm/hookd.log</string>
  <key>StandardErrorPath</key><string>$HOME/.duckterm/hookd.log</string>
</dict>
</plist>
EOF
  launchctl bootout "gui/$(id -u)/com.duckterm.hookd" 2>/dev/null || true
  launchctl bootstrap "gui/$(id -u)" "$PLIST" 2>/dev/null || launchctl load -w "$PLIST"
  say "launchd service registered + started (log: ~/.duckterm/hookd.log)"
else
  UNIT_BODY="[Unit]
Description=DuckTerm hookd — agent hook ingest + WSS push
After=network-online.target
Wants=network-online.target
StartLimitIntervalSec=60
StartLimitBurst=10

[Service]
Type=simple
ExecStart=$BIN serve
Restart=always
RestartSec=5
Environment=HOME=$HOME

[Install]
WantedBy=default.target"
  if [ "$IS_ROOT" = 1 ] || [ -n "${SUDO:-}" ]; then
    # system unit — reliable on headless servers, no user-bus/linger traps
    UNIT=/etc/systemd/system/duckterm-hookd.service
    if [ -e "$UNIT" ]; then
      # An existing unit may carry site-specific config (deploy-host.sh
      # writes env like DUCKTERM_LIVETAIL_*, --enable-web). Never downgrade
      # it — treat this run as a binary upgrade and just restart.
      say "existing $UNIT found — keeping it (binary upgraded), restarting"
      ${SUDO:-} systemctl daemon-reload
      ${SUDO:-} systemctl restart duckterm-hookd
    else
      printf '%s\n' "$UNIT_BODY" | sed -e "s|WantedBy=default.target|WantedBy=multi-user.target|" \
        -e "/^\[Service\]/a\\
User=$(id -un)" | ${SUDO:-} tee "$UNIT" >/dev/null
      ${SUDO:-} systemctl daemon-reload
      ${SUDO:-} systemctl enable --now duckterm-hookd
      say "systemd system service enabled + started"
    fi
  else
    # user unit — needs a live user bus; linger keeps it alive post-logout
    mkdir -p "$HOME/.config/systemd/user"
    printf '%s\n' "$UNIT_BODY" > "$HOME/.config/systemd/user/duckterm-hookd.service"
    loginctl enable-linger "$(id -un)" 2>/dev/null || say "⚠ enable-linger failed — service stops at logout (run: sudo loginctl enable-linger $(id -un))"
    systemctl --user daemon-reload || die "systemctl --user unavailable (no user bus over this SSH session?) — re-run with sudo for a system unit"
    systemctl --user enable --now duckterm-hookd
    say "systemd user service enabled + started"
  fi
fi

say "─── done ───"
say "verify from the DuckTerm app: Settings → Agent notifications → Verify"
