#!/usr/bin/env bash
set -uo pipefail
BENCH_ROOT="$(cd "$(dirname "$0")" && pwd)"
source "$BENCH_ROOT/lib.sh"

run="${1:-}"
if [ -z "$run" ] || [ ! -f "$run/meta.json" ]; then
  echo "usage: score.sh <run-dir> (meta.json required)" >&2
  exit 2
fi

run="$(cd "$run" && pwd)"

work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT

jq -c . "$run/meta.json" >"$work/meta.json" 2>/dev/null || { echo "bad meta.json" >&2; exit 2; }
meta="$(cat "$work/meta.json")"

jq -cR 'fromjson? | objects' "$run/claude.jsonl" >"$work/events.jsonl" 2>/dev/null
ev=""
[ -s "$work/events.jsonl" ] && ev=1
jq -cs '[.[] | select(.type=="system" and .subtype=="init")] | last // null' "$work/events.jsonl" >"$work/init.json" 2>/dev/null
jq -cs '[.[] | select(.type=="result")] | last // null' "$work/events.jsonl" >"$work/result.json" 2>/dev/null
subagents="$(jq -s '[.[] | select(.type=="assistant") | .message.content[]? | select(.type=="tool_use" and (.name=="Agent" or .name=="Task"))] | length' "$work/events.jsonl" 2>/dev/null)"
[ -s "$work/init.json" ] || echo null >"$work/init.json"
[ -s "$work/result.json" ] || echo null >"$work/result.json"
[ -n "$subagents" ] || subagents=0
init="$(cat "$work/init.json")"
result_subtype="$(jq -r '.subtype? // ""' "$work/result.json")"
has_result=0
[ "$(cat "$work/result.json")" != null ] && has_result=1

claude_exit="$(tr -d '[:space:]' <"$run/claude.exit" 2>/dev/null)"
err_file="$run/claude.err"
error_txt=""
[ -f "$run/error.txt" ] && error_txt="$(head -n1 "$run/error.txt")"

mode="$(jq -r '.mode // ""' <<<"$meta")"
plugin_path="$(jq -r '.plugin_path // ""' <<<"$meta")"
want_path=""
[ "$mode" != off ] && [ -n "$plugin_path" ] && want_path="$(realpath -m "$plugin_path")"
mismatch=0
if [ "$init" != null ]; then
  mapfile -t pas_paths < <(jq -r '.plugins[]? | select(.name | startswith("pasadena")) | .path' "$work/init.json")
  if [ "$mode" = off ]; then
    [ "${#pas_paths[@]}" -gt 0 ] && mismatch=1
  else
    if [ "${#pas_paths[@]}" -eq 0 ]; then
      mismatch=1
    else
      for p in "${pas_paths[@]}"; do
        [ "$(realpath -m "$p")" = "$want_path" ] || mismatch=1
      done
    fi
  fi
fi

cap=""
if [ "$claude_exit" = 124 ]; then
  cap=timeout
elif [ "$result_subtype" = error_max_budget_usd ]; then
  cap=budget
elif [ "$has_result" = 0 ] && grep -q budget "$err_file" 2>/dev/null; then
  cap=budget
fi

error=""
if [ -n "$error_txt" ]; then
  error="$error_txt"
elif [ "$mismatch" = 1 ]; then
  error="plugin mismatch"
elif [ -z "$ev" ]; then
  error="no events"
elif [ -n "$cap" ]; then
  error="$cap"
elif [ -s "$err_file" ]; then
  error="$(head -n1 "$err_file")"
fi

awk -F'\t' 'NF>=2 {printf "%s\t%s\n", $1, $2}' "$run/oracle.exit" 2>/dev/null \
  | jq -cR 'split("\t") | {path: .[0], code: .[1]}' | jq -cs . >"$work/oracle.json"

task="$(jq -r '.task // ""' <<<"$meta")"
checks_total=0
checks_passed=0
while IFS=$'\t' read -r path check; do
  checks_total=$((checks_total + 1))
  n="$(awk -F'\t' -v p="$path" '$1 == p { print NR; exit }' "$run/oracle.exit" 2>/dev/null)"
  [ -n "$n" ] && [ -f "$run/oracle-$n.log" ] || continue
  TREE="$run/tree" WANT="FAIL — $check" awk '
    BEGIN { tree = ENVIRON["TREE"]; want = ENVIRON["WANT"] }
    {
      s = $0; out = ""
      while ((i = index(s, tree)) > 0) { out = out substr(s, 1, i - 1) "<tree>"; s = substr(s, i + length(tree)) }
      line = out s
      gsub(/\t/, " ", line)
      sub(/^[ \t]+/, "", line)
      if (line == "All checks passed." || line ~ /^FAILED: [0-9]+$/) done = 1
      if (line == want) failed = 1
    }
    END { exit !(done && !failed) }
  ' "$run/oracle-$n.log" && checks_passed=$((checks_passed + 1))
done < <(awk -F'\t' -v t="$task" 'NR>1 && $1==t && $4=="target" { printf "%s\t%s\n", $2, $3 }' "$BENCH_CHECKS" 2>/dev/null)
rev="$(bench_rev)"

diff_file="$run/diff.patch"
diff_files="$(grep -c '^diff --git' "$diff_file" 2>/dev/null)"
diff_lines="$(grep -E '^[+-]' "$diff_file" 2>/dev/null | grep -Evc '^(\+\+\+|---) ')"
diff_empty=1
[ -s "$diff_file" ] && diff_empty=0

dup_symbols=0
if [ -f "$diff_file" ] && [ -f "$run/base-symbols.txt" ]; then
  dup_symbols="$(awk '
    /^\+\+\+ / { f = $0; sub(/^\+\+\+ (b\/)?/, "", f); next }
    /^\+/ {
      s = $0
      if (f ~ /\.sh$/ && s ~ /^\+[[:space:]]*(function[[:space:]]+)?[A-Za-z_][A-Za-z0-9_]*[[:space:]]*\(\)/) {
        sub(/^\+[[:space:]]*/, "", s); sub(/^function[[:space:]]+/, "", s); sub(/[[:space:]]*\(.*/, "", s)
        print s
      } else if (f ~ /\.(js|cjs)$/ && s ~ /^\+[[:space:]]*function[[:space:]]+[A-Za-z_$][A-Za-z0-9_$]*/) {
        sub(/^\+[[:space:]]*function[[:space:]]+/, "", s); sub(/[^A-Za-z0-9_$].*/, "", s)
        print s
      }
    }' "$diff_file" | sort -u | grep -Fxc -f "$run/base-symbols.txt")"
fi

weekly_used() {
  sed -n 's/.*weekly_used=\([0-9][0-9]*\).*/\1/p' "$1" 2>/dev/null | head -n1
}
wall=null
[ -f "$run/claude.secs" ] && wall="$(tr -dc '0-9.' <"$run/claude.secs")" && [ -n "$wall" ] || wall=null
codex_usage=null
if [ -f "$run/codex-before.txt" ] && [ -f "$run/codex-after.txt" ]; then
  b="$(weekly_used "$run/codex-before.txt")"
  a="$(weekly_used "$run/codex-after.txt")"
  [ -n "$b" ] && [ -n "$a" ] && codex_usage=$((a - b))
fi

printf '%s' "$error" >"$work/error.txt"

hard_error=0
{ [ -n "$error_txt" ] || [ "$claude_exit" = skipped ] || [ -z "$ev" ] || [ "$mismatch" = 1 ]; } && hard_error=1

jq -nc \
  --slurpfile meta "$work/meta.json" \
  --slurpfile init "$work/init.json" \
  --slurpfile result "$work/result.json" \
  --slurpfile oracle "$work/oracle.json" \
  --argjson subagents "$subagents" \
  --argjson hard_error "$hard_error" \
  --argjson diff_empty "$diff_empty" \
  --argjson diff_files "${diff_files:-0}" \
  --argjson diff_lines "${diff_lines:-0}" \
  --argjson dup_symbols "${dup_symbols:-0}" \
  --argjson codex_usage "$codex_usage" \
  --argjson wall "$wall" \
  --arg cap "$cap" \
  --arg bench_rev "$rev" \
  --argjson checks_passed "$checks_passed" \
  --argjson checks_total "$checks_total" \
  --rawfile error "$work/error.txt" \
  '
  $meta[0] as $meta | $init[0] as $init | $result[0] as $result | ($oracle[0] // []) as $oracle
  |  ($oracle | map(select(.code == "0")) | length) as $passed
  | ($oracle | length) as $total
  | (if $hard_error == 1 then "error"
     elif $diff_empty == 1 then "refused"
     elif $checks_total > 0 then
       (if $checks_passed == $checks_total then "pass" elif $checks_passed > 0 then "partial" else "fail" end)
     elif $total > 0 and $passed == $total then "pass"
     elif $passed > 0 then "partial"
     else "fail" end) as $verdict
  | ($result.usage // {}) as $u
  | (if $result != null and (($u.output_tokens // 0) == 0) and (($result.modelUsage // {}) | length > 0)
     then [$result.modelUsage[]] | {
       input_tokens: (map(.inputTokens // 0) | add),
       output_tokens: (map(.outputTokens // 0) | add),
       cache_read_input_tokens: (map(.cacheReadInputTokens // 0) | add),
       cache_creation_input_tokens: (map(.cacheCreationInputTokens // 0) | add)
     }
     else $u end) as $tok
  | {
      task: $meta.task,
      config: $meta.config,
      rep: $meta.rep,
      model: $meta.model,
      plugin_rev: $meta.plugin_rev,
      ts: $meta.ts,
      verdict: $verdict,
      capped: ($cap != ""),
      tests_passed: $passed,
      tests_total: $total,
      tests_failed: ($oracle | map(select(.code != "0") | .path)),
      checks_passed: $checks_passed,
      checks_total: $checks_total,
      score: (if $checks_total > 0 and $verdict != "error" then (($checks_passed * 100 / $checks_total) | round) / 100 else null end),
      bench_rev: $bench_rev,
      input_tokens: (if $result != null then $tok.input_tokens else null end),
      cache_read: (if $result != null then $tok.cache_read_input_tokens else null end),
      cache_write: (if $result != null then $tok.cache_creation_input_tokens else null end),
      output_tokens: (if $result != null then $tok.output_tokens else null end),
      cost_usd: (if $result != null then $result.total_cost_usd
                 elif $cap == "budget" then $meta.budget
                 else null end),
      cost_source: "cli-estimate",
      duration_s: (if $wall != null then $wall elif $result != null and $result.duration_ms != null then $result.duration_ms / 1000 else null end),
      num_turns: (if $result != null then $result.num_turns else null end),
      plugins: (if $init != null then [$init.plugins[]? | {name, path}] else [] end),
      subagent_calls: $subagents,
      diff_files: $diff_files,
      diff_lines: $diff_lines,
      dup_symbols: $dup_symbols,
      codex_usage: $codex_usage,
      error: (if $error == "" then null else $error end)
    }
  '
