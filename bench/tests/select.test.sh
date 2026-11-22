#!/usr/bin/env bash
set -uo pipefail

BENCH="$(cd "$(dirname "$0")/.." && pwd)"
baseline="$BENCH/fixtures/jobs/full-baseline-aaaa1111"
tmp="$(mktemp -d)" || exit 1
trap 'rm -rf "$tmp"' EXIT
fails=0

export BENCH_DIR="$tmp/bench"
export BENCH_CONFIG="$BENCH/config.json"
export BENCH_TASKS="$tmp/tasks.txt"
export BENCH_ENV_FILE="$tmp/none.env"
printf 'keep\n' >"$BENCH_TASKS" || exit 1

run_select() {
  stdout="$(bash "$BENCH/select.sh" "$@" 2>"$tmp/stderr")"
  rc=$?
  stderr="$(<"$tmp/stderr")"
}

assert_case() {
  if [ "$1" -eq 0 ]; then
    printf '  ok  — %s\n' "$2"
  else
    printf '  FAIL — %s (select exit %s)\n' "$2" "$rc"
    printf '        stdout: %s, stderr: %s\n' "$stdout" "$stderr"
    fails=$((fails + 1))
  fi
}

prepare_job() {
  local job
  job="$(bash "$BENCH/run.sh" --arm baseline --kind select --all-tasks -k 1 "$@" --print-job-name)" || exit 1
  job_dir="$BENCH_DIR/jobs/$job"
  mkdir -p "$job_dir" "$BENCH_DIR/venv/bin" || exit 1
  printf '#!/usr/bin/env bash\nexit 0\n' >"$BENCH_DIR/venv/bin/harbor" || exit 1
  chmod +x "$BENCH_DIR/venv/bin/harbor" || exit 1
}

run_select --dry-run
[[ "$rc" = 0 && "$stdout" == *' --job-name select-baseline-'* &&
   " $stdout " == *' -k 1 '* && " $stdout " != *' -i '* ]]
assert_case "$?" "dry-run prints a one-attempt baseline selection command for all tasks"

prepare_job
cp -R "$baseline"/task-*__*/ "$job_dir/" || exit 1
run_select
[ "$rc" = 0 ] && cmp -s "$BENCH_TASKS" <(printf 'task-a\ntask-c\n')
assert_case "$?" "selection writes the failed tasks from the baseline trials"

export BENCH_DIR="$tmp/empty"
prepare_job
printf 'keep\n' >"$BENCH_TASKS" || exit 1
run_select
[ "$rc" = 1 ] && cmp -s "$BENCH_TASKS" <(printf 'keep\n')
assert_case "$?" "selection exits 1 and preserves the task list when the job is empty"

export BENCH_DIR="$tmp/fresh"
BENCH_FRESH_STAMP=20260101000000 prepare_job --fresh
cp -R "$baseline"/task-*__*/ "$job_dir/" || exit 1
mkdir "$tmp/bin" || exit 1
cat >"$tmp/bin/date" <<'EOF' || exit 1
#!/usr/bin/env bash
if [ -e "$0.called" ]; then
  printf '20260101000001\n'
else
  touch "$0.called" || exit 1
  printf '20260101000000\n'
fi
EOF
chmod +x "$tmp/bin/date" || exit 1
unset BENCH_FRESH_STAMP
PATH="$tmp/bin:$PATH" run_select --fresh
[[ "$rc" = 0 && -f "$job_dir/bench-meta.json" ]] &&
  cmp -s "$BENCH_TASKS" <(printf 'task-a\ntask-c\n')
assert_case "$?" "fresh selection records the run and reads trials in the same stamped job"

export BENCH_DIR="$tmp/passing"
prepare_job
cp -R "$baseline/task-b__1" "$job_dir/" || exit 1
printf 'keep\n' >"$BENCH_TASKS" || exit 1
run_select
[[ "$rc" = 1 && "$stderr" = 'bench: no task failed with a valid trial; tasks.txt left unchanged' ]] &&
  cmp -s "$BENCH_TASKS" <(printf 'keep\n')
assert_case "$?" "selection exits 1 and preserves the task list when all trials pass"

echo
if [ "$fails" -gt 0 ]; then
  echo "FAILED: $fails"
  exit 1
fi
echo "All checks passed."
