#!/usr/bin/env bash
# Stop the prototype server. Usage: proto/stop.sh [--state-dir <path>]
set -uo pipefail

STATE=""
while [ $# -gt 0 ]; do
  case "$1" in
    --state-dir) STATE="$2"; shift 2 ;;
    *) printf '{"error":"unknown argument: %s"}\n' "$1"; exit 1 ;;
  esac
done

if [ -z "$STATE" ]; then
  root="$(git rev-parse --show-toplevel 2>/dev/null || printf '%s' "$PWD")"
  STATE="$root/.sdd/proto"
fi

PID_FILE="$STATE/pid"
[ -f "$PID_FILE" ] || { printf '{"stopped":false,"reason":"no pid file"}\n'; exit 0; }

pid="$(cat "$PID_FILE" 2>/dev/null)"
rm -f "$PID_FILE"
if [ -n "$pid" ] && kill "$pid" 2>/dev/null; then
  printf '{"stopped":true,"pid":%s}\n' "$pid"
else
  printf '{"stopped":false,"reason":"process %s not running"}\n' "${pid:-unknown}"
fi
