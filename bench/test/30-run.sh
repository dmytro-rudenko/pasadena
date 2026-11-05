echo "== run =="

run_rev="$(source "$ROOT/bench/lib.sh"; plugin_rev)"
run_cell() { echo "$BENCH_DIR/runs/$run_rev/t1/$1/1"; }
run_bench() { bash "$ROOT/bench/run.sh" "$@" >/dev/null 2>&1; }
run_has_arg() { grep -qxF -- "$1" "$FAKE_LOG" 2>/dev/null && echo yes || echo no; }
run_arg_after() { awk -v f="$1" 'p { print; exit } $0 == f { p = 1 }' "$FAKE_LOG" 2>/dev/null; }
run_env() { grep "^$1=" "$FAKE_LOG.env" 2>/dev/null | head -n1 | cut -d= -f2-; }
run_env_set() { grep -q "^$1=" "$FAKE_LOG.env" 2>/dev/null && echo yes || echo no; }

workflow_prompt='/pasadena:leonard Plan the implementation of the agreed specification at spec.md, then implement the plan with /pasadena:wolowitz. Work autonomously: do not ask questions, take the recommended option at every decision point, treat the spec and plan as approved. Do not push or open pull requests. Commit your work.'
plain_prompt='Implement the specification at spec.md. Work autonomously: do not ask questions, make reasonable decisions. Do not push or open pull requests. Commit your work.'
settings='{"enabledPlugins":{"pasadena@pasadena":false,"pasadena@synced":false}}'

fresh_bench
FAKE_WRITES="feature.txt=done feature2.txt=done" run_bench t1 plugin 1
assert_eq "$?" 0 "run: plugin exits 0"
for arg in -p --output-format stream-json --verbose --no-session-persistence --permission-mode bypassPermissions --max-budget-usd 15 --model sonnet --settings "$settings" --plugin-dir "$tmp/plugin"; do
  assert_eq "$(run_has_arg "$arg")" yes "run: plugin passes $arg"
done
assert_eq "$(run_arg_after --output-format)" stream-json "run: plugin --output-format stream-json"
assert_eq "$(run_arg_after --permission-mode)" bypassPermissions "run: plugin --permission-mode bypassPermissions"
assert_eq "$(run_arg_after --max-budget-usd)" 15 "run: plugin --max-budget-usd 15"
assert_eq "$(run_arg_after --model)" sonnet "run: plugin --model sonnet"
assert_eq "$(run_arg_after --settings)" "$settings" "run: plugin --settings disables installed pasadena"
assert_eq "$(run_arg_after --plugin-dir)" "$tmp/plugin" "run: plugin --plugin-dir is BENCH_PLUGIN"
prompt="$(run_arg_after -p)"
assert_contains "$prompt" "/pasadena:leonard Plan the implementation of the agreed specification at spec.md" "run: plugin prompt starts with leonard"
assert_eq "${prompt#/pasadena:leonard Plan the implementation of the agreed specification at spec.md}" "${workflow_prompt#/pasadena:leonard Plan the implementation of the agreed specification at spec.md}" "run: plugin prompt is the workflow prompt verbatim"
assert_eq "$(run_env PASADENA_CODEX)" 0 "run: plugin sets PASADENA_CODEX=0"
assert_eq "$(run_env_set PASADENA_REUSE)" yes "run: plugin env file has PASADENA_REUSE"
assert_eq "$(run_env PASADENA_REUSE)" "" "run: plugin leaves PASADENA_REUSE empty"
assert_eq "$(run_env codex-mode)" explore "run: plugin writes codex-mode explore"
cell="$(run_cell plugin)"
assert_eq "$(run_env XDG_STATE_HOME)" "$cell/state" "run: plugin XDG_STATE_HOME is <run>/state"
assert_eq "$(run_env pwd)" "$cell/tree" "run: claude runs in <run>/tree"
assert_eq "$(cat "$FAKE_LOG.count" 2>/dev/null)" 1 "run: tree has a single base commit"
assert_eq "$([ -e "$cell/tree" ] && echo present || echo gone)" gone "run: <run>/tree removed after run"
for f in diff.patch meta.json base-symbols.txt; do
  assert_eq "$([ -f "$cell/$f" ] && echo yes || echo no)" yes "run: <run>/$f kept"
done
assert_eq "$(grep -qx helper "$cell/base-symbols.txt" 2>/dev/null && echo yes || echo no)" yes "run: base-symbols.txt has helper"
assert_eq "$(wc -l 2>/dev/null <"$BENCH_DIR/runs.jsonl" | tr -d ' ')" 1 "run: one line appended to runs.jsonl"

mkdir -p "$cell"
touch "$cell/marker"
FAKE_WRITES="feature.txt=done feature2.txt=done" run_bench t1 plugin 1
assert_eq "$?" 0 "run: repeat with the same key exits 0"
assert_eq "$([ -e "$cell/marker" ] && echo present || echo gone)" gone "run: repeat clears the old run dir"

fresh_bench
FAKE_WRITES="feature.txt=done feature2.txt=done" run_bench t1 baseline 1
assert_eq "$?" 0 "run: baseline exits 0"
assert_eq "$(run_has_arg --plugin-dir)" no "run: baseline has no --plugin-dir"
assert_eq "$(run_arg_after --settings)" "$settings" "run: baseline --settings disables installed pasadena"
assert_eq "$(run_arg_after -p)" "$plain_prompt" "run: baseline prompt is the plain prompt"
assert_eq "$(run_env codex-mode)" "" "run: baseline writes no codex-mode"

fresh_bench
FAKE_WRITES="feature.txt=done feature2.txt=done" run_bench t1 plugin-noreuse 1
assert_eq "$?" 0 "run: plugin-noreuse exits 0"
assert_eq "$(run_env PASADENA_REUSE)" 0 "run: plugin-noreuse sets PASADENA_REUSE=0"
assert_eq "$(run_env PASADENA_CODEX)" 0 "run: plugin-noreuse sets PASADENA_CODEX=0"

fresh_bench
FAKE_WRITES="feature.txt=done feature2.txt=done" run_bench t1 plugin-haiku 1
assert_eq "$?" 0 "run: plugin-haiku exits 0"
assert_eq "$(run_arg_after --model)" haiku "run: plugin-haiku --model haiku"

fresh_bench
FAKE_CODEX_AVAILABLE=1 FAKE_WRITES="feature.txt=done feature2.txt=done" run_bench t1 plugin-codexfull 1
assert_eq "$?" 0 "run: plugin-codexfull without codex exits 0"
assert_eq "$(last_run .error)" "codex unavailable" "run: plugin-codexfull without codex is codex unavailable"
assert_eq "$(last_run .verdict)" error "run: plugin-codexfull without codex is verdict error"
assert_eq "$([ -s "$FAKE_LOG" ] && echo called || echo skipped)" skipped "run: plugin-codexfull without codex does not call claude"

fresh_bench
FAKE_CODEX_AVAILABLE=0 FAKE_CODEX_USED=10 FAKE_WRITES="feature.txt=done feature2.txt=done" run_bench t1 plugin-codexfull 1
assert_eq "$?" 0 "run: plugin-codexfull exits 0"
cell="$(run_cell plugin-codexfull)"
assert_eq "$([ -f "$cell/codex-before.txt" ] && echo yes || echo no)" yes "run: plugin-codexfull keeps codex-before.txt"
assert_eq "$(run_env codex-mode)" full "run: plugin-codexfull writes codex-mode full"

fresh_bench
start="$SECONDS"
BENCH_TIMEOUT=1 FAKE_CLAUDE=hang run_bench t1 plugin 1
assert_eq "$?" 0 "run: timeout exits 0"
assert_eq "$([ $((SECONDS - start)) -lt 20 ] && echo yes || echo no)" yes "run: timeout kills claude"
assert_eq "$(last_run .capped)" true "run: timeout is capped"
assert_eq "$(last_run .error)" timeout "run: timeout error is timeout"
assert_eq "$([ -f "$(run_cell plugin)/oracle.exit" ] && echo yes || echo no)" yes "run: oracle runs after timeout"

fresh_bench
run_bench nope plugin 1
assert_eq "$?" 2 "run: unknown task exits 2"
run_bench t1 nope 1
assert_eq "$?" 2 "run: unknown config exits 2"
