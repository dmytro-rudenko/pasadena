#!/usr/bin/env bash
set -uo pipefail

BENCH_ROOT="$(cd "$(dirname "$0")" && pwd)"
source "$BENCH_ROOT/lib.sh"

work="$(mktemp -d)" || exit 1
trap 'rm -rf "$work"' EXIT
mkdir -p "$BENCH_DIR" || exit 1
log="$BENCH_DIR/calibration.log"
map="$work/map.tsv"
: >"$map"
manual="$work/manual.tsv"
mkdir -p "$work/rows" || exit 1
awk -F'\t' 'NR > 1 && index($5, "manual:") == 1' "$BENCH_CHECKS" >"$manual" 2>/dev/null || : >"$manual"

say() { printf '%s %s %s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$1" "$2" >>"$log"; }

exclude() {
  say "$1" "excluded: $3"
  printf '%s\t%s\tx\n' "$1" "$2" >>"$map"
}

fail_checks() {
  TREE="$2" awk '
    function flush() { if (cur != "" && !(cur in seen)) { seen[cur] = 1; print cur lits } cur = ""; lits = "" }
    function lit(v) { gsub(/\t/, " ", v); lits = lits "\t" v }
    {
      s = $0
      sub(/^[ \t]+/, "", s)
      indented = s != $0
      if (index(s, "FAIL — ") == 1) {
        flush()
        name = substr(s, length("FAIL — ") + 1)
        tree = ENVIRON["TREE"]
        while (tree != "" && (i = index(name, tree)) > 0) name = substr(name, 1, i - 1) "<tree>" substr(name, i + length(tree))
        gsub(/\t/, " ", name)
        cur = name
        rest = name
        while ((i = index(rest, "\"")) > 0) {
          rest = substr(rest, i + 1)
          if ((j = index(rest, "\"")) == 0) break
          lit(substr(rest, 1, j - 1))
          rest = substr(rest, j + 1)
        }
      } else if (index(s, "ok  — ") == 1) {
        flush()
      } else if (cur != "" && indented && index(s, "expected substring: ") == 1) {
        lit(substr(s, length("expected substring: ") + 1))
      } else if (cur != "" && indented && index(s, "expected: ") == 1) {
        lit(substr(s, length("expected: ") + 1))
      }
    }
    END { flush() }
  ' "$1"
}

manual_row() {
  K1="$1" K2="$2" K3="$3" awk -F'\t' '$1 == ENVIRON["K1"] && $2 == ENVIRON["K2"] && $3 == ENVIRON["K3"] { print $4 "\t" $5; exit }' "$manual"
}

task_checks() {
  local id="$1" dir="$2" p code n=0 on f s status reason over targets=0
  : >"$dir/rows.tsv"
  while IFS=$'\t' read -r p code; do
    n=$((n + 1))
    fail_checks "$dir/base-out/oracle-$n.log" "$dir/base" >"$dir/base-fails"
    on="$(P="$p" awk -F'\t' '$1 == ENVIRON["P"] { print NR; exit }' "$dir/oracle-out/oracle.exit")"
    fail_checks "$dir/oracle-out/oracle-$on.log" "$dir/oracle" | cut -f1 >"$dir/oracle-fails"
    while IFS=$'\t' read -ra f; do
      grep -qxF -- "${f[0]}" "$dir/oracle-fails" && continue
      status=target reason=""
      for s in "${f[@]:1}"; do
        grep -qF -- "$s" "$dir/spec.txt" || { status=excluded reason="literal not in spec: \"$s\""; break; }
      done
      over="$(manual_row "$id" "$p" "${f[0]}")"
      [ -n "$over" ] && IFS=$'\t' read -r status reason <<<"$over"
      if [ "$status" = target ]; then
        targets=$((targets + 1))
      else
        say "$id" "check-excluded $p: ${f[0]}: $reason"
      fi
      printf '%s\t%s\t%s\t%s\t%s\n' "$id" "$p" "${f[0]}" "$status" "$reason" >>"$dir/rows.tsv"
    done <"$dir/base-fails"
  done <"$dir/base-out/oracle.exit"
  [ -s "$dir/rows.tsv" ] || return 2
  [ "$targets" -gt 0 ]
}

calibrate_task() {
  local id="$1" holdout="$2" base oracle tests spec dir kept="" p code rc
  base="$(task_field "$id" base)" || return 1
  oracle="$(task_field "$id" oracle)" || return 1
  tests="$(task_field "$id" tests)" || return 1
  spec="$(task_field "$id" spec)" || return 1
  dir="$work/$id"

  if [ -z "$tests" ]; then
    exclude "$id" "$tests" "no tests left"
    return 0
  fi

  mkdir -p "$dir" && git -C "$BENCH_REPO" show "$oracle:$spec" >"$dir/spec.txt" || { echo "calibrate: cannot read spec for $id" >&2; return 1; }
  make_tree "$oracle" "$dir/oracle" "$oracle" "$spec" || { echo "calibrate: cannot build oracle tree for $id" >&2; return 1; }
  run_oracle "$tests" "$dir/oracle" "$dir/oracle-out"
  while IFS=$'\t' read -r p code; do
    if [ "$code" = 0 ]; then
      kept="${kept:+$kept,}$p"
    else
      say "$id" "dropped-test $p: fails on oracle"
    fi
  done <"$dir/oracle-out/oracle.exit"

  if [ -z "$kept" ]; then
    exclude "$id" "$tests" "no tests left"
    rm -rf "$dir"
    return 0
  fi

  make_tree "$base" "$dir/base" "$oracle" "$spec" || { echo "calibrate: cannot build base tree for $id" >&2; return 1; }
  put_oracle_tests "$oracle" "$kept" "$dir/base" || { echo "calibrate: cannot copy oracle tests for $id" >&2; return 1; }
  run_oracle "$kept" "$dir/base" "$dir/base-out"

  task_checks "$id" "$dir"
  rc=$?
  if [ "$rc" = 1 ]; then
    exclude "$id" "$kept" "no target checks"
  elif [ "$rc" = 0 ] || awk -F'\t' '$2 != 0 { found = 1 } END { exit !found }' "$dir/base-out/oracle.exit"; then
    say "$id" "kept"
    printf '%s\t%s\t%s\n' "$id" "$kept" "$holdout" >>"$map"
    if [ "$rc" = 0 ]; then mv "$dir/rows.tsv" "$work/rows/$id"; fi
  else
    exclude "$id" "$kept" "passes on base"
  fi
  rm -rf "$dir"
}

mapfile -t regular < <(task_ids 0)
mapfile -t holdouts < <(task_ids 1)

for id in "${regular[@]}"; do
  [ -n "$id" ] && { calibrate_task "$id" 0 || exit 1; }
done
for id in "${holdouts[@]}"; do
  [ -n "$id" ] && { calibrate_task "$id" 1 || exit 1; }
done

excluded_holdout=0
for id in "${holdouts[@]}"; do
  [ -n "$id" ] && awk -F'\t' -v id="$id" '$1 == id && $3 == "x" { found = 1 } END { exit !found }' "$map" && excluded_holdout=1
done

if [ "$excluded_holdout" = 1 ]; then
  new_holdout=""
  for id in "${regular[@]}"; do
    [ -n "$id" ] && awk -F'\t' -v id="$id" '$1 == id && $3 == "0" { found = 1 } END { exit !found }' "$map" && new_holdout="$id"
  done
  if [ -n "$new_holdout" ]; then
    awk -F'\t' -v OFS='\t' -v id="$new_holdout" '$1 == id { $3 = 1 } { print }' "$map" >"$map.new" && mv "$map.new" "$map"
    say "$new_holdout" "holdout moved to $new_holdout"
  else
    echo "calibrate: holdout excluded and no task left to take its place" >&2
  fi
fi

if [ -s "$map" ]; then
  out="$BENCH_TASKS.tmp.$$"
  awk -F'\t' -v OFS='\t' '
    FILENAME == ARGV[1] { tests[$1] = $2; hold[$1] = $3; next }
    FNR == 1 { for (i = 1; i <= NF; i++) { if ($i == "tests") tc = i; if ($i == "holdout") hc = i } print; next }
    ($1 in hold) && tc && hc { $tc = tests[$1]; $hc = hold[$1] }
    { print }
  ' "$map" "$BENCH_TASKS" >"$out" && mv "$out" "$BENCH_TASKS" || { rm -f "$out"; exit 1; }
fi

if [ -e "$BENCH_CHECKS" ] || [ -n "$(ls -A "$work/rows")" ]; then
  out="$BENCH_CHECKS.tmp.$$"
  {
    printf 'task\ttest\tcheck\tstatus\treason\n'
    awk -F'\t' 'NR > 1 && $1 != "" { print $1 }' "$BENCH_TASKS" | while IFS= read -r id; do
      if [ -f "$work/rows/$id" ]; then cat "$work/rows/$id"; fi
    done
  } >"$out" && mv "$out" "$BENCH_CHECKS" || { rm -f "$out"; exit 1; }
fi

exit 0
