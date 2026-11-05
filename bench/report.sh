#!/usr/bin/env bash
set -uo pipefail

BENCH_ROOT="$(cd "$(dirname "$0")" && pwd)"
source "$BENCH_ROOT/lib.sh"

usage() {
  echo 'usage: report.sh [--rev R] [--tasks a,b] [--configs x,y] [--next "<matrix args>"] [--out <file>]' >&2
  exit 2
}

rev="" tasks_csv="" configs_csv="" next="" have_next=false out=""
while [ $# -gt 0 ]; do
  case "$1" in
    --rev) [ $# -ge 2 ] || usage; rev="$2"; shift 2 ;;
    --tasks) [ $# -ge 2 ] || usage; tasks_csv="$2"; shift 2 ;;
    --configs) [ $# -ge 2 ] || usage; configs_csv="$2"; shift 2 ;;
    --next) [ $# -ge 2 ] || usage; next="$2"; have_next=true; shift 2 ;;
    --out) [ $# -ge 2 ] || usage; out="$2"; shift 2 ;;
    *) usage ;;
  esac
done

if [ -n "$tasks_csv" ]; then
  IFS=, read -ra tasks <<<"$tasks_csv"
  for t in "${tasks[@]}"; do
    task_field "$t" id >/dev/null || exit 2
  done
fi
if [ -n "$configs_csv" ]; then
  IFS=, read -ra configs <<<"$configs_csv"
  for c in "${configs[@]}"; do
    config_field "$c" name >/dev/null || exit 2
  done
fi

pending=""
if [ "$have_next" = true ]; then
  read -ra next_args <<<"$next"
  pending="$(bash "$BENCH_ROOT/matrix.sh" "${next_args[@]}" --pending)" || exit
fi

order="$(config_names | jq -R . | jq -sc .)" || exit 1

prog="$(cat <<'JQ'
def cfgidx: . as $c | ($order | index($c)) // 999;
def money:
  (. * 100 | round) as $c
  | (if $c < 0 then -$c else $c end) as $a
  | (if $c < 0 then "-" else "" end)
    + (($a / 100 | floor) | tostring) + "."
    + (($a % 100) | tostring | if length < 2 then "0" + . else . end);
def dec1:
  (. * 10 | round) as $c | (($c / 10 | floor) | tostring) + "." + (($c % 10) | tostring);
def int: round | tostring;
def pct($k; $n): if $n == 0 then "0%" else (($k * 100 / $n + 0.5 | floor) | tostring) + "%" end;
def orn(f): if . == null then "-" else f end;
def vals($k): map(.[$k]) | map(select(. != null));
def mean: if length == 0 then null else add / length end;
def p95: sort | if length == 0 then null else .[((length * 0.95) | ceil) - 1] end;
def sum: add // 0;
def txt: if . == null then "" else tostring | gsub("\n"; " ") | gsub("\\|"; "\\|") end;
def ubs($b): if $b then " (upper bound)" else "" end;

def cellrow:
  . as $rs
  | length as $n
  | def cnt($v): [$rs[] | select(.verdict == $v)] | length;
  {
    name: $rs[0].config, n: $n,
    pass: cnt("pass"), partial: cnt("partial"), fail: cnt("fail"),
    refused: cnt("refused"), error: cnt("error"),
    capped: ([$rs[] | select(.capped == true)] | length),
    cost_mean: ($rs | vals("cost_usd") | mean), cost_p95: ($rs | vals("cost_usd") | p95),
    time_mean: ($rs | vals("duration_s") | mean), time_p95: ($rs | vals("duration_s") | p95),
    out: ($rs | vals("output_tokens") | mean),
    sub: ($rs | vals("subagent_calls") | mean),
    dup: ($rs | vals("dup_symbols") | mean),
    codex: ($rs | vals("codex_usage") | sum)
  };

def cellline:
  "| \(.name) | \(.n) | \(pct(.pass; .n)) | \(pct(.partial; .n)) | \(pct(.fail; .n))"
  + " | \(pct(.refused; .n)) | \(pct(.error; .n)) | \(pct(.capped; .n))"
  + " | \(.cost_mean | orn(money)) | \(.cost_p95 | orn(money))"
  + " | \(.time_mean | orn(int)) | \(.time_p95 | orn(int))"
  + " | \(.out | orn(int)) | \(.sub | orn(dec1)) | \(.dup | orn(dec1)) | \(.codex | int) |";

def delta($plugin):
  (.pass - $plugin.pass) as $d
  | "\(.name): pass \(if $d >= 0 then "+" else "" end)\($d) vs plugin\(if (if $d < 0 then -$d else $d end) <= 3 then " (noise)" else "" end)";

def runline:
  "| \(.task) | \(.config) | \(.rep) | \(.verdict) | \(if .capped == true then "yes" else "no" end)"
  + " | \(.cost_usd | orn(money)) | \(.duration_s | orn(int)) | \(.num_turns | txt) | \(.subagent_calls | txt)"
  + " | \(.diff_lines | txt) | \(.error | txt) | \((.tests_failed // []) | join(",") | txt)"
  + " | \($dir)/runs/\(.plugin_rev)/\(.task)/\(.config)/\(.rep) |";

def fc($rows; $k; $fallback; $n):
  ($rows | vals($k)) as $s
  | if ($s | length) == 0
    then {mean: ($fallback * $n), p95: ($fallback * $n), ub: true}
    else {mean: (($s | mean) * $n), p95: (($s | p95) * $n), ub: false} end;

($tasks | split(",") | map(select(length > 0))) as $tf
| ($configs | split(",") | map(select(length > 0))) as $cf
| [split("\n")[] | select(length > 0) | (try fromjson catch empty) | select(type == "object")] as $all
| (if $rev != "" then $rev else ($all | map(select(.config != "baseline")) | (.[-1] // {}) | .plugin_rev) end) as $r
| ($all | map(select(
    (.config == "baseline" or .plugin_rev == $r)
    and (($tf | length) == 0 or (.task | IN($tf[])))
    and (($cf | length) == 0 or (.config | IN($cf[])))))) as $sel
| ($sel | group_by(.config) | map(cellrow) | sort_by(.name | cfgidx)) as $cells
| ($cells | map(select(.name == "plugin")) | .[0]) as $plugin
| ($sel | sort_by([.task, (.config | cfgidx), .rep, .ts])) as $runs
| [
    "# Benchmark report (plugin_rev \($r // "none"))",
    "",
    "## Cells",
    "",
    "| cell | runs | pass | partial | fail | refused | error | capped | cost mean | cost p95 | time mean | time p95 | out tokens | subagents | dup | codex |",
    "|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|",
    ($cells[] | cellline),
    "",
    (if $plugin != null then ($cells[] | select(.name != "plugin") | delta($plugin)), "" else empty end),
    "Bias: oracle tests come from the original PRs; the plugin is current while tasks are historical (spec §5).",
    "",
    "## Runs",
    "",
    "| task | config | rep | verdict | capped | cost | time | turns | subagents | diff lines | error | failed tests | run |",
    "|---|---|---|---|---|---|---|---|---|---|---|---|---|",
    ($runs[] | runline),
    "",
    "## Spend",
    "",
    "selection: $\($sel | vals("cost_usd") | sum | money) / \($sel | vals("duration_s") | sum | int)s; all runs: $\($all | vals("cost_usd") | sum | money) / \($all | vals("duration_s") | sum | int)s"
  ]
  + (if $next then
      ($pending | split("\n") | map(select(length > 0) | split("\t"))) as $pl
      | ($pl | group_by(.[1]) | map({name: .[0][1], pending: length}) | sort_by(.name | cfgidx)
         | map(. as $c
             | ($sel | map(select(.config == $c.name))) as $rows
             | $c + {cost: fc($rows; "cost_usd"; $budget; $c.pending), time: fc($rows; "duration_s"; $timeout; $c.pending)})) as $fcs
      | [
          "",
          "## Forecast",
          "",
          "pending runs: \($pl | length)",
          "",
          "| cell | pending | cost mean | cost p95 | time mean | time p95 |",
          "|---|---|---|---|---|---|",
          ($fcs[]
            | "| \(.name) | \(.pending) | \(.cost.mean | money)\(ubs(.cost.ub)) | \(.cost.p95 | money)\(ubs(.cost.ub))"
              + " | \(.time.mean | int)\(ubs(.time.ub)) | \(.time.p95 | int)\(ubs(.time.ub)) |"),
          "| total | \($pl | length)"
            + " | \($fcs | map(.cost.mean) | sum | money)\(ubs($fcs | any(.cost.ub))) | \($fcs | map(.cost.p95) | sum | money)\(ubs($fcs | any(.cost.ub)))"
            + " | \($fcs | map(.time.mean) | sum | int)\(ubs($fcs | any(.time.ub))) | \($fcs | map(.time.p95) | sum | int)\(ubs($fcs | any(.time.ub))) |"
        ]
    else [] end)
| .[]
JQ
)"

report="$({ cat "$BENCH_DIR/runs.jsonl" 2>/dev/null || true; } | jq -rRs \
  --arg rev "$rev" --arg tasks "$tasks_csv" --arg configs "$configs_csv" \
  --argjson order "$order" --argjson next "$have_next" --arg pending "$pending" \
  --arg dir "$BENCH_DIR" --argjson budget "$BENCH_BUDGET" --argjson timeout "$BENCH_TIMEOUT" \
  "$prog")" || exit 1

printf '%s\n' "$report"
if [ -n "$out" ]; then
  mkdir -p "$(dirname "$out")" || exit 1
  printf '%s\n' "$report" >"$out" || exit 1
fi
