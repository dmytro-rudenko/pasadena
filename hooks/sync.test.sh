#!/usr/bin/env bash
# Self-check for the worktree sync hook. Run: bash hooks/sync.test.sh
set -uo pipefail
unset PASADENA_SYNC PASADENA_TRUNK

DIR="$(cd "$(dirname "$0")" && pwd)"
HOOK="$DIR/sync.sh"
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

assert_not_contains() {
  if [[ "$1" != *"$2"* ]]; then
    echo "  ok  — $3"
  else
    echo "  FAIL — $3"
    echo "        unexpected substring: $2"
    fails=$((fails + 1))
  fi
}

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

g() { git -c user.email=t@example.com -c user.name=tester "$@"; }

commit_in() {
  echo "$2" >>"$1/$2.txt"
  g -C "$1" add -A
  g -C "$1" commit -qm "$2"
}

# Sets globals: base (scratch dir), remote, main (clone on main), wt (linked worktree on branch wt)
setup() {
  base="$(mktemp -d)"
  remote="$base/remote.git"
  main="$base/main"
  wt="$base/wt"
  git init -q --bare -b main "$remote"
  git clone -q "$remote" "$main" 2>/dev/null
  commit_in "$main" init
  g -C "$main" push -q origin main
  g -C "$main" worktree add -q -b wt "$wt" origin/main 2>/dev/null
  g -C "$wt" branch -q --unset-upstream 2>/dev/null
}

# Advances origin/main by n commits from a separate clone
advance_trunk() {
  local other="$base/other" i
  [ -d "$other" ] || git clone -q "$remote" "$other" 2>/dev/null
  for i in $(seq "$1"); do commit_in "$other" "trunk$i-$RANDOM"; done
  g -C "$other" push -q origin HEAD:main
}

run() { printf '{"cwd":"%s","source":"%s"}' "$1" "${2:-startup}" | bash "$HOOK" session-start; }
ctx() { jq -r '.hookSpecificOutput.additionalContext // empty' <<<"$1"; }
head_of() { git -C "$1" rev-parse HEAD; }

echo "== fast-forward to origin/<trunk> =="
setup
advance_trunk 2
out="$(run "$wt")"
assert_eq "$(head_of "$wt")" "$(git -C "$remote" rev-parse main)" "clean worktree behind trunk is fast-forwarded"
assert_contains "$(ctx "$out")" "pulled 2 commits from origin/main" "reports what was pulled"
assert_eq "$(jq -r '.hookSpecificOutput.hookEventName' <<<"$out")" "SessionStart" "event name"
rm -rf "$base"

echo "== fast-forward to the upstream =="
setup
g -C "$wt" push -q -u origin wt 2>/dev/null
other="$base/up"
git clone -q -b wt "$remote" "$other" 2>/dev/null
commit_in "$other" upstream1
g -C "$other" push -q origin wt
advance_trunk 1
out="$(run "$wt")"
assert_eq "$(head_of "$wt")" "$(git -C "$remote" rev-parse wt)" "branch with an upstream follows the upstream"
assert_contains "$(ctx "$out")" "pulled 1 commit from origin/wt" "names the upstream"
rm -rf "$base"

echo "== silent cases =="
setup
assert_eq "$(run "$wt")" "" "nothing new: silent"
advance_trunk 1
before="$(head_of "$wt")"
assert_eq "$(run "$wt" resume)" "" "resume: silent"
assert_eq "$(run "$wt" compact)" "" "compact: silent"
assert_eq "$(printf '{"cwd":"%s","source":"startup"}' "$wt" | PASADENA_SYNC=0 bash "$HOOK" session-start)" "" "PASADENA_SYNC=0: silent"
assert_eq "$(head_of "$wt")" "$before" "silent cases leave HEAD alone"
main_before="$(head_of "$main")"
assert_eq "$(run "$main")" "" "main checkout (not a linked worktree): silent"
assert_eq "$(head_of "$main")" "$main_before" "main checkout is not pulled"
g -C "$wt" remote set-url origin "$base/missing.git"
out="$(run "$wt")"; rc=$?
assert_eq "$out" "" "fetch failure: silent"
assert_eq "$rc" "0" "fetch failure: exit 0"
g -C "$wt" checkout -q --detach
assert_eq "$(run "$wt")" "" "detached HEAD: silent"
assert_eq "$(run "$base")" "" "outside a repo: silent"
rm -rf "$base"

echo "== dirty tree =="
setup
advance_trunk 1
echo change >>"$wt/init.txt"
before="$(head_of "$wt")"
c="$(ctx "$(run "$wt")")"
assert_eq "$(head_of "$wt")" "$before" "dirty tree: HEAD unchanged"
assert_contains "$(cat "$wt/init.txt")" "change" "dirty tree: local change kept"
assert_contains "$c" "origin/main has 1 new commit" "dirty tree: names the target"
assert_contains "$c" "WIP commit" "dirty tree: asks for a WIP commit"
assert_contains "$c" "never git stash" "dirty tree: rules out git stash"
assert_contains "$c" "git rebase origin/main" "dirty unpushed branch: rebase"
assert_contains "$c" "resolve" "dirty tree: asks to resolve conflicts"
rm -rf "$base"

echo "== diverged, not pushed =="
setup
commit_in "$wt" local1
advance_trunk 1
before="$(head_of "$wt")"
c="$(ctx "$(run "$wt")")"
assert_eq "$(head_of "$wt")" "$before" "diverged: HEAD unchanged"
assert_contains "$c" "git rebase origin/main" "unpushed branch: rebase"
assert_not_contains "$c" "WIP commit" "clean tree: no WIP commit"
assert_contains "$c" "before starting the task" "asks to do it first"
rm -rf "$base"

echo "== diverged, pushed without upstream =="
setup
commit_in "$wt" local1
g -C "$wt" push -q origin wt
advance_trunk 1
c="$(ctx "$(run "$wt")")"
assert_contains "$c" "git merge origin/main" "pushed branch: merge"
assert_not_contains "$c" "git rebase" "pushed branch: no rebase"
rm -rf "$base"

echo "== diverged from the upstream =="
setup
g -C "$wt" push -q -u origin wt 2>/dev/null
other="$base/up"
git clone -q -b wt "$remote" "$other" 2>/dev/null
commit_in "$other" upstream1
g -C "$other" push -q origin wt
commit_in "$wt" local1
c="$(ctx "$(run "$wt")")"
assert_contains "$c" "git pull --rebase" "upstream diverged: pull --rebase of the unpushed commits"
rm -rf "$base"

echo "== trunk from PASADENA_TRUNK =="
setup
g -C "$main" push -q origin main:dev
g -C "$main" push -q origin --delete main 2>/dev/null
g -C "$wt" fetch -q --prune origin
other="$base/devc"
git clone -q -b dev "$remote" "$other" 2>/dev/null
commit_in "$other" dev1
g -C "$other" push -q origin dev
out="$(printf '{"cwd":"%s","source":"startup"}' "$wt" | PASADENA_TRUNK="release dev" bash "$HOOK" session-start)"
assert_contains "$(ctx "$out")" "from origin/dev" "first trunk present on origin is used"
rm -rf "$base"

echo "== registration =="
entry="$(jq -c '.hooks.SessionStart[] | select(any(.hooks[]; .command | contains("hooks/sync.sh\" session-start")))' "$DIR/claude-hooks.json")"
assert_contains "$entry" '"matcher":"startup"' "sync.sh is registered on SessionStart startup only"
assert_contains "$entry" '"shell":"bash"' "sync.sh shell is bash"
assert_contains "$entry" '"timeout":30' "sync.sh timeout is 30"

echo
if [ "$fails" -gt 0 ]; then
  echo "FAILED: $fails"
  exit 1
fi
echo "All checks passed."
