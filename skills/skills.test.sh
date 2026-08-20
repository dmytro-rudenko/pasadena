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
routers="pasadena journal leonard amy"

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

echo
if [ "$fails" -gt 0 ]; then
  echo "FAILED: $fails"
  exit 1
fi
echo "All checks passed."
