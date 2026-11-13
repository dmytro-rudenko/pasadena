echo "== report =="

brev="$(source "$ROOT/bench/lib.sh"; bench_rev)"

report_row() {
  jq -nc --arg t "$1" --arg c "$2" --argjson r "$3" --arg p "$4" --arg ts "$5" \
    --arg v "$6" --argjson cost "$7" --argjson dur "$8" --arg brev "$brev" \
    --argjson extra "${9:-{\}}" '{
    task:$t, config:$c, rep:$r, model:"opus", plugin_rev:$p, ts:$ts, verdict:$v,
    capped:false, tests_passed:(if $v=="pass" then 2 else 0 end), tests_total:2,
    tests_failed:(if $v=="pass" then [] else ["t/one.test.sh","t/two.test.sh"] end),
    input_tokens:100, cache_read:10, cache_write:5, output_tokens:50,
    cost_usd:$cost, cost_source:"result", duration_s:$dur, num_turns:7,
    plugins:["pasadena"], subagent_calls:2, diff_files:1, diff_lines:12,
    dup_symbols:0, codex_usage:0, error:null,
    bench_rev:$brev, score:null, checks_passed:0, checks_total:0} + $extra'
}

fresh_bench
mkdir -p "$BENCH_DIR"
{
  report_row t1 plugin 1 zzz 2026-11-01T00:00:00Z pass 4 40
  report_row t1 baseline 1 old 2026-11-02T00:00:00Z fail 0 30 '{"score":1,"checks_passed":3,"checks_total":3}'
  report_row t2 baseline 1 old 2026-11-02T01:00:00Z fail 0 30 '{"score":0,"checks_passed":0,"checks_total":3}'
  report_row t1 plugin 1 aaa 2026-11-03T00:00:00Z pass 1 100 '{"score":0.5,"checks_passed":1,"checks_total":2}'
  report_row t1 plugin 2 aaa 2026-11-03T01:00:00Z pass 2 100 '{"score":0,"checks_passed":0,"checks_total":3}'
  report_row t2 plugin 1 aaa 2026-11-03T02:00:00Z pass 3 100
  report_row t2 plugin 2 aaa 2026-11-03T03:00:00Z fail 10 100 '{"score":0.25,"checks_passed":1,"checks_total":4}'
} >"$BENCH_DIR/runs.jsonl"

report() {
  env -u BENCH_BUDGET -u BENCH_TIMEOUT bash "$ROOT/bench/report.sh" "$@" 2>/dev/null
}

section() {
  awk -v h="$1" '$0 == h {on=1; next} /^## / {on=0} on' <<<"$2"
}

col() {
  awk -F'|' -v name="$2" -v row="$3" '
    /^\| (cell|task) \|/ {for (i = 2; i < NF; i++) {h = $i; gsub(/^ +| +$/, "", h); if (h == name) c = i}; next}
    c && index($0, row) == 1 {v = $c; gsub(/^ +| +$/, "", v); print v; exit}' <<<"$1"
}

out="$(report)"
assert_contains "$out" "| cell | runs | score mean | pass |" "report: Cells header puts score mean after runs"
assert_contains "$out" "| plugin | 4 | 0.25 | 75% |" "report: plugin cell has 4 runs, score mean 0.25, 75% pass"
assert_contains "$out" "| baseline | 2 | 0.50 |" "report: baseline score mean of 1 and 0 is 0.50"
assert_contains "$out" "baseline: pass -3 vs plugin (noise)" "report: baseline pass delta -3 is noise"
assert_contains "$out" "baseline: score +0.25 vs plugin (noise)" "report: baseline score delta +0.25 is noise under 3 runs"
plugin_p95="$(col "$(section '## Cells' "$out")" "cost p95" "| plugin |")"
assert_contains "$plugin_p95" "10.00" "report: plugin cost p95 is 10.00"
assert_eq "$(section '## Runs' "$out" | grep -cE '^\| t[12] \|')" 6 "report: Runs has 6 data rows"
assert_eq "$(section '## Runs' "$out" | grep -c '| failed tests |')" 0 "report: Runs has no failed tests column"
assert_eq "$(col "$(section '## Runs' "$out")" checks "| t2 | plugin | 2 |")" "1/4" "report: Runs checks shows 1/4"
assert_eq "$(col "$(section '## Runs' "$out")" checks "| t1 | baseline | 1 |")" "3/3" "report: Runs checks shows 3/3"
assert_eq "$(col "$(section '## Runs' "$out")" checks "| t2 | plugin | 1 |")" "-" "report: Runs checks is - when checks_total is 0"
assert_contains "$out" "$BENCH_DIR/runs/aaa/t2/plugin/2" "report: Runs links the run directory"
assert_contains "$(section '## Spend' "$out")" 'selection: $16.00' "report: Spend selection is \$16.00 for plugin+baseline"
assert_contains "$(section '## Spend' "$out")" 'all runs: $20.00' "report: Spend all runs is \$20.00"

out="$(report --rev zzz)"
assert_contains "$out" "| plugin | 1 | - |" "report --rev zzz: plugin cell has 1 run and no score mean"

out="$(report --configs baseline)"
assert_eq "$([[ "$out" == *"| baseline |"* && "$out" != *"| plugin |"* ]] && echo baseline-only)" baseline-only "report --configs baseline: no plugin row"

pending="$(bash "$ROOT/bench/matrix.sh" --tasks t1 --reps 1 --pending 2>/dev/null | wc -l | tr -d ' ')"
out="$(report --next "--tasks t1 --reps 1")"
forecast="$(section '## Forecast' "$out")"
assert_contains "$forecast" "pending runs: $pending" "report --next: pending runs equals matrix --pending ($pending)"
haiku="$(grep -F '| plugin-haiku |' <<<"$forecast")"
assert_contains "$haiku" "(upper bound)" "report --next: cell without runs is an upper bound"
assert_contains "$haiku" "15.00" "report --next: cell without runs costs BENCH_BUDGET 15.00"

out="$(report --out "$BENCH_DIR/reports/sub/r.md")"
assert_eq "$([ -f "$BENCH_DIR/reports/sub/r.md" ] && echo exists)" exists "report --out creates the file"
assert_eq "$(cat "$BENCH_DIR/reports/sub/r.md" 2>/dev/null || echo missing)" "$out" "report --out file equals stdout"

fresh_bench
mkdir -p "$BENCH_DIR"
{
  report_row t1 plugin 1 aaa 2026-11-03T00:00:00Z pass 1 100 '{"score":1}'
  report_row t1 plugin 2 aaa 2026-11-03T01:00:00Z pass 1 100 '{"score":1}'
  report_row t1 plugin 3 aaa 2026-11-03T02:00:00Z pass 1 100 '{"score":1}'
  report_row t1 plugin 4 aaa 2026-11-03T03:00:00Z pass 1 100 '{"score":0,"bench_rev":"000000000000"}'
  report_row t1 plugin 1 bbb 2026-11-04T00:00:00Z pass 1 100 '{"score":0,"bench_rev":"000000000000"}'
  report_row t1 baseline 1 old 2026-11-02T00:00:00Z pass 1 100 '{"score":1}'
  report_row t1 baseline 2 old 2026-11-02T01:00:00Z fail 1 100 '{"score":0.5}'
  report_row t1 baseline 3 old 2026-11-02T02:00:00Z fail 1 100 '{"score":0.5}'
  report_row t1 baseline 4 old 2026-11-02T03:00:00Z fail 1 100 '{"score":0,"bench_rev":"000000000000"}'
} >"$BENCH_DIR/runs.jsonl"

out="$(report)"
assert_eq "$(grep -F 'baseline: score' <<<"$out")" "baseline: score -0.33 vs plugin" "report: score delta -0.33 has no noise with 3 runs in both cells"
assert_contains "$out" "| plugin | 3 | 1.00 |" "report: plugin cell drops runs with another bench_rev"
assert_contains "$out" "| baseline | 3 | 0.67 |" "report: baseline cell drops runs with another bench_rev"
assert_eq "$(grep -c 'runs/bbb/' <<<"$out")" 0 "report: a newer plugin_rev with another bench_rev is not the latest"
