#!/usr/bin/env bash
set -uo pipefail

input="$(cat)"
[ "${PASADENA_SYNC:-1}" = "0" ] && exit 0
[ "${1:-}" = "session-start" ] || exit 0
[ "$(jq -r '.source // empty' <<<"$input" 2>/dev/null)" = "startup" ] || exit 0

: "${PASADENA_TRUNK:=main master dev develop trunk}"

cwd="$(jq -r '.cwd // empty' <<<"$input" 2>/dev/null)"
[ -n "$cwd" ] || cwd="$PWD"
root="$(git -C "$cwd" rev-parse --show-toplevel 2>/dev/null)" || exit 0
gd() { git -C "$root" "$@"; }

[ "$(gd rev-parse --path-format=absolute --git-dir)" != "$(gd rev-parse --path-format=absolute --git-common-dir)" ] || exit 0
branch="$(gd symbolic-ref --quiet --short HEAD)" || exit 0

upstream="$(gd rev-parse --abbrev-ref --symbolic-full-name '@{u}' 2>/dev/null)"
if [ -n "$upstream" ]; then
  remote="$(gd config "branch.$branch.remote")"
else
  remote=origin
fi

export GIT_TERMINAL_PROMPT=0
if command -v timeout >/dev/null 2>&1; then
  timeout 20 git -C "$root" fetch --quiet "$remote" >/dev/null 2>&1 || exit 0
else
  gd fetch --quiet "$remote" >/dev/null 2>&1 || exit 0
fi

target="$upstream"
if [ -z "$target" ]; then
  for t in $PASADENA_TRUNK; do
    gd rev-parse --verify --quiet "refs/remotes/$remote/$t" >/dev/null && target="$remote/$t" && break
  done
fi
[ -n "$target" ] || exit 0

n="$(gd rev-list --count "HEAD..$target")"
[ "$n" -gt 0 ] || exit 0
commits="commits"
[ "$n" -eq 1 ] && commits="commit"

emit() {
  jq -n --arg ctx "$1" '{hookSpecificOutput:{hookEventName:"SessionStart",additionalContext:$ctx}}'
}

dirty="$(gd status --porcelain --untracked-files=no)"
if [ -z "$dirty" ] && gd merge-base --is-ancestor HEAD "$target" &&
  gd merge --ff-only --quiet "$target" >/dev/null 2>&1; then
  emit "pasadena sync: pulled $n $commits from $target into $branch."
  exit 0
fi

if [ -n "$upstream" ]; then
  step="git pull --rebase (it replays only the commits not yet pushed)"
elif gd rev-parse --verify --quiet "refs/remotes/$remote/$branch" >/dev/null; then
  step="git merge $target (the branch is already on $remote; a rebase would need a force push)"
else
  step="git rebase $target"
fi

msg="pasadena sync: $target has $n new $commits that $branch does not. Bring them into the branch before starting the task:"
[ -n "$dirty" ] && msg="$msg
- Commit the uncommitted changes as a temporary WIP commit — never git stash: the stash stack is shared with other worktrees."
msg="$msg
- Run $step.
- If it stops on conflicts, resolve them, continue, and run the tests."
[ -n "$dirty" ] && msg="$msg
- If the WIP commit is HEAD afterwards, git reset --mixed HEAD~1 returns its changes to the working tree."
emit "$msg"
exit 0
