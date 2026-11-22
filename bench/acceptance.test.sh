#!/usr/bin/env bash
set -uo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
fails=0
ok()   { echo "  ok  — $1"; }
bad()  { echo "  FAIL — $1"; fails=$((fails + 1)); }
tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT

(cd "$ROOT" && npm run --silent bench:test >/dev/null 2>&1) && ok "bench:test exits 0" || bad "bench:test exits 0"

mkdir -p "$tmp/venv/bin" "$tmp/stub"
printf '#!/usr/bin/env bash\necho 0.27.0\n' >"$tmp/venv/bin/harbor"; chmod +x "$tmp/venv/bin/harbor"
printf '#!/usr/bin/env bash\nexit 0\n' >"$tmp/stub/docker"; chmod +x "$tmp/stub/docker"
out="$(cd "$ROOT" && env -u ANTHROPIC_API_KEY -u CLAUDE_CODE_OAUTH_TOKEN PATH="$tmp/stub:$PATH" BENCH_DIR="$tmp" BENCH_ENV_FILE="$tmp/none.env" npm run --silent bench:setup 2>&1)"; rc=$?
[ "$rc" = 1 ] && ok "setup without token exits 1" || bad "setup without token exits 1 (rc=$rc)"
[[ "$out" == *"CLAUDE_CODE_OAUTH_TOKEN"* ]] && ok "setup explains the token" || bad "setup explains the token: $out"

printf 'task-a\ntask-b\n' >"$tmp/tasks.txt"
b="$(cd "$ROOT" && BENCH_TASKS="$tmp/tasks.txt" BENCH_DIR="$tmp" npm run --silent bench:baseline -- --dry-run 2>&1)"
p="$(cd "$ROOT" && BENCH_TASKS="$tmp/tasks.txt" BENCH_DIR="$tmp" npm run --silent bench:pasadena -- --dry-run 2>&1)"
[[ "$p" == *"-a bench.pasadena_agent:PasadenaClaudeCode"* ]] && ok "pasadena dry-run uses the custom agent" || bad "pasadena dry-run uses the custom agent: $p"
[[ "$b" == *"-a bench.tui_agent:TuiClaudeCode"* ]] && ok "baseline dry-run uses the TUI agent" || bad "baseline dry-run uses the TUI agent: $b"
norm() { sed -E 's/ -a [^ ]+//; s/ --job-name [^ ]+//' <<<"$1"; }
[[ "$b" == *" -m "*" -k "*" -n "*" -i task-a -i task-b"* ]] && [ "$(norm "$b")" = "$(norm "$p")" ] && ok "arms share -m/-k/-n/-i" || bad "arms differ beyond -a/--job-name"

(cd "$ROOT" && python3 bench/compare.py --jobs-dir bench/fixtures/jobs --out "$tmp/summary.md" >/dev/null 2>&1)
s="$(cat "$tmp/summary.md" 2>/dev/null)"
for want in "| baseline |" "| pasadena |" "| задача | baseline x/k | pasadena x/k | Δ |" "**Вердикт:**"; do
  [[ "$s" == *"$want"* ]] && ok "summary has $want" || bad "summary has $want"
done

(cd "$ROOT" && python3 -c 'from bench.tui_policy import decide, Keys
s = "❯ 1. a.txt (Recommended)\n  2. b.txt\nEnter to select · ↑/↓ to navigate · Esc to cancel"
assert decide(s, None, None, 0, 0.0) == Keys("1")' >/dev/null 2>&1) && ok "decide picks the recommended option" || bad "decide picks the recommended option"

(cd "$ROOT" && python3 bench/compare.py --jobs-dir bench/fixtures/jobs-agent-mismatch --out "$tmp/m.md" >/dev/null 2>"$tmp/m.err"); rc=$?
[ "$rc" = 1 ] && grep -q 'differ in agent' "$tmp/m.err" && ok "compare refuses arms with different agents" || bad "compare refuses arms with different agents (rc=$rc)"

mkdir -p "$tmp/aj/full-pasadena-x/t__1/agent/sessions/projects/-app"
echo '{"arm":"pasadena","kind":"full","createdAt":"2026-11-22T10:00:00Z"}' >"$tmp/aj/full-pasadena-x/bench-meta.json"
echo '{"type":"assistant","message":{"content":[{"type":"tool_use","name":"Write","input":{"file_path":"/tmp/pasadena/specs/s.md","content":"# S"}}]}}' >"$tmp/aj/full-pasadena-x/t__1/agent/sessions/projects/-app/a.jsonl"
(cd "$ROOT" && python3 bench/artifacts.py --jobs-dir "$tmp/aj" --out "$tmp/aout" >/dev/null 2>&1)
[ -f "$tmp/aout/t__1/specs/s.md" ] && ok "artifacts reads session transcripts" || bad "artifacts reads session transcripts"

echo
[ "$fails" -gt 0 ] && { echo "FAILED: $fails"; exit 1; }
echo "All checks passed."
