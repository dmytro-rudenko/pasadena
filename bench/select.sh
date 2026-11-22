#!/usr/bin/env bash
set -euo pipefail
. "$(cd "$(dirname "$0")" && pwd)/common.sh"

args=(--arm baseline --kind select --all-tasks -k 1)
for a in "$@"; do
  if [ "$a" = --dry-run ]; then
    exec bash "$BENCH_ROOT/run.sh" "${args[@]}" "$@"
  fi
done
export BENCH_FRESH_STAMP="${BENCH_FRESH_STAMP:-$(date -u +%Y%m%d%H%M%S)}"
job="$(bash "$BENCH_ROOT/run.sh" "${args[@]}" "$@" --print-job-name)"
bash "$BENCH_ROOT/run.sh" "${args[@]}" "$@"
tmp="$(mktemp)"
trap 'rm -f "$tmp"' EXIT
python3 "$BENCH_ROOT/compare.py" --failed "$BENCH_DIR/jobs/$job" --max "$(cfg hardSetMax)" >"$tmp" || exit 1
if [ ! -s "$tmp" ]; then
  echo 'bench: no task failed with a valid trial; tasks.txt left unchanged' >&2
  exit 1
fi
mv "$tmp" "$BENCH_TASKS"
echo "bench: $(wc -l <"$BENCH_TASKS") tasks written to $BENCH_TASKS"
