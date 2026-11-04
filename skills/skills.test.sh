#!/usr/bin/env bash
# Self-check for skill frontmatter. Run: bash skills/skills.test.sh
set -uo pipefail

SKILLS="$(cd "$(dirname "$0")" && pwd)"
fails=0

fail() {
  echo "  FAIL — $1"
  fails=$((fails + 1))
}

ok() { echo "  ok  — $1"; }

# Routing skills invoke another skill in the same turn, where a disallowed-tools
# entry would still be in force and would restrict the skill they route into.
routers="pasadena journal leonard amy leslie bernie"

for dir in "$SKILLS"/*/; do
  name="$(basename "$dir")"
  file="$dir/SKILL.md"
  [ -f "$file" ] || continue
  echo "$name"

  if [ "$(sed -n '1p' "$file")" != "---" ]; then
    fail "$name: frontmatter does not open with ---"
    continue
  fi

  end="$(awk 'NR > 1 && /^---$/ { print NR; exit }' "$file")"
  if [ -z "$end" ]; then
    fail "$name: frontmatter has no closing --- (a dashed setext line is not one)"
    continue
  fi
  ok "$name: frontmatter delimiters"

  fm="$(sed -n "2,$((end - 1))p" "$file")"

  grep -q "^name: $name$" <<<"$fm" ||
    fail "$name: frontmatter name does not match the directory"

  # Path rules are only ever consulted for Edit() and Read(); a Write() path
  # rule is silently ignored and warns at startup.
  if grep -qE '^\s*-?\s*(Write|NotebookEdit|Glob|MultiEdit)\([^)]' <<<"$fm"; then
    fail "$name: path rule on a tool that is never consulted — use Edit() or Read()"
  else
    ok "$name: no ignored path rules"
  fi

  if grep -q '^disallowed-tools:' <<<"$fm"; then
    case " $routers " in
      *" $name "*) fail "$name: routes into another skill, so it must not set disallowed-tools" ;;
      *) ok "$name: disallowed-tools on a leaf skill" ;;
    esac
  fi
done

ROOT="$(cd "$SKILLS/.." && pwd)"
entrypoints="pasadena journal"
adapted="leslie bernie stuart"

echo "README tables"
for dir in "$SKILLS"/*/; do
  name="$(basename "$dir")"
  case " $entrypoints " in *" $name "*) continue ;; esac
  for readme in README.md README.uk.md; do
    grep -q "^| \`$name\` |" "$ROOT/$readme" ||
      fail "$name: no row in $readme skills table"
  done
done
ok "README tables checked"

echo "Third-party notices"
for name in $adapted; do
  grep -q "skills/$name/SKILL.md" "$ROOT/THIRD_PARTY_NOTICES.md" ||
    fail "$name: not credited in THIRD_PARTY_NOTICES.md"
done
ok "notices checked"

echo "Workflow rules"
require() {
  grep -qF -- "$2" "$SKILLS/$1/SKILL.md" || fail "$1: missing \"$2\""
}
require_ref() {
  grep -qF -- "$2" "$SKILLS/wolowitz/references/$1" 2>/dev/null || fail "references/$1: missing \"$2\""
}
before=$fails
require amy "## Two loops"
require amy "acceptance tests"
require amy "**Tests for existing code.**"
require amy "mutation"
require leonard "### Task 0: acceptance tests"
require leonard "Wave 0"
require wolowitz "Wave 0"
require wolowitz "never grows"
require sheldon "pasadena:amy"
[ "$fails" -eq "$before" ] && ok "workflow rules checked"

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
require sheldon "Codex: available"
require leonard "Codex: available"
require leslie "Codex: available"
require wolowitz "codex.sh explore"
require_ref codex-tasks.md "codex.sh red"
require_ref codex-tasks.md "codex.sh green"
require wolowitz "codex.sh review"
require_ref codex-tasks.md "Gate red"
require_ref codex-tasks.md "Gate green"
require_ref codex-tasks.md "implementer-prompt-codex.md"
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
[ "$fails" -eq "$before" ] && ok "codex delegation documented"

echo "Reuse hook"
before=$fails
for readme in README.md README.uk.md; do
  for needle in PASADENA_REUSE= PASADENA_REUSE_HINT PASADENA_REUSE_SKIP "bash hooks/reuse.test.sh" '`SubagentStart`'; do
    grep -qF -- "$needle" "$ROOT/$readme" || fail "$readme: missing \"$needle\""
  done
done
grep -qF 'Pasadena uses six hooks' "$ROOT/README.md" || fail "README.md: hook count is not six"
grep -qF "Pasadena використовує шість hooks" "$ROOT/README.uk.md" || fail "README.uk.md: hook count is not six"
[ "$fails" -eq "$before" ] && ok "reuse hook documented"

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

echo "Frontmatter models"
before=$fails
for file in "$SKILLS"/*/SKILL.md; do
  name="$(basename "$(dirname "$file")")"
  fm="$(awk 'NR > 1 && /^---$/ { exit } NR > 1' "$file")"
  if ! grep -qxE 'model: (opus|sonnet)' <<<"$fm" || ! grep -qxE 'effort: (low|medium|high|xhigh|max)' <<<"$fm"; then
    fail "$name: frontmatter needs model: opus|sonnet and effort: low|medium|high|xhigh|max"
  fi
done
while read -r name model effort; do
  [ "$(sed -n '4,5p' "$SKILLS/$name/SKILL.md")" = "$(printf 'model: %s\neffort: %s' "$model" "$effort")" ] ||
    fail "$name: lines 4-5 are not model: $model, effort: $effort"
done <<'EOF'
amy opus high
sheldon opus high
leonard opus high
leslie opus high
wolowitz opus medium
penny opus medium
bernie sonnet xhigh
stuart sonnet xhigh
pasadena sonnet medium
raj sonnet medium
journal sonnet medium
EOF
[ "$fails" -eq "$before" ] && ok "frontmatter models checked"

echo "Model routing"
before=$fails
require leonard '**Complexity:** routine | complex'
require leonard '- the task is `**Complexity:** routine`;'
require leonard 'When in doubt, write `complex`.'
require wolowitz '| Test writer: Task 0, red of every task, test fixes, round 3, Finish | `opus` | `high` |'
require wolowitz '| Implementer, `routine` | `sonnet` | `xhigh` |'
require wolowitz '| Implementer: `complex`, round 3, Finish | `opus` | `medium` |'
require wolowitz '| `Explore`, when `codex.sh available` exits non-zero | `sonnet` | `xhigh` |'
require wolowitz '## Test writer and implementer'
require wolowitz 'test-writer-prompt.md'
require wolowitz 'references/two-dispatch.md'
require wolowitz '- for a test writer only, the instruction to invoke the `amy` skill'
wolowitz_flat="$(tr '\n' ' ' <"$SKILLS/wolowitz/SKILL.md")"
grep -qF 'A task with no `**Complexity:**` line is `complex`.' <<<"$wolowitz_flat" || fail "wolowitz: missing \"A task with no **Complexity:** line is complex.\""
! grep -qF 'whole `amy` cycle' <<<"$wolowitz_flat" || fail "wolowitz: a routine task still runs the whole amy cycle"
! grep -qF '## Complex tasks' "$SKILLS/wolowitz/SKILL.md" || fail "wolowitz: still has ## Complex tasks"
! grep -qF 'on Fable' "$SKILLS/wolowitz/SKILL.md" || fail "wolowitz: implementers still follow a Fable session"
! grep -qF "session's model" <<<"$wolowitz_flat" || fail "wolowitz: a dispatch still follows the session's model"
! grep -rqF --exclude=skills.test.sh 'complex-tasks.md' "$SKILLS" || fail "wolowitz: complex-tasks.md still referenced"
! grep -rqE '(Red|Green) dispatch' "$SKILLS/wolowitz" || fail "wolowitz: a Red or Green dispatch is still named"
test_writer="$SKILLS/wolowitz/test-writer-prompt.md"
if [ -f "$test_writer" ]; then
  grep -qF 'pasadena:amy' "$test_writer" || fail "test-writer-prompt.md: does not invoke pasadena:amy"
  grep -qF 'only the tests' "$test_writer" || fail "test-writer-prompt.md: missing \"only the tests\""
else
  fail "test-writer-prompt.md: missing"
fi
implementer="$SKILLS/wolowitz/implementer-prompt.md"
! grep -qiw 'amy' "$implementer" || fail "implementer-prompt.md: still mentions amy"
for block in "Red dispatch" "Green dispatch"; do
  ! grep -qF "## $block" "$implementer" || fail "implementer-prompt.md: still has \"$block\""
done
grep -qF 'checksums are recorded' "$implementer" || fail "implementer-prompt.md: does not protect the tests"
require_ref two-dispatch.md 'Gate red'
require_ref two-dispatch.md 'Gate green'
require_ref two-dispatch.md 'test-writer-prompt.md'
[ ! -e "$SKILLS/wolowitz/references/complex-tasks.md" ] || fail "references/complex-tasks.md: still present"
for readme in README.md README.uk.md; do
  grep -qF '| `wolowitz`, `penny` | `opus` | `medium` |' "$ROOT/$readme" || fail "$readme: no skill model table"
  grep -qF -- '--advisor' "$ROOT/$readme" || fail "$readme: no advisor note"
done
grep -qF '| Implementer, `complex` task, round 3, final fix | `opus` | `medium` |' "$ROOT/README.md" || fail "README.md: no dispatch model table"
grep -qF '| Implementer, `complex`-задача, раунд 3, фінальний fix | `opus` | `medium` |' "$ROOT/README.uk.md" || fail "README.uk.md: no dispatch model table"
! grep -qF 'stays on your own settings' "$ROOT/README.md" || fail "README.md: the main session still stays on the user's settings"
! grep -qF 'лишається на ваших налаштуваннях' "$ROOT/README.uk.md" || fail "README.uk.md: the main session still stays on the user's settings"
for manifest in .claude-plugin/plugin.json .claude-plugin/marketplace.json; do
  grep -qF '"version": "0.23.0"' "$ROOT/$manifest" || fail "$manifest: not on 0.23.0"
done
grep -qF '2026-11-02-skill-frontmatter-models.md' "$ROOT/docs/sdd/specs/2026-11-01-skill-model-routing.md" ||
  fail "docs/sdd/specs/2026-11-01-skill-model-routing.md: no link to the spec that supersedes it"
[ "$fails" -eq "$before" ] && ok "model routing checked"

echo "Grouped review"
before=$fails
require wolowitz '| Wave 0 review and grouped wave review | `sonnet` | `high` |'
require wolowitz '| Whole-branch review | `sonnet` | `xhigh` |'
! grep -qF '| Wave reviewer and whole-branch review |' "$SKILLS/wolowitz/SKILL.md" || fail "wolowitz: one review row still covers waves and the whole branch"
flat() { cat -- "$1" 2>/dev/null | tr '\n' ' ' | tr -s ' '; }
require_flat() {
  grep -qF -- "$2" <<<"$(flat "$SKILLS/$1/SKILL.md")" || fail "$1: missing \"$2\""
}
require_ref_flat() {
  grep -qF -- "$2" <<<"$(flat "$SKILLS/wolowitz/references/$1")" || fail "references/$1: missing \"$2\""
}
require_flat wolowitz 'one review for every third wave'
require wolowitz 'references/grouped-review.md'
require_flat wolowitz 'while the reviews run'
require_flat wolowitz 'fix(<scope>): whole-branch and security review findings'
require_flat wolowitz 'k mod 3 = 0'
require_flat wolowitz "not the plan's last wave"
require_flat wolowitz 'so uncommitted work is in the diff'
require_ref_flat grouped-review.md 'GROUP_BASE: <sha>'
require_ref_flat grouped-review.md 'git add -N'
require_ref_flat grouped-review.md 'fix(<scope>): review findings for task N'
for ref in two-dispatch.md codex-tasks.md; do
  require_ref_flat "$ref" 'review when the schedule has one'
done
reviewer="$SKILLS/wolowitz/reviewer-prompt.md"
grep -qF 'Review waves `<a>`–`<b>`' "$reviewer" || fail "reviewer-prompt.md: does not review a range of waves"
grep -qF '**The diff:** `git diff <BASE>` —' "$reviewer" || fail "reviewer-prompt.md: the diff misses the working tree"
grep -qF 'reviews every third wave' "$ROOT/README.md" || fail "README.md: wolowitz row does not name the review schedule"
grep -qF 'кожну третю хвилю' "$ROOT/README.uk.md" || fail "README.uk.md: wolowitz row does not name the review schedule"
grep -qF '| Wave 0 and grouped wave reviews | `sonnet` | `high` |' "$ROOT/README.md" || fail "README.md: no grouped review row"
grep -qF '| Whole-branch review, `Explore` fallback | `sonnet` | `xhigh` |' "$ROOT/README.md" || fail "README.md: no whole-branch review row"
grep -qF '| Ревʼю Wave 0 і груп хвиль | `sonnet` | `high` |' "$ROOT/README.uk.md" || fail "README.uk.md: no grouped review row"
grep -qF '| Ревʼю всієї гілки, fallback `Explore` | `sonnet` | `xhigh` |' "$ROOT/README.uk.md" || fail "README.uk.md: no whole-branch review row"
! grep -qF '| Reviews, `Explore` fallback |' "$ROOT/README.md" || fail "README.md: old review row still present"
! grep -qF '| Ревʼю, fallback `Explore` |' "$ROOT/README.uk.md" || fail "README.uk.md: old review row still present"
require_flat wolowitz 'A wave closing a group before the last wave'
require wolowitz '| A wave after Wave 0 closes no group, or closes the last one |'
require_ref_flat grouped-review.md 'Without subagents'
require_ref_flat grouped-review.md 'the counter carries on'
require_ref_flat grouped-review.md 'one at a time'
require_ref_flat grouped-review.md 'at step 8 of every wave in the group'
[ "$fails" -eq "$before" ] && ok "grouped review checked"

echo "Upstream adoption"
before=$fails
for file in "$SKILLS"/*/SKILL.md; do
  [ "$(wc -c <"$file")" -lt 20000 ] || fail "$file: 20000 bytes or more, compaction cuts it off"
done
require wolowitz 'references/codex-tasks.md'
require wolowitz 'git merge-base origin/<trunk> HEAD'
! grep -qF 'git merge-base <trunk>' "$SKILLS/wolowitz/SKILL.md" || fail "wolowitz: merge-base on a local trunk"
require wolowitz 'Declined to judge'
require sheldon '## Builder check'
require sheldon '**Who owns the technical choices.**'
[ -f "$SKILLS/sheldon/builder-check-prompt.md" ] || fail "sheldon: builder-check-prompt.md missing"
grep -qF 'skills/sheldon/builder-check-prompt.md' "$ROOT/THIRD_PARTY_NOTICES.md" || fail "builder check: not credited"
require leonard '## Review Focus'
grep -qF 'reasonable person' "$SKILLS/wolowitz/reviewer-prompt.md" || fail "reviewer-prompt.md: missing reasonable person rule"
grep -qF '## Declined to judge' "$SKILLS/wolowitz/reviewer-prompt.md" || fail "reviewer-prompt.md: missing Declined to judge"
[ "$fails" -eq "$before" ] && ok "upstream adoption checked"

echo "Parallel design"
before=$fails
require sheldon 'one subagent per section, all in parallel'
require sheldon 'section outline'
require sheldon 'open questions'
require sheldon 'one message through the `AskUserQuestion` tool'
require sheldon 'one approval'
require sheldon 'one or two sections'
! grep -qF 'After each section, ask whether everything looks right' "$SKILLS/sheldon/SKILL.md" || fail "sheldon: still asks after each section"
grep -qF 'one approval' "$ROOT/README.md" || fail "README.md: sheldon row lacks one approval"
grep -qF 'одне погодження' "$ROOT/README.uk.md" || fail "README.uk.md: sheldon row lacks одне погодження"
[ "$fails" -eq "$before" ] && ok "parallel design checked"

echo "Manifest versions"
manifests=".claude-plugin/plugin.json .claude-plugin/marketplace.json"
before=$fails
for manifest in $manifests; do
  count="$(grep -c '"version"' "$ROOT/$manifest")"
  [ "$count" -eq 1 ] || fail "$manifest: expected one \"version\" line, found $count"
done
versions="$(for manifest in $manifests; do grep -h '"version"' "$ROOT/$manifest"; done | sed 's/[^0-9.]//g' | sort -u)"
if [ -z "$versions" ] || [ "$(wc -l <<<"$versions")" -ne 1 ]; then
  fail "manifest versions differ: $(tr '\n' ' ' <<<"$versions")"
fi
[ "$fails" -eq "$before" ] && ok "manifest versions checked"

echo
if [ "$fails" -gt 0 ]; then
  echo "FAILED: $fails"
  exit 1
fi
echo "All checks passed."
