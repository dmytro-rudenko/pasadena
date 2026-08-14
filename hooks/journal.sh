#!/usr/bin/env bash
# Session journal mechanics. Invoked by Codex or Claude Code hooks, JSON arrives on stdin.
# Design: docs/design.md
set -uo pipefail

sub="${1:-}"
arg="${2:-}"

# Hook subcommands get JSON on stdin. `note` is invoked by hand and would block on it.
case "$sub" in
  note) input='{}' ;;
  *) input="$(cat)" ;;
esac

# Branches that never get a journal. Override per project or per user.
: "${PASADENA_TRUNK:=main master dev develop trunk}"

# Read a field from the stdin JSON; empty string when absent
jf() { jq -r "$1 // empty" <<<"$input" 2>/dev/null; }

cwd="$(jf '.cwd')"
[ -n "$cwd" ] || cwd="$PWD"

root="$(git -C "$cwd" rev-parse --show-toplevel 2>/dev/null || true)"
[ -n "$root" ] || exit 0

branch="$(git -C "$root" rev-parse --abbrev-ref HEAD 2>/dev/null || true)"
[ -n "$branch" ] || exit 0
[ "$branch" = "HEAD" ] && exit 0 # detached HEAD: no branch to hang a journal on

slug="${branch//\//-}"
canonical_file="$root/.pasadena/journal/$slug.md"
legacy_file="$root/.claude/journal/$slug.md"

# New journals are provider-neutral. Existing Claude journals remain readable so
# switching clients never strands an in-progress task.
if [ -f "$canonical_file" ]; then
  file="$canonical_file"
elif [ -f "$legacy_file" ]; then
  file="$legacy_file"
else
  file="$canonical_file"
fi
journal_rel="${file#"$root"/}"

is_trunk() { [[ " $PASADENA_TRUNK " == *" $branch "* ]]; }

# Body of section "## <title>" up to the next level-2 heading
extract_section() {
  awk -v hdr="## $1" '
    $0 == hdr { inside = 1; next }
    inside && /^## / { exit }
    inside { print }
  ' "$file"
}

# A frontmatter field. "-" is the file's way of writing "not set", so it comes
# back empty and callers do not have to know the convention.
frontmatter() {
  awk -v k="$1" '
    NR == 1 && $0 == "---" { inside = 1; next }
    inside && $0 == "---" { exit }
    inside && index($0, k ": ") == 1 { print substr($0, length(k) + 3); exit }
  ' "$file" | sed 's/^ *//; s/ *$//; s/^-$//'
}

# Newest sha anchor in the journal: a commit line (●) or a session start line (@)
journal_last_sha() {
  grep -oE '[●@] [0-9a-f]{7,40}' "$file" | tail -1 | awk '{print $2}'
}

# Where this branch left the trunk — the oldest commit a journal can be responsible for
branch_point() {
  local t base
  for t in $PASADENA_TRUNK; do
    base="$(git -C "$root" merge-base HEAD "$t" 2>/dev/null)" || continue
    [ -n "$base" ] && printf '%s' "$base" && return
  done
}

# Timeline notes written since the newest session start: ✎ by the model, ↳ by the fallback
notes_since_start() {
  awk '/▶ start/ { buf = ""; next } /✎|↳/ { buf = buf $0 "\n" } END { printf "%s", buf }' "$file"
}

# ## Now squeezed onto one line. Bash substring expansion is character-based;
# `cut -c` slices bytes and would split a Cyrillic character in half.
now_snippet() {
  local s
  s="$(extract_section 'Now' | tr '\n' ' ' | tr -s ' ' | sed 's/^ *//; s/ *$//')"
  case "$s" in '' | '('*')') return ;; esac
  printf '%s' "${s:0:200}"
}

# The model's ✎ is the good version of this line; this is the stand-in for a
# session that ended before one was written. Appended raw — a continuation line
# must not create its own ### day heading.
append_now_fallback() {
  local snip
  [ -n "$(notes_since_start)" ] && return
  snip="$(now_snippet)"
  [ -n "$snip" ] || return
  printf '  ↳ %s\n' "$snip" >>"$file"
}

# Append a line to the end of the file; the day heading is created on demand
append_line() {
  local today
  today="$(date +%F)"
  grep -q "^### $today\$" "$file" || printf '\n### %s\n' "$today" >>"$file"
  printf '%s\n' "$1" >>"$file"
}

# Hand context back to the session
emit_context() {
  jq -n --arg ctx "$1" \
    '{hookSpecificOutput:{hookEventName:"SessionStart",additionalContext:$ctx}}'
}

cmd_session_start() {
  if [ ! -f "$file" ]; then
    is_trunk && exit 0
    # The path goes out even with no journal: it is how the skills locate the
    # plugin's own scripts (proto/start.sh sits beside hooks/), and a session
    # that starts one mid-conversation never sees a second digest.
    emit_context "No session journal for branch \`$branch\`. If this task will span more than one session, offer to start one (skill raj). Skip it for a small fix.
Plugin scripts live beside \`$0\`."
    exit 0
  fi

  local state timeline notes spec plan anchor newlog ctx
  state="$(extract_section 'Now')"
  timeline="$(extract_section 'Timeline' | grep -v '^[[:space:]]*$' | tail -8)"
  # Separate from the 8-line tail: a burst of ● commits would otherwise push
  # every note out of the window. Overlap is cheaper than deduplicating.
  notes="$(grep -E '✎|↳' "$file" | tail -3)"

  # Commits made since the last journal entry — i.e. outside this journal's sight
  anchor="$(journal_last_sha)"
  newlog=""
  if [ -n "$anchor" ] && git -C "$root" cat-file -e "${anchor}^{commit}" 2>/dev/null; then
    newlog="$(git -C "$root" log --oneline "${anchor}..HEAD" 2>/dev/null | head -20)"
  fi

  # The SDD stage follows from these two: no spec means shaping, a spec without
  # a plan means planning, both means building. Cheaper to hand over than to
  # make the next session open the file and look.
  spec="$(frontmatter spec)"
  plan="$(frontmatter plan)"

  ctx="Session journal: \`$journal_rel\` (branch \`$branch\`)."

  if [ -n "$spec" ] || [ -n "$plan" ]; then
    ctx="$ctx

## Artifacts
spec: ${spec:--}
plan: ${plan:--}"
  fi

  ctx="$ctx

## Now
$state
## Recent entries
$timeline"

  if [ -n "$newlog" ]; then
    ctx="$ctx

## Commits since the last journal entry
$newlog"
  fi

  if [ -n "$notes" ]; then
    ctx="$ctx

## Recent notes
$notes"
  fi

  ctx="$ctx

Continue from \"Now\". Update that section at phase boundaries and before pausing — skill raj.
Record what happened at each stage boundary: bash \"$0\" note \"<one line>\""

  # startup/resume/clear — a new session. compact/fork — same session, no second start line.
  case "$(jf '.source')" in
    startup | resume | clear)
      append_line "- $(date +%H:%M) ▶ start · $branch @ $(git -C "$root" rev-parse --short HEAD)"
      ;;
  esac

  emit_context "$ctx"
  exit 0
}

# Record every commit that appeared since the journal's last sha anchor.
# Compares HEAD instead of parsing the command, so commits made by scripts,
# aliases, jj or an MCP git server are caught too.
cmd_commit() {
  [ -f "$file" ] || exit 0

  local head anchor log sha subject
  head="$(git -C "$root" rev-parse --short HEAD 2>/dev/null || true)"
  [ -n "$head" ] || exit 0
  grep -q "● $head" "$file" && exit 0

  anchor="$(journal_last_sha)"
  # Journal just created, no sha in it yet: the branch point off trunk is the boundary
  [ -n "$anchor" ] || anchor="$(branch_point)"

  if [ -n "$anchor" ] && git -C "$root" cat-file -e "${anchor}^{commit}" 2>/dev/null; then
    # ponytail: capped at 10 — a long rebase won't be replayed in full
    log="$(git -C "$root" log --oneline --reverse "${anchor}..HEAD" 2>/dev/null | tail -10)"
  else
    log="$(git -C "$root" log --oneline -1 2>/dev/null)"
  fi
  [ -n "$log" ] || exit 0

  while read -r sha subject; do
    grep -q "● $sha" "$file" || append_line "- $(date +%H:%M) ● $sha $subject"
  done <<<"$log"
  exit 0
}

# The one thing a hook cannot write: what actually happened. Called by the model.
cmd_note() {
  [ -f "$file" ] || exit 0
  local text
  text="$(printf '%s' "$arg" | tr '\n' ' ' | tr -s ' ' | sed 's/^ *//; s/ *$//')"
  [ -n "$text" ] || exit 0
  append_line "- $(date +%H:%M) ✎ $text"
  exit 0
}

# Never write two stop markers in a row — SessionEnd can follow StopFailure.
# The ↳ continuation sits below the marker, so it is skipped when looking back.
last_is_stop() { grep -v '^  ↳' "$file" | tail -1 | grep -qE '⏸|✖'; }

cmd_session_end() {
  [ -f "$file" ] || exit 0
  last_is_stop && exit 0

  local head dirty line
  head="$(git -C "$root" rev-parse --short HEAD 2>/dev/null || echo '?')"
  dirty="$(git -C "$root" status --porcelain 2>/dev/null |
    grep -vE '\.(claude|pasadena)/journal/' | awk '{print $NF}' | head -3 | paste -sd, -)"

  line="- $(date +%H:%M) ⏸ pause · ${arg:-other} · HEAD=$head"
  [ -n "$dirty" ] && line="$line · dirty: $dirty"
  append_line "$line"
  append_now_fallback
  exit 0
}

cmd_stop_failure() {
  [ -f "$file" ] || exit 0
  last_is_stop && exit 0
  append_line "- $(date +%H:%M) ✖ stopped · $(jf '.error_type')"
  append_now_fallback
  exit 0
}

case "$sub" in
  session-start) cmd_session_start ;;
  commit) cmd_commit ;;
  note) cmd_note ;;
  session-end) cmd_session_end ;;
  stop-failure) cmd_stop_failure ;;
  *) exit 0 ;;
esac
