echo "== matrix =="

matrix_rev="$(git -C "$tmp/plugin" rev-parse --short HEAD)"
matrix_brev="$(source "$ROOT/bench/lib.sh"; bench_rev)"
matrix_calls="$tmp/matrix.calls"
{
  printf '#!/usr/bin/env bash\ncalls=%q\nrev=%q\nbrev=%q\n' "$matrix_calls" "$matrix_rev" "$matrix_brev"
  cat <<'FAKERUN'
echo "$1 $2 $3" >>"$calls"
mkdir -p "$BENCH_DIR"
jq -nc --arg t "$1" --arg c "$2" --argjson r "$3" --arg p "$rev" --arg b "$brev" \
  '{task:$t,config:$c,rep:$r,plugin_rev:$p,bench_rev:$b,verdict:"pass"}' >>"$BENCH_DIR/runs.jsonl"
FAKERUN
} >"$tmp/fakerun.sh"
chmod +x "$tmp/fakerun.sh"

matrix() {
  BENCH_RUN="$tmp/fakerun.sh" bash "$ROOT/bench/matrix.sh" "$@"
}

matrix_count() {
  wc -l <"$matrix_calls" | tr -d ' '
}

fresh_bench
: >"$matrix_calls"
matrix --tasks t1 --configs plugin,baseline --reps 2 >/dev/null 2>&1
assert_eq "$(matrix_count)" 4 "matrix --tasks t1 --configs plugin,baseline --reps 2 makes 4 calls"

: >"$matrix_calls"
matrix --tasks t1 --configs plugin,baseline --reps 2 >/dev/null 2>&1
assert_eq "$(matrix_count)" 0 "a repeated matrix run makes no calls"

fresh_bench
: >"$matrix_calls"
matrix --holdout --configs plugin --reps 1 >/dev/null 2>&1
assert_eq "$(cat "$matrix_calls")" "t2 plugin 1" "matrix --holdout --configs plugin --reps 1 calls t2 plugin 1"

fresh_bench
mkdir -p "$BENCH_DIR"
jq -nc --arg p "$matrix_rev" --arg b "$matrix_brev" '{task:"t1",config:"plugin",rep:1,plugin_rev:$p,bench_rev:$b,verdict:"error"}' >"$BENCH_DIR/runs.jsonl"
: >"$matrix_calls"
matrix --tasks t1 --configs plugin --reps 1 >/dev/null 2>&1
assert_eq "$(matrix_count)" 0 "an error run is not rerun without --retry-errors"
: >"$matrix_calls"
matrix --tasks t1 --configs plugin --reps 1 --retry-errors >/dev/null 2>&1
assert_eq "$(cat "$matrix_calls")" "t1 plugin 1" "--retry-errors reruns the error run"
key_lines="$(jq -c --arg p "$matrix_rev" 'select(.task=="t1" and .config=="plugin" and .rep==1 and .plugin_rev==$p)' "$BENCH_DIR/runs.jsonl" 2>/dev/null)"
assert_eq "$(printf '%s\n' "$key_lines" | grep -c .)" 1 "after --retry-errors runs.jsonl holds one line for the key"
assert_eq "$(printf '%s\n' "$key_lines" | jq -r .verdict 2>/dev/null)" pass "the remaining line for the key has verdict pass"

fresh_bench
mkdir -p "$BENCH_DIR"
jq -nc --arg b "$matrix_brev" '{task:"t1",config:"baseline",rep:1,plugin_rev:"0000000",bench_rev:$b,verdict:"pass"}' >"$BENCH_DIR/runs.jsonl"
: >"$matrix_calls"
matrix --tasks t1 --configs baseline --reps 1 >/dev/null 2>&1
assert_eq "$(matrix_count)" 0 "baseline done under another plugin_rev counts as done"

fresh_bench
mkdir -p "$BENCH_DIR"
: >"$BENCH_DIR/runs.jsonl"
: >"$matrix_calls"
pending="$(matrix --pending --tasks t1 --reps 1 2>/dev/null)"
assert_eq "$(printf '%s\n' "$pending" | grep -c .)" 5 "--pending --tasks t1 --reps 1 on an empty runs.jsonl prints 5 lines"
assert_contains "$pending" "$(printf 't1\tplugin\t1')" "--pending prints task<TAB>config<TAB>rep"
assert_eq "$(matrix_count)" 0 "--pending makes no calls"

fresh_bench
mkdir -p "$BENCH_DIR"
{
  jq -nc --arg p "$matrix_rev" '{task:"t1",config:"plugin",rep:1,plugin_rev:$p,bench_rev:"000000000000",verdict:"pass"}'
  jq -nc --arg p "$matrix_rev" '{task:"t1",config:"plugin",rep:2,plugin_rev:$p,verdict:"pass"}'
} >"$BENCH_DIR/runs.jsonl"
pending="$(matrix --pending --tasks t1 --configs plugin --reps 2 2>/dev/null)"
assert_contains "$pending" "$(printf 't1\tplugin\t1')" "a run with another bench_rev stays pending"
assert_contains "$pending" "$(printf 't1\tplugin\t2')" "a run without bench_rev stays pending"

fresh_bench
mkdir -p "$BENCH_DIR"
{
  jq -nc --arg p "$matrix_rev" '{task:"t1",config:"plugin",rep:1,plugin_rev:$p,bench_rev:"000000000000",verdict:"error"}'
  jq -nc --arg p "$matrix_rev" --arg b "$matrix_brev" '{task:"t1",config:"plugin",rep:1,plugin_rev:$p,bench_rev:$b,verdict:"error"}'
} >"$BENCH_DIR/runs.jsonl"
: >"$matrix_calls"
matrix --tasks t1 --configs plugin --reps 1 --retry-errors >/dev/null 2>&1
assert_eq "$(cat "$matrix_calls")" "t1 plugin 1" "--retry-errors reruns the error run with the current bench_rev"
assert_eq "$(jq -c 'select(.verdict=="error" and .bench_rev=="000000000000")' "$BENCH_DIR/runs.jsonl" 2>/dev/null | grep -c .)" 1 "--retry-errors keeps the error run with another bench_rev"
assert_eq "$(jq -c --arg b "$matrix_brev" 'select(.verdict=="error" and .bench_rev==$b)' "$BENCH_DIR/runs.jsonl" 2>/dev/null | grep -c .)" 0 "--retry-errors drops the error run with the current bench_rev"

rc=0
matrix --bogus >/dev/null 2>&1 || rc=$?
assert_eq "$rc" 2 "matrix --bogus exits 2"
