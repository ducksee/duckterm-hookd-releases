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
#   4. `duckterm-hookd hook install` — wires agent hooks (marker-scoped).
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
#   DUCKTERM_BIN_DIR=/path      explicit binary directory (default: system/user)
#   DUCKTERM_SYSV_INIT_DIR=…    installer-test/staging override (default: /etc/init.d)
#   DUCKTERM_TARBALL=/path.tgz  install from a local tarball (offline)
#
# brew users: prefer `brew install ducksee/tap/duckterm-hookd` +
# `brew services start duckterm-hookd` — this script is for hosts
# without Homebrew (typical Linux servers).

set -eu

REPO="ducksee/duckterm-hookd-releases"
BIN_NAME="duckterm-hookd"
CONTROL_CENTER_URL="http://localhost:20080"

say()  { printf '\033[1;36m[hookd]\033[0m %s\n' "$*"; }
die()  { printf '\033[1;31m[hookd]\033[0m %s\n' "$*" >&2; exit 1; }

valid_version() {
  printf '%s\n' "$1" | grep -Eq '^[0-9]+\.[0-9]+\.[0-9]+$'
}

resolve_latest_version() {
  # The release repository's raw pointer is quota-free and travels over the
  # same host as this installer. Anonymous api.github.com has a shared-IP rate
  # limit that is routinely exhausted by proxies, schools, offices, and VPNs.
  candidate=$(curl -fsSL --connect-timeout 10 --max-time 20 \
    "https://raw.githubusercontent.com/$REPO/main/LATEST" 2>/dev/null \
    | tr -d '\r\n') || candidate=""
  if [ -n "$candidate" ] && valid_version "$candidate"; then
    printf '%s\n' "$candidate"
    return 0
  fi

  # Older release repositories may not have LATEST yet. Follow the public
  # release redirect without consuming API quota.
  effective=$(curl -fsSL --connect-timeout 10 --max-time 20 -o /dev/null \
    -w '%{url_effective}' "https://github.com/$REPO/releases/latest" 2>/dev/null) \
    || effective=""
  candidate=${effective##*/}
  candidate=${candidate#v}
  if [ -n "$candidate" ] && valid_version "$candidate"; then
    printf '%s\n' "$candidate"
    return 0
  fi

  # Last compatibility fallback. Treat rate-limit/error JSON as a miss rather
  # than fabricating a version from an arbitrary response.
  candidate=$(curl -fsSL --connect-timeout 10 --max-time 20 \
    "https://api.github.com/repos/$REPO/releases/latest" 2>/dev/null \
    | grep -m1 '"tag_name"' | sed -E 's/.*"tag_name": *"v?([^"]+)".*/\1/') \
    || candidate=""
  if [ -n "$candidate" ] && valid_version "$candidate"; then
    printf '%s\n' "$candidate"
    return 0
  fi
  return 1
}

is_wsl() {
  [ -n "${WSL_DISTRO_NAME:-}" ] || [ -n "${WSL_INTEROP:-}" ] \
    || grep -Eqi '(microsoft|wsl)' /proc/sys/kernel/osrelease /proc/version 2>/dev/null
}

systemd_is_pid1() {
  [ "$(cat /proc/1/comm 2>/dev/null || true)" = "systemd" ] \
    && command -v systemctl >/dev/null 2>&1
}

# >>> self-update whitelist backfill (docs/diagnostics/2026-10-12-hookd-install-sh-unit-whitelist-gap.md)
# Units written by deploy-host.sh before 2026-08-17 run hookd under
# ProtectSystem=full WITHOUT write access to the executable's directory, so
# every self-update (which stages its new binary next to the running one)
# dies with EROFS; this installer kept such units as they were, so those
# hosts needed a manual upgrade every release. This adds the one narrow
# exception the current deploy-host.sh template carries — write access to
# that single directory (both directive spellings: systemd < 231 only knows
# ReadWriteDirectories=) — and nothing else. It does not override a
# genuinely read-only filesystem, ownership, or any other mount policy.
#
# Only the canonical forms our two unit writers emit are handled. Anything
# else — other sections aside — is REFUSED (unit left byte-identical, with a
# reason): non-canonical/indented/continued lines, repeated ProtectSystem or
# ExecStart, list resets or -/+ prefixed entries, other mount-policy
# directives, a drop-in touching any of them, an ExecStart that is not one
# absolute, direct, symlink-free duckterm-hookd path, or a service binary
# that is not the one this installer just installed.
#
# unit_whitelist_backfill UNIT INSTALLED_BIN [DROPIN...]
# stdout: one line "changed: …" | "unchanged: …" | "refused: …" | "failed: …"
# status: 0 changed/unchanged, 2 refused, 1 failed. Only "changed" alters
# UNIT: staged beside it (owner/mode copied), verified, backed up to
# UNIT.hookd-whitelist.bak, then renamed over it.
# UWB_ROOT (tests only) prefixes every filesystem lookup of unit paths.
unit_whitelist_backfill() {
  uwb_unit=$1; uwb_bin=$2; shift 2
  uwb_root=${UWB_ROOT:-}
  if [ -L "$uwb_unit" ] || [ ! -f "$uwb_unit" ]; then
    echo "refused: $uwb_unit is not a regular file"; return 2
  fi
  if ! uwb_svc=$(awk '/^\[/ { s = ($0 == "[Service]"); next } s' "$uwb_unit"); then
    echo "failed: cannot read $uwb_unit"; return 1
  fi
  uwb_rel='ProtectSystem|ExecStart|ReadWritePaths|ReadWriteDirectories|ReadOnlyPaths|ReadOnlyDirectories|InaccessiblePaths|InaccessibleDirectories|TemporaryFileSystem|BindPaths|BindReadOnlyPaths|RootDirectory|RootImage|PrivateMounts'
  if printf '%s\n' "$uwb_svc" | grep -Eq "^[[:space:]]+($uwb_rel)|^($uwb_rel)[[:space:]]+=|\\\\[[:space:]]*\$"; then
    echo "refused: non-canonical sandbox or ExecStart lines in [Service]"; return 2
  fi
  if printf '%s\n' "$uwb_svc" | grep -Eq '^(ReadOnlyPaths|ReadOnlyDirectories|InaccessiblePaths|InaccessibleDirectories|TemporaryFileSystem|BindPaths|BindReadOnlyPaths|RootDirectory|RootImage|PrivateMounts)='; then
    echo "refused: [Service] carries other mount policy; fix the unit by hand"; return 2
  fi
  for uwb_d in "$@"; do
    [ -n "$uwb_d" ] || continue
    if [ ! -r "$uwb_d" ]; then echo "refused: drop-in $uwb_d is not readable"; return 2; fi
    if grep -Eq "^[[:space:]]*($uwb_rel)[[:space:]]*=" "$uwb_d"; then
      echo "refused: drop-in $uwb_d sets sandbox or ExecStart directives"; return 2
    fi
  done

  # Count assignment LINES (empty ones included — an empty assignment
  # resets earlier ones) across every [Service] section before reading any
  # value: repeats and resets are refused, never reconstructed.
  case $(printf '%s\n' "$uwb_svc" | grep -c '^ProtectSystem=') in
    0) echo "unchanged: no ProtectSystem"; return 0 ;;
    1) ;;
    *) echo "refused: ProtectSystem is assigned more than once (or reset)"; return 2 ;;
  esac
  uwb_ps=$(printf '%s\n' "$uwb_svc" | sed -n 's/^ProtectSystem=//p')
  case $uwb_ps in
    no|false) echo "unchanged: ProtectSystem=$uwb_ps"; return 0 ;;
    full|yes|true|strict) ;;
    *) echo "refused: unsupported ProtectSystem='$uwb_ps'"; return 2 ;;
  esac

  if [ "$(printf '%s\n' "$uwb_svc" | grep -c '^ExecStart=')" != 1 ]; then
    echo "refused: expected exactly one ExecStart assignment (repeats and resets are not supported)"; return 2
  fi
  uwb_es=$(printf '%s\n' "$uwb_svc" | sed -n 's/^ExecStart=//p')
  if [ -z "$uwb_es" ]; then echo "refused: empty ExecStart"; return 2; fi
  case $uwb_es in
    *%*|*\"*|*\'*|*\\*) echo "refused: ExecStart uses specifiers, quoting or escapes"; return 2 ;;
  esac
  uwb_exe=${uwb_es%% *}
  case $uwb_exe in
    /*) ;;
    *) echo "refused: ExecStart is not a direct absolute path ($uwb_exe)"; return 2 ;;
  esac
  case $uwb_exe in
    *[!A-Za-z0-9._/-]*|*//*|*/./*|*/../*) echo "refused: unsupported ExecStart path ($uwb_exe)"; return 2 ;;
    */duckterm-hookd) ;;
    *) echo "refused: ExecStart does not run duckterm-hookd directly ($uwb_exe)"; return 2 ;;
  esac
  if [ -L "$uwb_root$uwb_exe" ] || [ ! -f "$uwb_root$uwb_exe" ] \
     || ! uwb_real=$(readlink -f "$uwb_root$uwb_exe" 2>/dev/null) || [ "$uwb_real" != "$uwb_root$uwb_exe" ]; then
    echo "refused: $uwb_exe is missing or a symlink; the updater would stage next to its real target"; return 2
  fi
  if ! uwb_binreal=$(readlink -f "$uwb_bin" 2>/dev/null) || [ "$uwb_binreal" != "$uwb_root$uwb_exe" ]; then
    echo "refused: the service runs $uwb_exe but this installer installed $uwb_bin"; return 2
  fi
  uwb_dir=${uwb_exe%/*}
  case $uwb_dir in
    # A protected ROOT would whitelist its whole subtree; only an ordinary
    # child directory (e.g. /usr/local/bin) is supported.
    ''|/usr|/etc|/boot|/dev|/dev/*|/proc|/proc/*|/sys|/sys/*|/run|/run/*) echo "refused: unsupported install directory '${uwb_dir:-/}'"; return 2 ;;
  esac
  case $uwb_ps in
    strict) ;;
    full) case $uwb_dir in /usr|/usr/*|/boot|/boot/*|/etc|/etc/*) ;; *) echo "unchanged: $uwb_dir is writable under ProtectSystem=full"; return 0 ;; esac ;;
    *) case $uwb_dir in /usr|/usr/*|/boot|/boot/*) ;; *) echo "unchanged: $uwb_dir is writable under ProtectSystem=$uwb_ps"; return 0 ;; esac ;;
  esac

  uwb_lists=$(printf '%s\n' "$uwb_svc" | grep -E '^(ReadWritePaths|ReadWriteDirectories)=' || true)
  if printf '%s\n' "$uwb_lists" | grep -Eq '^(ReadWritePaths|ReadWriteDirectories)=[[:space:]]*$'; then
    echo "refused: a ReadWrite list is reset (empty assignment)"; return 2
  fi
  if printf '%s\n' "$uwb_lists" | sed 's/^[^=]*=//' | tr ' \t' '\n\n' | grep -Eq '^[-+]'; then
    echo "refused: prefixed (-/+) ReadWrite entries"; return 2
  fi
  uwb_add=""
  for uwb_k in ReadWritePaths ReadWriteDirectories; do
    if ! printf '%s\n' "$uwb_lists" | sed -n "s/^$uwb_k=//p" | tr ' \t' '\n\n' | grep -Fxq -- "$uwb_dir"; then
      uwb_add="$uwb_add${uwb_add:+
}$uwb_k=$uwb_dir"
    fi
  done
  if [ -z "$uwb_add" ]; then echo "unchanged: $uwb_dir is already whitelisted"; return 0; fi

  # Stage → verify → back up → rename. The original stays byte-identical on
  # any failure before the rename.
  uwb_stage="${uwb_unit%/*}/.${uwb_unit##*/}.hookd-whitelist.$$"
  uwb_bak="$uwb_unit.hookd-whitelist.bak"
  if ! uwb_tmp=$(mktemp 2>/dev/null); then echo "failed: mktemp"; return 1; fi
  # Lines travel through ENVIRON: some awks reject a newline in -v values.
  if ! UWB_ADD=$uwb_add awk '
         { print }
         /^\[/ { s = ($0 == "[Service]"); next }
         s && /^ProtectSystem=/ && !done { print ENVIRON["UWB_ADD"]; done = 1 }
       ' "$uwb_unit" > "$uwb_tmp" \
     || ! UWB_ADD=$uwb_add awk '
         # Verify: dropping exactly the inserted lines, in order, right after
         # [Service]'"'"'s ProtectSystem= line must give the original back.
         BEGIN { n = split(ENVIRON["UWB_ADD"], a, "\n") }
         k > 0 { if ($0 == a[n - k + 1]) { k--; next } k = 0 }
         { print }
         /^\[/ { s = ($0 == "[Service]"); next }
         s && /^ProtectSystem=/ && !done { k = n; done = 1 }
       ' "$uwb_tmp" | cmp -s - "$uwb_unit"; then
    rm -f "$uwb_tmp"; echo "failed: could not prepare the patched unit"; return 1
  fi
  if ! ${SUDO:-} cp -p "$uwb_unit" "$uwb_stage" \
     || ! ${SUDO:-} sh -c 'cat "$1" > "$2"' sh "$uwb_tmp" "$uwb_stage" \
     || ! ${SUDO:-} cmp -s "$uwb_tmp" "$uwb_stage" \
     || ! ${SUDO:-} cp -p "$uwb_unit" "$uwb_bak" \
     || ! ${SUDO:-} mv -f "$uwb_stage" "$uwb_unit"; then
    ${SUDO:-} rm -f "$uwb_stage"; rm -f "$uwb_tmp"
    echo "failed: could not write $uwb_unit (left unchanged)"; return 1
  fi
  if ! ${SUDO:-} cmp -s "$uwb_tmp" "$uwb_unit"; then
    rm -f "$uwb_tmp"; echo "failed: $uwb_unit does not hold the patched content (backup: $uwb_bak)"; return 1
  fi
  rm -f "$uwb_tmp"
  echo "changed: added $(printf '%s\n' "$uwb_add" | tr '\n' ' ')to $uwb_unit (backup: $uwb_bak)"
  return 0
}
# <<< self-update whitelist backfill

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

IS_WSL=0
if [ "$OS" = "linux" ] && is_wsl; then IS_WSL=1; fi
WSL_SYSV=0
FOREGROUND_MODE=0
# WSL1 cannot run systemd. Use Ubuntu's SysV/start-stop-daemon backend and a
# Windows-login launcher instead; WSL2 with systemd continues down the normal
# systemd path.
# Containers / no-init Linux (PID 1 = tini, sh, docker-init, …): while systemd
# is absent, a systemd unit could never be started by anyone. Foreground is
# the first-class service kind there (mirrors duckterm-web's installer): the
# container's own supervisor owns boot persistence, and we hand it a generated
# run script instead of failing the install. DUCKTERM_NO_SERVICE=1 keeps its
# existing meaning (install bytes only, no guidance, no run script).
if [ "$OS" = "linux" ] && [ "${DUCKTERM_NO_SERVICE:-}" != "1" ] && ! systemd_is_pid1; then
  if [ "$IS_WSL" = 1 ]; then
    WSL_SYSV=1
    say "WSL without systemd detected — installing a managed SysV service"
  else
    FOREGROUND_MODE=1
    say "no init supervisor (PID 1 is $(cat /proc/1/comm 2>/dev/null || echo unknown)) — foreground mode; boot persistence is delegated to your container supervisor"
  fi
fi

# ---- download ------------------------------------------------------------
tmp=$(mktemp -d); trap 'rm -rf "$tmp"' EXIT
VER="${DUCKTERM_VERSION:-}"
if [ -n "${DUCKTERM_TARBALL:-}" ]; then
  say "using local tarball $DUCKTERM_TARBALL"
  cp "$DUCKTERM_TARBALL" "$tmp/pkg.tar.gz"
else
  if [ -z "$VER" ]; then
    VER=$(resolve_latest_version) \
      || die "could not resolve latest version from GitHub releases (set DUCKTERM_VERSION=… or check network/proxy)"
  fi
  valid_version "$VER" || die "DUCKTERM_VERSION must be X.Y.Z (got '$VER')"
  ASSET="${BIN_NAME}_${OS}-${ARCH}.tar.gz"
  if [ "$IS_WSL" = 1 ]; then ASSET="${BIN_NAME}_${OS}-${ARCH}-wsl.tar.gz"; fi
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
if [ -n "${DUCKTERM_BIN_DIR:-}" ]; then
  BIN_DIR=$DUCKTERM_BIN_DIR; mkdir -p "$BIN_DIR"
elif [ "$IS_ROOT" = 1 ] || [ -w /usr/local/bin ]; then
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
${SUDO:-} ln -sfn "$BIN_NAME" "$BIN_DIR/dhook"
BIN="$BIN_DIR/$BIN_NAME"
if ! installed_version=$("$BIN" version 2>&1); then
  die "installed binary could not start on $OS-$ARCH (this host may require an unpacked/compatible release)"
fi
case "$installed_version" in
  "duckterm-hookd "*) ;;
  *) die "installed binary returned an invalid version response" ;;
esac
if [ -n "$VER" ]; then
  case "$installed_version" in
    "duckterm-hookd $VER"|"duckterm-hookd $VER ("*) ;;
    *) die "installed binary version does not match requested v$VER" ;;
  esac
fi
say "installed $BIN ($installed_version)"
case ":$PATH:" in *":$BIN_DIR:"*) ;; *) say "note: add $BIN_DIR to your PATH";; esac

# ---- bootstrap bundled Web UI -------------------------------------------
# Release archives carry a verified compatibility snapshot so first use does
# not depend on GitHub/DNS/proxy availability. Bootstrap advances an older UI
# to the bundled compatible release without rolling back a newer independent
# UI; `duckterm-hookd ui upgrade` remains independently usable.
if [ "${DUCKTERM_NO_UI:-}" != "1" ] && [ -f "$tmp/duckterm-hookd-web.tar.gz" ]; then
  "$BIN" ui bootstrap "$tmp/duckterm-hookd-web.tar.gz" \
    || say "⚠ bundled Web UI install failed — Hookd will use its emergency page; retry with '$BIN_NAME ui upgrade'"
fi

# ---- pair (before the service starts — first connect is authenticated) ---
if "$BIN" status --json 2>/dev/null | grep -Eq '"paired"[[:space:]]*:[[:space:]]*true'; then
  if [ "${DUCKTERM_PAIR_QR:-}" = "1" ] || [ -n "${DUCKTERM_PAIR_TOKEN:-}" ]; then
    say "already paired — keeping existing ~/.duckterm/hookd-config.json (pairing flags ignored; to re-pair: duckterm-hookd unpair, or pair --force)"
  else
    say "already paired — keeping existing ~/.duckterm/hookd-config.json"
  fi
elif [ "${DUCKTERM_PAIR_QR:-}" = "1" ]; then
  "$BIN" pair --qr
elif [ -n "${DUCKTERM_PAIR_TOKEN:-}" ]; then
  "$BIN" pair --token "$DUCKTERM_PAIR_TOKEN" --user "$DUCKTERM_PAIR_USER"
else
  say "not paired yet — choose ONE pairing method (do not run both):"
  say "  $BIN_NAME pair --qr                                      (scan once in the DuckTerm app)"
  say "  or: $BIN_NAME pair --token <legacy-pair-token> --user <account-id>"
  say "  (the service self-heals: it picks pairing up on its next retry, no restart needed)"
fi

# WSL1 shares the Windows host network, and modern WSL2 networking can mirror
# localhost too. Allocate stable per-install ports once instead of letting
# Windows and multiple distributions all contend for 11434 / 20080. Explicit
# user values are preserved by the idempotent command.
if [ "$IS_WSL" = "1" ]; then
  WSL_PORT_OUTPUT=$("$BIN" config --ensure-wsl-ports) \
    || die "could not allocate non-conflicting WSL LAN/Web ports"
  say "$WSL_PORT_OUTPUT"
  WSL_WEB_URL=$(printf '%s\n' "$WSL_PORT_OUTPUT" | sed -n 's/^WSL Web URL: //p' | tail -1)
  [ -n "$WSL_WEB_URL" ] \
    || die "WSL port allocator did not report the effective Web URL"
  CONTROL_CENTER_URL=$WSL_WEB_URL
fi

prepare_wsl_lan_firewall() {
  [ "$IS_WSL" = "1" ] || return 0
  if ${SUDO:-} "$BIN" firewall install; then
    say "WSL LAN Direct firewall reconciled for the allocated port"
    return 0
  fi
  say "⚠ WSL LAN Direct is listening, but its Windows inbound rule could not be installed"
  say "  Open Windows Terminal as Administrator, enter this WSL distribution, then run:"
  say "  $BIN firewall install"
  return 0
}

# ---- wire agent hooks ----------------------------------------------------
"$BIN" hook install || say "⚠ hook install reported an issue — re-run '$BIN_NAME hook install' after fixing"

# ---- supervisor ----------------------------------------------------------
[ "${DUCKTERM_NO_SERVICE:-}" = "1" ] && {
  say "skipping service (DUCKTERM_NO_SERVICE=1). Run: $BIN_NAME serve"
  say "then open the local control center: $CONTROL_CENTER_URL"
  exit 0
}
if [ "$FOREGROUND_MODE" = 1 ]; then
  RUN_SH="$HOME/.duckterm/run-hookd.sh"
  RUN_DIR=$(dirname "$RUN_SH")
  mkdir -p "$RUN_DIR"
  {
    printf '#!/bin/sh\n'
    printf '# duckterm-hookd entry for hosts without an init supervisor (containers).\n'
    printf '# Wire this into the container supervisor for boot persistence, e.g.\n'
    printf '#   docker CMD / compose command: ["%s"]\n' "$RUN_SH"
    printf '#   ad hoc: setsid nohup %s >>%s/hookd.log 2>&1 &\n' "$RUN_SH" "$RUN_DIR"
    printf 'exec "%s" serve\n' "$BIN"
  } > "$RUN_SH"
  chmod 0755 "$RUN_SH"
  say "foreground entry written: $RUN_SH"
  say "PID 1 is $(cat /proc/1/comm 2>/dev/null || echo unknown), not systemd: boot persistence is delegated to your container supervisor"
  say "start now: setsid nohup $RUN_SH >>$RUN_DIR/hookd.log 2>&1 &"
  say "persist:   point the container supervisor (docker CMD / compose / s6) at $RUN_SH"
  say "then open the local control center: $CONTROL_CENTER_URL"
  exit 0
fi
if [ "$WSL_SYSV" = 1 ]; then
  if [ "$IS_ROOT" != 1 ] && [ -z "${SUDO:-}" ]; then
    die "WSL1 service installation requires root or passwordless sudo"
  fi
  SYSV_INIT_DIR="${DUCKTERM_SYSV_INIT_DIR:-/etc/init.d}"
  SYSV_INIT="$SYSV_INIT_DIR/duckterm-hookd"
  SERVICE_USER=$(id -un)
  SERVICE_HOME=$HOME
  SYSV_STAGE="$tmp/duckterm-hookd.init"
  cat > "$SYSV_STAGE" <<EOF
#!/bin/sh
### BEGIN INIT INFO
# Provides:          duckterm-hookd
# Required-Start:    \$network
# Required-Stop:     \$network
# Default-Start:     2 3 4 5
# Default-Stop:      0 1 6
# Short-Description: DuckTerm Hookd background service
### END INIT INFO

NAME=duckterm-hookd
DAEMON="$BIN"
SERVICE_USER="$SERVICE_USER"
SERVICE_HOME="$SERVICE_HOME"
PIDFILE=/var/run/duckterm-hookd.pid
LOGFILE="$SERVICE_HOME/.duckterm/hookd.log"

is_running() {
  [ -s "\$PIDFILE" ] || return 1
  pid=\$(cat "\$PIDFILE" 2>/dev/null) || return 1
  kill -0 "\$pid" 2>/dev/null
}

case "\${1:-}" in
  start)
    if is_running; then echo "\$NAME already running"; exit 0; fi
    rm -f "\$PIDFILE"
    mkdir -p "\$(dirname "\$LOGFILE")"
    chown "\$SERVICE_USER" "\$(dirname "\$LOGFILE")" 2>/dev/null || true
    start-stop-daemon --start --background --make-pidfile --pidfile "\$PIDFILE" \
      --chuid "\$SERVICE_USER" --chdir "\$SERVICE_HOME" --startas /bin/sh -- \
      -c "exec env HOME=\"\$SERVICE_HOME\" DUCKTERM_HOOKD_LOG_PATH=\"\$LOGFILE\" \"\$DAEMON\" serve >/dev/null 2>&1"
    sleep 1
    is_running || { echo "\$NAME failed to start; see \$LOGFILE" >&2; exit 1; }
    echo "\$NAME started"
    ;;
  stop)
    if ! is_running; then rm -f "\$PIDFILE"; echo "\$NAME stopped"; exit 0; fi
    start-stop-daemon --stop --retry TERM/10/KILL/5 --pidfile "\$PIDFILE" --remove-pidfile
    echo "\$NAME stopped"
    ;;
  restart|reload)
    "\$0" stop
    "\$0" start
    ;;
  status)
    if is_running; then echo "\$NAME is running (pid \$(cat "\$PIDFILE"))"; exit 0; fi
    echo "\$NAME is not running" >&2
    exit 3
    ;;
  *) echo "Usage: \$0 {start|stop|restart|reload|status}" >&2; exit 2 ;;
esac
EOF
  ${SUDO:-} mkdir -p "$SYSV_INIT_DIR"
  ${SUDO:-} cp "$SYSV_STAGE" "$SYSV_INIT"
  ${SUDO:-} chmod 755 "$SYSV_INIT"
  if command -v update-rc.d >/dev/null 2>&1 && [ "$SYSV_INIT_DIR" = /etc/init.d ]; then
    ${SUDO:-} update-rc.d duckterm-hookd defaults >/dev/null
  fi
  ${SUDO:-} service duckterm-hookd restart
  ${SUDO:-} service duckterm-hookd status
  prepare_wsl_lan_firewall
  say "WSL SysV service registered + started (log: ~/.duckterm/hookd.log)"
  say "local control center: $CONTROL_CENTER_URL"

  # WSL1 does not execute Linux runlevels at Windows boot. A transparent
  # per-user Windows Startup launcher starts the default distro's SysV service
  # after login. Failure here does not invalidate the already-running service,
  # but it is reported honestly so the operator can add the launcher manually.
  if command -v cmd.exe >/dev/null 2>&1 && command -v wslpath >/dev/null 2>&1; then
    APPDATA_WIN=$(cmd.exe /d /c "echo %APPDATA%" 2>/dev/null | tr -d '\r' | tail -1)
    APPDATA_WSL=$(wslpath -u "$APPDATA_WIN" 2>/dev/null || true)
    if [ -n "$APPDATA_WSL" ]; then
      STARTUP_DIR="$APPDATA_WSL/Microsoft/Windows/Start Menu/Programs/Startup"
      mkdir -p "$STARTUP_DIR"
      printf '%s\r\n' '@echo off' 'C:\Windows\System32\wsl.exe -u root -- /etc/init.d/duckterm-hookd start >NUL 2>&1' \
        > "$STARTUP_DIR/DuckTerm-Hookd.cmd"
      say "Windows login autostart installed for the default WSL distro"
    else
      say "⚠ could not resolve the Windows Startup folder; the SysV service is running but must be started after Windows reboot"
    fi
  else
    say "⚠ Windows interop unavailable; the SysV service is running but must be started after Windows reboot"
  fi
  exit 0
fi

if [ "$OS" = "darwin" ]; then
  PLIST="$HOME/Library/LaunchAgents/com.duckterm.hookd.plist"
  if [ -e "$PLIST" ]; then
    # Existing agent may carry site-specific args/env (deploy-host.sh adds
    # --enable-web etc.). Preserve those fields while transferring log-file
    # ownership from launchd to Hookd's bounded rotating writer.
    PLIST_STAGE="$PLIST.duckterm-log.$$"
    cp "$PLIST" "$PLIST_STAGE"
    /usr/libexec/PlistBuddy -c 'Add :EnvironmentVariables dict' "$PLIST_STAGE" 2>/dev/null || true
    /usr/libexec/PlistBuddy -c 'Delete :EnvironmentVariables:DUCKTERM_HOOKD_LOG_PATH' "$PLIST_STAGE" 2>/dev/null || true
    /usr/libexec/PlistBuddy -c "Add :EnvironmentVariables:DUCKTERM_HOOKD_LOG_PATH string $HOME/.duckterm/hookd.log" "$PLIST_STAGE" \
      || { rm -f "$PLIST_STAGE"; die "could not configure bounded Hookd log path"; }
    /usr/libexec/PlistBuddy -c 'Delete :StandardOutPath' "$PLIST_STAGE" 2>/dev/null || true
    /usr/libexec/PlistBuddy -c 'Add :StandardOutPath string /dev/null' "$PLIST_STAGE" \
      || { rm -f "$PLIST_STAGE"; die "could not detach launchd stdout log"; }
    /usr/libexec/PlistBuddy -c 'Delete :StandardErrorPath' "$PLIST_STAGE" 2>/dev/null || true
    /usr/libexec/PlistBuddy -c 'Add :StandardErrorPath string /dev/null' "$PLIST_STAGE" \
      || { rm -f "$PLIST_STAGE"; die "could not detach launchd stderr log"; }
    /usr/bin/plutil -lint "$PLIST_STAGE" >/dev/null \
      || { rm -f "$PLIST_STAGE"; die "updated launchd service is invalid"; }
    mv "$PLIST_STAGE" "$PLIST"
    say "existing $PLIST found — preserved settings and enabled bounded logging, restarting"
    # kickstart reuses launchd's already-loaded environment and would leave the
    # old append-only descriptors active. Reload the definition transactionally.
    launchctl bootout "gui/$(id -u)/com.duckterm.hookd" 2>/dev/null \
      || launchctl unload "$PLIST" 2>/dev/null \
      || true
    launchctl bootstrap "gui/$(id -u)" "$PLIST" 2>/dev/null \
      || launchctl load -w "$PLIST"
    say "launchd service restarted"
    say "─── done ───"
    say "local control center: $CONTROL_CENTER_URL"
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
  <key>EnvironmentVariables</key>
  <dict>
    <key>DUCKTERM_HOOKD_LOG_PATH</key><string>$HOME/.duckterm/hookd.log</string>
  </dict>
  <key>StandardOutPath</key><string>/dev/null</string>
  <key>StandardErrorPath</key><string>/dev/null</string>
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
Environment=DUCKTERM_HOOKD_LOG_PATH=$HOME/.duckterm/hookd.log

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
      # …with one additive exception. Units written before the log path was
      # part of the template send every line to journald unbounded, which on
      # a server with no herdr/agents was measured at ~73% of all system log
      # volume. Backfill ONLY when the key is absent, append-only inside
      # [Service], and say so. Anything else about the unit stays untouched.
      if ! grep -q 'DUCKTERM_HOOKD_LOG_PATH' "$UNIT" 2>/dev/null; then
        # The path must belong to the identity the UNIT runs as, never to
        # whoever ran the installer. Under `sudo install.sh` on a host whose
        # unit carries `User=someone` (deploy-host.sh writes that), the
        # installer's $HOME is root's; writing it here would leave the service
        # unable to open the file, the daemon would fall back to stderr — back
        # into unbounded journald — and we would have printed "added bounded
        # log path" over a no-op. Both writers of this unit set
        # Environment=HOME=, so read it; fall back to the passwd home of
        # User=; refuse to guess.
        UNIT_HOME="$(sed -n 's/^Environment=HOME=\(.*\)$/\1/p' "$UNIT" 2>/dev/null | head -1)"
        if [ -z "$UNIT_HOME" ]; then
          UNIT_USER="$(sed -n 's/^User=\(.*\)$/\1/p' "$UNIT" 2>/dev/null | head -1)"
          [ -n "$UNIT_USER" ] && UNIT_HOME="$(getent passwd "$UNIT_USER" 2>/dev/null | cut -d: -f6)"
        fi
        if [ -z "$UNIT_HOME" ]; then
          say "⚠ $UNIT declares no HOME or User — add Environment=DUCKTERM_HOOKD_LOG_PATH=<service-home>/.duckterm/hookd.log under [Service] by hand to bound the log"
        else
          # Build the edited unit in a temp file and copy it over: never edit a
          # system unit in place. `cp` onto the existing path keeps its owner
          # and mode (a temp file's would not). Verify the key landed before we
          # claim success — a silent no-op here would look exactly like a fix.
          UNIT_TMP="$(mktemp 2>/dev/null || echo "")"
          if [ -n "$UNIT_TMP" ] \
            && awk -v line="Environment=DUCKTERM_HOOKD_LOG_PATH=$UNIT_HOME/.duckterm/hookd.log" '
                 { print }
                 /^\[Service\]/ && !added { print line; added = 1 }
               ' "$UNIT" > "$UNIT_TMP" 2>/dev/null \
            && grep -q 'DUCKTERM_HOOKD_LOG_PATH' "$UNIT_TMP" \
            && ${SUDO:-} cp "$UNIT_TMP" "$UNIT" 2>/dev/null; then
            say "added bounded log path to $UNIT under $UNIT_HOME (was journald-unbounded)"
          else
            say "⚠ could not add DUCKTERM_HOOKD_LOG_PATH to $UNIT — add it under [Service] by hand to bound the log"
          fi
          [ -n "$UNIT_TMP" ] && rm -f "$UNIT_TMP"
        fi
      fi
      # …and the self-update whitelist (see unit_whitelist_backfill). Drop-ins
      # from systemd itself plus the standard directories, so an override
      # cannot be missed when `systemctl show` is unavailable.
      UWB_DROPINS="$(systemctl show -p DropInPaths --value duckterm-hookd 2>/dev/null || true)"
      for d in /etc/systemd/system/duckterm-hookd.service.d/*.conf \
               /run/systemd/system/duckterm-hookd.service.d/*.conf \
               /usr/lib/systemd/system/duckterm-hookd.service.d/*.conf \
               /lib/systemd/system/duckterm-hookd.service.d/*.conf; do
        [ -e "$d" ] && UWB_DROPINS="$UWB_DROPINS $d"
      done
      UWB_RC=0
      # shellcheck disable=SC2086 # drop-in paths are space-separated by systemd
      UWB_OUT="$(unit_whitelist_backfill "$UNIT" "$BIN" $UWB_DROPINS)" || UWB_RC=$?
      case $UWB_RC in
        0) say "self-update whitelist: $UWB_OUT" ;;
        *) say "⚠ self-update whitelist: $UWB_OUT — in-service self-update may keep failing (install_readonly) until $UNIT is fixed by hand" ;;
      esac
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

prepare_wsl_lan_firewall

say "─── done ───"
say "local control center: $CONTROL_CENTER_URL"
say "verify from the DuckTerm app: Settings → Agent notifications → Verify"
