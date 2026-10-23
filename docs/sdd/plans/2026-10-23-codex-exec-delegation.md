# Делегування в `codex exec` — implementation plan

**Goal:** skills Pasadena делегують explore, другу думку в review і прості задачі плану в Codex через `hooks/codex.sh`; TDD для Codex-задач забезпечує контролер `wolowitz`; без Codex усе працює як раніше.
**Spec:** docs/sdd/specs/2026-10-23-codex-exec-delegation.md
**Verification:** `bash hooks/codex.test.sh && bash skills/skills.test.sh && bash hooks/journal.test.sh && bash hooks/nudge.test.sh && bash proto/server.test.sh` — кожен скрипт закінчується рядком `All checks passed.`

## Waves
| Wave | Tasks | Why together |
|---|---|---|
| 0 | 0 | alone — acceptance tests, red until the last wave |
| 1 | 1, 2, 3, 4, 5 | disjoint: `hooks/codex.sh` / `skills/wolowitz/` / `skills/leonard/` / `skills/leslie/`+`skills/sheldon/` / README+manifests. Interfaces are fixed in Global constraints, so the skill texts do not consume Task 1's code |
| 2 | 6 | alone — end-to-end check with the real `codex` needs everything in place |

Every task has `**Executor:** claude`: `hooks/codex.sh` does not exist in the installed plugin (cache 0.8.0) yet, so this build cannot delegate to it.

## Global constraints

- `hooks/codex.sh` lives beside `hooks/journal.sh`; skills refer to it as "`codex.sh` lives beside `journal.sh`" (the session-start digest names that directory).
- Subcommands, exactly: `available`, `explore <prompt-file>`, `review <base> <prompt-file>`, `red <prompt-file>`, `green <thread-id> <prompt-file>`.
- Exit codes: `0` ok; `1` Codex failed (exit ≠ 0, or empty final message, or no thread id from `red`); `2` usage error; `75` ChatGPT usage limit; `124` idle stop.
- Env: `PASADENA_CODEX` (`0` = off), `PASADENA_CODEX_IDLE` (default `120`), `PASADENA_CODEX_CMD_IDLE` (default `600`), `PASADENA_CODEX_MODEL` (adds `-m`).
- Usage-limit marker: `${XDG_STATE_HOME:-$HOME/.local/state}/pasadena/codex-exhausted`, ignored once older than 21600 s.
- Stderr usage line: `codex usage: input=<input_tokens> cached=<cached_input_tokens> output=<output_tokens>`.
- Plan task field: `**Executor:** codex | claude`, written after `**Depends on:**`.
- Do not write the strings `.codex-plugin`, `Codex plan mode`, `Codex workflow` anywhere — `skills.test.sh` treats them as Codex host support.
- No code comments (user rule). Prose in skills is English, as in the existing skills; README.uk.md is Ukrainian.
- Plugin version becomes `0.10.0` in both manifests.

---

### Task 0: acceptance tests

**Writes:** `hooks/codex.test.sh`, `skills/skills.test.sh`
**Executor:** claude
**Covers:**
- «`bash hooks/codex.test.sh` з фейковим `codex` у `PATH` покриває: `available` …; прапорці кожної підкоманди …; розбір `thread_id` …; idle-kill з кодом `124` …; `PASADENA_CODEX_CMD_IDLE` …; вихід ≠ 0, коли файл `-o` порожній; код `75` і маркер …; рядок `codex usage: …`»
- «`bash skills/skills.test.sh` отримує нові перевірки: `leonard/SKILL.md` описує `**Executor:**`; `wolowitz/SKILL.md` згадує `codex.sh red`, `codex.sh green`, gate red і gate green; `wolowitz/implementer-prompt-codex.md` існує і не містить «Skill tool»; версії в маніфестах збігаються»
- «Наявні `journal.test.sh`, `nudge.test.sh`, `proto/server.test.sh` лишаються зеленими» — covered by the Verification command.

- [x] **Step 1: write `hooks/codex.test.sh`** (new file, `chmod +x` not needed — run with `bash`):

```bash
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
ev '{"type":"thread.started","thread_id":"fake-thread-1"}'
case "${FAKE_MODE:-ok}" in
  hang) sleep 30; exit 0 ;;
  fail) exit 3 ;;
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
ev '{"type":"turn.completed","usage":{"input_tokens":100,"cached_input_tokens":40,"output_tokens":7}}'
[ "${FAKE_MODE:-ok}" = empty ] || printf 'final answer' >"$out"
exit 0
FAKE
chmod +x "$bin/codex"

repo="$tmp/repo"
git init -q "$repo"
git -C "$repo" -c user.email=t@t -c user.name=t commit -q --allow-empty -m base
base="$(git -C "$repo" rev-parse HEAD)"
echo second >"$repo/f.txt"
git -C "$repo" add f.txt
git -C "$repo" -c user.email=t@t -c user.name=t commit -q -m second
prompt="$tmp/prompt.md"
printf 'PROMPT-MARKER\n' >"$prompt"

cx() {
  local envs=()
  while [[ "${1:-}" == *=* ]]; do envs+=("$1"); shift; done
  (cd "$repo" && env PATH="$bin:/usr/bin:/bin" ${envs[@]+"${envs[@]}"} bash "$CODEX_SH" "$@")
}

echo "== available =="
cx available; assert_eq "$?" 0 "available with codex logged in"
cx PASADENA_CODEX=0 available; assert_eq "$?" 1 "PASADENA_CODEX=0 turns it off"
cx FAKE_LOGIN=1 available; assert_eq "$?" 1 "logged-out codex is unavailable"
(cd "$repo" && env PATH="/usr/bin:/bin" bash "$CODEX_SH" available); assert_eq "$?" 1 "missing codex is unavailable"
mkdir -p "$(dirname "$marker")"
touch "$marker"
cx available; assert_eq "$?" 1 "fresh exhausted marker blocks delegation"
touch -d '7 hours ago' "$marker"
cx available; assert_eq "$?" 0 "stale marker is ignored"
assert_eq "$([ -e "$marker" ] && echo present || echo gone)" gone "stale marker is removed"

echo "== explore =="
: >"$FAKE_LOG"
out="$(cx explore "$prompt" 2>"$tmp/err")"; st=$?
assert_eq "$st" 0 "explore exits 0"
assert_eq "$out" "final answer" "explore prints only the final message"
assert_contains "$(cat "$FAKE_LOG")" "exec -s read-only -C $repo --json -o" "explore runs read-only in the working dir"
assert_contains "$(cat "$FAKE_LOG.stdin")" "PROMPT-MARKER" "explore passes the prompt file on stdin"
assert_contains "$(cat "$tmp/err")" "codex usage: input=100 cached=40 output=7" "usage line on stderr"

: >"$FAKE_LOG"
cx PASADENA_CODEX_MODEL=gpt-test explore "$prompt" >/dev/null 2>&1
assert_contains "$(cat "$FAKE_LOG")" "-m gpt-test" "PASADENA_CODEX_MODEL adds -m"

echo "== review =="
: >"$FAKE_LOG"
cx review "$base" "$prompt" >/dev/null 2>&1; st=$?
assert_eq "$st" 0 "review exits 0"
assert_contains "$(cat "$FAKE_LOG")" "exec -s read-only -C $repo --json -o" "review runs read-only"
assert_contains "$(cat "$FAKE_LOG")" "PROMPT-MARKER" "review passes the prompt as the argument"
assert_contains "$(cat "$FAKE_LOG.stdin")" "+second" "review pipes the local diff on stdin"
cx review not-a-ref "$prompt" >/dev/null 2>&1; assert_eq "$?" 2 "unknown base is a usage error"

echo "== red / green =="
: >"$FAKE_LOG"
out="$(cx red "$prompt" 2>/dev/null)"; st=$?
assert_eq "$st" 0 "red exits 0"
assert_eq "$(sed -n 1p <<<"$out")" "fake-thread-1" "red prints the thread id first"
assert_eq "$(sed -n 2p <<<"$out")" "final answer" "red prints the final message after the id"
assert_contains "$(cat "$FAKE_LOG")" "exec -s workspace-write -C $repo --json -o" "red runs workspace-write"

: >"$FAKE_LOG"
out="$(cx green fake-thread-1 "$prompt" 2>/dev/null)"; st=$?
assert_eq "$st" 0 "green exits 0"
assert_eq "$out" "final answer" "green prints the final message"
assert_contains "$(cat "$FAKE_LOG")" 'exec resume fake-thread-1 -c sandbox_mode="workspace-write" --json -o' "green resumes the thread with workspace-write"
assert_contains "$(cat "$FAKE_LOG.stdin")" "PROMPT-MARKER" "green passes the prompt file on stdin"

echo "== idle =="
start="$(date +%s)"
cx FAKE_MODE=hang PASADENA_CODEX_IDLE=1 explore "$prompt" >/dev/null 2>&1; st=$?
assert_eq "$st" 124 "silent codex is stopped with 124"
assert_eq "$(( $(date +%s) - start < 10 ))" 1 "idle stop happens within seconds"
cx FAKE_MODE=cmd PASADENA_CODEX_IDLE=1 PASADENA_CODEX_CMD_IDLE=10 explore "$prompt" >/dev/null 2>&1
assert_eq "$?" 0 "a running command gets the command idle limit"

echo "== failures =="
cx FAKE_MODE=quota explore "$prompt" >/dev/null 2>&1; assert_eq "$?" 75 "usage limit exits 75"
assert_eq "$([ -e "$marker" ] && echo present || echo gone)" present "usage limit leaves the marker"
cx available; assert_eq "$?" 1 "available is off after the usage limit"
rm -f "$marker"
cx FAKE_MODE=empty explore "$prompt" >/dev/null 2>&1; assert_eq "$?" 1 "empty final message is a failure"
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
```

- [x] **Step 2: edit `skills/skills.test.sh`** — replace the whole `echo "Claude Code only"` block (from `echo "Claude Code only"` through `[ "$fails" -eq "$before" ] && ok "no Codex support left"`) with:

```bash
echo "Claude Code only"
before=$fails
for path in .codex-plugin .agents/plugins/marketplace.json hooks/hooks.json; do
  [ ! -e "$ROOT/$path" ] || fail "$path: Codex artifact still present"
done
hosted="$(git -C "$ROOT" grep -l -E '\.codex-plugin|Codex plan mode|Codex workflow' -- ':!docs/sdd' ':!skills/skills.test.sh')"
[ -z "$hosted" ] || fail "Codex host support mentioned in: $(tr '\n' ' ' <<<"$hosted")"
hosts="$(git -C "$ROOT" grep -l 'host does not prefix' -- skills ':!skills/skills.test.sh')"
[ -z "$hosts" ] || fail "host-neutral skill wording remains in: $(tr '\n' ' ' <<<"$hosts")"
[ "$fails" -eq "$before" ] && ok "no Codex host support left"

echo "Codex delegation"
before=$fails
require leonard "**Executor:** codex | claude"
require leonard "codex.sh available"
require leonard "codex.sh explore"
require leslie "codex.sh explore"
require sheldon "codex.sh explore"
require wolowitz "codex.sh explore"
require wolowitz "codex.sh red"
require wolowitz "codex.sh green"
require wolowitz "codex.sh review"
require wolowitz "Gate red"
require wolowitz "Gate green"
require wolowitz "implementer-prompt-codex.md"
codex_prompt="$SKILLS/wolowitz/implementer-prompt-codex.md"
if [ -f "$codex_prompt" ]; then
  ! grep -q "Skill tool" "$codex_prompt" || fail "implementer-prompt-codex.md: tells Codex to use the Skill tool"
  grep -qF "only the tests" "$codex_prompt" || fail "implementer-prompt-codex.md: missing \"only the tests\""
else
  fail "skills/wolowitz/implementer-prompt-codex.md: missing"
fi
for readme in README.md README.uk.md; do
  for needle in PASADENA_CODEX_IDLE PASADENA_CODEX_CMD_IDLE PASADENA_CODEX_MODEL "bash hooks/codex.test.sh"; do
    grep -qF -- "$needle" "$ROOT/$readme" || fail "$readme: missing \"$needle\""
  done
done
grep -q '"version": "0.10.0"' "$ROOT/.claude-plugin/plugin.json" || fail "plugin.json: version is not 0.10.0"
[ "$fails" -eq "$before" ] && ok "codex delegation documented"
```

- [x] **Step 3: run them, watch them fail** —
  `bash skills/skills.test.sh` → last line `FAILED: 22` (12 `require` + missing prompt file + 8 README needles + version); the "Claude Code only" group stays `ok` although `hooks/codex.test.sh` now mentions codex.
  `bash hooks/codex.test.sh` → last line `FAILED: <n>`, every check failing because `hooks/codex.sh` does not exist (bash exits 127), except "idle stop happens within seconds".
  `bash hooks/journal.test.sh`, `bash hooks/nudge.test.sh`, `bash proto/server.test.sh` → `All checks passed.`

---

### Task 1: `hooks/codex.sh`

**Writes:** `hooks/codex.sh`
**Reads:** `hooks/codex.test.sh`, `hooks/journal.sh` (style: `set -uo pipefail`, `case "$sub"` dispatch)
**Depends on:** Task 0
**Executor:** claude
**Satisfies:** every check in `hooks/codex.test.sh`
**Interfaces:**
- Produces: the subcommands, exit codes, env vars, marker path and usage line listed in Global constraints.

- [ ] **Step 1: run the acceptance tests, watch them fail** — `bash hooks/codex.test.sh`, expect `FAILED:` (script missing).
- [ ] **Step 2: write `hooks/codex.sh`:**

```bash
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

run() {
  local input="$1" pid status open limit usage_line
  shift
  : >"$events"
  codex "$@" <"$input" >"$events" 2>"$work/stderr" &
  pid=$!
  while kill -0 "$pid" 2>/dev/null; do
    sleep 1
    open="$(jq -s '[.[] | select(.item.type? == "command_execution") | if .type == "item.started" then 1 elif .type == "item.completed" then -1 else 0 end] | add // 0' "$events" 2>/dev/null || echo 0)"
    limit="$PASADENA_CODEX_IDLE"
    [ "${open:-0}" -gt 0 ] && limit="$PASADENA_CODEX_CMD_IDLE"
    if [ $(($(date +%s) - $(mtime "$events"))) -gt "$limit" ]; then
      kill "$pid" 2>/dev/null
      wait "$pid" 2>/dev/null
      echo "codex: no events for ${limit}s, stopped" >&2
      return 124
    fi
  done
  wait "$pid"
  status=$?
  usage_line="$(jq -r 'select(.type == "turn.completed") | .usage | "codex usage: input=\(.input_tokens) cached=\(.cached_input_tokens) output=\(.output_tokens)"' "$events" 2>/dev/null | tail -1)"
  [ -n "$usage_line" ] && echo "$usage_line" >&2
  if jq -r 'select(.type == "error" or .type == "turn.failed") | (.message // .error.message // "")' "$events" 2>/dev/null | grep -qiE 'usage limit|rate limit|quota'; then
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
trap 'rm -rf "$work"' EXIT
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
    git diff "$2..HEAD" >"$work/diff"
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
```

- [ ] **Step 3: run them, watch them pass** — `bash hooks/codex.test.sh`, expect `All checks passed.`

---

### Task 2: `wolowitz` runs Codex tasks, explore and review

**Writes:** `skills/wolowitz/SKILL.md`, `skills/wolowitz/implementer-prompt-codex.md`
**Reads:** `skills/wolowitz/implementer-prompt.md`, `skills/wolowitz/reviewer-prompt.md`
**Depends on:** Task 0
**Executor:** claude
**Satisfies:** `skills.test.sh` → `require wolowitz …` (8 checks) and the `implementer-prompt-codex.md` checks

- [ ] **Step 1: watch them fail** — `bash skills/skills.test.sh`, expect `FAIL — wolowitz: missing "codex.sh red"` among the failures.
- [ ] **Step 2: edit `skills/wolowitz/SKILL.md`:**
  1. In `## Models`, replace the row `| Read-only \`Explore\` lookup | \`sonnet\` is allowed |` with
     `| Read-only lookup | \`codex.sh explore <prompt-file>\` when \`codex.sh available\` exits 0; otherwise \`Explore\` on \`sonnet\` |`
  2. Insert a new section directly after `## Without subagents` (before `## Setup`):

~~~markdown
## Codex tasks

`codex.sh` lives beside `journal.sh`; the session-start digest names that
directory. A task with `**Executor:** codex` runs as two Codex calls with your
own gates between them, because Codex cannot load amy and its report is not
evidence. Start every `codex.sh` call through Bash with `run_in_background`.

1. **Red.** Write a prompt file in the scratchpad: the full text of
   `skills/amy/SKILL.md`, then `implementer-prompt-codex.md` filled in for the
   task. Run `codex.sh red <prompt-file>`. Line 1 of its output is the thread
   id; keep it.
2. **Gate red.** Check it yourself:
   - of the task's `**Writes:**` files, only test files changed;
   - the task's verification command is red, and each failure is the reason
     the plan predicts — a syntax or import error does not count;
   - record `sha256sum` of the task's test files.
   When the gate fails, run `codex.sh green <thread-id> <prompt-file>` with a
   prompt that names the problem and says to fix the tests only, then run Gate
   red again.
3. **Green.** Run `codex.sh green <thread-id> <prompt-file>` with a prompt that
   says: write the minimum code that makes these tests pass; do not edit the
   tests.
4. **Gate green.**
   - `sha256sum` of the test files matches the recorded one;
   - every file the task changed is in its `**Writes:**`;
   - the task's verification command is green.
5. The rest of the wave — suite, review, commit, PR comment — is unchanged.

Fix loop: rounds 1–2 go to `codex.sh green <thread-id>` with the findings
verbatim; round 3 goes to a fresh Claude implementer on the session's model.
When `codex.sh` exits non-zero, the task goes to a Claude implementer at once
and the wave's PR comment names the exit code. Exit `75` means the ChatGPT
plan's usage limit: tell the user in one line that Codex is off for the rest
of the session and Claude usage is no longer being saved. The wave's PR
comment sums the `codex usage:` lines its Codex calls printed on stderr.
~~~

  3. In `### 2. Dispatch the whole wave at once`, after the bullet list that ends with `` - `model` set to the session's model, per **Models**. `` add the paragraph:
     `A task whose block says \`**Executor:** codex\` is not dispatched through the Agent tool: run it through **Codex tasks**, started in the same message as the wave's Claude dispatches. When \`codex.sh available\` exits non-zero at build time, dispatch it as a Claude task and say so in the wave's PR comment.`
  4. In `### 4. Review the wave`, after the paragraph starting `One reviewer on \`fable\``, add:
     `When \`codex.sh available\` exits 0, run \`codex.sh review <BASE> skills/wolowitz/reviewer-prompt.md\` in the background in the same message as the \`fable\` dispatch. Every \`fable\` finding goes to the fix loop. A Codex finding goes there only after you confirm it yourself at its \`file:line\`; drop the unconfirmed ones with a one-line note in the wave's PR comment. The \`fable\` verdict stays the verdict.`
  5. In `## Finish`, item 1, append the sentence:
     `With \`codex.sh available\`, run \`codex.sh review $(git merge-base <trunk> HEAD) skills/wolowitz/reviewer-prompt.md\` beside it and merge its findings by the rule in step 4.`
- [ ] **Step 3: write `skills/wolowitz/implementer-prompt-codex.md`:**

~~~markdown
# Codex implementer prompt

Fill the angle brackets. The controller puts the full text of
`skills/amy/SKILL.md` above this prompt and sends both to `codex.sh red`.

---

You are implementing one task of an approved plan, in two steps. Other agents
are implementing other tasks of the same wave right now, in this same worktree.

**Working directory:** `<absolute path to the worktree>`

**Your task:** Task `<N>` in `<path to the plan>`.
Read **only** that task's block and the `## Global constraints` section.

**Spec:** `<path>` — read it if the task's intent is unclear.

**Context you cannot get from the task text:**
<interfaces and decisions from earlier waves; the controller's resolution of
any ambiguity>

## This step: only the tests

Write only the tests of your task's red steps. Do not create or edit any
non-test file. Run the task's verification command and confirm every new test
fails for the reason the task predicts. The controller runs it again and
checks.

The next message, in this same session, asks for the implementation.

## Rules

1. The rules of amy above apply to every step: the test comes first, you
   watch it fail for the right reason, you write the minimum that passes.
2. Write only the files your task's `**Writes:**` line names. If the task
   cannot be done without another file, stop and report `BLOCKED` with its
   name.
3. Do not commit. Run only the task's verification command, not the whole
   suite.
4. Use exactly the names, strings, numbers and signatures the task gives.
5. When you implement, do not edit the tests. The controller checks their
   checksums.

## Report

Under twenty-five lines:

- **Status:** DONE | DONE_WITH_CONCERNS | BLOCKED
- Files you wrote
- The last lines (up to 10) of your verification command's output and its exit code, pasted
- Anything you decided that the task did not specify
~~~

- [ ] **Step 4: watch them pass** — `bash skills/skills.test.sh`: no `FAIL — wolowitz` and no `implementer-prompt-codex.md` line remains.

---

### Task 3: `leonard` marks Executor and delegates explore

**Writes:** `skills/leonard/SKILL.md`
**Depends on:** Task 0
**Executor:** claude
**Satisfies:** `require leonard "**Executor:** codex | claude"`, `require leonard "codex.sh available"`, `require leonard "codex.sh explore"`

- [ ] **Step 1: watch them fail** — `bash skills/skills.test.sh`, expect `FAIL — leonard: missing "codex.sh explore"`.
- [ ] **Step 2: edit `skills/leonard/SKILL.md`:**
  1. After the bullet list under `Explore before decomposing` (it ends with the `**Enumerate every file**` bullet), add:
     `When \`codex.sh available\` exits 0 (\`codex.sh\` lives beside \`journal.sh\`), hand the bulk reading to \`codex.sh explore <prompt-file>\`: ask for the stack, conventions, reusable helpers and the files each task touches, as facts with \`file:line\`. You draw the conclusions. Confirm with one \`Read\` or \`grep\` every fact a task will rely on — a signature, a name, a path — before it goes into the plan.`
  2. In the example task block, add the line `**Executor:** codex` directly after `**Depends on:** Task 1`.
  3. In the Task 0 template, add `**Executor:** claude` directly after the `**Writes:**` line.
  4. After the paragraph starting ``**Writes:**` is load-bearing`, add:

~~~markdown
`**Executor:** codex | claude` says who implements the task. Write `codex`
only when all of these hold:

- `**Writes:**` names at most 3 files, one of them a test;
- no other task names it in `**Depends on:**`;
- every name, string, number and signature is given in the task text;
- `codex.sh available` exits 0 while you plan.

Otherwise write `claude`. Task 0 is always `**Executor:** claude`. The user
sees the split when approving the plan.
~~~

- [ ] **Step 3: watch them pass** — `bash skills/skills.test.sh`: no `FAIL — leonard` line remains.

---

### Task 4: `leslie` and `sheldon` delegate explore

**Writes:** `skills/leslie/SKILL.md`, `skills/sheldon/SKILL.md`
**Depends on:** Task 0
**Executor:** claude
**Satisfies:** `require leslie "codex.sh explore"`, `require sheldon "codex.sh explore"`

- [ ] **Step 1: watch them fail** — `bash skills/skills.test.sh`, expect `FAIL — leslie: missing "codex.sh explore"` and the same for sheldon.
- [ ] **Step 2: edit `skills/leslie/SKILL.md`** — at the end of `## Phase 2 — Pattern` (after item 3), add:
  `In both phases, when \`codex.sh available\` exits 0 (\`codex.sh\` lives beside \`journal.sh\`), hand the bulk reading — where the code lives, the call chain, working analogues and their differences — to \`codex.sh explore <prompt-file>\`, asking for facts with \`file:line\`. Reproducing and instrumenting stay yours, and so does the hypothesis: confirm each fact it rests on with one \`Read\` or \`grep\`.`
- [ ] **Step 3: edit `skills/sheldon/SKILL.md`** — in `## Understand the idea`, after the first paragraph (ends `the existing repository context.`), add:
  `When \`codex.sh available\` exits 0 (\`codex.sh\` lives beside \`journal.sh\`), hand the survey of a large repository to \`codex.sh explore <prompt-file>\` and ask for facts with \`file:line\`. The questions and the design stay yours; confirm with one \`Read\` or \`grep\` each fact a question or the spec rests on.`
- [ ] **Step 4: watch them pass** — `bash skills/skills.test.sh`: no `FAIL — leslie` or `FAIL — sheldon` line remains.

---

### Task 5: README, checks list and version 0.10.0

**Writes:** `README.md`, `README.uk.md`, `.claude-plugin/plugin.json`, `.claude-plugin/marketplace.json`
**Depends on:** Task 0
**Executor:** claude
**Satisfies:** the 8 README needles and the `0.10.0` version check in `skills.test.sh`

- [ ] **Step 1: watch them fail** — `bash skills/skills.test.sh`, expect `FAIL — README.md: missing "PASADENA_CODEX_IDLE"` and `FAIL — plugin.json: version is not 0.10.0`.
- [ ] **Step 2: `README.md`** — insert before `## Checks`:

~~~markdown
## Codex delegation

When the Codex CLI is installed and logged in, the skills hand part of the work to `codex exec` to save Claude usage. Claude stays the orchestrator and checks every result itself. Codex runs here as a worker, not as a plugin host.

- **explore** — `leonard`, `leslie`, `sheldon` and `wolowitz` send bulk read-only lookups to Codex and get back facts with `file:line`.
- **review** — `wolowitz` runs a Codex review of the local diff beside the `fable` reviewer; only findings Claude confirms count.
- **implement** — plan tasks marked `**Executor:** codex` are written by Codex in two calls, tests first and then code, with Claude running the tests between them.

| Variable | Default | Effect |
|---|---|---|
| `PASADENA_CODEX` | `1` | `0` turns delegation off |
| `PASADENA_CODEX_IDLE` | `120` | seconds without a Codex event before the call is stopped |
| `PASADENA_CODEX_CMD_IDLE` | `600` | the same limit while Codex runs a command |
| `PASADENA_CODEX_MODEL` | — | passed to Codex as `-m` |

Codex spends your ChatGPT plan's usage. When it runs out, `hooks/codex.sh` exits `75`, the skills tell you once, and delegation stays off for six hours or until you delete `~/.local/state/pasadena/codex-exhausted`.
~~~

  In `## Checks`, add `bash hooks/codex.test.sh` as the last line of the code block, and append to the paragraph below it: `The Codex checks run \`hooks/codex.sh\` against a fake \`codex\` and cover availability, each subcommand's flags, the idle stop and the usage-limit marker.`
- [ ] **Step 3: `README.uk.md`** — insert before `## Перевірки`:

~~~markdown
## Делегування в Codex

Якщо Codex CLI встановлено і в ньому виконано вхід, skills віддають частину роботи в `codex exec`, щоб заощадити ліміти Claude. Claude лишається оркестратором і сам перевіряє кожен результат. Codex тут виконавець, а не хост плагіна.

- **explore** — `leonard`, `leslie`, `sheldon` і `wolowitz` віддають Codex об'ємні read-only пошуки й отримують факти з `file:line`.
- **review** — `wolowitz` запускає Codex-ревʼю локального diff поруч із ревʼюером `fable`; зараховуються лише знахідки, які підтвердив Claude.
- **implement** — задачі плану з `**Executor:** codex` Codex пише у два виклики: спершу тести, потім код, а Claude між ними сам запускає тести.

| Змінна | За замовчуванням | Дія |
|---|---|---|
| `PASADENA_CODEX` | `1` | `0` вимикає делегування |
| `PASADENA_CODEX_IDLE` | `120` | секунд без подій від Codex, після яких виклик зупиняється |
| `PASADENA_CODEX_CMD_IDLE` | `600` | той самий ліміт, поки Codex виконує команду |
| `PASADENA_CODEX_MODEL` | — | передається в Codex як `-m` |

Codex витрачає ліміти вашого ChatGPT-плану. Коли вони закінчуються, `hooks/codex.sh` завершується з кодом `75`, skills один раз про це кажуть, і делегування вимикається на шість годин або доки ви не видалите `~/.local/state/pasadena/codex-exhausted`.
~~~

  In `## Перевірки`, add `bash hooks/codex.test.sh` as the last line of the code block, and append: `Перевірки Codex запускають \`hooks/codex.sh\` з фейковим \`codex\` і покривають доступність, прапорці кожної підкоманди, зупинку за простоєм і маркер вичерпаного ліміту.`
- [ ] **Step 4: versions** — in `.claude-plugin/plugin.json` and `.claude-plugin/marketplace.json` change `"version": "0.9.0"` to `"version": "0.10.0"`.
- [ ] **Step 5: watch them pass** — `bash skills/skills.test.sh`, expect `All checks passed.` once Tasks 2–4 are in; at minimum no README or version `FAIL` line remains.

---

### Task 6: end-to-end check with the real `codex`

**Writes:** none in the repository (a throwaway repo in the session scratchpad)
**Depends on:** Tasks 1, 2, 3, 4, 5
**Executor:** claude (run by the controller itself, not dispatched)
**Covers:** spec §6 item 4

- [ ] **Step 1:** `bash hooks/codex.sh available; echo $?` → `0`; `PASADENA_CODEX=0 bash hooks/codex.sh available; echo $?` → `1` (a `codex` task then runs as a Claude task).
- [ ] **Step 2:** in `<scratchpad>/e2e`, `git init` and commit an empty base; write `plan.md` with one task: **Writes:** `sum.sh`, `sum.test.sh`; `sum.sh` prints the sum of its two integer arguments; verification `bash sum.test.sh`, expect `All checks passed.`; red reason: `sum.sh: No such file`.
- [ ] **Step 3: red** — build the prompt file per `## Codex tasks` in `skills/wolowitz/SKILL.md`, run `bash <repo>/hooks/codex.sh red <prompt>` from `<scratchpad>/e2e`; Gate red: only `sum.test.sh` exists, `bash sum.test.sh` fails with `No such file`; record `sha256sum sum.test.sh`.
- [ ] **Step 4: green** — `bash <repo>/hooks/codex.sh green <thread-id> <prompt>`; Gate green: `sha256sum sum.test.sh` unchanged, `bash sum.test.sh` → `All checks passed.`
- [ ] **Step 5:** paste both gate outputs and both `codex usage:` lines into the wave's PR comment.
