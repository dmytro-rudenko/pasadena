echo "== revision =="
fresh_bench
rm -f "$BENCH_CHECKS"

rrepo="$tmp/rrepo"
git init -q "$rrepo"
printf 'alpha "beta"\n' >"$rrepo/spec.md"
git -C "$rrepo" add -A
gitc -C "$rrepo" commit -qm base
RBASE="$(git -C "$rrepo" rev-parse HEAD)"
mkdir -p "$rrepo/t"
echo amended >>"$rrepo/spec.md"
echo alpha >"$rrepo/feature.txt"
echo gamma >"$rrepo/literal.txt"
cat >"$rrepo/t/c.test.sh" <<'CTEST'
fails=0
check() {
  local name="$1"
  shift
  if "$@" 2>/dev/null; then
    echo "  ok  — $name"
  else
    echo "  FAIL — $name"
    fails=$((fails + 1))
  fi
}
check 'feature: missing "alpha"' grep -qx alpha feature.txt
check 'literal: missing "gamma"' grep -qx gamma literal.txt
check "path: $(pwd)/feature.txt absent" test -f feature.txt
echo
if [ "$fails" -gt 0 ]; then
  echo "FAILED: $fails"
  exit 1
fi
echo "All checks passed."
CTEST
git -C "$rrepo" add -A
gitc -C "$rrepo" commit -qm oracle
RORACLE="$(git -C "$rrepo" rev-parse HEAD)"

rtasks="$tmp/rtasks.tsv"
{
  printf 'id\tbase\tspec\toracle\ttests\tholdout\n'
  printf 'r1\t%s\tspec.md\t%s\tt/c.test.sh\t0\n' "$RBASE" "$RORACLE"
  printf 'r0\t%s\tspec.md\t%s\tt/c.test.sh\t0\n' "$RORACLE" "$RORACLE"
} >"$rtasks"

rcal() {
  BENCH_REPO="$rrepo" BENCH_TASKS="$rtasks" bash "$ROOT/bench/calibrate.sh" >/dev/null 2>&1
}
check_row() {
  awk -F'\t' -v t="$1" -v c="$2" '$1 == t && $3 == c { print $4 "|" $5 }' "$BENCH_CHECKS" 2>/dev/null
}

rcal
assert_eq "$?" 0 "revision: calibrate.sh exits 0"
assert_eq "$(grep -cxF "$(printf 'r1\tt/c.test.sh\tfeature: missing "alpha"\ttarget\t')" "$BENCH_CHECKS" 2>/dev/null)" 1 "revision: feature check is an automatic target"
assert_eq "$(check_row r1 'literal: missing "gamma"')" 'excluded|literal not in spec: "gamma"' "revision: literal check absent from spec is excluded"
assert_eq "$(check_row r1 'path: <tree>/feature.txt absent')" 'target|' "revision: tree path is normalised to <tree> in a target"
assert_eq "$(awk -F'\t' '$1 == "r0" { print $6 }' "$rtasks")" x "revision: r0 with base=oracle is excluded"
assert_contains "$(cat "$BENCH_DIR/calibration.log" 2>/dev/null)" " r0 excluded:" "revision: calibration.log explains r0"

awk -F'\t' -v OFS='\t' '$3 == "path: <tree>/feature.txt absent" { $4 = "excluded"; $5 = "manual: test" } 1' "$BENCH_CHECKS" >"$tmp/checks.new" 2>/dev/null
mv "$tmp/checks.new" "$BENCH_CHECKS"
rcal
assert_eq "$(check_row r1 'path: <tree>/feature.txt absent')" 'excluded|manual: test' "revision: recalibration keeps the manual decision without a duplicate"

rrev="$(source "$ROOT/bench/lib.sh"; plugin_rev)"
rcell="$BENCH_DIR/runs/$rrev/r1/plugin/1"
FAKE_WRITES="feature.txt=alpha" BENCH_REPO="$rrepo" BENCH_TASKS="$rtasks" bash "$ROOT/bench/run.sh" r1 plugin 1 >/dev/null 2>&1
assert_eq "$(last_run .checks_total)" 1 "revision: plugin run has checks_total 1"
assert_eq "$(last_run .checks_passed)" 1 "revision: plugin run has checks_passed 1"
assert_eq "$(last_run .score)" 1 "revision: plugin run has score 1"
assert_eq "$(last_run .verdict)" pass "revision: plugin run passes on its targets"
brev="$(last_run .bench_rev)"
assert_eq "$([[ "$brev" =~ ^[0-9a-f]{12}$ ]] && echo yes || echo no)" yes "revision: bench_rev is 12 hex characters"
assert_eq "$brev" "$(cat "$rtasks" "$BENCH_CHECKS" 2>/dev/null | sha256sum | cut -c1-12)" "revision: bench_rev hashes tasks and checks"

assert_contains "$(cat "$FAKE_LOG.spec" 2>/dev/null)" amended "revision: agent sees the oracle spec"
assert_eq "$([ -f "$rcell/diff.patch" ] && ! grep -q 'spec.md' "$rcell/diff.patch" && echo clean || echo dirty)" clean "revision: diff.patch leaves out spec.md"
assert_eq "$([ -n "$(jq -r '.ub_tools.dryer // empty' "$rcell/meta.json" 2>/dev/null)" ] && echo yes || echo no)" yes "revision: meta.json records ub_tools.dryer"

FAKE_WRITES="other.txt=x" BENCH_REPO="$rrepo" BENCH_TASKS="$rtasks" bash "$ROOT/bench/run.sh" r1 baseline 1 >/dev/null 2>"$tmp/r.err"
assert_eq "$(grep 'invalid value' "$tmp/r.err")" "" "revision: run.sh stderr has no invalid value"
assert_eq "$(last_run .verdict)" fail "revision: baseline run without the feature fails"
assert_eq "$(last_run .checks_passed)" 0 "revision: baseline run has checks_passed 0"

rreport="$(BENCH_TASKS="$rtasks" bash "$ROOT/bench/report.sh" --tasks r1 2>/dev/null)"
assert_contains "$rreport" "score mean" "revision: report has a score mean column"
assert_contains "$(grep -E '^\| r1 \| plugin \|' <<<"$rreport")" "| 1/1 |" "revision: report run row shows checks 1/1"

tail -1 "$BENCH_DIR/runs.jsonl" | jq -c 'del(.bench_rev) | .config = "plugin-haiku"' >>"$BENCH_DIR/runs.jsonl"
rreport="$(BENCH_TASKS="$rtasks" bash "$ROOT/bench/report.sh" 2>/dev/null)"
assert_eq "$(grep -c 'plugin-haiku' <<<"$rreport")" 0 "revision: report drops runs without the current bench_rev"
rpending="$(BENCH_TASKS="$rtasks" bash "$ROOT/bench/matrix.sh" --tasks r1 --configs plugin --reps 1 --pending 2>&1)"
assert_eq "$?" 0 "revision: matrix --pending exits 0"
assert_eq "$rpending" "" "revision: matrix finds the run with the current bench_rev"
assert_eq "$(BENCH_TASKS="$rtasks" bash "$ROOT/bench/matrix.sh" --tasks r1 --configs plugin-haiku --reps 1 --pending 2>/dev/null)" "$(printf 'r1\tplugin-haiku\t1')" "revision: matrix keeps a run without bench_rev pending"

fresh_bench
rm -f "$BENCH_CHECKS"
