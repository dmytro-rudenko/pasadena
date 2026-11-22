#!/usr/bin/env bash
set -uo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
tmp="$(mktemp -d)" || exit 1
trap 'rm -rf "$tmp"' EXIT
fails=0

assert() {
  if [ "$1" -eq 0 ]; then
    printf '  ok  — %s\n' "$2"
  else
    printf '  FAIL — %s\n' "$2"
    fails=$((fails + 1))
  fi
}

jobs="$tmp/jobs"
trial="$jobs/full-pasadena-abcd1234/task-a__XyZ"
mkdir -p "$trial/agent" "$jobs/full-pasadena-abcd1234" || exit 1
echo '{"arm":"pasadena","kind":"full","createdAt":"2026-11-22T10:00:00Z"}' >"$jobs/full-pasadena-abcd1234/bench-meta.json"
python3 - "$trial/agent/claude-code.txt" <<'PY' || exit 1
import json
import sys

def tool(name, payload):
    return json.dumps({"type": "assistant", "message": {"content": [{"type": "tool_use", "name": name, "input": payload}]}})

lines = [
    tool("Bash", {"command": "mkdir -p /tmp/pasadena/specs && cat > /tmp/pasadena/specs/s.md <<'EOF'\n# Spec v1\nEOF"}),
    tool("Write", {"file_path": "/tmp/pasadena/plans/p.md", "content": "# Plan\n- [ ] Task 1\n"}),
    tool("Write", {"file_path": "/app/main.c", "content": "int main(){}"}),
    tool("Bash", {"command": "cat > /tmp/pasadena/specs/s.md <<'EOF'\n# Spec v2\nEOF"}),
    tool("Write", {"file_path": "/tmp/pasadena/../../escaped.md", "content": "x"}),
    "not json",
]
open(sys.argv[1], "w").write("\n".join(lines) + "\n")
PY

session="$jobs/full-pasadena-abcd1234/task-b__Q/agent/sessions/projects/-app"
mkdir -p "$session" || exit 1
python3 - "$session/s1.jsonl" <<'PY' || exit 1
import json
import sys

event = {"type": "assistant", "message": {"content": [{"type": "tool_use", "name": "Write", "input": {"file_path": "/tmp/pasadena/plans/q.md", "content": "# Q"}}]}}
open(sys.argv[1], "w").write(json.dumps(event) + "\n")
PY
mkdir -p "$jobs/full-pasadena-abcd1234/task-b__Q/agent/sessions/plans" || exit 1
printf '# Plan mode plan\n' >"$jobs/full-pasadena-abcd1234/task-b__Q/agent/sessions/plans/quiet-panda.md"
printf 'host secret\n' >"$tmp/host-secret.txt"
ln -s "$tmp/host-secret.txt" "$jobs/full-pasadena-abcd1234/task-b__Q/agent/sessions/plans/leak.md"
mkdir -p "$tmp/host-dir" "$jobs/full-pasadena-abcd1234/task-c__R/agent/sessions" || exit 1
printf 'host secret\n' >"$tmp/host-dir/secret.md"
ln -s "$tmp/host-dir" "$jobs/full-pasadena-abcd1234/task-c__R/agent/sessions/plans"

out="$tmp/out"
python3 "$ROOT/bench/artifacts.py" --jobs-dir "$jobs" --out "$out" >"$tmp/stdout" 2>&1
rc=$?
assert "$rc" "artifacts exits 0"

[ "$(cat "$out/task-a__XyZ/specs/s.md" 2>/dev/null)" = "# Spec v2" ]
assert "$?" "the latest heredoc version of a spec is kept"

grep -qx -- '- \[ \] Task 1' "$out/task-a__XyZ/plans/p.md" 2>/dev/null
assert "$?" "a plan written with the Write tool is extracted"

[ "$(cat "$out/task-b__Q/plans/q.md" 2>/dev/null)" = "# Q" ]
assert "$?" "a plan written in a session transcript is extracted"

[ "$(cat "$out/task-b__Q/plan-mode/quiet-panda.md" 2>/dev/null)" = "# Plan mode plan" ]
assert "$?" "a plan-mode plan file is copied"

[ ! -e "$out/task-b__Q/plan-mode/leak.md" ]
assert "$?" "a symlinked plan-mode file is not followed"

[ ! -e "$out/task-c__R/plan-mode/secret.md" ]
assert "$?" "a symlinked plans directory is not followed"

[ ! -e "$out/task-a__XyZ/main.c" ] && [ ! -e "$out/task-a__XyZ/app" ]
assert "$?" "files outside /tmp/pasadena are ignored"

[ -z "$(find "$tmp" -name escaped.md)" ]
assert "$?" "paths that climb out of /tmp/pasadena are not written"

python3 "$ROOT/bench/artifacts.py" --jobs-dir "$tmp/empty" --out "$out" >/dev/null 2>"$tmp/stderr"
rc=$?
[ "$rc" = 1 ] && grep -q 'npm run bench:pasadena' "$tmp/stderr"
assert "$?" "no pasadena job exits 1 and points to bench:pasadena"

echo
if [ "$fails" -gt 0 ]; then
  echo "FAILED: $fails"
  exit 1
fi
echo "All checks passed."
