#!/usr/bin/env bash
set -uo pipefail

: "${PASADENA_CODEX_IDLE:=120}"
: "${PASADENA_CODEX_CMD_IDLE:=600}"
marker="${XDG_STATE_HOME:-$HOME/.local/state}/pasadena/codex-exhausted"
marker_ttl=21600

usage() {
  echo "usage: codex.sh available | explore <prompt-file> | review <base> <prompt-file> | red <prompt-file> | green <thread-id> <prompt-file>" >&2
  exit 2
}

mtime() { stat -c %Y "$1" 2>/dev/null || stat -f %m "$1"; }

cmd_available() {
  [ "${PASADENA_CODEX:-1}" != "0" ] || exit 1
  command -v codex >/dev/null 2>&1 || exit 1
  if [ -f "$marker" ]; then
    [ $(($(date +%s) - $(mtime "$marker"))) -ge "$marker_ttl" ] || exit 1
    rm -f "$marker"
  fi
  codex login status >/dev/null 2>&1 || exit 1
  exit 0
}

model_args=()
[ -n "${PASADENA_CODEX_MODEL:-}" ] && model_args=(-m "$PASADENA_CODEX_MODEL")

codex_pid=""

stop_codex() {
  [ -n "$codex_pid" ] || return 0
  kill -0 -- "-$codex_pid" 2>/dev/null || kill -0 "$codex_pid" 2>/dev/null || return 0
  kill -TERM -- "-$codex_pid" 2>/dev/null || kill "$codex_pid" 2>/dev/null
  return 0
}

run() {
  local input="$1" status open limit
  shift
  : >"$events"
  set -m
  codex "$@" <"$input" >"$events" 2>"$work/stderr" &
  codex_pid=$!
  set +m
  while kill -0 "$codex_pid" 2>/dev/null; do
    sleep 1
    open="$(jq -s '[.[] | select(.item.type? == "command_execution") | if .type == "item.started" then 1 elif .type == "item.completed" then -1 else 0 end] | add // 0' "$events" 2>/dev/null || echo 0)"
    limit="$PASADENA_CODEX_IDLE"
    [ "${open:-0}" -gt 0 ] && limit="$PASADENA_CODEX_CMD_IDLE"
    if [ $(($(date +%s) - $(mtime "$events"))) -gt "$limit" ]; then
      stop_codex
      wait "$codex_pid" 2>/dev/null
      echo "codex: no events for ${limit}s, stopped" >&2
      return 124
    fi
  done
  wait "$codex_pid"
  status=$?
  usage_line="$(jq -r 'select(.type == "turn.completed") | .usage | "codex usage: input=\(.input_tokens) cached=\(.cached_input_tokens) output=\(.output_tokens)"' "$events" 2>/dev/null | tail -1)"
  if jq -r 'select(.type == "error" or .type == "turn.failed") | (.message // .error.message // "")' "$events" 2>/dev/null | grep -qiE 'usage limit|insufficient_quota'; then
    mkdir -p "$(dirname "$marker")"
    touch "$marker"
    echo "codex: usage limit reached; delegation is off until $marker is gone" >&2
    return 75
  fi
  if [ "$status" -ne 0 ]; then
    echo "codex: exited with $status" >&2
    sed -n 1,5p "$work/stderr" >&2
    return 1
  fi
  if [ ! -s "$last" ]; then
    echo "codex: no final message" >&2
    return 1
  fi
  return 0
}

sub="${1:-}"
case "$sub" in
  available) cmd_available ;;
  explore | review | red | green) ;;
  *) usage ;;
esac

work="$(mktemp -d)"
usage_line=""
trap 'stop_codex; rm -rf "$work"; [ -z "$usage_line" ] || echo "$usage_line" >&2' EXIT
trap 'stop_codex; exit 130' INT
trap 'stop_codex; exit 143' TERM
events="$work/events.jsonl"
last="$work/last.txt"

case "$sub" in
  explore)
    [ -f "${2:-}" ] || usage
    run "$2" exec -s read-only -C "$PWD" ${model_args[@]+"${model_args[@]}"} --json -o "$last" - || exit $?
    cat "$last"
    ;;
  review)
    [ -f "${3:-}" ] || usage
    git rev-parse --verify --quiet "${2:-}^{commit}" >/dev/null || usage
    git diff "$2" >"$work/diff"
    while IFS= read -r -d '' path; do
      git diff --no-index -- /dev/null "$path" >>"$work/diff"
    done < <(git ls-files -z --others --exclude-standard)
    if [ ! -s "$work/diff" ]; then
      echo "codex: nothing to review" >&2
      exit 1
    fi
    run "$work/diff" exec -s read-only -C "$PWD" ${model_args[@]+"${model_args[@]}"} --json -o "$last" "$(cat "$3")" || exit $?
    cat "$last"
    ;;
  red)
    [ -f "${2:-}" ] || usage
    run "$2" exec -s workspace-write -C "$PWD" ${model_args[@]+"${model_args[@]}"} --json -o "$last" - || exit $?
    thread="$(jq -r 'select(.type == "thread.started") | .thread_id' "$events" 2>/dev/null | head -1)"
    if [ -z "$thread" ]; then
      echo "codex: no thread id" >&2
      exit 1
    fi
    echo "$thread"
    cat "$last"
    ;;
  green)
    [ -n "${2:-}" ] && [ -f "${3:-}" ] || usage
    run "$3" exec resume "$2" -c 'sandbox_mode="workspace-write"' ${model_args[@]+"${model_args[@]}"} --json -o "$last" - || exit $?
    cat "$last"
    ;;
esac
