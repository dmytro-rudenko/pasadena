#!/usr/bin/env bash
# Self-check for the reuse hook. Run: bash hooks/reuse.test.sh
set -uo pipefail
unset PASADENA_REUSE PASADENA_REUSE_HINT PASADENA_REUSE_SKIP

DIR="$(cd "$(dirname "$0")" && pwd)"
HOOK="$DIR/reuse.sh"
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

assert_exit0() {
  if [ "$1" -eq 0 ]; then
    echo "  ok  — $2"
  else
    echo "  FAIL — $2"
    echo "        expected exit 0, got: $1"
    fails=$((fails + 1))
  fi
}

assert_jq() {
  if jq -e "$1" "$DIR/claude-hooks.json" >/dev/null 2>&1; then
    echo "  ok  — $2"
  else
    echo "  FAIL — $2"
    echo "        expected true: $1"
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
spaced="$(mktemp -d)/with space"
mkdir -p "$spaced"
git -C "$spaced" init -q
plain="$(mktemp -d)"
home="$(mktemp -d)"
fallback_home="$(mktemp -d)"
fakebin="$(mktemp -d)"
markdir="$(mktemp -d)"
export FAKE_TE_REFRESH_MARK="$markdir/refresh-called"
cat >"$fakebin/te" <<'EOF'
#!/usr/bin/env bash
[ -n "${FAKE_TE_SLEEP:-}" ] && exec sleep "$FAKE_TE_SLEEP"
case "${3:-}" in
  config) printf '%s\n' "${FAKE_TE_CONFIG:-}" ;;
  repomap)
    if [ -n "${4:-}" ]; then
      touch "$FAKE_TE_REFRESH_MARK"
      exit 0
    fi
    printf '%s\ncwd=%s\n' "${FAKE_TE_MAP:-}" "$(pwd -P)"
    ;;
esac
EOF
chmod +x "$fakebin/te"
mkdir -p "$fallback_home/.tokeneconomizer/bin"
cp "$fakebin/te" "$fallback_home/.tokeneconomizer/bin/te"
chmod +x "$fallback_home/.tokeneconomizer/bin/te"
repo_real="$(cd "$repo" && pwd -P)"
spaced_real="$(cd "$spaced" && pwd -P)"

no_te_path=""
IFS=: read -ra path_dirs <<<"$PATH"
for d in "${path_dirs[@]}"; do
  [ -x "$d/te" ] || no_te_path="$no_te_path${no_te_path:+:}$d"
done

RULE='Reuse before you write'
HINT='te config set repomap=on'
ON='{"other":{"repomap":"on"}}'
OFF='{"other":{"repomap":"off"}}'
MAP=$'me/x: ~10 tokens (budget 2048), commit abc\n# Repository map\nsrc/FormInput.tsx:\n│export function FormInput("quoted\\path")'

payload() {
  jq -n --arg c "$1" --arg a "${2:-}" 'if $a == "" then {cwd: $c} else {cwd: $c, agent_type: $a} end'
}
with_te() { payload "${CWD:-$repo}" "${2:-}" | (cd "$plain" && HOME="$home" PATH="$fakebin:$no_te_path" bash "$HOOK" "$1" 2>/dev/null); }
without_te() { payload "${CWD:-$repo}" "${2:-}" | (cd "$plain" && HOME="${TE_HOME:-$home}" PATH="$no_te_path" bash "$HOOK" "$1" 2>/dev/null); }
rc_of() { "$@" >/dev/null; echo "$?"; }
event() { jq -r '.hookSpecificOutput.hookEventName' 2>/dev/null <<<"$1"; }
context() { jq -r '.hookSpecificOutput.additionalContext' 2>/dev/null <<<"$1"; }

echo "== session-start =="
out="$(FAKE_TE_CONFIG="$ON" with_te session-start)"
assert_contains "$(context "$out")" "$RULE" "session-start gives the rule"
assert_contains "$(event "$out")" "SessionStart" "session-start event name"
assert_not_contains "$(context "$out")" "$HINT" "repomap on: no hint"
ctx="$(context "$(FAKE_TE_CONFIG='{"other":{"repomap":"start"}}' with_te session-start)")"
assert_not_contains "$ctx" "$HINT" "repomap start: no hint"
assert_contains "$ctx" "$RULE" "repomap start: rule"
assert_contains "$(context "$(FAKE_TE_CONFIG="$OFF" with_te session-start)")" "$HINT" "repomap off: hint"
assert_contains "$(context "$(FAKE_TE_CONFIG='not json' with_te session-start)")" "$HINT" "unparseable config: hint"
assert_contains "$(context "$(without_te session-start)")" "$HINT" "no te: hint"
assert_not_contains "$(context "$(PASADENA_REUSE_HINT=0 without_te session-start)")" "$HINT" "PASADENA_REUSE_HINT=0 hides the hint"
assert_contains "$(context "$(PASADENA_REUSE_HINT=0 without_te session-start)")" "$RULE" "PASADENA_REUSE_HINT=0 keeps the rule"

echo "== subagent-start =="
out="$(FAKE_TE_MAP="$MAP" with_te subagent-start general-purpose)"
ctx="$(context "$out")"
assert_contains "$ctx" "$RULE" "subagent gets the rule"
assert_contains "$ctx" "# Repository map" "subagent gets the map heading"
assert_contains "$ctx" 'FormInput("quoted\path")' "subagent gets the map body with special characters"
assert_not_contains "$ctx" "~10 tokens" "status line is dropped"
assert_contains "$ctx" "cwd=$repo_real" "te runs in the event cwd"assert_contains "$(event "$out")" "SubagentStart" "subagent-start event name"
ctx="$(context "$(FAKE_TE_MAP='no map cached for x' with_te subagent-start general-purpose)")"
assert_contains "$ctx" "$RULE" "no cached map: rule"
assert_not_contains "$ctx" "no map cached" "no cached map: no te message"
assert_contains "$(context "$(without_te subagent-start general-purpose)")" "$RULE" "no te: rule only"
assert_not_contains "$(context "$(without_te subagent-start general-purpose)")" "$HINT" "subagent never gets the hint"
assert_contains "$(context "$(TE_HOME="$fallback_home" FAKE_TE_MAP="$MAP" without_te subagent-start general-purpose)")" "FormInput" "te found at ~/.tokeneconomizer/bin/te"

echo "== subagent filter =="
assert_empty "$(FAKE_TE_MAP="$MAP" with_te subagent-start Explore)" "Explore is skipped"
assert_empty "$(FAKE_TE_MAP="$MAP" with_te subagent-start plan)" "plan is skipped, case-insensitive"
assert_contains "$(context "$(FAKE_TE_MAP="$MAP" with_te subagent-start Explorer-custom)")" "FormInput" "partial match is not skipped"
assert_contains "$(context "$(PASADENA_REUSE_SKIP= FAKE_TE_MAP="$MAP" with_te subagent-start Explore)")" "FormInput" "empty PASADENA_REUSE_SKIP disables the filter"
assert_contains "$(context "$(FAKE_TE_MAP="$MAP" with_te subagent-start)")" "$RULE" "missing agent_type gets the rule"

echo "== timeout =="
start="$(date +%s%N)"
out="$(FAKE_TE_SLEEP=5 with_te subagent-start general-purpose)"
elapsed=$(( ($(date +%s%N) - start) / 1000000 ))
if [ "$elapsed" -lt 4000 ]; then echo "  ok  — hanging te is cut off (${elapsed}ms)"; else echo "  FAIL — hanging te took ${elapsed}ms"; fails=$((fails + 1)); fi
assert_contains "$(context "$out")" "$RULE" "hanging te: rule"
assert_not_contains "$(context "$out")" "# Repository map" "hanging te: no map"

echo "== silent cases =="
assert_empty "$(PASADENA_REUSE=0 FAKE_TE_CONFIG="$ON" with_te session-start)" "PASADENA_REUSE=0 silences session-start"
assert_empty "$(PASADENA_REUSE=0 FAKE_TE_MAP="$MAP" with_te subagent-start general-purpose)" "PASADENA_REUSE=0 silences subagent-start"
assert_empty "$(CWD="$plain" with_te session-start)" "session-start silent outside a Git repo"
assert_empty "$(CWD="$plain" with_te subagent-start general-purpose)" "subagent-start silent outside a Git repo"
ctx="$(context "$(CWD="$spaced" FAKE_TE_MAP="$MAP" with_te subagent-start general-purpose)")"
assert_contains "$ctx" "FormInput" "cwd with a space works"
assert_contains "$ctx" "cwd=$spaced_real" "te runs in the cwd with a space"
echo "== exit code =="
assert_exit0 "$(FAKE_TE_SLEEP=5 rc_of with_te subagent-start general-purpose)" "exit 0 even when te hangs"
assert_exit0 "$(PASADENA_REUSE=0 rc_of with_te session-start)" "exit 0 with PASADENA_REUSE=0 on session-start"
assert_exit0 "$(PASADENA_REUSE=0 rc_of with_te subagent-start general-purpose)" "exit 0 with PASADENA_REUSE=0 on subagent-start"
assert_exit0 "$(CWD="$plain" rc_of with_te session-start)" "exit 0 outside a Git repo on session-start"
assert_exit0 "$(CWD="$plain" rc_of with_te subagent-start general-purpose)" "exit 0 outside a Git repo on subagent-start"
assert_exit0 "$(FAKE_TE_MAP="$MAP" rc_of with_te subagent-start Explore)" "exit 0 when Explore is skipped"
assert_exit0 "$(rc_of with_te bogus-mode)" "exit 0 on an unknown mode"
assert_exit0 "$(FAKE_TE_CONFIG="$ON" rc_of with_te session-start)" "exit 0 on session-start with repomap on"

echo "== no refresh =="
if [ ! -e "$FAKE_TE_REFRESH_MARK" ]; then
  echo "  ok  — te repomap refresh is never called"
else
  echo "  FAIL — te repomap refresh was called"
  fails=$((fails + 1))
fi

echo "== registration =="
assert_contains "$(jq -r '.hooks.SessionStart[0].hooks[1].command' "$DIR/claude-hooks.json")" \
  'hooks/reuse.sh" session-start' "SessionStart registers reuse.sh session-start"
assert_contains "$(jq -r '.hooks.SessionStart[0].hooks[0].command' "$DIR/claude-hooks.json")" \
  'hooks/journal.sh" session-start' "journal.sh stays first in SessionStart"
assert_contains "$(jq -r '.hooks.SubagentStart[0].hooks[0].command' "$DIR/claude-hooks.json")" \
  'hooks/reuse.sh" subagent-start' "SubagentStart registers reuse.sh subagent-start"
assert_jq '.hooks.SubagentStart[0].hooks[0].timeout == 10' "SubagentStart timeout is 10"
assert_jq '.hooks.SubagentStart[0].hooks[0].shell == "bash"' "SubagentStart shell is bash"
assert_jq '.hooks.SubagentStart[0] | type == "object" and (has("matcher") | not)' "SubagentStart has no matcher"
assert_jq '.hooks.SessionStart[0].hooks[1].timeout == 10' "SessionStart reuse timeout is 10"
assert_jq '.hooks.SessionStart[0].hooks[1].shell == "bash"' "SessionStart reuse shell is bash"
rm -rf "$repo" "$(dirname "$spaced")" "$plain" "$home" "$fallback_home" "$fakebin" "$markdir"

echo
if [ "$fails" -gt 0 ]; then
  echo "FAILED: $fails"
  exit 1
fi
echo "All checks passed."
