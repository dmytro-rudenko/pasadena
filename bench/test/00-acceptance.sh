echo "== acceptance: plugin run =="
fresh_bench
FAKE_WRITES="feature.txt=done feature2.txt=done" bash "$ROOT/bench/run.sh" t1 plugin 1 >/dev/null 2>&1
assert_eq "$?" 0 "run.sh t1 plugin 1 exits 0"
assert_eq "$(last_run .verdict)" pass "plugin run verdict is pass"
for field in cost_usd duration_s output_tokens; do
  assert_eq "$(last_run ".$field" | jq -e '. > 0' 2>/dev/null)" true "plugin run $field > 0"
done
assert_eq "$(last_run '.plugins[] | select(.name=="pasadena") | .path')" "$(realpath "$tmp/plugin")" "plugin run loads pasadena from BENCH_PLUGIN"

echo "== acceptance: baseline run =="
FAKE_WRITES="feature.txt=done feature2.txt=done" bash "$ROOT/bench/run.sh" t1 baseline 1 >/dev/null 2>&1
assert_eq "$?" 0 "run.sh t1 baseline 1 exits 0"
assert_eq "$(last_run '[.plugins[]|select(.name=="pasadena")]|length')" 0 "baseline run has no pasadena plugin"
assert_eq "$(last_run .verdict)" pass "baseline run verdict is pass"

echo "== acceptance: calibrate =="
printf 't3\t%s\tspec.md\t%s\tt/one.test.sh\t0\n' "$ORACLE" "$ORACLE" >>"$tmp/tasks.tsv"
bash "$ROOT/bench/calibrate.sh" >/dev/null 2>&1
assert_eq "$?" 0 "calibrate.sh exits 0"
calibration="$(cat "$BENCH_DIR/calibration.log" 2>/dev/null)"
assert_contains "$calibration" "t3" "calibration.log names t3"
assert_contains "$calibration" "passes on base" "calibration.log explains t3 passes on base"
assert_eq "$(awk -F'\t' '$1=="t3" {print $6}' "$tmp/tasks.tsv")" x "t3 holdout is x"
grep -v "^t3"$'\t' "$tmp/tasks.tsv" >"$tmp/tasks.tsv.new"
mv "$tmp/tasks.tsv.new" "$tmp/tasks.tsv"

echo "== acceptance: report =="
out="$(bash "$ROOT/bench/report.sh" --tasks t1 --next "--tasks t1 --reps 1" --out "$BENCH_DIR/reports/01-dry.md" 2>/dev/null)"
assert_contains "$out" "| baseline |" "report has a baseline row"
assert_contains "$out" "| plugin |" "report has a plugin row"
assert_contains "$out" "## Runs" "report has a Runs section"
assert_eq "$(grep -cF '| t1 |' <<<"$out")" 2 "report has one row per t1 run"
assert_contains "$out" "## Spend" "report has a Spend section"
assert_contains "$out" "## Forecast" "report has a Forecast section"
assert_contains "$out" "pending runs: 3" "report forecasts 3 pending runs"
assert_eq "$([ -f "$BENCH_DIR/reports/01-dry.md" ] && echo exists)" exists "report written to --out"
assert_eq "$(cat "$BENCH_DIR/reports/01-dry.md" 2>/dev/null)" "$out" "--out file equals stdout"
