#!/usr/bin/env bash
# Self-check for the Codex worker wrapper. Run: bash hooks/codex.test.sh
set -uo pipefail

DIR="$(cd "$(dirname "$0")" && pwd)"
CODEX_SH="$DIR/codex.sh"
fails=0

assert_eq() {
  if [ "$1" = "$2" ]; then
    echo "  ok  — $3"
  else
    echo "  FAIL — $3"
    echo "        expected: $2"
    echo "        got: $1"
    fails=$((fails + 1))
  fi
}

assert_contains() {
  if [[ "$1" == *"$2"* ]]; then
    echo "  ok  — $3"
  else
    echo "  FAIL — $3"
    echo "        expected substring: $2"
    echo "        got: $1"
    fails=$((fails + 1))
  fi
}

tmp="$(mktemp -d)"
bin="$tmp/bin"
mkdir -p "$bin"
export FAKE_LOG="$tmp/args.log"
export XDG_STATE_HOME="$tmp/state"
marker="$XDG_STATE_HOME/pasadena/codex-exhausted"

cat >"$bin/codex" <<'FAKE'
#!/usr/bin/env bash
if [ "${1:-}" = login ]; then exit "${FAKE_LOGIN:-0}"; fi
printf '%s\n' "$*" >>"$FAKE_LOG"
cat >"$FAKE_LOG.stdin"
out=""
prev=""
for a in "$@"; do
  [ "$prev" = "-o" ] && out="$a"
  prev="$a"
done
ev() { printf '%s\n' "$1"; }
[ "${FAKE_MODE:-ok}" = nothread ] || ev '{"type":"thread.started","thread_id":"fake-thread-1"}'
case "${FAKE_MODE:-ok}" in
  hang) exec sleep 30 ;;
  fail) exit 3 ;;
  child)
    sleep 30 &
    echo "$!" >"$FAKE_LOG.child"
    wait
    exit 0
    ;;
  ratelimit) ev '{"type":"error","message":"rate limit exceeded, retrying"}' ;;
  diskquota)
    ev '{"type":"error","message":"Disk quota exceeded"}'
    exit 1
    ;;
  quota)
    ev '{"type":"turn.failed","error":{"message":"You have hit your usage limit. Try again later."}}'
    exit 1
    ;;
  cmd)
    ev '{"type":"item.started","item":{"id":"item_0","type":"command_execution","command":"sleep 3"}}'
    sleep 3
    ev '{"type":"item.completed","item":{"id":"item_0","type":"command_execution","command":"sleep 3"}}'
    ;;
esac
ev '{"type":"item.completed","item":{"id":"item_1","type":"agent_message","text":"final answer"}}'
[ "${FAKE_MODE:-ok}" = nothread ] || ev '{"type":"thread.started","thread_id":"fake-thread-2"}'
ev '{"type":"turn.completed","usage":{"input_tokens":100,"cached_input_tokens":40,"output_tokens":7}}'
case "${FAKE_MODE:-ok}" in
  nofile) ;;
  empty) : >"$out" ;;
  *) printf 'final answer' >"$out" ;;
esac
exit 0
FAKE
chmod +x "$bin/codex"

repo="$tmp/repo"
git init -q "$repo"
git -C "$repo" -c user.email=t@t -c user.name=t -c commit.gpgsign=false commit -q --allow-empty -m base
base="$(git -C "$repo" rev-parse HEAD)"
echo second >"$repo/f.txt"
git -C "$repo" add f.txt
git -C "$repo" -c user.email=t@t -c user.name=t -c commit.gpgsign=false commit -q -m second
prompt="$tmp/prompt.md"
printf 'PROMPT-MARKER\n' >"$prompt"

cx() {
  local envs=()
  while [[ "${1:-}" == *=* ]]; do envs+=("$1"); shift; done
  (cd "$repo" && env PATH="$bin:$PATH" ${envs[@]+"${envs[@]}"} bash "$CODEX_SH" "$@")
}

nocodex=""
IFS=: read -ra path_dirs <<<"$PATH"
for d in "${path_dirs[@]}"; do
  [ -x "$d/codex" ] && continue
  nocodex="${nocodex:+$nocodex:}$d"
done

echo "== available =="
cx available; assert_eq "$?" 0 "available with codex logged in"
cx PASADENA_CODEX=0 available; assert_eq "$?" 1 "PASADENA_CODEX=0 turns it off"
cx FAKE_LOGIN=1 available; assert_eq "$?" 1 "logged-out codex is unavailable"
(cd "$repo" && env PATH="$nocodex" bash "$CODEX_SH" available); assert_eq "$?" 1 "missing codex is unavailable"
mkdir -p "$(dirname "$marker")"
touch "$marker"
cx available; assert_eq "$?" 1 "fresh exhausted marker blocks delegation"
touch -d '7 hours ago' "$marker" 2>/dev/null || touch -t "$(date -v-7H +%Y%m%d%H%M)" "$marker"
cx available; assert_eq "$?" 0 "stale marker is ignored"
assert_eq "$([ -e "$marker" ] && echo present || echo gone)" gone "stale marker is removed"

echo "== explore =="
: >"$FAKE_LOG"
out="$(cx explore "$prompt" 2>"$tmp/err")"; st=$?
assert_eq "$st" 0 "explore exits 0"
assert_eq "$out" "final answer" "explore prints only the final message"
assert_contains "$(cat "$FAKE_LOG")" "exec -s read-only -C $repo --json -o" "explore runs read-only in the working dir"
line="$(cat "$FAKE_LOG")"
assert_eq "${line: -2}" " -" "explore reads the prompt from stdin (-)"
assert_contains "$(cat "$FAKE_LOG.stdin")" "PROMPT-MARKER" "explore passes the prompt file on stdin"
assert_contains "$(cat "$tmp/err")" "codex usage: input=100 cached=40 output=7" "usage line on stderr"

: >"$FAKE_LOG"
cx PASADENA_CODEX_MODEL=gpt-test explore "$prompt" >/dev/null 2>&1
assert_contains "$(cat "$FAKE_LOG")" "-m gpt-test" "PASADENA_CODEX_MODEL adds -m"

echo "== review =="
: >"$FAKE_LOG"
cx review HEAD "$prompt" >/dev/null 2>&1; assert_eq "$?" 1 "review with nothing to review is a failure"
assert_eq "$(cat "$FAKE_LOG")" "" "review with nothing to review does not call codex"
echo third >>"$repo/f.txt"
echo brand-new >"$repo/new.txt"
echo cyrillic-name >"$repo/файл.txt"
cx review "$base" "$prompt" >/dev/null 2>&1; st=$?
assert_eq "$st" 0 "review exits 0"
assert_contains "$(cat "$FAKE_LOG")" "exec -s read-only -C $repo --json -o" "review runs read-only"
assert_contains "$(cat "$FAKE_LOG")" "PROMPT-MARKER" "review passes the prompt as the argument"
line="$(cat "$FAKE_LOG")"
[ -n "$line" ] && [ "${line: -2}" != " -" ]; assert_eq "$?" 0 "review does not read the prompt from stdin (-)"
assert_contains "$(cat "$FAKE_LOG.stdin")" "+second" "review pipes the local diff on stdin"
assert_contains "$(cat "$FAKE_LOG.stdin")" "+third" "review includes uncommitted changes"
assert_contains "$(cat "$FAKE_LOG.stdin")" "+brand-new" "review includes untracked files"
assert_contains "$(cat "$FAKE_LOG.stdin")" "+cyrillic-name" "review includes untracked files with non-ASCII names"
cx review not-a-ref "$prompt" >/dev/null 2>&1; assert_eq "$?" 2 "unknown base is a usage error"

echo "== red / green =="
: >"$FAKE_LOG"
out="$(cx red "$prompt" 2>/dev/null)"; st=$?
assert_eq "$st" 0 "red exits 0"
assert_eq "$(sed -n 1p <<<"$out")" "fake-thread-1" "red prints the thread id first"
assert_eq "$(sed -n 2p <<<"$out")" "final answer" "red prints the final message after the id"
assert_contains "$(cat "$FAKE_LOG")" "exec -s workspace-write -C $repo --json -o" "red runs workspace-write"
line="$(cat "$FAKE_LOG")"
assert_eq "${line: -2}" " -" "red reads the prompt from stdin (-)"
out="$(cx red "$prompt" 2>&1)"
assert_eq "$(sed -n 1p <<<"$out")" "fake-thread-1" "red prints the thread id first even with stderr merged"
assert_contains "$(tail -n 1 <<<"$out")" "codex usage:" "usage line comes last"
cx FAKE_MODE=nothread red "$prompt" >/dev/null 2>&1; assert_eq "$?" 1 "red without a thread id is a failure"

: >"$FAKE_LOG"
out="$(cx green fake-thread-1 "$prompt" 2>/dev/null)"; st=$?
assert_eq "$st" 0 "green exits 0"
assert_eq "$out" "final answer" "green prints the final message"
assert_contains "$(cat "$FAKE_LOG")" 'exec resume fake-thread-1 -c sandbox_mode="workspace-write" --json -o' "green resumes the thread with workspace-write"
line="$(cat "$FAKE_LOG")"
assert_eq "${line: -2}" " -" "green reads the prompt from stdin (-)"
assert_contains "$(cat "$FAKE_LOG.stdin")" "PROMPT-MARKER" "green passes the prompt file on stdin"

echo "== idle =="
start="$(date +%s)"
cx FAKE_MODE=hang PASADENA_CODEX_IDLE=1 explore "$prompt" >/dev/null 2>&1; st=$?
assert_eq "$st" 124 "silent codex is stopped with 124"
assert_eq "$(( $(date +%s) - start < 10 ))" 1 "idle stop happens within seconds"
cx FAKE_MODE=child PASADENA_CODEX_IDLE=1 explore "$prompt" >/dev/null 2>&1; assert_eq "$?" 124 "silent codex with a child is stopped with 124"
sleep 1
kill -0 "$(cat "$FAKE_LOG.child")" 2>/dev/null; assert_eq "$?" 1 "idle stop kills the command codex is running"
rm -f "$FAKE_LOG.child"
(cd "$repo" && exec env PATH="$bin:$PATH" FAKE_MODE=child PASADENA_CODEX_IDLE=30 bash "$CODEX_SH" explore "$prompt") >/dev/null 2>&1 &
cxpid=$!
for _ in $(seq 50); do
  [ -s "$FAKE_LOG.child" ] && break
  sleep 0.1
done
kill -TERM "$cxpid"
wait "$cxpid"; assert_eq "$?" 143 "TERM to codex.sh exits 143"
sleep 1
kill -0 "$(cat "$FAKE_LOG.child")" 2>/dev/null; assert_eq "$?" 1 "TERM to codex.sh stops the command codex is running"
cx FAKE_MODE=cmd PASADENA_CODEX_IDLE=1 PASADENA_CODEX_CMD_IDLE=10 explore "$prompt" >/dev/null 2>&1
assert_eq "$?" 0 "a running command gets the command idle limit"

echo "== failures =="
rm -f "$marker"
cx FAKE_MODE=quota explore "$prompt" >/dev/null 2>&1; assert_eq "$?" 75 "usage limit exits 75"
assert_eq "$([ -e "$marker" ] && echo present || echo gone)" present "usage limit leaves the marker"
cx available; assert_eq "$?" 1 "available is off after the usage limit"
rm -f "$marker"
cx FAKE_MODE=ratelimit explore "$prompt" >/dev/null 2>&1; assert_eq "$?" 0 "transient rate limit is not a usage limit"
assert_eq "$([ -e "$marker" ] && echo present || echo gone)" gone "transient rate limit leaves no marker"
cx FAKE_MODE=diskquota explore "$prompt" >/dev/null 2>&1; assert_eq "$?" 1 "disk quota is a plain failure"
assert_eq "$([ -e "$marker" ] && echo present || echo gone)" gone "disk quota leaves no marker"
cx FAKE_MODE=nofile explore "$prompt" >/dev/null 2>&1; assert_eq "$?" 1 "missing final message file is a failure"
cx FAKE_MODE=empty explore "$prompt" >/dev/null 2>&1; assert_eq "$?" 1 "empty final message file is a failure"
cx FAKE_MODE=fail explore "$prompt" >/dev/null 2>&1; assert_eq "$?" 1 "codex exit != 0 is a failure"
cx explore >/dev/null 2>&1; assert_eq "$?" 2 "missing prompt file is a usage error"
cx >/dev/null 2>&1; assert_eq "$?" 2 "no subcommand is a usage error"

rm -rf "$tmp"

echo
if [ "$fails" -gt 0 ]; then
  echo "FAILED: $fails"
  exit 1
fi
echo "All checks passed."
