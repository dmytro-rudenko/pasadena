BENCH_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$BENCH_ROOT/.." && pwd)"
BENCH_DIR="${BENCH_DIR:-$REPO_ROOT/.bench}"
BENCH_CONFIG="${BENCH_CONFIG:-$BENCH_ROOT/config.json}"
BENCH_TASKS="${BENCH_TASKS:-$BENCH_ROOT/tasks.txt}"
BENCH_PLUGIN_ROOT="${BENCH_PLUGIN_ROOT:-$REPO_ROOT}"
BENCH_ENV_FILE="${BENCH_ENV_FILE:-$BENCH_ROOT/.env}"
HARBOR="$BENCH_DIR/venv/bin/harbor"

cfg() {
  python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))[sys.argv[2]])' "$BENCH_CONFIG" "$1"
}

require_venv() {
  if [ ! -x "$HARBOR" ]; then
    echo "bench: $BENCH_DIR/venv is missing — run: npm run bench:setup" >&2
    exit 1
  fi
}

load_env() {
  if [ -f "$BENCH_ENV_FILE" ]; then
    set -a
    . "$BENCH_ENV_FILE"
    set +a
  fi
}
