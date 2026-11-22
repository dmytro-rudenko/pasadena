#!/usr/bin/env bash
set -uo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
tmp="$(mktemp -d)" || exit 1
trap 'rm -rf "$tmp"' EXIT
fails=0

export BENCH_DIR="$tmp/bench"
export BENCH_CONFIG="$ROOT/bench/config.json"
export BENCH_TASKS="$tmp/tasks.txt"
export BENCH_PLUGIN_ROOT="$tmp/plugin"
export BENCH_ENV_FILE="$tmp/none.env"
export RUN_TEST_HARBOR_ARGV="$tmp/harbor-argv"
mkdir "$BENCH_PLUGIN_ROOT" || exit 1
cp -R "$ROOT"/{.claude-plugin,skills,hooks,proto} "$BENCH_PLUGIN_ROOT" || exit 1
mkdir -p "$BENCH_PLUGIN_ROOT/.claude" && cp -R "$ROOT/.claude/commands" "$BENCH_PLUGIN_ROOT/.claude/" || exit 1
mkdir -p "$BENCH_PLUGIN_ROOT/bench" && cp "$ROOT"/bench/pasadena_{wrap,agent}.py "$ROOT"/bench/tui_{agent,policy}.py "$BENCH_PLUGIN_ROOT/bench/" || exit 1
printf 'task-a\ntask-b\n' >"$BENCH_TASKS" || exit 1

run_bench() {
  bash "$ROOT/bench/run.sh" "$@" >"$tmp/stdout" 2>"$tmp/stderr"
  rc=$?
  stdout="$(<"$tmp/stdout")"
  stderr="$(<"$tmp/stderr")"
}

assert_case() {
  if [ "$1" -eq 0 ]; then
    printf '  ok  — %s\n' "$2"
  else
    printf '  FAIL — %s (runner exit %s)\n' "$2" "$rc"
    printf '        stdout: %s, stderr: %s\n' "$stdout" "$stderr"
    fails=$((fails + 1))
  fi
}

has_args() {
  local expected
  for expected; do
    [[ " $stdout " == *" $expected "* ]] || return 1
  done
}

shared_args() {
  sed -E 's/ -a [^ ]+//; s/ --job-name [^ ]+//' <<<"$1"
}

run_bench --arm baseline --dry-run
baseline_dry_run="$stdout"
[[ "$rc" = 0 && "$stdout" == *' --job-name full-baseline-'* ]] &&
  has_args '-a bench.tui_agent:TuiClaudeCode' '-d terminal-bench@2.0' '-m anthropic/claude-opus-5-5' \
    '-k 3' '-n 2' '-r 2' '--agent-timeout-multiplier 1.0' '--ak version=2.1.330' \
    "-o $BENCH_DIR/jobs" '-i task-a -i task-b'
assert_case "$?" "baseline dry-run uses the TUI agent and the benchmark config"

run_bench --arm pasadena --dry-run
[[ "$rc" = 0 && "$stdout" == *' --job-name full-pasadena-'* ]] &&
  has_args '-a bench.pasadena_agent:PasadenaClaudeCode' &&
  [ "$(shared_args "$baseline_dry_run")" = "$(shared_args "$stdout")" ]
assert_case "$?" "Pasadena dry-run uses the custom agent and shares the baseline options"

run_bench --arm baseline --print-job-name
first_job="$stdout" first_rc="$rc"
run_bench --arm baseline --print-job-name
second_job="$stdout" second_rc="$rc"
printf 'x\n' >>"$BENCH_TASKS" || exit 1
run_bench --arm baseline --print-job-name
[[ "$first_rc" = 0 && "$second_rc" = 0 && "$rc" = 0 &&
   "$first_job" =~ ^full-baseline-[0-9a-f]{8}$ && "$first_job" = "$second_job" &&
   "$stdout" =~ ^full-baseline-[0-9a-f]{8}$ && "$stdout" != "$first_job" ]]
assert_case "$?" "job names are stable and change with the task list"
printf 'task-a\ntask-b\n' >"$BENCH_TASKS" || exit 1

run_bench --arm baseline --print-job-name
baseline_job="$stdout" baseline_rc="$rc"
run_bench --arm pasadena --print-job-name
pasadena_job="$stdout" pasadena_rc="$rc"
printf '\nx\n' >>"$BENCH_PLUGIN_ROOT/skills/amy/SKILL.md" || exit 1
run_bench --arm baseline --print-job-name
baseline_changed="$stdout" baseline_changed_rc="$rc"
run_bench --arm pasadena --print-job-name
[[ "$baseline_rc" = 0 && "$pasadena_rc" = 0 && "$baseline_changed_rc" = 0 && "$rc" = 0 &&
   "$baseline_job" =~ ^full-baseline-[0-9a-f]{8}$ && "$baseline_job" = "$baseline_changed" &&
   "$pasadena_job" =~ ^full-pasadena-[0-9a-f]{8}$ &&
   "$stdout" =~ ^full-pasadena-[0-9a-f]{8}$ && "$stdout" != "$pasadena_job" ]]
assert_case "$?" "editing a skill changes only the Pasadena job name"

before_wrap="$stdout"
printf '\n# x\n' >>"$BENCH_PLUGIN_ROOT/bench/pasadena_wrap.py" || exit 1
run_bench --arm pasadena --print-job-name
[[ "$rc" = 0 && "$stdout" != "$before_wrap" ]]
assert_case "$?" "editing the Pasadena agent wrapper changes the Pasadena job name"

run_bench --arm baseline --print-job-name
baseline_before_policy="$stdout" baseline_before_rc="$rc"
run_bench --arm pasadena --print-job-name
pasadena_before_policy="$stdout" pasadena_before_rc="$rc"
printf '\n# x\n' >>"$BENCH_PLUGIN_ROOT/bench/tui_policy.py" || exit 1
run_bench --arm baseline --print-job-name
baseline_after_policy="$stdout" baseline_after_rc="$rc"
run_bench --arm pasadena --print-job-name
[[ "$baseline_before_rc" = 0 && "$pasadena_before_rc" = 0 && "$baseline_after_rc" = 0 && "$rc" = 0 &&
   "$baseline_after_policy" != "$baseline_before_policy" && "$stdout" != "$pasadena_before_policy" ]]
assert_case "$?" "editing the TUI policy changes both job names"

run_bench --arm baseline --fresh --print-job-name
[[ "$rc" = 0 && "$stdout" =~ ^full-baseline-[0-9a-f]{8}-[0-9]{14}$ ]]
assert_case "$?" "fresh job names end in a 14-digit timestamp"

BENCH_FRESH_STAMP=20260101000000 run_bench --arm baseline --fresh --print-job-name
[[ "$rc" = 0 && "$stdout" =~ ^full-baseline-[0-9a-f]{8}-20260101000000$ ]]
assert_case "$?" "fresh job names use BENCH_FRESH_STAMP when set"

run_bench --arm baseline --task x --dry-run
dry_run=" $stdout "
[[ "$rc" = 0 && "$dry_run" == *' --job-name smoke-'* &&
   "$dry_run" == *' -i x '* && " ${dry_run#* -i }" != *' -i '* ]]
assert_case "$?" "a smoke run includes exactly one task filter for x"

: >"$BENCH_TASKS" || exit 1
run_bench --arm baseline --dry-run
[[ "$rc" = 1 && "$stderr" == *'npm run bench:select'* ]]
assert_case "$?" "an empty task list exits 1 and points to bench:select"
printf 'task-a\ntask-b\n' >"$BENCH_TASKS" || exit 1

run_bench --arm baseline -- -k 1 --dry-run
[[ "$rc" = 0 && " $stdout " != *' -k 3 '* && "$stdout" != *' ' ]] &&
  has_args '-k 1'
assert_case "$?" "the attempt override replaces the default and leaves no empty argument"

run_bench --arm baseline --kind select --all-tasks --dry-run
[[ "$rc" = 0 && "$stdout" == *' --job-name select-baseline-'* &&
   " $stdout " != *' -i '* ]]
assert_case "$?" "a select run over all tasks omits task filters"

run_bench --arm baseline
[[ "$rc" = 1 && "$stderr" == *'npm run bench:setup'* ]]
assert_case "$?" "a run without the venv exits 1 and points to bench:setup"

mkdir -p "$BENCH_DIR/venv/bin" || exit 1
cat >"$BENCH_DIR/venv/bin/harbor" <<'EOF' || exit 1
#!/usr/bin/env bash
set -euo pipefail
printf '%s\0' "$@" >"$RUN_TEST_HARBOR_ARGV"
EOF
chmod +x "$BENCH_DIR/venv/bin/harbor" || exit 1

check_metadata() {
  python3 - "$BENCH_DIR/jobs" "$RUN_TEST_HARBOR_ARGV" <<'PY'
import json
import sys
from pathlib import Path

metadata_path, = Path(sys.argv[1]).glob("*/bench-meta.json")
metadata = json.loads(metadata_path.read_text())
assert metadata["attempts"] == 3, metadata
assert metadata["arm"] == "pasadena", metadata
assert metadata["agent"] == "tui", metadata
assert isinstance(metadata["pluginContentHash"], str) and metadata["pluginContentHash"], metadata
assert metadata["tasks"] == ["task-a", "task-b"], metadata
assert metadata["args"] == [], metadata

argv = Path(sys.argv[2]).read_bytes().split(b"\0")
assert argv[0] == b"run" and all(argv[:-1]) and argv[-1] == b"", argv
PY
}

run_bench --arm pasadena
[ "$rc" = 0 ] && check_metadata
assert_case "$?" "a Pasadena run writes metadata and invokes Harbor without empty arguments"

metadata_paths=("$BENCH_DIR"/jobs/*/bench-meta.json)
created_at="2000-01-01T00:00:00Z"
python3 - "${metadata_paths[0]}" "$created_at" <<'PY' || exit 1
import json
import sys
from pathlib import Path

path = Path(sys.argv[1])
metadata = json.loads(path.read_text())
metadata["createdAt"] = sys.argv[2]
path.write_text(json.dumps(metadata))
PY
rm -f "$RUN_TEST_HARBOR_ARGV" || exit 1
run_bench --arm pasadena
[ "$rc" = 0 ] && [ -s "$RUN_TEST_HARBOR_ARGV" ] &&
  python3 - "${metadata_paths[0]}" "$created_at" <<'PY'
import json
import sys
from pathlib import Path

created_at = json.loads(Path(sys.argv[1]).read_text())["createdAt"]
assert created_at == sys.argv[2], f"createdAt changed to {created_at}"
PY
assert_case "$?" "resuming a Pasadena job preserves its original creation time"

echo
if [ "$fails" -gt 0 ]; then
  echo "FAILED: $fails"
  exit 1
fi
echo "All checks passed."
