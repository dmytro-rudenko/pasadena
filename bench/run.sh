#!/usr/bin/env bash
set -uo pipefail

BENCH_ROOT="$(cd "$(dirname "$0")" && pwd)"
source "$BENCH_ROOT/lib.sh"

if [ "$#" -ne 3 ]; then
  echo "usage: run.sh <task> <config> <rep>" >&2
  exit 2
fi
task="$1" config="$2" rep="$3"

base="$(task_field "$task" base)" || exit 2
spec="$(task_field "$task" spec)" || exit 2
oracle="$(task_field "$task" oracle)" || exit 2
tests="$(task_field "$task" tests)" || exit 2
holdout="$(task_field "$task" holdout)" || exit 2
if [ "$holdout" = x ]; then
  echo "task excluded by calibration: $task" >&2
  exit 2
fi

mode="$(config_field "$config" mode)" || exit 2
prompt_kind="$(config_field "$config" prompt)" || exit 2
env_pairs="$(config_field "$config" env)" || exit 2
codex_mode="$(config_field "$config" codex_mode)" || exit 2
model="$(config_field "$config" model)" || exit 2

case "$prompt_kind" in
  plain) prompt="Implement the specification at $spec. Work autonomously: do not ask questions, make reasonable decisions. Do not push or open pull requests. Commit your work." ;;
  workflow) prompt="/pasadena:leonard Plan the implementation of the agreed specification at $spec, then implement the plan with /pasadena:wolowitz. Work autonomously: do not ask questions, take the recommended option at every decision point, treat the spec and plan as approved. Do not push or open pull requests. Commit your work." ;;
  *) echo "unknown prompt: $prompt_kind" >&2; exit 2 ;;
esac

rev="$(plugin_rev)" || exit 2
run="$BENCH_DIR/runs/$rev/$task/$config/$rep"
rm -rf "$run"
mkdir -p "$run/state/pasadena" || exit 2

plugin_path=""
[ "$mode" = plugin ] && plugin_path="$BENCH_PLUGIN"

jq -n \
  --arg task "$task" --arg config "$config" --argjson rep "$rep" \
  --arg model "$model" --arg plugin_rev "$rev" --arg mode "$mode" \
  --arg plugin_path "$plugin_path" --argjson budget "$BENCH_BUDGET" \
  --arg base_commit "$base" --arg ts "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
  '{task:$task, config:$config, rep:$rep, model:$model, plugin_rev:$plugin_rev,
    mode:$mode, plugin_path:$plugin_path, budget:$budget,
    base_commit:$base_commit, ts:$ts}' >"$run/meta.json"

if ! make_tree "$base" "$run/tree" >"$run/tree.log" 2>&1; then
  echo "tree setup failed" >"$run/error.txt"
fi

(
  cd "$run/tree" 2>/dev/null || exit 0
  {
    grep -rhoE '^[[:space:]]*(function[[:space:]]+)?[A-Za-z_][A-Za-z0-9_]*[[:space:]]*\(\)' --include='*.sh' . \
      | sed -E 's/^[[:space:]]*(function[[:space:]]+)?//; s/[[:space:]]*\(\)$//'
    grep -rhoE 'function[[:space:]]+[A-Za-z_$][A-Za-z0-9_$]*' --include='*.js' --include='*.cjs' . \
      | sed -E 's/^function[[:space:]]+//'
  } | sort -u
) >"$run/base-symbols.txt"

if [ "$codex_mode" != - ]; then
  printf '%s\n' "$codex_mode" >"$run/state/pasadena/codex-mode"
fi

if [ -f "$run/error.txt" ]; then
  echo skipped >"$run/claude.exit"
elif [ "$codex_mode" = full ]; then
  if XDG_STATE_HOME="$run/state" bash "$BENCH_PLUGIN/hooks/codex.sh" available >/dev/null 2>&1; then
    XDG_STATE_HOME="$run/state" bash "$BENCH_PLUGIN/hooks/codex.sh" budget >"$run/codex-before.txt" 2>/dev/null
  else
    echo "codex unavailable" >"$run/error.txt"
    echo skipped >"$run/claude.exit"
  fi
fi

if [ "$(cat "$run/claude.exit" 2>/dev/null)" = skipped ]; then
  : >"$run/diff.patch"
else
  pairs=()
  [ "$env_pairs" != - ] && read -ra pairs <<<"$env_pairs"
  args=(-p "$prompt" --output-format stream-json --verbose
    --no-session-persistence --permission-mode bypassPermissions
    --max-budget-usd "$BENCH_BUDGET" --model "$model"
    --settings '{"enabledPlugins":{"pasadena@pasadena":false,"pasadena@synced":false}}')
  [ "$mode" = plugin ] && args+=(--plugin-dir "$BENCH_PLUGIN")

  (cd "$run/tree" && env XDG_STATE_HOME="$run/state" "${pairs[@]}" timeout "$BENCH_TIMEOUT" claude "${args[@]}") \
    >"$run/claude.jsonl" 2>"$run/claude.err" </dev/null
  code=$?
  echo "$code" >"$run/claude.exit"
  if [ "$code" = 124 ] && [ ! -s "$run/claude.jsonl" ]; then
    echo timeout >"$run/error.txt"
  fi

  if [ "$codex_mode" = full ]; then
    XDG_STATE_HOME="$run/state" bash "$BENCH_PLUGIN/hooks/codex.sh" budget >"$run/codex-after.txt" 2>/dev/null
  fi

  git -C "$run/tree" add -A
  git -C "$run/tree" diff --cached "$(git -C "$run/tree" rev-list --max-parents=0 HEAD)" >"$run/diff.patch"

  put_oracle_tests "$oracle" "$tests" "$run/tree"
  run_oracle "$tests" "$run/tree" "$run"
fi

mkdir -p "$BENCH_DIR"
bash "$BENCH_ROOT/score.sh" "$run" >>"$BENCH_DIR/runs.jsonl"
rm -rf "$run/tree" "$run/tree.log"
exit 0
