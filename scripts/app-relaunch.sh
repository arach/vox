#!/bin/bash
# app-relaunch.sh — Stop any running Vox menu-bar app, rebuild, and relaunch it.
#
# Usage: ./scripts/app-relaunch.sh [--no-build] [--foreground]
#
# Options:
#   --no-build        Skip rebuild (relaunch existing dev binary)
#   --foreground, -f  Run raw binary in foreground (Ctrl-C to stop, see logs in terminal)
#                     Default is bundled app launch via dist/dev/Vox Dev.app

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

BOLD='\033[1m'; GREEN='\033[32m'; YELLOW='\033[33m'; RED='\033[31m'; RESET='\033[0m'
say()  { printf "  ${BOLD}→${RESET} %s\n" "$1"; }
ok()   { printf "  ${GREEN}✓${RESET} %s\n" "$1"; }
warn() { printf "  ${YELLOW}!${RESET} %s\n" "$1"; }
fail() { printf "  ${RED}✗${RESET} %s\n" "$1"; exit 1; }

DO_BUILD=true
DETACH=true

for arg in "$@"; do
  case "$arg" in
    --no-build)        DO_BUILD=false ;;
    --foreground|-f)   DETACH=false ;;
    -h|--help)
      sed -n '2,9p' "$0" | sed 's/^# \{0,1\}//'
      exit 0
      ;;
    *) fail "unknown option: $arg (use --help)" ;;
  esac
done

# Match the scratch path used by `bun run app:build` so we share its build cache.
SCRATCH="$ROOT/app/.build-$(swift --version 2>&1 | shasum | cut -d ' ' -f 1)"

# ---------------------------------------------------------------------------
# 1. Stop any running Vox.
# ---------------------------------------------------------------------------

INSTALLED_PATTERN='Vox\.app/Contents/MacOS/Vox'
DEV_BUNDLE_PATTERN='dist/dev/Vox Dev\.app/Contents/MacOS/Vox'
DEV_PATTERN='app/\.build.*/debug/Vox'
ANY_PATTERN="(${INSTALLED_PATTERN}|${DEV_BUNDLE_PATTERN}|${DEV_PATTERN})"

if pgrep -f "$INSTALLED_PATTERN" >/dev/null 2>&1; then
  say "quitting installed /Applications/Vox.app"
  osascript -e 'tell application "Vox" to quit' 2>/dev/null || true
fi

if pgrep -f "$DEV_BUNDLE_PATTERN" >/dev/null 2>&1; then
  say "quitting dev app bundle"
  osascript -e 'tell application id "cc.voxd.app.dev" to quit' 2>/dev/null || true
fi

if pgrep -f "$DEV_PATTERN" >/dev/null 2>&1; then
  say "stopping previous dev binary"
  pkill -f "$DEV_PATTERN" 2>/dev/null || true
fi

# Wait up to ~3s for graceful exit.
for _ in 1 2 3 4 5 6; do
  pgrep -f "$ANY_PATTERN" >/dev/null 2>&1 || break
  sleep 0.5
done

if pgrep -f "$ANY_PATTERN" >/dev/null 2>&1; then
  warn "process didn't exit cleanly, forcing kill"
  pkill -9 -f "$ANY_PATTERN" 2>/dev/null || true
  sleep 0.3
fi

ok "no Vox process running"

if $DETACH; then
  LINK_ARGS=(--launch)
  if ! $DO_BUILD; then
    LINK_ARGS=(--no-build --launch)
  fi
  exec "$ROOT/scripts/link-dev-app.sh" "${LINK_ARGS[@]}"
fi

# ---------------------------------------------------------------------------
# 2. Build (optional).
# ---------------------------------------------------------------------------

if $DO_BUILD; then
  say "building Vox app target"
  swift build --package-path "$ROOT/app" --scratch-path "$SCRATCH"
  ok "build complete"
fi

# ---------------------------------------------------------------------------
# 3. Locate dev binary and launch.
# ---------------------------------------------------------------------------

BIN_DIR=$(swift build --package-path "$ROOT/app" --scratch-path "$SCRATCH" --show-bin-path)
BIN="$BIN_DIR/Vox"
[ -x "$BIN" ] || fail "binary not found at $BIN (try without --no-build)"

say "launching dev binary (foreground — Ctrl-C to stop)"
exec "$BIN"
