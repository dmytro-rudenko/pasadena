# Codex modes: `/codex-mode explore | full | auto` — implementation plan

**Goal:** `/codex-mode` shows and sets a global Codex mode (`explore`, `full`, `auto`) and a per-branch mode (`explore`, `full`) in the journal. The session-start digest names the effective mode. `sheldon` resolves `auto`. In `full`, `leonard`, `wolowitz` and `amy` hand every task except Task 0 to Codex, within the Codex usage budget read by `codex.sh budget`, and the final review is done by Claude only.
**Spec:** docs/sdd/specs/2026-11-03-codex-mode.md
**Verification:** `bash hooks/codex.test.sh && bash hooks/journal.test.sh && bash skills/skills.test.sh` — each prints `All checks passed.` as its last line.

## Context

Today Codex reads code, reviews the branch once at Finish, and implements only the narrow tasks that pass `leonard`'s five conditions. The user wants an explicit switch: `full` (Codex builds, Claude plans, gates and reviews), `explore` (today's behaviour), and `auto` (`sheldon` picks a mode by risk). In `full` and `auto`, Codex gets only as many tasks as the remaining ChatGPT-plan limit allows.

**Executor split:** every task is `claude`. `codex.sh available` exits 1 while planning, because the weekly Codex limit is at 100%. The mode feature does not exist yet, so the `explore` rules apply.

## Waves
| Wave | Tasks | Why together |
|---|---|---|
| 0 | 0 | alone — acceptance checks in `skills/skills.test.sh`, red until the last wave |
| 1 | 1, 5, 6, 7, 8, 9, 10, 11 | disjoint files: `hooks/codex.sh`+test, `skills/sheldon`, `skills/raj`, `skills/leonard`, `skills/wolowitz`, `skills/amy`, READMEs, manifests |
| 2 | 2, 3 | disjoint: `hooks/codex.sh`+test vs `hooks/journal.sh`+test |
| 3 | 4 | alone — the command calls `codex.sh mode` (Task 1) and `journal.sh codex-mode` (Task 3) |

Serialized: Tasks 1 and 2 both write `hooks/codex.sh` and `hooks/codex.test.sh`, so they run in two waves. Task 3 consumes `codex.sh mode get` from Task 1. Task 4 consumes the outputs of Tasks 1 and 3.

## Global constraints
- Bash scripts keep `set -uo pipefail`, two-space indent, and the `usage` → exit 2 convention of `hooks/codex.sh`.
- State lives under `${XDG_STATE_HOME:-$HOME/.local/state}/pasadena/`:
  - mode file `codex-mode`, one line, one of `explore`, `full`, `auto`;
  - cost log `codex-cost.tsv`, lines `<epoch>\t<routine|complex>\t<pct>`.
- Codex limits come from `${CODEX_HOME:-$HOME/.codex}/sessions/**/rollout-*.jsonl`. Each line is JSON, and the relevant records are `{"type":"event_msg","payload":{"type":"token_count","rate_limits":{"primary":{...},"secondary":{...}}}}`. `primary` is the 5-hour window and `secondary` the weekly window. Each window has `used_percent` (float), `window_minutes` and `resets_at` (epoch seconds).
- Journal field: `codex-mode: explore|full` in the frontmatter, directly after `plan:`. It is never `auto`.
- Digest line: `Codex mode: <mode> (branch).` when the journal has the field, otherwise `Codex mode: <global mode> (global).`.
- The reserve is `10` percentage points of the weekly window. The default estimates are `3` for `routine` and `6` for `complex`.
- Skill text is English. Code identifiers and commands stay verbatim. No code comments unless they record a non-obvious constraint (AGENTS.md).
- Plugin version becomes `0.21.0` in both manifests.

## Review Focus
- `codex.sh budget` when the newest rollout file has no `rate_limits` but an older one does: the older file's values are used.
- `journal.sh codex-mode` on a journal without a `plan:` line: the field goes in just before the closing `---`, and nothing is duplicated.
- `journal.sh codex-mode` must not block on stdin, since it is invoked by hand like `note`.
- The `journal.test.sh` digest checks must not depend on the developer's real `~/.local/state/pasadena/codex-exhausted` or `codex-mode`. Today three of them fail on a machine whose Codex limit is exhausted.
- `codex.sh cost estimate` with an even number of entries rounds the median up (2, 5 → `4`).

---

### Task 0: acceptance tests

**Writes:** `skills/skills.test.sh`
**Executor:** claude
**Covers:**
- "`bash skills/skills.test.sh` → усі зелені" (spec §6, with the `require` list in §3.10)
- "наявність `commands/codex-mode.md`"
- "`README.md` і `README.uk.md`, розділ «Codex delegation»: три режими, команда"
- "Версія `0.20.0` → `0.21.0`"

- [x] **Step 1: write the acceptance tests.** In `skills/skills.test.sh`, directly after the line `[ "$fails" -eq "$before" ] && ok "codex delegation documented"`, insert:

```bash

echo "Codex mode"
before=$fails
require sheldon "Codex mode: auto"
require sheldon "journal.sh codex-mode"
require sheldon "codex.sh mode get"
require raj "journal.sh codex-mode"
require leonard "Codex mode: full"
require leonard "Codex budget:"
require leonard "codex.sh budget"
require leonard "codex.sh cost estimate"
require wolowitz "Codex mode: full"
require wolowitz "codex budget: exhausted"
require wolowitz "codex.sh cost add"
require wolowitz "codex review: skipped (codex-mode full)"
require amy "codex.sh red"
require amy "codex.sh budget"
mode_cmd="$ROOT/commands/codex-mode.md"
if [ -f "$mode_cmd" ]; then
  for needle in "argument-hint:" "codex.sh mode set" "journal.sh codex-mode" "--branch"; do
    grep -qF -- "$needle" "$mode_cmd" || fail "commands/codex-mode.md: missing \"$needle\""
  done
else
  fail "commands/codex-mode.md: missing"
fi
for readme in README.md README.uk.md; do
  for needle in "/codex-mode" "codex.sh budget" "codex-cost.tsv"; do
    grep -qF -- "$needle" "$ROOT/$readme" || fail "$readme: missing \"$needle\""
  done
done
[ "$fails" -eq "$before" ] && ok "codex mode documented"
```

  Also change the line `grep -qF '"version": "0.20.0"' "$ROOT/$manifest" || fail "$manifest: not on 0.20.0"` to `grep -qF '"version": "0.21.0"' "$ROOT/$manifest" || fail "$manifest: not on 0.21.0"`.
- [x] **Step 2: run them and watch them fail.** Run `bash skills/skills.test.sh` and expect last line `FAILED: 23`: 14 `require` lines, 1 missing command file, 6 README needles and 2 manifest versions. The behaviour is missing.

### Task 1: `codex.sh mode`

**Writes:** `hooks/codex.sh`, `hooks/codex.test.sh`
**Reads:** `hooks/codex.sh` (`usage`, first `case "$sub"` dispatch at the `sub="${1:-}"` line), `hooks/codex.test.sh` (`cx`, `assert_eq`, `$XDG_STATE_HOME`, `$tmp`)
**Depends on:** Task 0
**Executor:** claude
**Complexity:** complex
**Satisfies:** spec §6 "`bash hooks/codex.test.sh` → зелений" (mode part)
**Interfaces:**
- Produces: `bash codex.sh mode [get]` prints one of `explore|full|auto` and exits 0. `bash codex.sh mode set <explore|full|auto>` writes the mode file and exits 0. Anything else exits 2 through `usage`. The subcommand writes no `codex.log` and sets no traps.

- [x] **Step 1: write the failing test.** In `hooks/codex.test.sh`, insert directly before the line `rm -rf "$tmp"`:

```bash
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
```

- [x] **Step 2: run it and watch it fail.** Run `bash hooks/codex.test.sh` and expect `FAILED:` as the last line. The `mode` checks fail because `mode` currently hits `usage`.
- [x] **Step 3: implement.** In `hooks/codex.sh`:
  - After the `log_max=1048576` line, add:
    ```bash
    mode_file="${XDG_STATE_HOME:-$HOME/.local/state}/pasadena/codex-mode"
    ```
  - Change the `usage` echo to:
    ```bash
    echo "usage: codex.sh available | explore <prompt-file> | review <base> <prompt-file> | red <prompt-file> | green <thread-id> <prompt-file> | mode [get | set <explore|full|auto>]" >&2
    ```
  - Add this after `cmd_available() { … }`:
    ```bash
    cmd_mode() {
      local m=""
      case "${1:-get}" in
        get)
          [ -f "$mode_file" ] && m="$(head -1 "$mode_file")"
          case "$m" in explore | full | auto) ;; *) m=explore ;; esac
          echo "$m"
          ;;
        set)
          case "${2:-}" in explore | full | auto) ;; *) usage ;; esac
          mkdir -p "$(dirname "$mode_file")"
          echo "$2" >"$mode_file"
          ;;
        *) usage ;;
      esac
      exit 0
    }
    ```
  - In the first dispatch `case "$sub" in`, before `explore | review | red | green) ;;`, add:
    ```bash
      mode) cmd_mode "${2:-get}" "${3:-}" ;;
    ```
- [x] **Step 4: run it and watch it pass.** Run `bash hooks/codex.test.sh` and expect `All checks passed.`

### Task 2: `codex.sh budget` and `codex.sh cost`

**Writes:** `hooks/codex.sh`, `hooks/codex.test.sh`
**Reads:** `hooks/codex.sh` (after Task 1: `mode_file`, `cmd_mode`, first dispatch), `hooks/codex.test.sh`
**Depends on:** Task 1
**Executor:** claude
**Complexity:** complex
**Satisfies:** spec §6 "`bash hooks/codex.test.sh` → зелений" (budget/cost part)
**Interfaces:**
- Produces:
  - `bash codex.sh budget` prints `weekly_left=<n> weekly_used=<n> five_hour_left=<n> five_hour_reset=<epoch>` and exits 0. When no rollout file with a non-null `rate_limits` exists, it exits 1 with empty stdout.
  - `bash codex.sh cost add <routine|complex> <non-negative int>` appends to `codex-cost.tsv` and exits 0.
  - `bash codex.sh cost estimate <routine|complex>` prints an integer ≥ 1.
  - Bad arguments exit 2.
  - Neither subcommand writes `codex.log` or sets traps.

- [ ] **Step 1: write the failing test.** In `hooks/codex.test.sh`, insert directly before the line `rm -rf "$tmp"` (after Task 1's `== mode ==` block):

```bash
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
out="$(cx CODEX_HOME="$chome" XDG_STATE_HOME="$bstate" budget)"
assert_eq "$out" "weekly_left=59 weekly_used=41 five_hour_left=73 five_hour_reset=$future" "budget reads the last rate_limits, skipping a newer file without them"
echo '{"type":"event_msg","payload":{"type":"token_count","rate_limits":{"primary":{"used_percent":99.0,"window_minutes":300,"resets_at":'"$past"'},"secondary":{"used_percent":100.0,"window_minutes":10080,"resets_at":'"$past"'}}}}' >>"$new"
out="$(cx CODEX_HOME="$chome" XDG_STATE_HOME="$bstate" budget)"
assert_eq "$out" "weekly_left=100 weekly_used=0 five_hour_left=100 five_hour_reset=$past" "a window whose reset is past counts as fresh"
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
```

- [ ] **Step 2: run it and watch it fail.** Run `bash hooks/codex.test.sh` and expect `FAILED:` as the last line. The budget and cost checks fail because both subcommands currently hit `usage`.
- [ ] **Step 3: implement.** In `hooks/codex.sh`:
  - After the `mode_file=` line, add:
    ```bash
    cost_file="${XDG_STATE_HOME:-$HOME/.local/state}/pasadena/codex-cost.tsv"
    codex_home="${CODEX_HOME:-$HOME/.codex}"
    ```
  - Change the `usage` echo to:
    ```bash
    echo "usage: codex.sh available | explore <prompt-file> | review <base> <prompt-file> | red <prompt-file> | green <thread-id> <prompt-file> | mode [get | set <explore|full|auto>] | budget | cost add <routine|complex> <pct> | cost estimate <routine|complex>" >&2
    ```
  - Add this after `cmd_mode() { … }`:
    ```bash
    cmd_budget() {
      local f rl="" files=()
      while IFS= read -r -d '' f; do files+=("$f"); done < <(find "$codex_home/sessions" -type f -name 'rollout-*.jsonl' -print0 2>/dev/null)
      [ "${#files[@]}" -gt 0 ] || exit 1
      while IFS= read -r f; do
        rl="$(jq -c 'select(.payload.rate_limits? != null) | .payload.rate_limits' "$f" 2>/dev/null | tail -1)"
        [ -z "$rl" ] || break
      done < <(ls -t "${files[@]}")
      [ -n "$rl" ] || exit 1
      jq -r --argjson now "$(date +%s)" '
        def used($w): if $w == null or (($w.resets_at // 0) <= $now) then 0 else ($w.used_percent // 0 | ceil) end;
        used(.secondary) as $wu | used(.primary) as $fu |
        "weekly_left=\([100 - $wu, 0] | max) weekly_used=\($wu) five_hour_left=\([100 - $fu, 0] | max) five_hour_reset=\(.primary.resets_at // 0)"
      ' <<<"$rl" || exit 1
      exit 0
    }

    cmd_cost() {
      case "${1:-}:${2:-}" in
        add:routine | add:complex | estimate:routine | estimate:complex) ;;
        *) usage ;;
      esac
      if [ "$1" = add ]; then
        [[ "${3:-}" =~ ^[0-9]+$ ]] || usage
        mkdir -p "$(dirname "$cost_file")"
        printf '%s\t%s\t%s\n' "$(date +%s)" "$2" "$3" >>"$cost_file"
        exit 0
      fi
      local vals default=3
      [ "$2" = complex ] && default=6
      vals="$(awk -F'\t' -v c="$2" '$2 == c { print $3 }' "$cost_file" 2>/dev/null | tail -10 | sort -n)"
      if [ -z "$vals" ]; then
        echo "$default"
        exit 0
      fi
      awk '{ a[NR] = $1 } END {
        m = (NR % 2) ? a[(NR + 1) / 2] : (a[NR / 2] + a[NR / 2 + 1]) / 2
        r = int(m); if (r < m) r++; if (r < 1) r = 1
        print r
      }' <<<"$vals"
      exit 0
    }
    ```
  - In the first dispatch `case "$sub" in`, after the `mode)` line, add:
    ```bash
      budget) cmd_budget ;;
      cost) cmd_cost "${2:-}" "${3:-}" "${4:-}" ;;
    ```
- [ ] **Step 4: run it and watch it pass.** Run `bash hooks/codex.test.sh` and expect `All checks passed.`

### Task 3: `journal.sh codex-mode` and the digest line

**Writes:** `hooks/journal.sh`, `hooks/journal.test.sh`
**Reads:** `hooks/journal.sh` (stdin `case "$sub"`, `frontmatter`, `append_line`, `codex_line`, final dispatch), `hooks/journal.test.sh` (`setup_repo`, `make_canonical_journal`, `assert_contains`)
**Depends on:** Task 1
**Executor:** claude
**Complexity:** complex
**Satisfies:** spec §6 "`bash hooks/journal.test.sh` → зелений"
**Interfaces:**
- Consumes: `bash codex.sh mode get` (Task 1) prints `explore|full|auto`.
- Produces:
  - `bash journal.sh codex-mode <explore|full>`, run in the repo:
    - sets or replaces `codex-mode: <mode>` in the frontmatter (after `plan:`, or just before the closing `---` when there is no `plan:`);
    - appends `- HH:MM ✎ codex-mode: <mode>` to the timeline and exits 0.
  - With no journal it prints `no journal for <branch>` on stderr and exits 1. Any other value exits 2.
  - Digest line `Codex mode: <mode> (branch|global).` follows the `Codex: …` line in every session-start digest.

- [ ] **Step 1: write the failing test.** In `hooks/journal.test.sh`:
  - Directly after `fails=0`, add:
    ```bash
    export XDG_STATE_HOME="$(mktemp -d)"
    ```
  - Directly after the `assert_empty() { … }` function, add:
    ```bash
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
    ```
  - Directly before the final `echo` that precedes `if [ "$fails" -gt 0 ]`, add:

```bash
echo "== Codex mode =="

CODEX_SH="$(dirname "$HOOK")/codex.sh"
rm -f "$XDG_STATE_HOME/pasadena/codex-mode"

d="$(setup_repo)"
git -C "$d" checkout -q -b feat/x
err="$(cd "$d" && bash "$HOOK" codex-mode full 2>&1 >/dev/null)"; rc=$?
assert_eq "$rc" 1 "codex-mode without a journal exits 1"
assert_contains "$err" "no journal for feat/x" "codex-mode without a journal says so"

out="$(printf '{"cwd":"%s","source":"startup"}' "$d" | bash "$HOOK" session-start)"
ctx="$(jq -r '.hookSpecificOutput.additionalContext' <<<"$out")"
assert_contains "$ctx" "Codex mode: explore (global)." "no journal, no mode file: explore (global)"
bash "$CODEX_SH" mode set auto
out="$(printf '{"cwd":"%s","source":"startup"}' "$d" | bash "$HOOK" session-start)"
ctx="$(jq -r '.hookSpecificOutput.additionalContext' <<<"$out")"
assert_contains "$ctx" "Codex mode: auto (global)." "no journal: digest shows the global mode"

make_canonical_journal "$d" "feat-x"
jfile="$d/.pasadena/journal/feat-x.md"
(cd "$d" && bash "$HOOK" codex-mode full </dev/null); rc=$?
assert_eq "$rc" 0 "codex-mode full on a journal without plan: succeeds"
fm="$(awk 'NR == 1 { next } /^---$/ { exit } { print }' "$jfile")"
assert_eq "$(grep -c '^codex-mode: full$' <<<"$fm")" 1 "without plan: the field goes inside the frontmatter"

awk '/^status: in-progress$/ { print "spec: docs/sdd/specs/x.md"; print "plan: docs/sdd/plans/x.md" } { print }' \
  "$jfile" | grep -v '^codex-mode: ' >"$d/tmp" && mv "$d/tmp" "$jfile"
(cd "$d" && bash "$HOOK" codex-mode full </dev/null)
assert_eq "$(grep -A1 '^plan: ' "$jfile" | tail -1)" "codex-mode: full" "the field goes right after plan:"
(cd "$d" && bash "$HOOK" codex-mode explore </dev/null)
assert_eq "$(grep -c '^codex-mode: ' "$jfile")" 1 "a second call replaces the field"
assert_eq "$(grep -A1 '^plan: ' "$jfile" | tail -1)" "codex-mode: explore" "the replaced field holds the new mode"
assert_contains "$(tail -1 "$jfile")" "✎ codex-mode: explore" "the change is noted in the timeline"
(cd "$d" && bash "$HOOK" codex-mode auto 2>/dev/null </dev/null); rc=$?
assert_eq "$rc" 2 "auto is not a branch mode"
(cd "$d" && bash "$HOOK" codex-mode 2>/dev/null </dev/null); rc=$?
assert_eq "$rc" 2 "codex-mode without a value is a usage error"
assert_eq "$(grep -c '^codex-mode: explore$' "$jfile")" 1 "a rejected value leaves the field alone"

out="$(printf '{"cwd":"%s","source":"startup"}' "$d" | bash "$HOOK" session-start)"
ctx="$(jq -r '.hookSpecificOutput.additionalContext' <<<"$out")"
assert_contains "$ctx" "Codex mode: explore (branch)." "journal field wins over the global mode"
rm -rf "$d"
```

  - Directly after that new block, still before the final `echo`, add `rm -rf "$XDG_STATE_HOME"`.
- [ ] **Step 2: run it and watch it fail.** Run `bash hooks/journal.test.sh` and expect `FAILED:` as the last line. The `Codex mode` checks fail. The three `Codex: available` checks that fail today pass now, because `XDG_STATE_HOME` is isolated.
- [ ] **Step 3: implement.** In `hooks/journal.sh`:
  - Change the stdin case line `note) input='{}' ;;` to:
    ```bash
      note | codex-mode) input='{}' ;;
    ```
  - Replace `codex_line()` with:
    ```bash
    codex_line() {
      local sh m="" src=global
      sh="$(dirname "$0")/codex.sh"
      if bash "$sh" available >/dev/null 2>&1; then
        printf 'Codex: available — send read-only code lookups to `bash %s explore <prompt-file>` instead of Explore or a read-only fork.' "$sh"
      else
        printf 'Codex: off — do code lookups yourself.'
      fi
      [ -f "$file" ] && m="$(frontmatter codex-mode)"
      case "$m" in
        explore | full) src=branch ;;
        *) m="$(bash "$sh" mode get 2>/dev/null)"; [ -n "$m" ] || m=explore ;;
      esac
      printf '\nCodex mode: %s (%s).' "$m" "$src"
    }
    ```
  - Add this after `cmd_note() { … }`:
    ```bash
    cmd_codex_mode() {
      case "$arg" in
        explore | full) ;;
        *) echo "usage: journal.sh codex-mode explore|full" >&2; exit 2 ;;
      esac
      if [ ! -f "$file" ]; then
        echo "no journal for $branch" >&2
        exit 1
      fi
      awk -v m="$arg" '
        NR == 1 && $0 == "---" { inside = 1; print; next }
        inside && index($0, "codex-mode: ") == 1 { next }
        inside && index($0, "plan: ") == 1 { print; print "codex-mode: " m; done = 1; next }
        inside && $0 == "---" { if (!done) print "codex-mode: " m; inside = 0; print; next }
        { print }
      ' "$file" >"$file.tmp" && mv "$file.tmp" "$file"
      append_line "- $(date +%H:%M) ✎ codex-mode: $arg"
      exit 0
    }
    ```
  - In the final dispatch, after `note) cmd_note ;;`, add:
    ```bash
      codex-mode) cmd_codex_mode ;;
    ```
- [ ] **Step 4: run it and watch it pass.** Run `bash hooks/journal.test.sh` and expect `All checks passed.`

### Task 4: `/codex-mode` command

**Writes:** `commands/codex-mode.md`
**Reads:** `commands/bazinga.md` (command frontmatter style)
**Depends on:** Task 1, Task 3
**Executor:** claude
**Complexity:** routine
**Satisfies:** Task 0 checks `commands/codex-mode.md: missing` and its four needles.
**Interfaces:**
- Consumes: `codex.sh mode get|set <mode>` and `codex.sh available` (Task 1, existing), and `journal.sh codex-mode <explore|full>` (Task 3).

- [ ] **Step 1: see the failing check.** Run `bash skills/skills.test.sh` and confirm the output contains `FAIL — commands/codex-mode.md: missing`.
- [ ] **Step 2: implement.** Create `commands/codex-mode.md` with exactly:

````markdown
---
description: Show or set how much work Pasadena hands to Codex — explore, full or auto
argument-hint: [explore|full|auto] [--branch]
allowed-tools: Bash(bash ${CLAUDE_PLUGIN_ROOT}/hooks/codex.sh *), Bash(bash ${CLAUDE_PLUGIN_ROOT}/hooks/journal.sh *), Bash(git rev-parse *), Read
---

Arguments: `$ARGUMENTS`

Pasadena has three Codex modes:

- `explore` — Codex reads code and reviews the branch once at the finish; it
  implements only the narrow tasks `leonard` marks `**Executor:** codex`.
- `full` — Codex implements every task except Task 0, within the remaining
  Codex usage; Claude plans, runs the gates and does the final review alone.
- `auto` — `sheldon` picks `explore` or `full` per task from its
  classification and the task's risks.

The global mode applies to every branch. A branch's journal may hold its own
`codex-mode: explore|full` line, which wins on that branch.

Do exactly one of these, by the arguments:

1. **No arguments.** Run `bash ${CLAUDE_PLUGIN_ROOT}/hooks/codex.sh mode get`
   and `bash ${CLAUDE_PLUGIN_ROOT}/hooks/codex.sh available` (exit 0 means
   available). Read the `codex-mode:` line from
   `.pasadena/journal/<branch with / replaced by ->.md` at the repository root
   (`git rev-parse --show-toplevel`, `git rev-parse --abbrev-ref HEAD`); the
   value is `-` when the journal or the line is missing. Reply with three
   lines: `global: <mode>`, `branch: <mode or ->`, `codex: available | off`.
2. **`explore`, `full` or `auto`.** Run
   `bash ${CLAUDE_PLUGIN_ROOT}/hooks/codex.sh mode set <mode>` and report the
   new global mode. When the branch journal has a `codex-mode:` line, add that
   it still wins on this branch.
3. **`explore --branch` or `full --branch`.** Run
   `bash ${CLAUDE_PLUGIN_ROOT}/hooks/journal.sh codex-mode <mode>`. Exit 0:
   report the branch mode. Exit 1: say this branch has no journal and that
   `/pasadena` starts one; run nothing else.
4. **`auto --branch`.** Say a branch holds only `explore` or `full`, because
   `auto` is resolved by `sheldon` into one of them; run nothing.
5. **Anything else.** List the valid forms above; run nothing.
````

- [ ] **Step 3: run the check and watch it pass.** Run `bash skills/skills.test.sh` and confirm the output has no line starting `  FAIL — commands/codex-mode.md`.

### Task 5: `sheldon` resolves `auto`

**Writes:** `skills/sheldon/SKILL.md`
**Reads:** `skills/sheldon/SKILL.md` (`## Classify first — and say it out loud`, `## Step 0, architectural only: somewhere to work`)
**Depends on:** Task 0
**Executor:** claude
**Complexity:** routine
**Satisfies:** Task 0 `require sheldon "Codex mode: auto"`, `"journal.sh codex-mode"`, `"codex.sh mode get"`.

- [x] **Step 1: see the failing checks.** Run `bash skills/skills.test.sh` and confirm `FAIL — sheldon: missing "Codex mode: auto"` and the other two `sheldon` lines.
- [x] **Step 2: implement.** Insert this new section directly before the line `## Step 0, architectural only: somewhere to work`:

```markdown
## Codex mode

The session-start digest names the effective Codex mode in a line such as
`Codex mode: auto (global).`; with no such line, run `codex.sh mode get`
beside `journal.sh`. Only `auto` is yours to resolve. An explicit `explore` or
`full`, global or on the branch, stays as it is and is not asked about.

When the digest says `Codex mode: auto`, name the resolved mode out loud
together with the path:

- **Spike** → `explore`: nothing gets built.
- **Bounded** → `full`.
- **Architectural** that touches concurrency, persisted state or migrations,
  security, or an interface other components depend on → `explore`.
- **Any other Architectural** → one `AskUserQuestion`: `explore` or `full`,
  recommending `full`.

When the classification moves to a heavier path, resolve the mode again by the
same rules.

On the Architectural path, once `raj` has created the journal in Step 0, have
it record the mode with `journal.sh codex-mode <explore|full>` — the resolved
one, or the explicit global one. On the Bounded path the effective mode stays in
the conversation: name it when you invoke `amy`. With `full`, the in-chat design
lists the exact path of every file the change writes, the test file included;
`amy` builds the task's `**Writes:**` from that list.
```

- [x] **Step 3: run the checks and watch them pass.** Run `bash skills/skills.test.sh` and confirm none of the three `sheldon` lines from Step 1 remain.

### Task 6: `raj` records the branch mode

**Writes:** `skills/raj/SKILL.md`
**Reads:** `skills/raj/SKILL.md` (`## Create`)
**Depends on:** Task 0
**Executor:** claude
**Complexity:** routine
**Satisfies:** Task 0 `require raj "journal.sh codex-mode"`.

- [x] **Step 1: see the failing check.** Run `bash skills/skills.test.sh` and confirm `FAIL — raj: missing "journal.sh codex-mode"`.
- [x] **Step 2: implement.** In `## Create`, directly after the paragraph that begins ``"`spec:` and `plan:` point at whatever files"``, insert:

```markdown
The frontmatter may also hold `codex-mode: explore|full`, the branch's Codex
mode, which wins over the global one. Write it only through
`bash "<path from the session-start digest>" codex-mode <explore|full>`, never
by hand: the script places it after `plan:`, replaces an existing line, and
notes the change in the timeline. When `sheldon` hands you a mode while
starting the journal, run it right after creating the file. Exit `1` means the
journal is missing; exit `2` means the value was not `explore` or `full`.
```

- [x] **Step 3: run the check and watch it pass.** Run `bash skills/skills.test.sh` and confirm the `raj` line from Step 1 is gone.

### Task 7: `leonard` plans `full` within the budget

**Writes:** `skills/leonard/SKILL.md`
**Reads:** `skills/leonard/SKILL.md` (the paragraph `` `**Executor:** codex | claude` says who implements the task.`` and the paragraph ending ``The user sees the split when approving the plan.``)
**Depends on:** Task 0
**Executor:** claude
**Complexity:** routine
**Satisfies:** Task 0 `require leonard "Codex mode: full"`, `"Codex budget:"`, `"codex.sh budget"`, `"codex.sh cost estimate"`.

- [x] **Step 1: see the failing checks.** Run `bash skills/skills.test.sh` and confirm the four `leonard: missing` lines.
- [x] **Step 2: implement.** Directly after the paragraph that ends ``The user sees the split when approving the plan.``, insert the block below. Keep every existing line, including the five conditions, which the `Model routing` checks require.

```markdown
**Codex mode `full`.** The session-start digest names the effective mode.
When it says `Codex mode: full` and `codex.sh available` exits 0, the five
conditions above do not apply: every task except Task 0 is a candidate for
`codex`, and the budget below decides which candidates get it. Write each
candidate's text so it stands alone — Codex sees only its prompt, never the
conversation or the spec. `**Complexity:**` is written as usual; it picks the
model of a Claude fallback. `Codex mode: auto` at planning time means `sheldon`
left no resolution: plan as in `explore`.

Budget, once every task has its `**Complexity:**`: run `codex.sh budget`,
`codex.sh cost estimate routine` and `codex.sh cost estimate complex` once
each.

1. `headroom` = `weekly_left` − 10; the 10 is the reserve.
2. Order the candidates: `routine` first, then `complex`, each group by task
   number.
3. Walk that order and give a candidate `codex` while its estimate plus the
   estimates already given fits in `headroom`; every candidate that does not
   fit is `claude`.
4. Under the plan header write one line:
   `Codex budget: weekly <left>% left, reserve 10%, <k>/<n> tasks to codex (estimate <sum>%)`.
5. When `codex.sh budget` exits 1 the budget is unknown: every candidate gets
   `codex` and the line reads `Codex budget: unknown, all <n> tasks to codex`.
   The build-time guard and exit `75` stay as protection.

In `explore`, none of this applies and no `Codex budget:` line is written.
```

- [x] **Step 3: run the checks and watch them pass.** Run `bash skills/skills.test.sh` and confirm no `leonard: missing` line remains, and `model routing checked` is still printed.

### Task 8: `wolowitz` builds in `full`

**Writes:** `skills/wolowitz/SKILL.md`
**Reads:** `skills/wolowitz/SKILL.md` (`## Codex tasks`, `## Finish` step 1), `skills/wolowitz/references/codex-tasks.md`
**Depends on:** Task 0
**Executor:** claude
**Complexity:** complex
**Satisfies:** Task 0 `require wolowitz "Codex mode: full"`, `"codex budget: exhausted"`, `"codex.sh cost add"`, `"codex review: skipped (codex-mode full)"`.

- [x] **Step 1: see the failing checks.** Run `bash skills/skills.test.sh` and confirm the four `wolowitz: missing` lines.
- [x] **Step 2: implement.**
  - In `## Codex tasks`, directly after the paragraph ending ``and read it again after a compaction.`` (the one naming `references/codex-tasks.md`), insert:

```markdown
**Codex mode `full`.** The session-start digest names the effective mode.
When it says `Codex mode: full`:

- **Executor.** A plan with a `Codex budget:` line already carries the split:
  follow each task's `**Executor:**`. A plan without one was written in
  `explore`; before Wave 1, split it yourself. Every task except Task 0 is a
  candidate. Run `codex.sh budget` and
  `codex.sh cost estimate routine|complex`. Give candidates `codex` in order —
  `routine` first, then `complex`, each by task number — while the sum of
  their estimates fits in `weekly_left` − 10. The rest stay with Claude.
  When `codex.sh budget` exits 1, all of them go to `codex`. Name the split in
  the Wave 1 PR comment.
- **Budget guard.** Before each Codex task's `codex.sh red`, run
  `codex.sh budget` and `codex.sh cost estimate <the task's complexity>`; a
  task with no `**Complexity:**` line is `complex`. The task goes to Codex when
  `weekly_left` − 10 ≥ estimate and `five_hour_left` ≥ estimate, or when
  `codex.sh budget` exits 1. Otherwise that task and every remaining Codex
  task of the plan go to Claude per **Test writer and implementer**, and the
  wave's PR comment carries
  `codex budget: exhausted (<weekly|five_hour> <left>% < <need>%)`.
- **Cost.** After each Codex task's Gate green, run
  `codex.sh cost add <the task's complexity> <delta>`. `<delta>` is
  `weekly_used` from a fresh `codex.sh budget` minus `weekly_used` from the
  guard's run. Skip it when the delta is negative (the week reset) or when
  either `codex.sh budget` run exited 1.
- **Finish.** No Codex review; the final PR comment carries
  `codex review: skipped (codex-mode full)`.

In `explore`, none of this applies.
```

  - In `## Finish`, step 1, change the sentence that starts ``When `codex.sh available` exits 0, write a`` so it begins ``When `codex.sh available` exits 0 and the digest does not say `Codex mode: full`, write a``. Leave the rest of that sentence and the step unchanged.
- [x] **Step 3: run the checks and watch them pass.** Run `bash skills/skills.test.sh` and confirm no `wolowitz: missing` line remains, and `model routing checked` and `codex delegation documented` are still printed.

### Task 9: `amy` runs a Bounded change through Codex in `full`

**Writes:** `skills/amy/SKILL.md`
**Reads:** `skills/amy/SKILL.md` (`## When it applies`, `## Two loops`), `skills/wolowitz/references/codex-tasks.md`, `skills/wolowitz/reviewer-prompt.md`
**Depends on:** Task 0
**Executor:** claude
**Complexity:** routine
**Satisfies:** Task 0 `require amy "codex.sh red"`, `"codex.sh budget"`.

- [x] **Step 1: see the failing checks.** Run `bash skills/skills.test.sh` and confirm the two `amy: missing` lines.
- [x] **Step 2: implement.** Insert this new section directly before the line `## Any runner counts`:

```markdown
## Codex mode `full` on a bounded change

This section applies only when `sheldon` handed you an approved Bounded design
with the effective Codex mode `full` — explicit, or resolved from `auto` — and
`codex.sh available` (beside `journal.sh`) exits 0. A test writer or
implementer dispatched by `wolowitz` skips it: there the builder runs Codex.
Invoked directly, with no classification, `auto` works as `explore` and this
section does not apply.

1. **Budget guard.** Run `codex.sh budget` and
   `codex.sh cost estimate routine`. Go on when `weekly_left` − 10 ≥ estimate
   and `five_hour_left` ≥ estimate, or when `codex.sh budget` exits 1.
   Otherwise say in one line that the Codex budget is short and do the change
   yourself.
2. **Writes.** The file paths listed in the approved design, the test file
   included, are the change's `**Writes:**`; the verification command is the
   one you would run for these tests.
3. **The cycle.** Follow `skills/wolowitz/references/codex-tasks.md` under the
   plugin root: `codex.sh red`, Gate red, `codex.sh green`, Gate green, fix
   rounds 1–2 through `codex.sh green`. The prompt file holds this skill's full
   text, then the approved design, in place of `implementer-prompt-codex.md`.
   After round 2, or when any `codex.sh` call exits non-zero, finish the change
   yourself through this skill; on exit `75` tell the user once that Codex is
   off and Claude usage is no longer being saved.
4. **Review.** After Gate green, dispatch a `sonnet` reviewer with
   `skills/wolowitz/reviewer-prompt.md`: the commit before the change as
   `BASE`, the approved design in place of the plan and the spec, `-` for task
   numbers and waves. Fix its findings yourself through this skill. Without
   the Agent tool, review the diff yourself.
5. **Cost.** Run `codex.sh cost add routine <delta>`, `<delta>` being
   `weekly_used` from a fresh `codex.sh budget` minus the one from step 1. Skip
   it when negative or when either run exited 1.

Then **Verify before claiming**, as always.
```

- [x] **Step 3: run the checks and watch them pass.** Run `bash skills/skills.test.sh` and confirm no `amy: missing` line remains.

### Task 10: READMEs

**Writes:** `README.md`, `README.uk.md`
**Reads:** `README.md` (`## Codex delegation`), `README.uk.md` (`## Делегування в Codex`)
**Depends on:** Task 0
**Executor:** claude
**Complexity:** routine
**Satisfies:** Task 0 README needles `/codex-mode`, `codex.sh budget`, `codex-cost.tsv` in both files.

- [x] **Step 1: see the failing checks.** Run `bash skills/skills.test.sh` and confirm six `README…: missing` lines.
- [x] **Step 2: implement.**
  - In `README.md`, insert directly after the `- **implement** — …` bullet of `## Codex delegation`:

```markdown

### Modes

`/codex-mode` shows the current mode; `/codex-mode explore|full|auto` sets the global one, kept in `pasadena/codex-mode` under `${XDG_STATE_HOME:-~/.local/state}`; `/codex-mode explore|full --branch` sets it for the current branch in the journal's `codex-mode:` line, which wins on that branch. The session-start digest names the effective mode.

| Mode | Reading | Implementation | Final review |
|---|---|---|---|
| `explore` (default) | Codex | Codex only for tasks marked `**Executor:** codex` | Claude `sonnet` + Codex |
| `full` | Codex | Codex for every task except Task 0, and for bounded fixes, within the usage budget | Claude only |
| `auto` | — | `sheldon` picks: spike → `explore`, bounded → `full`, architectural with concurrency, persisted state, security or a shared interface → `explore`, other architectural → asks | — |

In `full`, `bash hooks/codex.sh budget` reads the remaining 5-hour and weekly limits from Codex's own session files under `${CODEX_HOME:-~/.codex}/sessions`. `leonard` hands Codex only as many tasks as fit in the weekly limit minus a 10% reserve and names the split in the plan's `Codex budget:` line; `wolowitz` checks again before each Codex task and gives the rest to Claude when the limit runs short. A task's cost is learned from how far the weekly limit moved: `pasadena/codex-cost.tsv` under the state directory keeps the history, and the estimate is the median of the last ten tasks (3% routine, 6% complex until there is history).
```

  - In `README.uk.md`, insert directly after the `- **implement** — …` bullet of `## Делегування в Codex`:

```markdown

### Режими

`/codex-mode` показує поточний режим; `/codex-mode explore|full|auto` задає глобальний, він зберігається в `pasadena/codex-mode` у `${XDG_STATE_HOME:-~/.local/state}`; `/codex-mode explore|full --branch` задає режим поточної гілки рядком `codex-mode:` у журналі, і на цій гілці він має перевагу. Digest на старті сесії називає чинний режим.

| Режим | Читання | Реалізація | Фінальне ревʼю |
|---|---|---|---|
| `explore` (типовий) | Codex | Codex лише для задач з `**Executor:** codex` | Claude `sonnet` + Codex |
| `full` | Codex | Codex для кожної задачі, крім Task 0, і для bounded-правок, у межах лімітів | лише Claude |
| `auto` | — | обирає `sheldon`: spike → `explore`, bounded → `full`, architectural з concurrency, збереженим станом, security чи спільним інтерфейсом → `explore`, інші architectural → питає | — |

У `full` команда `bash hooks/codex.sh budget` читає залишок 5-годинного і тижневого лімітів із власних session-файлів Codex у `${CODEX_HOME:-~/.codex}/sessions`. `leonard` віддає Codex стільки задач, скільки вміщається в тижневий ліміт мінус 10% резерву, і показує розподіл рядком `Codex budget:` у плані; `wolowitz` перевіряє ще раз перед кожною Codex-задачею і віддає решту Claude, коли ліміту бракує. Вартість задачі визначається з того, наскільки зрушив тижневий ліміт: історія лежить у `pasadena/codex-cost.tsv` у теці стану, а оцінка — медіана останніх десяти задач (3% routine, 6% complex, поки історії немає).
```

- [x] **Step 3: run the checks and watch them pass.** Run `bash skills/skills.test.sh` and confirm no `README.md: missing` or `README.uk.md: missing` line remains.

### Task 11: version `0.21.0`

**Writes:** `.claude-plugin/plugin.json`, `.claude-plugin/marketplace.json`
**Depends on:** Task 0
**Executor:** claude
**Complexity:** routine
**Satisfies:** Task 0 `not on 0.21.0` checks for both manifests.

- [x] **Step 1: see the failing checks.** Run `bash skills/skills.test.sh` and confirm `FAIL — .claude-plugin/plugin.json: not on 0.21.0` and the same for `marketplace.json`.
- [x] **Step 2: implement.** In both files, change `"version": "0.20.0"` to `"version": "0.21.0"`.
- [x] **Step 3: run the checks and watch them pass.** Run `bash skills/skills.test.sh` and confirm both lines are gone and `manifest versions checked` is printed.

---

## Final verification

```bash
bash hooks/codex.test.sh    # All checks passed.
bash hooks/journal.test.sh  # All checks passed.
bash skills/skills.test.sh  # All checks passed.
```

Manual, after merge and plugin reinstall:
- `/codex-mode` prints `global: explore`, `branch: -`, `codex: …`.
- `/codex-mode full`; a new session shows `Codex mode: full (global).` in the digest.
- `bash hooks/codex.sh budget` matches `/status` in the Codex CLI.
