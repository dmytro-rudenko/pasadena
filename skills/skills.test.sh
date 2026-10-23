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
[ "$fails" -eq "$before" ] && ok "codex delegation documented"

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
