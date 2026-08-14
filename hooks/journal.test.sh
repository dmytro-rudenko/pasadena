#!/usr/bin/env bash
# Self-check for the journal hook. Run: bash hooks/journal.test.sh
set -uo pipefail

HOOK="$(cd "$(dirname "$0")" && pwd)/journal.sh"
CLAUDE_HOOKS="$(cd "$(dirname "$0")" && pwd)/hooks.json"
CODEX_HOOKS="$(cd "$(dirname "$0")" && pwd)/codex-hooks.json"
fails=0

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

assert_equals() {
  if [ "$1" = "$2" ]; then
    echo "  ok  — $3"
  else
    echo "  FAIL — $3"
    echo "        expected: $2"
    echo "        got: $1"
    fails=$((fails + 1))
  fi
}

assert_empty() {
  if [ -z "$1" ]; then
    echo "  ok  — $2"
  else
    echo "  FAIL — $2"
    echo "        expected empty output, got: $1"
    fails=$((fails + 1))
  fi
}

# Temp repo with a single commit on branch dev
setup_repo() {
  local d branch="${1:-dev}"
  d="$(mktemp -d)"
  git -C "$d" init -q -b "$branch"
  git -C "$d" config user.email t@example.com
  git -C "$d" config user.name tester
  echo x >"$d/f.txt"
  git -C "$d" add -A
  git -C "$d" commit -qm "init"
  printf '%s' "$d"
}

# Minimal journal for a branch
make_journal() {
  local d="$1" slug="$2"
  mkdir -p "$d/.claude/journal"
  cat >"$d/.claude/journal/$slug.md" <<'EOF'
---
branch: feat/x
status: in-progress
---

## Goal
Test goal.

## Now
Stopped at step 2, next edit src/a.ts.

## Timeline
### 2026-08-09
- 10:00 · seed
EOF
}

make_canonical_journal() {
  local d="$1" slug="$2"
  make_journal "$d" "$slug"
  mkdir -p "$d/.pasadena/journal"
  sed 's/Stopped at step 2/Canonical journal resumes at step 2/' \
    "$d/.claude/journal/$slug.md" >"$d/.pasadena/journal/$slug.md"
}

echo "== Task 0: hook registration =="
assert_contains "$(jq -r '.hooks.SessionStart[0].matcher' "$CLAUDE_HOOKS")" \
  "startup|resume|clear|compact|fork" "Claude SessionStart includes fork"
assert_contains "$(jq -r '.hooks.SessionEnd | length' "$CLAUDE_HOOKS")" \
  "2" "Claude config has clear and exit SessionEnd matchers"
assert_contains "$(jq -r '.hooks.StopFailure[0].matcher' "$CLAUDE_HOOKS")" \
  "rate_limit" "Claude config registers StopFailure"
assert_contains "$(jq -r '.hooks.SessionEnd[0].hooks[0].command' "$CLAUDE_HOOKS")" \
  'session-end clear' "Claude clear SessionEnd passes clear"
assert_contains "$(jq -r '.hooks.SessionEnd[1].hooks[0].command' "$CLAUDE_HOOKS")" \
  'session-end exit' "Claude exit SessionEnd passes exit"
assert_contains "$(jq -r '.hooks.SessionStart[0].matcher' "$CODEX_HOOKS")" \
  "startup|resume|clear|compact" "Codex SessionStart events are registered"
assert_empty "$(jq -r '.hooks.StopFailure // empty' "$CODEX_HOOKS")" \
  "Codex config does not invent StopFailure"

assert_equals "$(jq -c '.hooks | keys' "$CODEX_HOOKS")" \
  '["PostToolUse","SessionEnd","SessionStart"]' "Codex config has exactly its three supported events"
assert_empty "$(jq -r '[.hooks[] | .[] | .hooks[] | .command | select(contains("${CLAUDE_PLUGIN_ROOT}") | not)] | .[]' "$CLAUDE_HOOKS")" \
  "every Claude hook command uses CLAUDE_PLUGIN_ROOT"
assert_empty "$(jq -r '[.hooks[] | .[] | .hooks[] | .command | select(contains("${PLUGIN_ROOT}"))] | .[]' "$CLAUDE_HOOKS")" \
  "no Claude hook command uses PLUGIN_ROOT"
assert_empty "$(jq -r '[.hooks[] | .[] | .hooks[] | .command | select(contains("${PLUGIN_ROOT}") | not)] | .[]' "$CODEX_HOOKS")" \
  "every Codex hook command uses PLUGIN_ROOT"
assert_empty "$(jq -r '[.hooks[] | .[] | .hooks[] | .command | select(contains("${CLAUDE_PLUGIN_ROOT}"))] | .[]' "$CODEX_HOOKS")" \
  "no Codex hook command uses CLAUDE_PLUGIN_ROOT"
assert_equals "$(jq -r '.hooks' .codex-plugin/plugin.json)" \
  "./hooks/codex-hooks.json" "Codex manifest routes to its dedicated hook config"
assert_equals "$(jq -r 'has("hooks")' .claude-plugin/plugin.json)" \
  "false" "Claude manifest has no ineffective hooks path"

echo "== Task 1: path resolution and trunk branches =="

d="$(setup_repo)"
out="$(printf '{"cwd":"%s","source":"startup"}' "$d" | bash "$HOOK" session-start)"
assert_empty "$out" "silent on dev without a journal"

git -C "$d" checkout -q -b feat/x
out="$(printf '{"cwd":"%s","source":"startup"}' "$d" | bash "$HOOK" session-start)"
assert_contains "$out" "No session journal" "on a feature branch without a journal it offers to start one"
rm -rf "$d"

# Default trunk list covers more than dev/main
d="$(setup_repo master)"
out="$(printf '{"cwd":"%s","source":"startup"}' "$d" | bash "$HOOK" session-start)"
assert_empty "$out" "master is trunk by default"

# PASADENA_TRUNK overrides the list — main stops being trunk
out="$(printf '{"cwd":"%s","source":"startup"}' "$d" |
  PASADENA_TRUNK="trunk release" bash "$HOOK" session-start)"
assert_contains "$out" "No session journal" "PASADENA_TRUNK overrides the default trunk list"

# Detached HEAD has no branch to hang a journal on
git -C "$d" checkout -q --detach
out="$(printf '{"cwd":"%s","source":"startup"}' "$d" | bash "$HOOK" session-start)"
assert_empty "$out" "silent on detached HEAD"
rm -rf "$d"

echo "== Task 2: context on session start =="

d="$(setup_repo)"
git -C "$d" checkout -q -b feat/x
make_journal "$d" "feat-x"
out="$(printf '{"cwd":"%s","source":"startup"}' "$d" | bash "$HOOK" session-start)"
ctx="$(jq -r '.hookSpecificOutput.additionalContext' <<<"$out")"
title="$(jq -r '.hookSpecificOutput.sessionTitle // empty' <<<"$out")"
assert_contains "$ctx" "Stopped at step 2" "context carries the Now section"
assert_contains "$ctx" "10:00 · seed" "context carries the timeline tail"
assert_empty "$title" "Codex does not emit a Claude session title"
assert_contains "$(cat "$d/.claude/journal/feat-x.md")" "▶ start" "start line appended"

# Compact — same session, no second ▶
printf '{"cwd":"%s","source":"compact"}' "$d" | bash "$HOOK" session-start >/dev/null
assert_contains "$(grep -c '▶ start' "$d/.claude/journal/feat-x.md")" "1" "compact does not append a second ▶"

# /clear — new session, start line written
printf '{"cwd":"%s","source":"clear"}' "$d" | bash "$HOOK" session-start >/dev/null
assert_contains "$(grep -c '▶ start' "$d/.claude/journal/feat-x.md")" "2" "clear appends a new ▶"
rm -rf "$d"

# Codex journals use the provider-neutral path and win over legacy files.
d="$(setup_repo)"
git -C "$d" checkout -q -b feat/x
make_canonical_journal "$d" "feat-x"
out="$(printf '{"cwd":"%s","source":"startup"}' "$d" | bash "$HOOK" session-start)"
ctx="$(jq -r '.hookSpecificOutput.additionalContext' <<<"$out")"
assert_contains "$ctx" "Canonical journal resumes" "canonical journal is preferred over legacy"
assert_contains "$(cat "$d/.pasadena/journal/feat-x.md")" "▶ start" "canonical journal receives the session start"
rm -rf "$d"

echo "== Task 3: commit tracking =="

d="$(setup_repo)"
git -C "$d" checkout -q -b feat/x
make_journal "$d" "feat-x"
echo y >"$d/g.txt"
git -C "$d" add -A
git -C "$d" commit -qm "feat: add g"
sha="$(git -C "$d" rev-parse --short HEAD)"

# The command is not a git commit — HEAD moved, so the commit is recorded anyway
payload="$(jq -nc --arg cwd "$d" '{cwd:$cwd,tool_name:"Bash",tool_input:{command:"bash release.sh"}}')"
printf '%s' "$payload" | bash "$HOOK" commit
assert_contains "$(cat "$d/.claude/journal/feat-x.md")" "● $sha feat: add g" "commit recorded with sha and subject"

# Same HEAD twice does not duplicate the line
printf '%s' "$payload" | bash "$HOOK" commit
assert_contains "$(grep -c "● $sha" "$d/.claude/journal/feat-x.md")" "1" "repeat call does not duplicate"

# HEAD unchanged — nothing new to write
printf '%s' "$payload" | bash "$HOOK" commit
assert_contains "$(grep -c '●' "$d/.claude/journal/feat-x.md")" "1" "no commit, no line"

# Two commits between hook calls — both land in the journal
echo a >"$d/h.txt" && git -C "$d" add -A && git -C "$d" commit -qm "feat: add h"
sha_h="$(git -C "$d" rev-parse --short HEAD)"
echo b >"$d/i.txt" && git -C "$d" add -A && git -C "$d" commit -qm "feat: add i"
sha_i="$(git -C "$d" rev-parse --short HEAD)"
printf '%s' "$payload" | bash "$HOOK" commit
body="$(cat "$d/.claude/journal/feat-x.md")"
assert_contains "$body" "● $sha_h feat: add h" "first of two commits recorded"
assert_contains "$body" "● $sha_i feat: add i" "second of two commits recorded"
rm -rf "$d"

# A journal created mid-session has no sha anchor yet — the branch point off trunk
# is the boundary, so commits made before the first hook call are not lost
d="$(setup_repo main)"
git -C "$d" checkout -q -b feat/z
echo a >"$d/a.txt" && git -C "$d" add -A && git -C "$d" commit -qm "feat: first"
sha_1="$(git -C "$d" rev-parse --short HEAD)"
echo b >"$d/b.txt" && git -C "$d" add -A && git -C "$d" commit -qm "feat: second"
sha_2="$(git -C "$d" rev-parse --short HEAD)"
make_journal "$d" "feat-z" # created after both commits, timeline empty
printf '{"cwd":"%s","tool_name":"Bash","tool_input":{"command":"./release.sh"}}' "$d" | bash "$HOOK" commit
body="$(cat "$d/.claude/journal/feat-z.md")"
assert_contains "$body" "● $sha_1 feat: first" "anchorless journal picks up from the branch point"
assert_contains "$body" "● $sha_2 feat: second" "anchorless journal records every commit on the branch"
assert_contains "$(grep -c '● ' "$d/.claude/journal/feat-z.md")" "2" "trunk commits stay out of the journal"
rm -rf "$d"

echo "== Task 4: pause and abort =="

d="$(setup_repo)"
git -C "$d" checkout -q -b feat/x
make_journal "$d" "feat-x"
echo dirty >"$d/f.txt"

printf '{"cwd":"%s"}' "$d" | bash "$HOOK" session-end clear
body="$(cat "$d/.claude/journal/feat-x.md")"
assert_contains "$body" "⏸ pause · clear" "pause recorded with its reason"
assert_contains "$body" "f.txt" "pause lists dirty files"

# Two stop markers in a row are not written
printf '{"cwd":"%s"}' "$d" | bash "$HOOK" session-end exit
assert_contains "$(grep -c '⏸' "$d/.claude/journal/feat-x.md")" "1" "no two pause markers in a row"
rm -rf "$d"

# Hard stop
d="$(setup_repo)"
git -C "$d" checkout -q -b feat/y
make_journal "$d" "feat-y"
printf '{"cwd":"%s","error_type":"rate_limit"}' "$d" | bash "$HOOK" stop-failure
assert_contains "$(cat "$d/.claude/journal/feat-y.md")" "✖ stopped · rate_limit" "abort recorded with its error type"
rm -rf "$d"

echo "== Task 5: model notes =="

d="$(setup_repo)"
git -C "$d" checkout -q -b feat/x
make_journal "$d" "feat-x"
today="$(date +%F)"

# `note` is invoked by hand from the project directory, not by a hook with JSON on stdin
(cd "$d" && bash "$HOOK" note "Phase 2/3: defer path covered by a test") >/dev/null
body="$(cat "$d/.claude/journal/feat-x.md")"
assert_contains "$body" "✎ Phase 2/3: defer path covered by a test" "note appends a ✎ line"
assert_contains "$body" "### $today" "note creates today's heading"

# A multi-line argument must not break the one-line-per-entry timeline
(cd "$d" && bash "$HOOK" note "$(printf 'first\nsecond')") >/dev/null
assert_contains "$(grep -c '✎ first second' "$d/.claude/journal/feat-x.md")" "1" \
  "a multi-line note collapses to one line"

before="$(wc -l <"$d/.claude/journal/feat-x.md")"
(cd "$d" && bash "$HOOK" note "") >/dev/null
assert_contains "$(wc -l <"$d/.claude/journal/feat-x.md")" "$before" "an empty note is a no-op"
rm -rf "$d"

# No journal on this branch — nothing to write to
d="$(setup_repo)"
git -C "$d" checkout -q -b feat/x
(cd "$d" && bash "$HOOK" note "orphan") >/dev/null
assert_empty "$(ls "$d/.claude/journal" 2>/dev/null)" "note without a journal creates no file"
rm -rf "$d"

echo "== Task 6: end-of-session fallback =="

# No ✎ this session — the hook snapshots ## Now under the pause line
d="$(setup_repo)"
git -C "$d" checkout -q -b feat/x
make_journal "$d" "feat-x"
printf '{"cwd":"%s","source":"startup"}' "$d" | bash "$HOOK" session-start >/dev/null
printf '{"cwd":"%s"}' "$d" | bash "$HOOK" session-end exit
assert_contains "$(cat "$d/.claude/journal/feat-x.md")" "↳ Stopped at step 2, next edit src/a.ts." \
  "pause falls back to a ## Now snapshot"
rm -rf "$d"

# A ✎ was written this session — the model already said it, no duplicate
d="$(setup_repo)"
git -C "$d" checkout -q -b feat/x
make_journal "$d" "feat-x"
printf '{"cwd":"%s","source":"startup"}' "$d" | bash "$HOOK" session-start >/dev/null
(cd "$d" && bash "$HOOK" note "wrapped up the defer path") >/dev/null
printf '{"cwd":"%s"}' "$d" | bash "$HOOK" session-end exit
assert_empty "$(grep '↳' "$d/.claude/journal/feat-x.md")" "a ✎ this session suppresses the fallback"
rm -rf "$d"

# A journal whose Now is still the creation placeholder gets no fallback line
d="$(setup_repo)"
git -C "$d" checkout -q -b feat/x
make_journal "$d" "feat-x"
awk '{ sub(/^Stopped at step 2.*/, "(filled in on the first update)"); print }' \
  "$d/.claude/journal/feat-x.md" >"$d/tmp" && mv "$d/tmp" "$d/.claude/journal/feat-x.md"
printf '{"cwd":"%s","source":"startup"}' "$d" | bash "$HOOK" session-start >/dev/null
printf '{"cwd":"%s"}' "$d" | bash "$HOOK" session-end exit
assert_empty "$(grep '↳' "$d/.claude/journal/feat-x.md")" "a placeholder Now writes no fallback"
rm -rf "$d"

# StopFailure then SessionEnd: the ↳ between them must not hide the ✖ marker
d="$(setup_repo)"
git -C "$d" checkout -q -b feat/y
make_journal "$d" "feat-y"
printf '{"cwd":"%s","error_type":"rate_limit"}' "$d" | bash "$HOOK" stop-failure
printf '{"cwd":"%s"}' "$d" | bash "$HOOK" session-end other
body="$(cat "$d/.claude/journal/feat-y.md")"
assert_contains "$body" "↳ Stopped at step 2" "a hard stop carries a ## Now snapshot too"
assert_empty "$(grep '⏸' "$d/.claude/journal/feat-y.md")" \
  "session-end after a hard stop adds no second marker"
rm -rf "$d"

# The digest must carry the notes and tell the model how to write one
d="$(setup_repo)"
git -C "$d" checkout -q -b feat/x
make_journal "$d" "feat-x"
(cd "$d" && bash "$HOOK" note "decided to trim AxiosError before stringify") >/dev/null
out="$(printf '{"cwd":"%s","source":"startup"}' "$d" | bash "$HOOK" session-start)"
ctx="$(jq -r '.hookSpecificOutput.additionalContext' <<<"$out")"
assert_contains "$ctx" "## Recent notes" "digest has a notes block"
assert_contains "$ctx" "decided to trim AxiosError" "digest carries the note text"
assert_contains "$ctx" "$HOOK" "digest carries the absolute path for writing notes"
rm -rf "$d"

# A journal with no notes yet gets no empty block
d="$(setup_repo)"
git -C "$d" checkout -q -b feat/x
make_journal "$d" "feat-x"
out="$(printf '{"cwd":"%s","source":"startup"}' "$d" | bash "$HOOK" session-start)"
ctx="$(jq -r '.hookSpecificOutput.additionalContext' <<<"$out")"
assert_empty "$(grep 'Recent notes' <<<"$ctx")" "no notes, no notes block"
rm -rf "$d"

echo "== Task 7: spec and plan in the digest =="

# Without a journal the nudge must still carry the script path — it is how the
# SDD skills find proto/start.sh, and a journal started mid-session emits no
# second digest.
d="$(setup_repo)"
git -C "$d" checkout -q -b feat/x
out="$(printf '{"cwd":"%s","source":"startup"}' "$d" | bash "$HOOK" session-start)"
ctx="$(jq -r '.hookSpecificOutput.additionalContext' <<<"$out")"
assert_contains "$ctx" "$HOOK" "the no-journal nudge carries the script path"
rm -rf "$d"


# The SDD stage is derived from these two fields, so a resuming session must
# get them without going to look for the file.
d="$(setup_repo)"
git -C "$d" checkout -q -b feat/x
make_journal "$d" "feat-x"
awk '/^status: in-progress$/ { print "spec: docs/sdd/specs/2026-08-12-x.md"; print "plan: docs/sdd/plans/2026-08-12-x.md" } { print }' \
  "$d/.claude/journal/feat-x.md" >"$d/tmp" && mv "$d/tmp" "$d/.claude/journal/feat-x.md"
out="$(printf '{"cwd":"%s","source":"startup"}' "$d" | bash "$HOOK" session-start)"
ctx="$(jq -r '.hookSpecificOutput.additionalContext' <<<"$out")"
assert_contains "$ctx" "## Artifacts" "digest has an artifacts block"
assert_contains "$ctx" "docs/sdd/specs/2026-08-12-x.md" "digest carries the spec path"
assert_contains "$ctx" "docs/sdd/plans/2026-08-12-x.md" "digest carries the plan path"
rm -rf "$d"

# Only one of the two set — the block still appears, the missing one reads as -
d="$(setup_repo)"
git -C "$d" checkout -q -b feat/x
make_journal "$d" "feat-x"
awk '/^status: in-progress$/ { print "spec: docs/sdd/specs/2026-08-12-x.md"; print "plan: -" } { print }' \
  "$d/.claude/journal/feat-x.md" >"$d/tmp" && mv "$d/tmp" "$d/.claude/journal/feat-x.md"
out="$(printf '{"cwd":"%s","source":"startup"}' "$d" | bash "$HOOK" session-start)"
ctx="$(jq -r '.hookSpecificOutput.additionalContext' <<<"$out")"
assert_contains "$ctx" "plan: -" "an unset plan still shows, so the stage is unambiguous"
rm -rf "$d"

# Neither set — no block at all, the same way an empty notes block is suppressed
d="$(setup_repo)"
git -C "$d" checkout -q -b feat/x
make_journal "$d" "feat-x"
awk '/^status: in-progress$/ { print "spec: -"; print "plan: -" } { print }' \
  "$d/.claude/journal/feat-x.md" >"$d/tmp" && mv "$d/tmp" "$d/.claude/journal/feat-x.md"
out="$(printf '{"cwd":"%s","source":"startup"}' "$d" | bash "$HOOK" session-start)"
ctx="$(jq -r '.hookSpecificOutput.additionalContext' <<<"$out")"
assert_empty "$(grep 'Artifacts' <<<"$ctx")" "no artifacts, no artifacts block"
rm -rf "$d"

echo
if [ "$fails" -gt 0 ]; then
  echo "FAILED: $fails"
  exit 1
fi
echo "All checks passed."
