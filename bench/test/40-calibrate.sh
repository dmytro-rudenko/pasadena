echo "== calibrate =="
fresh_bench
cal="$tmp/cal.tsv"
cal_header="$(head -1 "$tmp/tasks.tsv")"
{
  printf '%s\n' "$cal_header"
  printf 't4\t%s\tspec.md\t%s\tt/missing.test.sh,t/one.test.sh\t0\n' "$BASE" "$ORACLE"
  printf 't3\t%s\tspec.md\t%s\tt/one.test.sh\t0\n' "$ORACLE" "$ORACLE"
  printf 't1\t%s\tspec.md\t%s\tt/one.test.sh,t/two.test.sh\t0\n' "$BASE" "$ORACLE"
  printf 't5\t%s\tspec.md\t%s\tt/missing.test.sh\t0\n' "$BASE" "$ORACLE"
  printf 't2\t%s\tspec.md\t%s\tt/one.test.sh\t1\n' "$ORACLE" "$ORACLE"
} >"$cal"

cal_field() {
  awk -F'\t' -v id="$1" -v col="$2" '$1 == id { print $col }' "$cal"
}

BENCH_TASKS="$cal" bash "$ROOT/bench/calibrate.sh" >/dev/null 2>&1
assert_eq "$?" 0 "calibrate.sh exits 0"
cal_log="$(cat "$BENCH_DIR/calibration.log" 2>/dev/null)"

assert_eq "$(head -1 "$cal")" "$cal_header" "tasks file keeps its header"

assert_eq "$(cal_field t1 5)" "t/one.test.sh,t/two.test.sh" "t1 keeps both tests"
assert_contains "$cal_log" " t1 kept" "calibration.log records t1 kept"

assert_eq "$(cal_field t4 5)" "t/one.test.sh" "t4 drops the test that fails on oracle"
assert_eq "$(cal_field t4 6)" 0 "t4 stays holdout 0"
assert_contains "$cal_log" " t4 dropped-test t/missing.test.sh: fails on oracle" "calibration.log records t4 dropped test"

assert_eq "$(cal_field t5 6)" x "t5 with no tests left is excluded"
assert_contains "$cal_log" " t5 excluded: no tests left" "calibration.log explains t5 has no tests left"

assert_eq "$(cal_field t3 6)" x "t3 passing on base is excluded"
assert_contains "$cal_log" " t3 excluded: passes on base" "calibration.log explains t3 passes on base"

assert_eq "$(cal_field t2 6)" x "holdout t2 passing on base is excluded"
assert_contains "$cal_log" " t2 excluded: passes on base" "calibration.log explains t2 passes on base"
assert_eq "$(cal_field t1 6)" 1 "t1 becomes the holdout"
assert_contains "$cal_log" "holdout moved to t1" "calibration.log records holdout moved to t1"
