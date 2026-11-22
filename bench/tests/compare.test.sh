#!/usr/bin/env bash
set -uo pipefail

BENCH="$(cd "$(dirname "$0")/.." && pwd)"
fixtures="$BENCH/fixtures"
baseline="$fixtures/jobs/full-baseline-aaaa1111"
tmp="$(mktemp -d)" || exit 1
trap 'rm -rf "$tmp"' EXIT
mkdir "$tmp/empty" || exit 1
fails=0

ok() { printf '  ok  — %s\n' "$1"; }
fail() {
  printf '  FAIL — %s\n' "$1"
  fails=$((fails + 1))
}

run_compare() {
  stdout="$(python3 "$BENCH/compare.py" "$@" 2>"$tmp/stderr")"
  rc=$?
  stderr="$(<"$tmp/stderr")"
}

assert_exit() {
  local expected="$1" label="$2"
  if [[ "$rc" != "$expected" ]]; then
    fail "$label (expected exit $expected, got $rc)${stderr:+ — $stderr}"
    return 1
  fi
  ok "$label"
}

assert_contains() {
  local actual="$1" expected="$2" label="$3"
  if [[ "$actual" == *"$expected"* ]]; then
    ok "$label"
  else
    fail "$label (expected substring: $expected)"
    printf '        got: %s\n' "$actual"
  fi
}

read_report() {
  local report="$1"
  if [[ ! -f "$report" ]]; then
    fail "compare writes $report"
    return 1
  fi
  summary="$(<"$report")"
}

assert_failed_tasks() {
  local max="$1" expected="$2"
  run_compare --failed "$baseline" --max "$max"
  if assert_exit 0 "--failed --max $max exits 0"; then
    if [[ "$stdout" == "$expected" ]]; then
      ok "--failed --max $max lists the expected tasks"
    else
      printf '        expected: %q, got: %q\n' "$expected" "$stdout"
      fail "--failed --max $max lists the expected tasks"
    fi
  fi
}

run_compare --jobs-dir "$fixtures/jobs" --out "$tmp/s.md"
if assert_exit 0 "full comparison exits 0" && read_report "$tmp/s.md"; then
  assert_contains "$summary" ', attempts: 2, claude code:' "report header uses the jobs' attempt count"
  assert_contains "$summary" '| baseline | 1/5 (20.0%) | 3.6–62.4% |' "baseline pass rate and Wilson interval"
  assert_contains "$summary" '| pasadena | 4/6 (66.7%) | 30.0–90.3% |' "pasadena pass rate and Wilson interval"
  assert_contains "$summary" 'Δ pass rate (pasadena − baseline): +46.7 п.п.' "pass rate difference"
  assert_contains "$summary" '| задача | baseline x/k | pasadena x/k | Δ |' "per-task table header"
  assert_contains "$summary" '| task-a | 0/2 | 2/2 | + |' "task-a win"
  assert_contains "$summary" '| task-c | 0/1 | 0/2 | = |' "task-c tie excludes its invalid trial"
  assert_contains "$summary" 'Виграші: 2, програші: 0, нічиї: 1' "per-task result counts"
  assert_contains "$summary" '| pass@k | infra error | токени in/out |' "infra error column"
  if [[ "$summary" =~ \|\ baseline\ \|([^|]*\|){4}\ 1\ \| ]]; then
    ok "baseline reports one infra error"
  else
    fail "baseline reports one infra error"
    printf '        got: %s\n' "$summary"
  fi
  assert_contains "$summary" 'УВАГА: кількість валідних trial різниться (5 проти 6)' "unequal valid trial counts warning"
  assert_contains "$summary" '**Вердикт:** різниця в межах шуму при N=11 валідних trial.' "verdict for overlapping Wilson intervals"
  if [[ "$summary" == *smoke* ]]; then
    fail "summary excludes the smoke job"
  else
    ok "summary excludes the smoke job"
  fi
fi

run_compare --jobs-dir "$fixtures/jobs-mismatch" --out "$tmp/mismatch.md"
if assert_exit 1 "mismatched tasks exit 1"; then
  assert_contains "$stderr" tasks "mismatched tasks diagnostic"
fi

run_compare --jobs-dir "$fixtures/jobs-plugin-missing" --out "$tmp/plugin-missing.md"
if assert_exit 0 "missing plugin comparison exits 0" && read_report "$tmp/plugin-missing.md"; then
  assert_contains "$summary" 'УВАГА: плагін pasadena не встановився в 1 trial' "missing plugin warning"
fi

run_compare --jobs-dir "$fixtures/jobs-agent-mismatch" --out "$tmp/agent-mismatch.md"
if assert_exit 1 "mismatched agents exit 1"; then
  assert_contains "$stderr" 'bench: baseline and pasadena differ in agent' "mismatched agents diagnostic"
fi

cp -r "$fixtures/jobs" "$tmp/tui-jobs"
python3 - "$tmp/tui-jobs/full-pasadena-bbbb2222/task-a__1/result.json" <<'EOF'
import json
import sys

path = sys.argv[1]
with open(path, encoding="utf-8") as f:
    result = json.load(f)
result["exception_info"] = {"exception_type": "TuiApiError"}
result["reward_valid"] = True
with open(path, "w", encoding="utf-8") as f:
    json.dump(result, f)
EOF
run_compare --jobs-dir "$tmp/tui-jobs" --out "$tmp/tui.md"
if assert_exit 0 "TUI infra error comparison exits 0" && read_report "$tmp/tui.md"; then
  if [[ "$summary" =~ \|\ pasadena\ \|([^|]*\|){4}\ 1\ \| ]]; then
    ok "pasadena reports one infra error for a TuiApiError trial"
  else
    fail "pasadena reports one infra error for a TuiApiError trial"
    printf '        got: %s\n' "$summary"
  fi
  if [[ "$summary" == *'плагін pasadena не встановився'* ]]; then
    fail "TuiApiError is not reported as a missing plugin"
  else
    ok "TuiApiError is not reported as a missing plugin"
  fi
fi

run_compare --jobs-dir "$tmp/empty" --out "$tmp/empty.md"
if assert_exit 1 "empty jobs directory exits 1"; then
  assert_contains "$stderr" 'npm run bench:baseline' "empty jobs directory suggests running baseline"
fi

assert_failed_tasks 15 $'task-a\ntask-c'
assert_failed_tasks 1 task-a

echo
if [ "$fails" -gt 0 ]; then
  echo "FAILED: $fails"
  exit 1
fi
echo "All checks passed."
