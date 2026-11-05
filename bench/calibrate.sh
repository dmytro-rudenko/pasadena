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

say() { printf '%s %s %s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$1" "$2" >>"$log"; }

exclude() {
  say "$1" "excluded: $3"
  printf '%s\t%s\tx\n' "$1" "$2" >>"$map"
}

calibrate_task() {
  local id="$1" holdout="$2" base oracle tests dir kept="" p code
  base="$(task_field "$id" base)" || return 1
  oracle="$(task_field "$id" oracle)" || return 1
  tests="$(task_field "$id" tests)" || return 1
  dir="$work/$id"

  if [ -z "$tests" ]; then
    exclude "$id" "$tests" "no tests left"
    return 0
  fi

  make_tree "$oracle" "$dir/oracle" || { echo "calibrate: cannot build oracle tree for $id" >&2; return 1; }
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

  make_tree "$base" "$dir/base" || { echo "calibrate: cannot build base tree for $id" >&2; return 1; }
  put_oracle_tests "$oracle" "$kept" "$dir/base" || { echo "calibrate: cannot copy oracle tests for $id" >&2; return 1; }
  run_oracle "$kept" "$dir/base" "$dir/base-out"

  if awk -F'\t' '$2 != 0 { found = 1 } END { exit !found }' "$dir/base-out/oracle.exit"; then
    say "$id" "kept"
    printf '%s\t%s\t%s\n' "$id" "$kept" "$holdout" >>"$map"
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

exit 0
