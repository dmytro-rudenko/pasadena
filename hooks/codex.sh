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

print_last() {
  cat "$last"
  [ -z "$(tail -c 1 "$last")" ] || echo
}

codex_alive() {
  kill -0 -- "-$codex_pid" 2>/dev/null || kill -0 "$codex_pid" 2>/dev/null
}

stop_codex() {
  local i
  [ -n "$codex_pid" ] || return 0
  codex_alive || return 0
  kill -TERM -- "-$codex_pid" 2>/dev/null || kill -TERM "$codex_pid" 2>/dev/null
  for i in $(seq 50); do
    codex_alive || return 0
    sleep 0.1
  done
  kill -KILL -- "-$codex_pid" 2>/dev/null || kill -KILL "$codex_pid" 2>/dev/null
  return 0
}

hash_file() {
  if [ -f "$1" ]; then
    { sha256sum "$1" 2>/dev/null || shasum -a 256 "$1"; } | cut -d' ' -f1
  else
    echo missing
  fi
}

snapshot() {
  local path
  [ -n "$top" ] || return 0
  while IFS= read -r -d '' path; do
    printf '%s\t%s\n' "$(hash_file "$top/$path")" "$path"
  done < <(git -C "$top" ls-files -z -m -o --exclude-standard) | LC_ALL=C sort -u >"$1"
}

changed_line() {
  local paths tab
  tab="$(printf '\t')"
  snapshot "$work/after"
  paths="$(LC_ALL=C comm -3 "$work/before" "$work/after" | sed "s/^$tab//" | cut -f2- | LC_ALL=C sort -u | tr '\n' ' ')"
  echo "codex changed:${paths:+ ${paths% }}"
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
track=""
top="$(git rev-parse --show-toplevel 2>/dev/null)"
trap 'stop_codex; [ -z "$track" ] || changed_line >&2; rm -rf "$work"; [ -z "$usage_line" ] || echo "$usage_line" >&2' EXIT
trap 'stop_codex; exit 130' INT
trap 'stop_codex; exit 143' TERM
events="$work/events.jsonl"
last="$work/last.txt"

case "$sub" in
  explore)
    [ -f "${2:-}" ] || usage
    run "$2" exec -s read-only -C "$PWD" ${model_args[@]+"${model_args[@]}"} --json -o "$last" - || exit $?
    print_last
    ;;
  review)
    [ -f "${3:-}" ] || usage
    [ -n "$top" ] || usage
    git rev-parse --verify --quiet "${2:-}^{commit}" >/dev/null || usage
    git diff "$2" >"$work/diff"
    while IFS= read -r -d '' path; do
      git -C "$top" diff --no-index -- /dev/null "$path" >>"$work/diff"
    done < <(git -C "$top" ls-files -z --others --exclude-standard)
    if [ ! -s "$work/diff" ]; then
      echo "codex: nothing to review" >&2
      exit 1
    fi
    run "$work/diff" exec -s read-only -C "$PWD" ${model_args[@]+"${model_args[@]}"} --json -o "$last" "$(cat "$3")" || exit $?
    print_last
    ;;
  red)
    [ -f "${2:-}" ] || usage
    snapshot "$work/before"
    track=1
    run "$2" exec -s workspace-write -C "$PWD" ${model_args[@]+"${model_args[@]}"} --json -o "$last" - || exit $?
    thread="$(jq -r 'select(.type == "thread.started") | .thread_id' "$events" 2>/dev/null | head -1)"
    if [ -z "$thread" ]; then
      echo "codex: no thread id" >&2
      exit 1
    fi
    echo "$thread"
    print_last
    ;;
  green)
    [[ "${2:-}" =~ ^[A-Za-z0-9][A-Za-z0-9-]*$ ]] && [ -f "${3:-}" ] || usage
    snapshot "$work/before"
    track=1
    run "$3" exec resume "$2" -c 'sandbox_mode="workspace-write"' ${model_args[@]+"${model_args[@]}"} --json -o "$last" - || exit $?
    print_last
    ;;
esac
