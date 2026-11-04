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
  stubborn)
    echo "$$" >"$FAKE_LOG.stubborn"
    trap '' TERM
    while :; do sleep 1; done
    ;;
  writes)
    echo made >"$PWD/made-by-codex.txt"
    echo by-codex >>"$PWD/f.txt"
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
  log)
    ev '{"type":"turn.started"}'
    ev '{"type":"item.completed","item":{"id":"item_2","type":"reasoning","text":"thinking\nabout it"}}'
    ev '{"type":"item.started","item":{"id":"item_3","type":"command_execution","command":"rg -n foo","status":"in_progress"}}'
    ev '{"type":"item.completed","item":{"id":"item_3","type":"command_execution","command":"rg -n foo","exit_code":2,"status":"failed"}}'
    ev '{"type":"item.started","item":{"id":"item_4","type":"command_execution","command":"ls","status":"in_progress"}}'
    ev '{"type":"item.completed","item":{"id":"item_4","type":"command_execution","command":"ls","exit_code":0,"status":"completed"}}'
    ev '{"type":"item.completed","item":{"id":"item_5","type":"file_change","changes":[{"path":"a.ts","kind":"update"},{"path":"b.ts","kind":"add"}],"status":"completed"}}'
    ev "{\"type\":\"item.completed\",\"item\":{\"id\":\"item_6\",\"type\":\"agent_message\",\"text\":\"$(printf 'x%.0s' $(seq 250))\"}}"
    ev '{"type":"error","message":"boom"}'
    ;;
  live)
    ev '{"type":"item.started","item":{"id":"item_7","type":"command_execution","command":"live-marker","status":"in_progress"}}'
    sleep 4
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

out="$(cx explore "$prompt" 2>&1)"
grep -qx "final answer" <<<"$out"; assert_eq "$?" 0 "explore final message is its own line with stderr merged"
assert_contains "$(tail -n 1 <<<"$out")" "codex usage:" "explore usage line is its own last line"

: >"$FAKE_LOG"
cx PASADENA_CODEX_MODEL=gpt-test explore "$prompt" >/dev/null 2>&1
assert_contains "$(cat "$FAKE_LOG")" "-m gpt-test" "PASADENA_CODEX_MODEL adds -m"
assert_contains "$(cat "$FAKE_LOG")" 'model_reasoning_effort="medium"' "explore runs at medium effort"

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
assert_contains "$(cat "$FAKE_LOG")" 'model_reasoning_effort="high"' "review runs at high effort"
line="$(cat "$FAKE_LOG")"
[ -n "$line" ] && [ "${line: -2}" != " -" ]; assert_eq "$?" 0 "review does not read the prompt from stdin (-)"
assert_contains "$(cat "$FAKE_LOG.stdin")" "+second" "review pipes the local diff on stdin"
assert_contains "$(cat "$FAKE_LOG.stdin")" "+third" "review includes uncommitted changes"
assert_contains "$(cat "$FAKE_LOG.stdin")" "+brand-new" "review includes untracked files"
assert_contains "$(cat "$FAKE_LOG.stdin")" "+cyrillic-name" "review includes untracked files with non-ASCII names"
mkdir -p "$repo/sub"
: >"$FAKE_LOG.stdin"
(cd "$repo/sub" && env PATH="$bin:$PATH" bash "$CODEX_SH" review "$base" "$prompt") >/dev/null 2>&1; st=$?
assert_eq "$st" 0 "review from a subdirectory exits 0"
assert_contains "$(cat "$FAKE_LOG.stdin")" "+brand-new" "review from a subdirectory includes untracked files at the top"
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
assert_contains "$line" 'model_reasoning_effort="xhigh"' "red runs at xhigh effort"
out="$(cx red "$prompt" 2>&1)"
assert_eq "$(sed -n 1p <<<"$out")" "fake-thread-1" "red prints the thread id first even with stderr merged"
assert_contains "$(tail -n 1 <<<"$out")" "codex usage:" "usage line comes last"
assert_eq "$(sed -n 2p <<<"$out")" "final answer" "red final message is its own line with stderr merged"
assert_eq "$(sed -n 3p <<<"$out")" "codex changed:" "red that changes nothing reports an empty change list"
assert_eq "$(wc -l <<<"$out" | tr -d ' ')" 4 "red merged output is thread id, final answer, change list, usage line"
out="$(cx FAKE_MODE=log red "$prompt" 2>&1)"
assert_eq "$(sed -n 1p <<<"$out")" "fake-thread-1" "red prints the thread id first when codex logs events"
assert_eq "$(grep -c '^fake-thread' <<<"$out")" 1 "red prints the thread id once"
cx FAKE_MODE=nothread red "$prompt" >/dev/null 2>&1; assert_eq "$?" 1 "red without a thread id is a failure"
err="$(cx FAKE_MODE=writes red "$prompt" 2>&1 >/dev/null)"
changed="$(grep '^codex changed:' <<<"$err")"
assert_contains "$changed" " f.txt" "change list names a modified tracked file"
assert_contains "$changed" " made-by-codex.txt" "change list names a new file"
[[ -n "$changed" && "$changed" != *" new.txt"* ]]; assert_eq "$?" 0 "change list leaves out untouched untracked files"
rm -f "$repo/made-by-codex.txt"

: >"$FAKE_LOG"
cx green --dangerously-bypass-approvals-and-sandbox "$prompt" routine >/dev/null 2>&1; assert_eq "$?" 2 "green rejects a thread id that looks like a flag"
assert_eq "$(cat "$FAKE_LOG")" "" "green with a bad thread id does not call codex"

: >"$FAKE_LOG"
out="$(cx green fake-thread-1 "$prompt" routine 2>/dev/null)"; st=$?
assert_eq "$st" 0 "green exits 0"
assert_eq "$out" "final answer" "green prints the final message"
assert_contains "$(cat "$FAKE_LOG")" 'exec resume fake-thread-1 -c sandbox_mode="workspace-write" --json -o' "green resumes the thread with workspace-write"
line="$(cat "$FAKE_LOG")"
assert_eq "${line: -2}" " -" "green reads the prompt from stdin (-)"
assert_contains "$(cat "$FAKE_LOG.stdin")" "PROMPT-MARKER" "green passes the prompt file on stdin"
assert_contains "$line" 'model_reasoning_effort="high"' "routine green runs at high effort"

: >"$FAKE_LOG"
cx green fake-thread-1 "$prompt" >/dev/null 2>&1; assert_eq "$?" 2 "green without a complexity is a usage error"
cx green fake-thread-1 "$prompt" hard >/dev/null 2>&1; assert_eq "$?" 2 "green rejects an unknown complexity"
assert_eq "$(cat "$FAKE_LOG")" "" "green with a bad complexity does not call codex"

: >"$FAKE_LOG"
cx PASADENA_CODEX_MODEL=gpt-base PASADENA_CODEX_MODEL_COMPLEX=gpt-big green fake-thread-1 "$prompt" complex >/dev/null 2>&1
assert_contains "$(cat "$FAKE_LOG")" '-m gpt-big -c model_reasoning_effort="xhigh"' "complex green takes the complex model at xhigh effort"
: >"$FAKE_LOG"
cx PASADENA_CODEX_MODEL=gpt-base PASADENA_CODEX_MODEL_COMPLEX=gpt-big green fake-thread-1 "$prompt" routine >/dev/null 2>&1
assert_contains "$(cat "$FAKE_LOG")" '-m gpt-base -c model_reasoning_effort="high"' "routine green falls back to PASADENA_CODEX_MODEL"
: >"$FAKE_LOG"
cx PASADENA_CODEX_MODEL_ROUTINE=gpt-small green fake-thread-1 "$prompt" routine >/dev/null 2>&1
assert_contains "$(cat "$FAKE_LOG")" "-m gpt-small" "routine green takes PASADENA_CODEX_MODEL_ROUTINE"

echo "== session log =="
codex_log="$XDG_STATE_HOME/pasadena/codex.log"
rm -f "$codex_log" "$codex_log.1"
out="$(cx FAKE_MODE=log explore "$prompt" 2>"$tmp/err")"
assert_eq "$out" "final answer" "session log stays off stdout"
[[ "$(cat "$tmp/err")" != *"codex ›"* ]]; assert_eq "$?" 0 "session log stays off stderr"
err="$(cat "$codex_log")"
assert_eq "$(grep -c '^== .* explore ' <<<"$err")" 1 "each call opens the log with a header line"
assert_eq "$(stat -c %a "$codex_log" 2>/dev/null || stat -f %Lp "$codex_log")" 600 "the log is readable by its owner only"
assert_contains "$err" "codex › · thinking about it" "reasoning is logged on one line"
assert_contains "$err" "codex › \$ rg -n foo" "started command is logged"
assert_contains "$err" "codex › exit 2" "failed command logs its exit code"
assert_eq "$(grep -c '^codex › exit' <<<"$err")" 1 "successful command logs no exit line"
assert_contains "$err" "codex › edit: a.ts b.ts" "file change lists its paths"
assert_contains "$err" "codex › $(printf 'x%.0s' $(seq 200))…" "long agent message is cut to 200 characters"
[[ "$err" != *"$(printf 'x%.0s' $(seq 201))"* ]]; assert_eq "$?" 0 "long agent message is not logged in full"
assert_contains "$err" "codex › error: boom" "error is logged"
[[ "$err" != *"turn.started"* && "$err" != *"usage\":"* ]]; assert_eq "$?" 0 "unknown and turn events are not logged raw"
cx explore "$prompt" >/dev/null 2>&1
assert_eq "$(grep -c '^== ' "$codex_log")" 2 "later calls append to the log"
head -c 1048577 /dev/zero >"$codex_log"
cx explore "$prompt" >/dev/null 2>&1
assert_eq "$(grep -c '^== ' "$codex_log")" 1 "an oversized log is rotated"
[ -f "$codex_log.1" ]; assert_eq "$?" 0 "the rotated log is kept as .1"
cx PASADENA_CODEX_LOG="$tmp/custom.log" explore "$prompt" >/dev/null 2>&1
assert_contains "$(cat "$tmp/custom.log")" "codex › final answer" "PASADENA_CODEX_LOG moves the log"

rm -f "$tmp/live.err"
(cd "$repo" && exec env PATH="$bin:$PATH" PASADENA_CODEX_LOG="$tmp/live.err" FAKE_MODE=live bash "$CODEX_SH" explore "$prompt") >/dev/null 2>&1 &
cxpid=$!
for _ in $(seq 30); do
  grep -q "live-marker" "$tmp/live.err" 2>/dev/null && break
  sleep 0.1
done
seen=no
grep -q "codex › \$ live-marker" "$tmp/live.err" 2>/dev/null && kill -0 "$cxpid" 2>/dev/null && seen=yes
assert_eq "$seen" yes "session log appears while codex is still running"
wait "$cxpid"

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
rm -f "$FAKE_LOG.stubborn"
start="$(date +%s)"
(cd "$repo" && exec env PATH="$bin:$PATH" FAKE_MODE=stubborn PASADENA_CODEX_IDLE=1 bash "$CODEX_SH" explore "$prompt") >/dev/null 2>&1 &
cxpid=$!
while kill -0 "$cxpid" 2>/dev/null && [ $(($(date +%s) - start)) -lt 15 ]; do sleep 0.2; done
if kill -0 "$cxpid" 2>/dev/null; then
  kill -KILL "$cxpid" 2>/dev/null
  st=timeout
else
  wait "$cxpid"; st=$?
fi
assert_eq "$st" 124 "codex that ignores TERM is killed and stopped with 124 within 15s"
stubborn_pid="$(cat "$FAKE_LOG.stubborn" 2>/dev/null)"
kill -0 "$stubborn_pid" 2>/dev/null; st=$?
[ -n "$stubborn_pid" ] && kill -KILL -- "-$stubborn_pid" "$stubborn_pid" 2>/dev/null
assert_eq "$st" 1 "codex that ignores TERM is gone after the stop"
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

echo "== mode =="
mstate="$tmp/mstate"
out="$(cx XDG_STATE_HOME="$mstate" mode get)"; assert_eq "$out" explore "mode defaults to explore"
out="$(cx XDG_STATE_HOME="$mstate" mode)"; assert_eq "$out" explore "mode without an argument is get"
assert_eq "$([ -e "$mstate/pasadena/codex.log" ] && echo present || echo absent)" absent "mode get writes no session log"
cx XDG_STATE_HOME="$mstate" mode set full; assert_eq "$?" 0 "mode set full succeeds"
assert_eq "$(cat "$mstate/pasadena/codex-mode")" full "mode set writes the state file"
out="$(cx XDG_STATE_HOME="$mstate" mode get)"; assert_eq "$out" full "mode get returns the set mode"
cx XDG_STATE_HOME="$mstate" mode set auto; out="$(cx XDG_STATE_HOME="$mstate" mode get)"; assert_eq "$out" auto "auto is a valid global mode"
cx XDG_STATE_HOME="$mstate" mode set bogus >/dev/null 2>&1; assert_eq "$?" 2 "mode set rejects an unknown mode"
cx XDG_STATE_HOME="$mstate" mode set >/dev/null 2>&1; assert_eq "$?" 2 "mode set without a value is a usage error"
cx XDG_STATE_HOME="$mstate" mode frob >/dev/null 2>&1; assert_eq "$?" 2 "unknown mode action is a usage error"
out="$(cx XDG_STATE_HOME="$mstate" mode get)"; assert_eq "$out" auto "a rejected set leaves the mode unchanged"
printf 'garbage\n' >"$mstate/pasadena/codex-mode"
out="$(cx XDG_STATE_HOME="$mstate" mode get)"; assert_eq "$out" explore "an unknown value in the file reads as explore"
assert_eq "$([ -e "$mstate/pasadena/codex.log" ] && echo present || echo absent)" absent "mode writes no session log"

echo "== budget =="
chome="$tmp/codexhome"
bstate="$tmp/bstate"
now="$(date +%s)"
future=$((now + 3600))
past=$((now - 10))
cx CODEX_HOME="$chome" XDG_STATE_HOME="$bstate" budget >"$tmp/b.out" 2>/dev/null; rc=$?
assert_eq "$rc" 1 "budget without rollout files exits 1"
assert_eq "$(cat "$tmp/b.out")" "" "budget without rollout files prints nothing"
mkdir -p "$chome/sessions/2026/11/03"
old="$chome/sessions/2026/11/03/rollout-old.jsonl"
new="$chome/sessions/2026/11/03/rollout-new.jsonl"
{
  echo '{"type":"session_meta","payload":{"id":"x"}}'
  echo '{"type":"event_msg","payload":{"type":"token_count","info":null,"rate_limits":{"primary":{"used_percent":10.0,"window_minutes":300,"resets_at":'"$future"'},"secondary":{"used_percent":20.0,"window_minutes":10080,"resets_at":'"$future"'}}}}'
  echo '{"type":"event_msg","payload":{"type":"token_count","info":null,"rate_limits":{"primary":{"used_percent":27.0,"window_minutes":300,"resets_at":'"$future"'},"secondary":{"used_percent":40.4,"window_minutes":10080,"resets_at":'"$future"'}}}}'
} >"$old"
printf '%s\n' '{"type":"session_meta","payload":{"id":"y"}}' '{"type":"event_msg","payload":{"type":"token_count","info":null,"rate_limits":null}}' >"$new"
touch -t 202601010000 "$old"
echo '{"type":"event_msg","payload":{"type":"token_count","info":null,"rate_limits":{"limit_id":"premium","limit_name":null,"primary":null,"secondary":null}}}' >>"$new"
out="$(cx CODEX_HOME="$chome" XDG_STATE_HOME="$bstate" budget)"
assert_eq "$out" "weekly_left=59 weekly_used=41 five_hour_left=73 five_hour_reset=$future" "budget skips a premium record with null windows and a newer file without real rate_limits"
echo '{"type":"event_msg","payload":{"type":"token_count","rate_limits":{"primary":{"used_percent":99.0,"window_minutes":300,"resets_at":'"$past"'},"secondary":{"used_percent":100.0,"window_minutes":10080,"resets_at":'"$past"'}}}}' >>"$new"
out="$(cx CODEX_HOME="$chome" XDG_STATE_HOME="$bstate" budget)"
assert_eq "$out" "weekly_left=100 weekly_used=0 five_hour_left=100 five_hour_reset=$past" "a window whose reset is past counts as fresh"
echo '{"type":"event_msg","payload":{"type":"token_count","info":null,"rate_limits":{"limit_id":"premium","limit_name":null,"primary":null,"secondary":null}}}' >>"$new"
out="$(cx CODEX_HOME="$chome" XDG_STATE_HOME="$bstate" budget)"
assert_eq "$out" "weekly_left=100 weekly_used=0 five_hour_left=100 five_hour_reset=$past" "a premium record after a real one in the same file is skipped"
assert_eq "$([ -e "$bstate/pasadena/codex.log" ] && echo present || echo absent)" absent "budget writes no session log"

echo "== cost =="
out="$(cx XDG_STATE_HOME="$bstate" cost estimate routine)"; assert_eq "$out" 3 "routine estimate defaults to 3"
out="$(cx XDG_STATE_HOME="$bstate" cost estimate complex)"; assert_eq "$out" 6 "complex estimate defaults to 6"
cx XDG_STATE_HOME="$bstate" cost add routine 2; assert_eq "$?" 0 "cost add succeeds"
cx XDG_STATE_HOME="$bstate" cost add routine 5
out="$(cx XDG_STATE_HOME="$bstate" cost estimate routine)"; assert_eq "$out" 4 "even count: median 3.5 rounds up to 4"
cx XDG_STATE_HOME="$bstate" cost add routine 9
out="$(cx XDG_STATE_HOME="$bstate" cost estimate routine)"; assert_eq "$out" 5 "median of 2, 5, 9 is 5"
out="$(cx XDG_STATE_HOME="$bstate" cost estimate complex)"; assert_eq "$out" 6 "routine entries do not move the complex estimate"
cx XDG_STATE_HOME="$bstate" cost add complex 0
out="$(cx XDG_STATE_HOME="$bstate" cost estimate complex)"; assert_eq "$out" 1 "estimate is at least 1"
for i in 1 1 1 1 1 1 1 1 1 1; do cx XDG_STATE_HOME="$bstate" cost add routine "$i"; done
out="$(cx XDG_STATE_HOME="$bstate" cost estimate routine)"; assert_eq "$out" 1 "only the last 10 entries count"
cx XDG_STATE_HOME="$bstate" cost add routine -1 >/dev/null 2>&1; assert_eq "$?" 2 "negative cost is a usage error"
cx XDG_STATE_HOME="$bstate" cost add easy 3 >/dev/null 2>&1; assert_eq "$?" 2 "unknown complexity is a usage error"
cx XDG_STATE_HOME="$bstate" cost estimate >/dev/null 2>&1; assert_eq "$?" 2 "estimate without complexity is a usage error"
cx XDG_STATE_HOME="$bstate" cost >/dev/null 2>&1; assert_eq "$?" 2 "cost without action is a usage error"
assert_eq "$(awk -F'\t' 'END { print NF }' "$bstate/pasadena/codex-cost.tsv")" 3 "cost log lines have three tab-separated fields"

rm -rf "$tmp"

echo
if [ "$fails" -gt 0 ]; then
  echo "FAILED: $fails"
  exit 1
fi
echo "All checks passed."
