#!/usr/bin/env bash
set -euo pipefail
. "$(cd "$(dirname "$0")" && pwd)/common.sh"
if ! command -v docker >/dev/null 2>&1 || ! docker info >/dev/null 2>&1; then
  echo "bench: Docker is not available or not running" >&2; exit 1
fi
want="$(cfg harborVersion)"
if [ ! -x "$HARBOR" ] || [ "$("$HARBOR" --version 2>/dev/null)" != "$want" ]; then
  python3 -m venv "$BENCH_DIR/venv"
  "$BENCH_DIR/venv/bin/pip" install -q "harbor==$want"
fi
load_env
if [ -z "${ANTHROPIC_API_KEY:-}" ] && [ -z "${CLAUDE_CODE_OAUTH_TOKEN:-}" ]; then
  echo "bench: set ANTHROPIC_API_KEY or CLAUDE_CODE_OAUTH_TOKEN (get one with 'claude setup-token') in the environment or $BENCH_ENV_FILE" >&2
  exit 1
fi
echo "bench: ready (harbor $want)"
