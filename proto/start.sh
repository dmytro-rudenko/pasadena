#!/usr/bin/env bash
# Start the prototype server. Prints one line of JSON with the URL.
#
# Usage: proto/start.sh --content-dir <path> [--state-dir <path>]
#                      [--host <addr>] [--idle-minutes <n>] [--open]
#
# Defaults: state under <repo root>/.sdd/proto, bind 127.0.0.1, idle 4h.
set -uo pipefail

DIR="$(cd "$(dirname "$0")" && pwd)"
CONTENT=""
STATE=""
HOST="127.0.0.1"
IDLE_MIN=240
OPEN=0

while [ $# -gt 0 ]; do
  case "$1" in
    --content-dir) CONTENT="$2"; shift 2 ;;
    --state-dir) STATE="$2"; shift 2 ;;
    --host) HOST="$2"; shift 2 ;;
    --idle-minutes) IDLE_MIN="$2"; shift 2 ;;
    --open) OPEN=1; shift ;;
    *) printf '{"error":"unknown argument: %s"}\n' "$1"; exit 1 ;;
  esac
done

if [ -z "$CONTENT" ]; then
  printf '{"error":"--content-dir is required"}\n'
  exit 1
fi

if [ -z "$STATE" ]; then
  root="$(git rev-parse --show-toplevel 2>/dev/null || printf '%s' "$PWD")"
  STATE="$root/.sdd/proto"
fi

# The state dir holds the session key. Nobody else's business.
umask 077
mkdir -p "$CONTENT" "$STATE" || exit 1

PID_FILE="$STATE/pid"
LOG_FILE="$STATE/log"

# One server per state dir; a second would fight over the port file.
if [ -f "$PID_FILE" ]; then
  old="$(cat "$PID_FILE" 2>/dev/null)"
  [ -n "$old" ] && kill "$old" 2>/dev/null
  rm -f "$PID_FILE"
fi

: >"$LOG_FILE"
SDD_CONTENT_DIR="$CONTENT" SDD_STATE_DIR="$STATE" SDD_HOST="$HOST" \
  SDD_IDLE_MS="$((IDLE_MIN * 60 * 1000))" \
  nohup node "$DIR/server.cjs" >"$LOG_FILE" 2>&1 &
pid=$!
disown "$pid" 2>/dev/null
printf '%s\n' "$pid" >"$PID_FILE"

# Wait for the startup line. 5s is generous for a loopback listen().
for _ in $(seq 1 50); do
  if grep -q '"type":"server-started"' "$LOG_FILE" 2>/dev/null; then
    line="$(grep '"type":"server-started"' "$LOG_FILE" | head -1)"
    if [ "$OPEN" = 1 ]; then
      url="$(printf '%s' "$line" | sed -n 's/.*"url":"\([^"]*\)".*/\1/p')"
      for opener in xdg-open open start; do
        command -v "$opener" >/dev/null 2>&1 && { "$opener" "$url" >/dev/null 2>&1 & break; }
      done
    fi
    printf '%s\n' "$line"
    exit 0
  fi
  if grep -q '"error"' "$LOG_FILE" 2>/dev/null; then
    grep '"error"' "$LOG_FILE" | head -1
    exit 1
  fi
  sleep 0.1
done

printf '{"error":"server did not start within 5s; see %s"}\n' "$LOG_FILE"
exit 1
