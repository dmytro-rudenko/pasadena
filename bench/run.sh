#!/usr/bin/env bash
set -euo pipefail
. "$(cd "$(dirname "$0")" && pwd)/common.sh"

arm=""
kind=full
all_tasks=0
task=""
fresh=0
dry=0
print_name=0
pass=()
attempts="$(cfg attempts)"
while [ "$#" -gt 0 ]; do
  case "$1" in
    --arm) arm="$2"; shift 2 ;;
    --kind) kind="$2"; shift 2 ;;
    --all-tasks) all_tasks=1; shift ;;
    --task) task="$2"; shift 2 ;;
    --fresh) fresh=1; shift ;;
    --dry-run) dry=1; shift ;;
    --print-job-name) print_name=1; shift ;;
    -k|--n-attempts) attempts="$2"; shift 2 ;;
    --) shift ;;
    *) pass+=("$1"); shift ;;
  esac
done

case "$arm" in
  baseline) agent=bench.tui_agent:TuiClaudeCode ;;
  pasadena) agent=bench.pasadena_agent:PasadenaClaudeCode ;;
  *) echo "bench: --arm baseline|pasadena is required" >&2; exit 2 ;;
esac
case "$kind" in
  full|select) ;;
  *) echo "bench: --kind must be full or select" >&2; exit 2 ;;
esac

tasks=()
if [ -n "$task" ]; then
  tasks=("$task")
  kind=smoke
elif [ "$all_tasks" = 0 ]; then
  while IFS= read -r name || [ -n "$name" ]; do
    [ -n "$name" ] || continue
    tasks+=("$name")
  done <"$BENCH_TASKS"
  if [ "${#tasks[@]}" -eq 0 ]; then
    echo "bench: $BENCH_TASKS is empty — run: npm run bench:select" >&2
    exit 1
  fi
fi

agent_hash="$(cd "$BENCH_PLUGIN_ROOT" && sha256sum bench/tui_agent.py bench/tui_policy.py | sha256sum | cut -c1-64)"
plugin_hash=""
if [ "$arm" = pasadena ]; then
  plugin_hash="$(
    cd "$BENCH_PLUGIN_ROOT" &&
      find .claude-plugin skills hooks .claude/commands proto bench/pasadena_wrap.py bench/pasadena_agent.py -type f -print0 |
      LC_ALL=C sort -z | xargs -0 sha256sum | sha256sum | cut -c1-64
  )"
fi
hash="$(
  {
    cat "$BENCH_CONFIG" &&
      printf '\0%s' "${#tasks[@]}" "${tasks[@]}" "$attempts" "${pass[@]}" "$agent_hash" "$plugin_hash"
  } | sha256sum | cut -c1-8
)"
job="$kind-$arm-$hash"
if [ "$fresh" = 1 ]; then
  job="$job-${BENCH_FRESH_STAMP-$(date -u +%Y%m%d%H%M%S)}"
fi
if [ "$print_name" = 1 ]; then
  echo "$job"
  exit 0
fi

dataset="$(cfg dataset)"
model="$(cfg model)"
concurrency="$(cfg concurrency)"
retries="$(cfg retries)"
timeout_multiplier="$(cfg agentTimeoutMultiplier)"
claude_version="$(cfg claudeCodeVersion)"
cmd=(
  "$HARBOR" run -d "$dataset" -m "$model" -k "$attempts" -n "$concurrency" -r "$retries"
  --agent-timeout-multiplier "$timeout_multiplier" --ak "version=$claude_version"
  -o "$BENCH_DIR/jobs" --job-name "$job" -a "$agent"
)
for name in "${tasks[@]}"; do
  cmd+=(-i "$name")
done
cmd+=("${pass[@]}")

if [ "$dry" = 1 ]; then
  echo "${cmd[*]}"
  exit 0
fi

require_venv
load_env
job_dir="$BENCH_DIR/jobs/$job"
mkdir -p "$job_dir"
git_sha="$(git -C "$REPO_ROOT" rev-parse HEAD)"
git_status="$(git --no-optional-locks -C "$REPO_ROOT" status --porcelain)"
python3 - "$job_dir/bench-meta.json" "$arm" "$kind" "$hash" "$attempts" "$claude_version" \
  "$plugin_hash" "$git_sha" "${git_status:0:1}" "${#tasks[@]}" "${tasks[@]}" "${pass[@]}" <<'PY'
import json
import sys
from datetime import datetime, timezone

out, arm, kind, job_hash, attempts, version, plugin_hash, git_sha, git_status, task_count, *args = sys.argv[1:]
task_count = int(task_count)
metadata = {
    "arm": arm,
    "agent": "tui",
    "kind": kind,
    "hash": job_hash,
    "args": args[task_count:],
    "tasks": args[:task_count] or ["*"],
    "attempts": int(attempts),
    "claudeCodeVersion": version,
    "pluginContentHash": plugin_hash or None,
    "gitSha": git_sha,
    "gitDirty": bool(git_status),
    "createdAt": datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
}
try:
    with open(out, "x", encoding="utf-8") as handle:
        json.dump(metadata, handle, indent=2)
except FileExistsError:
    pass
PY
PYTHONPATH="$REPO_ROOT${PYTHONPATH:+:$PYTHONPATH}" exec "${cmd[@]}"
