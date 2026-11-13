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

fresh_bench
rm -f "$BENCH_CHECKS"
crepo="$tmp/crepo"
git init -q "$crepo"
printf '# spec\nfeature banner\n' >"$crepo/spec.md"
git -C "$crepo" add -A
gitc -C "$crepo" commit -qm base
CBASE="$(git -C "$crepo" rev-parse HEAD)"
mkdir -p "$crepo/t"
echo amended >>"$crepo/spec.md"
echo omega >"$crepo/omega.txt"
echo ready >"$crepo/feature.txt"
echo zeta-banner >"$crepo/banner.txt"
cat >"$crepo/t/x1.test.sh" <<'XTEST'
fails=0
if grep -qx omega omega.txt 2>/dev/null; then
  echo '  ok  — omega: missing "omega"'
else
  echo '  FAIL — omega: missing "omega"'
  fails=$((fails + 1))
fi
echo
if [ "$fails" -gt 0 ]; then
  echo "FAILED: $fails"
  exit 1
fi
echo "All checks passed."
XTEST
cat >"$crepo/t/x2.test.sh" <<'XTEST'
fails=0
if [ -f feature.txt ]; then
  echo '  ok  — feature: present'
else
  echo '  FAIL — feature: present'
  fails=$((fails + 1))
fi
if grep -q zeta-banner banner.txt 2>/dev/null; then
  echo '  ok  — banner: text'
else
  echo '  FAIL — banner: text'
  echo '        expected substring: zeta-banner'
  echo '        got: '
  fails=$((fails + 1))
fi
echo
if [ "$fails" -gt 0 ]; then
  echo "FAILED: $fails"
  exit 1
fi
echo "All checks passed."
XTEST
git -C "$crepo" add -A
gitc -C "$crepo" commit -qm oracle
CORACLE="$(git -C "$crepo" rev-parse HEAD)"

ctasks="$tmp/ctasks.tsv"
{
  printf 'id\tbase\tspec\toracle\ttests\tholdout\n'
  printf 'x1\t%s\tspec.md\t%s\tt/x1.test.sh\t0\n' "$CBASE" "$CORACLE"
  printf 'x2\t%s\tspec.md\t%s\tt/x2.test.sh\t1\n' "$CBASE" "$CORACLE"
} >"$ctasks"

BENCH_REPO="$crepo" BENCH_TASKS="$ctasks" bash "$ROOT/bench/calibrate.sh" >/dev/null 2>&1
assert_eq "$?" 0 "checks: calibrate.sh exits 0"
cal_log="$(cat "$BENCH_DIR/calibration.log" 2>/dev/null)"
ccheck_row() {
  awk -F'\t' -v t="$1" -v c="$2" '$1 == t && $3 == c { print $4 "|" $5 }' "$BENCH_CHECKS" 2>/dev/null
}

assert_eq "$(head -1 "$BENCH_CHECKS" 2>/dev/null)" "$(printf 'task\ttest\tcheck\tstatus\treason')" "checks: checks.tsv header"

assert_eq "$(awk -F'\t' '$1 == "x1" { print $6 }' "$ctasks")" x "checks: x1 with only out-of-spec literals is excluded"
assert_contains "$cal_log" " x1 excluded: no target checks" "checks: calibration.log explains x1 has no target checks"
assert_eq "$(awk -F'\t' '$1 == "x1"' "$BENCH_CHECKS" 2>/dev/null)" "" "checks: excluded task x1 has no rows in checks.tsv"

assert_eq "$(awk -F'\t' '$1 == "x2" { print $6 }' "$ctasks")" 1 "checks: x2 with a target stays the holdout"
assert_eq "$(ccheck_row x2 'feature: present')" 'target|' "checks: x2 check without literals is a target"
assert_eq "$(ccheck_row x2 'banner: text')" 'excluded|literal not in spec: "zeta-banner"' "checks: expected substring literal absent from spec is excluded"
assert_contains "$cal_log" ' x2 check-excluded t/x2.test.sh: banner: text: literal not in spec: "zeta-banner"' "checks: calibration.log records the excluded banner check"

unlogged=0
while IFS=$'\t' read -r ct ctest ccheck cstatus creason; do
  [ "$cstatus" = excluded ] || continue
  [[ "$cal_log" == *" $ct check-excluded $ctest: $ccheck: $creason"* ]] || unlogged=$((unlogged + 1))
done < <(tail -n +2 "$BENCH_CHECKS" 2>/dev/null)
assert_eq "$unlogged" 0 "checks: every excluded checks.tsv row is in calibration.log"

banner_logged() {
  grep -cF ' x2 check-excluded t/x2.test.sh: banner: text:' "$BENCH_DIR/calibration.log" 2>/dev/null
}
banner_before="$(banner_logged)"
awk -F'\t' -v OFS='\t' '$1 == "x2" && $3 == "banner: text" { $4 = "target"; $5 = "manual: spec implies it" } 1' "$BENCH_CHECKS" >"$tmp/checks.new" 2>/dev/null
mv "$tmp/checks.new" "$BENCH_CHECKS"
BENCH_REPO="$crepo" BENCH_TASKS="$ctasks" bash "$ROOT/bench/calibrate.sh" >/dev/null 2>&1
assert_eq "$(grep -cxF "$(printf 'x2\tt/x2.test.sh\tbanner: text\ttarget\tmanual: spec implies it')" "$BENCH_CHECKS" 2>/dev/null)" 1 "checks: manual target overrides the automatic exclusion once"
assert_eq "$(awk -F'\t' '$1 == "x2" && $3 == "banner: text"' "$BENCH_CHECKS" 2>/dev/null | wc -l)" 1 "checks: banner check has a single row after recalibration"
assert_eq "$(banner_logged)" "$banner_before" "checks: recalibration logs no check-excluded line for the manual target"

fresh_bench
rm -f "$BENCH_CHECKS"
