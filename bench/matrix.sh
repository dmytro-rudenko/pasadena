#!/usr/bin/env bash
set -uo pipefail

BENCH_ROOT="$(cd "$(dirname "$0")" && pwd)"
source "$BENCH_ROOT/lib.sh"

usage() {
  echo "usage: matrix.sh [--tasks a,b] [--configs x,y] [--reps N] [--holdout] [--retry-errors] [--pending]" >&2
  exit 2
}

tasks_csv="" configs_csv="" reps=3 holdout=0 retry=0 pending=0
while [ $# -gt 0 ]; do
  case "$1" in
    --tasks) [ $# -ge 2 ] || usage; tasks_csv="$2"; shift 2 ;;
    --configs) [ $# -ge 2 ] || usage; configs_csv="$2"; shift 2 ;;
    --reps) [ $# -ge 2 ] || usage; reps="$2"; shift 2 ;;
    --holdout) holdout=1; shift ;;
    --retry-errors) retry=1; shift ;;
    --pending) pending=1; shift ;;
    *) usage ;;
  esac
done
[[ "$reps" =~ ^[1-9][0-9]*$ ]] || usage

if [ -n "$tasks_csv" ]; then
  IFS=, read -ra tasks <<<"$tasks_csv"
else
  mapfile -t tasks < <(task_ids "$holdout")
fi
if [ -n "$configs_csv" ]; then
  IFS=, read -ra configs <<<"$configs_csv"
else
  mapfile -t configs < <(config_names)
fi

for t in "${tasks[@]}"; do
  task_field "$t" id >/dev/null || exit 2
done
for c in "${configs[@]}"; do
  config_field "$c" name >/dev/null || exit 2
done

rev="$(plugin_rev)" || exit 1
brev="$(bench_rev)"
runs="$BENCH_DIR/runs.jsonl"

declare -A finished errored
if [ -f "$runs" ]; then
  while IFS=$'\t' read -r r_rev r_task r_config r_rep r_verdict; do
    [ "$r_config" = baseline ] && r_rev='*'
    if [ "$r_verdict" = error ]; then
      errored["$r_rev/$r_task/$r_config/$r_rep"]=1
    else
      finished["$r_rev/$r_task/$r_config/$r_rep"]=1
    fi
  done < <(jq -r --arg brev "$brev" 'select((.bench_rev // "") == $brev) | [.plugin_rev,.task,.config,(.rep|tostring),.verdict]|@tsv' "$runs" 2>/dev/null)
fi

drop_errors() {
  local task="$1" config="$2" rep="$3" any=false tmp
  [ "$config" = baseline ] && any=true
  tmp="$(mktemp "$runs.XXXXXX")" || return
  if jq -rR --arg rev "$rev" --arg brev "$brev" --arg t "$task" --arg c "$config" --argjson r "$rep" --argjson any "$any" '
    . as $line
    | (try fromjson catch null) as $o
    | select((($o | type) == "object"
        and $o.task == $t and $o.config == $c and $o.rep == $r and $o.verdict == "error"
        and $o.bench_rev == $brev
        and ($any or $o.plugin_rev == $rev)) | not)
    | $line
  ' "$runs" >"$tmp"; then
    mv "$tmp" "$runs"
  else
    rm -f "$tmp"
    return 1
  fi
}

for task in "${tasks[@]}"; do
  for config in "${configs[@]}"; do
    key_rev="$rev"
    [ "$config" = baseline ] && key_rev='*'
    for ((rep = 1; rep <= reps; rep++)); do
      key="$key_rev/$task/$config/$rep"
      [ -n "${finished[$key]:-}" ] && continue
      if [ -n "${errored[$key]:-}" ]; then
        [ "$retry" -eq 1 ] || continue
        [ "$pending" -eq 1 ] || drop_errors "$task" "$config" "$rep" || exit 1
      fi
      if [ "$pending" -eq 1 ]; then
        printf '%s\t%s\t%s\n' "$task" "$config" "$rep"
        continue
      fi
      bash "$BENCH_RUN" "$task" "$config" "$rep" || exit $?
    done
  done
done
