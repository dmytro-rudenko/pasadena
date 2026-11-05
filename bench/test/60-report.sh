echo "== report =="

report_row() {
  jq -nc --arg t "$1" --arg c "$2" --argjson r "$3" --arg p "$4" --arg ts "$5" \
    --arg v "$6" --argjson cost "$7" --argjson dur "$8" '{
    task:$t, config:$c, rep:$r, model:"opus", plugin_rev:$p, ts:$ts, verdict:$v,
    capped:false, tests_passed:(if $v=="pass" then 2 else 0 end), tests_total:2,
    tests_failed:(if $v=="pass" then [] else ["t/one.test.sh","t/two.test.sh"] end),
    input_tokens:100, cache_read:10, cache_write:5, output_tokens:50,
    cost_usd:$cost, cost_source:"result", duration_s:$dur, num_turns:7,
    plugins:["pasadena"], subagent_calls:2, diff_files:1, diff_lines:12,
    dup_symbols:0, codex_usage:0, error:null}'
}

fresh_bench
mkdir -p "$BENCH_DIR"
{
  report_row t1 plugin 1 zzz 2026-11-01T00:00:00Z pass 4 40
  report_row t1 baseline 1 old 2026-11-02T00:00:00Z fail 0 30
  report_row t2 baseline 1 old 2026-11-02T01:00:00Z fail 0 30
  report_row t1 plugin 1 aaa 2026-11-03T00:00:00Z pass 1 100
  report_row t1 plugin 2 aaa 2026-11-03T01:00:00Z pass 2 100
  report_row t2 plugin 1 aaa 2026-11-03T02:00:00Z pass 3 100
  report_row t2 plugin 2 aaa 2026-11-03T03:00:00Z fail 10 100
} >"$BENCH_DIR/runs.jsonl"

report() {
  env -u BENCH_BUDGET -u BENCH_TIMEOUT bash "$ROOT/bench/report.sh" "$@" 2>/dev/null
}

section() {
  awk -v h="$1" '$0 == h {on=1; next} /^## / {on=0} on' <<<"$2"
}

out="$(report)"
assert_contains "$out" "| plugin | 4 | 75% |" "report: plugin cell has 4 runs, 75% pass"
assert_contains "$out" "baseline: pass -3 vs plugin (noise)" "report: baseline pass delta -3 is noise"
plugin_p95="$(grep -F '| plugin |' <<<"$(section '## Cells' "$out")" | head -1 | awk -F'|' '{gsub(/ /,"",$11); print $11}')"
assert_contains "$plugin_p95" "10.00" "report: plugin cost p95 is 10.00"
assert_eq "$(section '## Runs' "$out" | grep -cE '^\| t[12] \|')" 6 "report: Runs has 6 data rows"
assert_contains "$out" "$BENCH_DIR/runs/aaa/t2/plugin/2" "report: Runs links the run directory"
assert_contains "$(section '## Spend' "$out")" 'selection: $16.00' "report: Spend selection is \$16.00 for plugin+baseline"
assert_contains "$(section '## Spend' "$out")" 'all runs: $20.00' "report: Spend all runs is \$20.00"

out="$(report --rev zzz)"
assert_contains "$out" "| plugin | 1 |" "report --rev zzz: plugin cell has 1 run"

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
