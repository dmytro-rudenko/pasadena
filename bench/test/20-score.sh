echo "== score =="

score_init() {
  jq -c --arg p "$1" '.plugins[0].path = $p' "$FIXTURES/init.json"
}

mkrun() {
  local dir="$1"
  rm -rf "$dir"
  mkdir -p "$dir"
  jq -n --arg p "$tmp/plugin" '{task:"t1",config:"plugin",rep:1,model:"claude-haiku-5-5",plugin_rev:"abc1234",mode:"plugin",plugin_path:$p,budget:15,base_commit:"0000000",ts:"2026-11-05T00:00:00Z"}' >"$dir/meta.json"
  echo 0 >"$dir/claude.exit"
  : >"$dir/claude.err"
  {
    score_init "$tmp/plugin"
    jq -c . "$FIXTURES/assistant.json"
    jq -c . "$FIXTURES/assistant.json"
    jq -c . "$FIXTURES/result-success.json"
  } >"$dir/claude.jsonl"
  cat >"$dir/diff.patch" <<'PATCH'
diff --git a/feature.txt b/feature.txt
new file mode 100644
--- /dev/null
+++ b/feature.txt
@@ -0,0 +1 @@
+done
PATCH
  printf 't/one.test.sh\t0\nt/two.test.sh\t0\n' >"$dir/oracle.exit"
  echo helper >"$dir/base-symbols.txt"
}

score_run() {
  bash "$ROOT/bench/score.sh" "$1" 2>/dev/null
}

score_field() {
  printf '%s' "$1" | jq -c "$2" 2>/dev/null
}

no_result() {
  grep -v '"type":"result"' "$1/claude.jsonl" >"$1/claude.jsonl.new"
  mv "$1/claude.jsonl.new" "$1/claude.jsonl"
}

d="$tmp/score/basic"
mkrun "$d"
out="$(score_run "$d")"
assert_eq "$?" 0 "score basic exits 0"
assert_eq "$(score_field "$out" .verdict)" '"pass"' "score basic verdict is pass"
assert_eq "$(score_field "$out" .capped)" false "score basic capped is false"
assert_eq "$(score_field "$out" .tests_passed)" 2 "score basic tests_passed is 2"
assert_eq "$(score_field "$out" .tests_total)" 2 "score basic tests_total is 2"
assert_eq "$(score_field "$out" .subagent_calls)" 2 "score basic subagent_calls is 2"
assert_eq "$(score_field "$out" ".cost_usd == $(jq .total_cost_usd "$FIXTURES/result-success.json")")" true "score basic cost_usd is fixture total_cost_usd"
assert_eq "$(score_field "$out" ".duration_s == $(jq '.duration_ms / 1000' "$FIXTURES/result-success.json")")" true "score basic duration_s is duration_ms/1000"
assert_eq "$(score_field "$out" .output_tokens)" "$(jq .usage.output_tokens "$FIXTURES/result-success.json")" "score basic output_tokens from usage"
assert_eq "$(score_field "$out" .cost_source)" '"cli-estimate"' "score basic cost_source is cli-estimate"

d="$tmp/score/nometa"
mkrun "$d"
rm "$d/meta.json"
score_run "$d" >/dev/null
assert_eq "$?" 2 "score without meta.json exits 2"

d="$tmp/score/partial"
mkrun "$d"
printf 't/one.test.sh\t0\nt/two.test.sh\t1\n' >"$d/oracle.exit"
out="$(score_run "$d")"
assert_eq "$(score_field "$out" .verdict)" '"partial"' "score one failing test is partial"
assert_eq "$(score_field "$out" .tests_failed)" '["t/two.test.sh"]' "score partial tests_failed lists t/two.test.sh"

d="$tmp/score/fail"
mkrun "$d"
printf 't/one.test.sh\t1\nt/two.test.sh\t1\n' >"$d/oracle.exit"
out="$(score_run "$d")"
assert_eq "$(score_field "$out" .verdict)" '"fail"' "score both failing tests is fail"

d="$tmp/score/refused"
mkrun "$d"
: >"$d/diff.patch"
out="$(score_run "$d")"
assert_eq "$(score_field "$out" .verdict)" '"refused"' "score empty diff is refused"

d="$tmp/score/noevents"
mkrun "$d"
: >"$d/claude.jsonl"
out="$(score_run "$d")"
assert_eq "$(score_field "$out" .verdict)" '"error"' "score empty claude.jsonl is error"

d="$tmp/score/codexoff"
mkrun "$d"
echo "codex unavailable" >"$d/error.txt"
echo skipped >"$d/claude.exit"
: >"$d/claude.jsonl"
out="$(score_run "$d")"
assert_eq "$(score_field "$out" .verdict)" '"error"' "score skipped run is error"
assert_eq "$(score_field "$out" .error)" '"codex unavailable"' "score skipped run error is codex unavailable"

d="$tmp/score/nopasadena"
mkrun "$d"
{
  jq -c '.plugins = []' "$FIXTURES/init.json"
  jq -c . "$FIXTURES/assistant.json"
  jq -c . "$FIXTURES/result-success.json"
} >"$d/claude.jsonl"
out="$(score_run "$d")"
assert_eq "$(score_field "$out" .verdict)" '"error"' "score plugin mode without pasadena is error"
assert_eq "$(score_field "$out" .error)" '"plugin mismatch"' "score plugin mode without pasadena is plugin mismatch"

d="$tmp/score/offwithpasadena"
mkrun "$d"
jq '.mode = "off" | .config = "baseline"' "$d/meta.json" >"$d/meta.json.new"
mv "$d/meta.json.new" "$d/meta.json"
out="$(score_run "$d")"
assert_eq "$(score_field "$out" .verdict)" '"error"' "score off mode with pasadena is error"
assert_eq "$(score_field "$out" .error)" '"plugin mismatch"' "score off mode with pasadena is plugin mismatch"

d="$tmp/score/elsewhere"
mkrun "$d"
{
  score_init /elsewhere
  jq -c . "$FIXTURES/assistant.json"
  jq -c . "$FIXTURES/result-success.json"
} >"$d/claude.jsonl"
out="$(score_run "$d")"
assert_eq "$(score_field "$out" .verdict)" '"error"' "score pasadena from /elsewhere is error"
assert_eq "$(score_field "$out" .error)" '"plugin mismatch"' "score pasadena from /elsewhere is plugin mismatch"

d="$tmp/score/timeout"
mkrun "$d"
echo 124 >"$d/claude.exit"
no_result "$d"
out="$(score_run "$d")"
assert_eq "$(score_field "$out" .capped)" true "score timeout is capped"
assert_eq "$(score_field "$out" .error)" '"timeout"' "score timeout error is timeout"
assert_eq "$(score_field "$out" .cost_usd)" null "score timeout cost_usd is null"
assert_eq "$(score_field "$out" .verdict)" '"pass"' "score timeout verdict follows the oracle"

d="$tmp/score/budget"
mkrun "$d"
echo 1 >"$d/claude.exit"
{
  score_init "$tmp/plugin"
  jq -c . "$FIXTURES/assistant.json"
  jq -c . "$FIXTURES/result-budget.json"
} >"$d/claude.jsonl"
out="$(score_run "$d")"
assert_eq "$(score_field "$out" .capped)" true "score result-budget is capped"
assert_eq "$(score_field "$out" .error)" '"budget"' "score result-budget error is budget"
assert_eq "$(score_field "$out" .output_tokens)" "$(jq '[.modelUsage[].outputTokens] | add' "$FIXTURES/result-budget.json")" "score result-budget output_tokens from modelUsage"

d="$tmp/score/budgeterr"
mkrun "$d"
echo 1 >"$d/claude.exit"
no_result "$d"
printf 'starting\nError: Exceeded USD budget (15)\n' >"$d/claude.err"
out="$(score_run "$d")"
assert_eq "$(score_field "$out" .capped)" true "score budget from claude.err is capped"
assert_eq "$(score_field "$out" .error)" '"budget"' "score budget from claude.err error is budget"
assert_eq "$(score_field "$out" .cost_usd)" 15 "score budget without result cost_usd is 15"

d="$tmp/score/dups"
mkrun "$d"
cat >"$d/diff.patch" <<'PATCH'
diff --git a/src/b.sh b/src/b.sh
new file mode 100644
--- /dev/null
+++ b/src/b.sh
@@ -0,0 +1,2 @@
+helper() {
+}
diff --git a/src/app.js b/src/app.js
new file mode 100644
--- /dev/null
+++ b/src/app.js
@@ -0,0 +1,2 @@
+function fresh() {
+}
PATCH
out="$(score_run "$d")"
assert_eq "$(score_field "$out" .dup_symbols)" 1 "score dup_symbols counts helper only"
assert_eq "$(score_field "$out" .diff_files)" 2 "score diff_files is 2"

d="$tmp/score/codex"
mkrun "$d"
echo "weekly_left=90 weekly_used=10" >"$d/codex-before.txt"
echo "weekly_left=86 weekly_used=14" >"$d/codex-after.txt"
out="$(score_run "$d")"
assert_eq "$(score_field "$out" .codex_usage)" 4 "score codex_usage is after minus before"

d="$tmp/score/nocodex"
mkrun "$d"
out="$(score_run "$d")"
assert_eq "$(score_field "$out" .codex_usage)" null "score codex_usage is null without files"

d="$tmp/score/warning"
mkrun "$d"
{
  echo "warning: x"
  cat "$d/claude.jsonl"
} >"$d/claude.jsonl.new"
mv "$d/claude.jsonl.new" "$d/claude.jsonl"
out="$(score_run "$d")"
assert_eq "$?" 0 "score with a non-JSON line exits 0"
assert_eq "$(score_field "$out" .verdict)" '"pass"' "score with a non-JSON line still parses"

d="$tmp/score/stable"
mkrun "$d"
first="$(score_run "$d")"
second="$(score_run "$d")"
assert_eq "$([ -n "$first" ] && [ "$first" = "$second" ] && echo same)" same "score is byte-for-byte stable across runs"

d="$tmp/score/scalars"
mkrun "$d"
{
  echo 42
  score_init "$tmp/plugin"
  echo '"x"'
  jq -c . "$FIXTURES/assistant.json"
  echo '[1]'
  jq -c . "$FIXTURES/assistant.json"
  echo 42
  jq -c . "$FIXTURES/result-success.json"
  echo '[1]'
} >"$d/claude.jsonl"
out="$(score_run "$d")"
assert_eq "$(score_field "$out" ".cost_usd == $(jq .total_cost_usd "$FIXTURES/result-success.json")")" true "score with scalar lines keeps fixture cost_usd"
assert_eq "$(score_field "$out" .subagent_calls)" 2 "score with scalar lines subagent_calls is 2"
assert_eq "$(score_field "$out" '.plugins | length > 0')" true "score with scalar lines plugins non-empty"
assert_eq "$(score_field "$out" .verdict)" '"pass"' "score with scalar lines verdict is pass"

printf 'task\ttest\tcheck\tstatus\treason\n' >"$BENCH_CHECKS"
printf 't1\tt/c.test.sh\ta\ttarget\t\nt1\tt/c.test.sh\tb\ttarget\t\nt1\tt/c.test.sh\t<tree>/x\ttarget\t\n' >>"$BENCH_CHECKS"

d="$tmp/score/checks"
mkrun "$d"
printf 't/c.test.sh\t1\n' >"$d/oracle.exit"
printf 'ok — b\n  FAIL — a\n  FAIL — %s/tree/x\nFAILED: 2\n' "$d" >"$d/oracle-1.log"
out="$(score_run "$d")"
assert_eq "$(score_field "$out" .checks_total)" 3 "score checks_total counts target rows of the task"
assert_eq "$(score_field "$out" .checks_passed)" 1 "score checks_passed matches FAIL lines with the tree path as <tree>"
assert_eq "$(score_field "$out" .score)" 0.33 "score is checks_passed/checks_total to two places"
assert_eq "$(score_field "$out" .verdict)" '"partial"' "score verdict follows the checks"
assert_eq "$(score_field "$out" .bench_rev)" "\"$(bash -c 'source "$1/bench/lib.sh"; bench_rev' _ "$ROOT")\"" "score bench_rev equals lib.sh bench_rev"

d="$tmp/score/unfinished"
mkrun "$d"
printf 't/c.test.sh\t1\n' >"$d/oracle.exit"
printf 'ok — b\nsyntax error near x\n' >"$d/oracle-1.log"
out="$(score_run "$d")"
assert_eq "$(score_field "$out" .checks_passed)" 0 "score log without a summary line passes no checks"

d="$tmp/score/nochecks"
mkrun "$d"
jq '.task = "t2"' "$d/meta.json" >"$d/meta.json.new"
mv "$d/meta.json.new" "$d/meta.json"
out="$(score_run "$d")"
assert_eq "$(score_field "$out" .checks_total)" 0 "score task without checks rows has checks_total 0"
assert_eq "$(score_field "$out" .score)" null "score task without checks rows has score null"
assert_eq "$(score_field "$out" .verdict)" '"pass"' "score task without checks rows keeps verdict by exit codes"

d="$tmp/score/checks"
out="$(bash "$ROOT/bench/score.sh" "$d/" 2>/dev/null)"
assert_eq "$(score_field "$out" .checks_passed)" 1 "score run path with a trailing slash still maps the tree path to <tree>"
out="$(cd "$tmp/score" && bash "$ROOT/bench/score.sh" checks 2>/dev/null)"
assert_eq "$(score_field "$out" .checks_passed)" 1 "score relative run path still maps the tree path to <tree>"

ln -s "$tmp/score" "$tmp/score-link"
d="$tmp/score/checkslink"
mkrun "$d"
printf 't/c.test.sh\t1\n' >"$d/oracle.exit"
printf 'ok — b\n  FAIL — a\n  FAIL — %s/tree/x\nFAILED: 2\n' "$tmp/score-link/checkslink" >"$d/oracle-1.log"
out="$(bash "$ROOT/bench/score.sh" "$tmp/score-link/checkslink" 2>/dev/null)"
assert_eq "$(score_field "$out" .checks_passed)" 1 "score run path through a symlink maps the logical tree path to <tree>"

d="$tmp/score/checkserror"
mkrun "$d"
printf 't/c.test.sh\t1\n' >"$d/oracle.exit"
printf 'ok — b\n  FAIL — a\n  FAIL — %s/tree/x\nFAILED: 2\n' "$d" >"$d/oracle-1.log"
echo "codex unavailable" >"$d/error.txt"
echo skipped >"$d/claude.exit"
: >"$d/claude.jsonl"
out="$(score_run "$d")"
assert_eq "$(score_field "$out" .verdict)" '"error"' "score error run with checks rows is error"
assert_eq "$(score_field "$out" .score)" null "score error run with checks rows has score null"

d="$tmp/score/checksrefused"
mkrun "$d"
: >"$d/diff.patch"
printf 't/c.test.sh\t1\n' >"$d/oracle.exit"
printf '  FAIL — a\n  FAIL — b\n  FAIL — %s/tree/x\nFAILED: 3\n' "$d" >"$d/oracle-1.log"
out="$(score_run "$d")"
assert_eq "$(score_field "$out" .verdict)" '"refused"' "score refused run with checks rows is refused"
assert_eq "$(score_field "$out" .score)" 0 "score refused run with checks rows has score 0"

printf 'task\ttest\tcheck\tstatus\treason\n' >"$BENCH_CHECKS"
printf 't1\tt/c.test.sh\ttab name\ttarget\t\n' >>"$BENCH_CHECKS"

d="$tmp/score/checkstab"
mkrun "$d"
printf 't/c.test.sh\t1\n' >"$d/oracle.exit"
printf '  FAIL — tab\tname\nFAILED: 1\n' >"$d/oracle-1.log"
out="$(score_run "$d")"
assert_eq "$(score_field "$out" .checks_total)" 1 "score check name with a tab has one target"
assert_eq "$(score_field "$out" .checks_passed)" 0 "score FAIL line with a tab matches the check written with a space"

rm -f "$BENCH_CHECKS"

d="$tmp/score/offquiet"
mkrun "$d"
jq '.mode = "off" | .config = "baseline" | .plugin_path = ""' "$d/meta.json" >"$d/meta.json.new"
mv "$d/meta.json.new" "$d/meta.json"
{
  jq -c '.plugins = []' "$FIXTURES/init.json"
  jq -c . "$FIXTURES/assistant.json"
  jq -c . "$FIXTURES/result-success.json"
} >"$d/claude.jsonl"
err="$(bash "$ROOT/bench/score.sh" "$d" 2>&1 >/dev/null)"
assert_eq "$err" "" "score off mode with empty plugin_path writes nothing to stderr"
