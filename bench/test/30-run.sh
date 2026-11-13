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

run_ub() { jq -r ".ub_tools.$2 // empty" "$1/meta.json" 2>/dev/null; }

fresh_bench
FAKE_WRITES="feature.txt=done feature2.txt=done" run_bench t1 plugin 1
assert_eq "$(cat "$FAKE_LOG.spec" 2>/dev/null)" "$(git -C "$repo" show "$ORACLE:spec.md")" "run: tree spec.md is the oracle's spec"
assert_eq "$(grep -qx amended "$FAKE_LOG.spec" 2>/dev/null && echo yes || echo no)" yes "run: tree spec.md has the oracle's amendment"

run_configs="$tmp/run-configs.tsv"
head -n1 "$ROOT/bench/configs.tsv" >"$run_configs"
printf 'plugin-nocrapper\tplugin\tworkflow\tPASADENA_CODEX=0 PASADENA_CRAPPER=/nonexistent\texplore\tsonnet\n' >>"$run_configs"
fresh_bench
BENCH_CONFIGS="$run_configs" FAKE_WRITES="feature.txt=done feature2.txt=done" run_bench t1 plugin-nocrapper 1
assert_eq "$(run_ub "$(run_cell plugin-nocrapper)" crapper)" "crapper: unavailable (PASADENA_CRAPPER is not executable)" "run: meta.json ub_tools.crapper uses the cell env"

run_bare="$tmp/plugin-bare"
rm -rf "$run_bare"
git init -q "$run_bare"
mkdir -p "$run_bare/hooks"
cp "$plugin/hooks/codex.sh" "$run_bare/hooks/codex.sh"
git -C "$run_bare" add -A
gitc -C "$run_bare" commit -qm bare
bare_rev="$(BENCH_PLUGIN="$run_bare"; source "$ROOT/bench/lib.sh"; plugin_rev)"
fresh_bench
BENCH_PLUGIN="$run_bare" FAKE_WRITES="feature.txt=done feature2.txt=done" run_bench t1 plugin 1
assert_eq "$(run_ub "$BENCH_DIR/runs/$bare_rev/t1/plugin/1" dryer)" unknown "run: meta.json ub_tools.dryer is unknown without ub-tools.sh"

run_old="$tmp/plugin-old"
rm -rf "$run_old"
git init -q "$run_old"
mkdir -p "$run_old/hooks"
cp "$plugin/hooks/codex.sh" "$run_old/hooks/codex.sh"
printf '#!/usr/bin/env bash\necho "usage: ub-tools.sh install"\nexit 0\n' >"$run_old/hooks/ub-tools.sh"
chmod +x "$run_old/hooks/ub-tools.sh"
git -C "$run_old" add -A
gitc -C "$run_old" commit -qm old
old_rev="$(BENCH_PLUGIN="$run_old"; source "$ROOT/bench/lib.sh"; plugin_rev)"
fresh_bench
BENCH_PLUGIN="$run_old" FAKE_WRITES="feature.txt=done feature2.txt=done" run_bench t1 plugin 1
assert_eq "$(run_ub "$BENCH_DIR/runs/$old_rev/t1/plugin/1" dryer)" unknown "run: meta.json ub_tools.dryer is unknown when ub-tools.sh lacks available"

fresh_bench
run_bench t1 baseline 1
secs="$(cat "$(run_cell baseline)/claude.secs" 2>/dev/null)"
assert_eq "$([[ "$secs" =~ ^[0-9]+\.[0-9]{3}$ ]] && echo yes)" yes "run: claude.secs holds the wall time of the claude call"
