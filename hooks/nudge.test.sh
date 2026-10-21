#!/usr/bin/env bash
# Self-check for the nudge hook. Run: bash hooks/nudge.test.sh
set -uo pipefail

DIR="$(cd "$(dirname "$0")" && pwd)"
HOOK="$DIR/nudge.sh"
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

assert_empty() {
  if [ -z "$1" ]; then
    echo "  ok  — $2"
  else
    echo "  FAIL — $2"
    echo "        expected empty output, got: $1"
    fails=$((fails + 1))
  fi
}

repo="$(mktemp -d)"
git -C "$repo" init -q
plain="$(mktemp -d)"

run() { jq -n --arg p "$1" --arg c "${2:-$repo}" '{prompt:$p,cwd:$c}' | bash "$HOOK" 2>/dev/null; }

echo "== bug prompts =="
assert_contains "$(run 'Тести в price.test.sh падають. Полагодь.')" "pasadena:leslie" "Ukrainian bug prompt points to leslie"
assert_contains "$(run 'the build is failing')" "pasadena:leslie" "English bug prompt points to leslie"
assert_contains "$(run 'полагодь і додай тест')" "pasadena:leslie" "bug wins over feature"
assert_contains "$(run 'the test failed')" "pasadena:leslie" "past-tense failure points to leslie"
assert_contains "$(run 'this does not work')" "pasadena:leslie" "does not work points to leslie"

echo "== feature prompts =="
out="$(run 'Додай функцію mul')"
assert_contains "$out" "pasadena:amy" "feature prompt points to amy"
assert_empty "$(grep -o leslie <<<"$out")" "feature prompt does not mention leslie"

echo "== output shape =="
assert_contains "$(run 'fix the crash' | jq -r '.hookSpecificOutput.hookEventName' 2>/dev/null)" "UserPromptSubmit" "valid JSON with the event name"

echo "== silent cases =="
assert_empty "$(run '/fix the crash')" "slash command stays silent"
assert_empty "$(run 'add a prefix to names')" "fix inside a word stays silent"
assert_empty "$(run 'rename the fixture dir')" "fixture stays silent"
assert_empty "$(run 'виправдай вибір')" "виправдай stays silent"
assert_empty "$(run 'виклич pasadena:leslie і полагодь')" "named skill stays silent"
assert_empty "$(run 'що таке монада?')" "unrelated prompt stays silent"
assert_empty "$(PASADENA_NUDGE=0 run 'полагодь тест')" "PASADENA_NUDGE=0 turns it off"
assert_empty "$(run 'полагодь тест' "$plain")" "silent outside a Git repo"

echo "== registration =="
assert_contains "$(jq -r '.hooks.UserPromptSubmit[0].hooks[0].command' "$DIR/claude-hooks.json")" \
  'hooks/nudge.sh' "Claude Code registers UserPromptSubmit"
assert_contains "$(jq -r '.hooks.UserPromptSubmit[0].hooks[0].command' "$DIR/hooks.json")" \
  '[ -n "${CLAUDE_PLUGIN_ROOT:-}" ] || bash "${PLUGIN_ROOT}/hooks/nudge.sh"' "Codex registers UserPromptSubmit behind the guard"
assert_contains "$(jq -r '.hooks.UserPromptSubmit[0].hooks[0].timeout' "$DIR/claude-hooks.json")" \
  '5' "Claude Code UserPromptSubmit timeout is 5"
assert_contains "$(jq -r '.hooks.UserPromptSubmit[0].hooks[0].timeout' "$DIR/hooks.json")" \
  '5' "Codex UserPromptSubmit timeout is 5"

rm -rf "$repo" "$plain"

echo
if [ "$fails" -gt 0 ]; then
  echo "FAILED: $fails"
  exit 1
fi
echo "All checks passed."
