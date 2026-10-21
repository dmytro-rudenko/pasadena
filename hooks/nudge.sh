#!/usr/bin/env bash
set -uo pipefail

[ "${PASADENA_NUDGE:-1}" = "0" ] && exit 0

case "$(locale charmap 2>/dev/null)" in UTF-8) ;; *) export LC_ALL=C.UTF-8 2>/dev/null ;; esac
input="$(cat)"
prompt="$(jq -r '.prompt // empty' <<<"$input" 2>/dev/null)"
cwd="$(jq -r '.cwd // empty' <<<"$input" 2>/dev/null)"
[ -n "$cwd" ] || cwd="$PWD"

[ "$(git -C "$cwd" rev-parse --is-inside-work-tree 2>/dev/null)" = "true" ] || exit 0

trimmed="${prompt#"${prompt%%[![:space:]]*}"}"
[ "${trimmed:0:1}" = "/" ] && exit 0
grep -qiE 'leslie|amy|pasadena:' <<<"$prompt" && exit 0

bug='баг|помилк|падає|падають|впав|зламал|не працює|полагод|виправ([^д]|$)|(^|[^[:alnum:]_])(fix(ed|es|ing)?|bug|broken|fail(s|ed|ing)?|crash(es|ed)?|regression)([^[:alnum:]_]|$)|error|does ?n.t work|not working'
feature='додай|реаліз|імплемент|зроби функц|нов(а|у|ий) фіч|implement|add (a |an )?(feature|function|endpoint|test)|build (a|the)'

if grep -qiE "$bug" <<<"$prompt"; then
  ctx='This prompt looks like a bug or failing check. Before changing any code, invoke the leslie skill with the Skill tool, as pasadena:leslie, and follow it: root cause first, then the fix through amy.'
elif grep -qiE "$feature" <<<"$prompt"; then
  ctx='This prompt looks like new behaviour. Before writing production code, invoke the amy skill with the Skill tool, as pasadena:amy: failing test first.'
else
  exit 0
fi

jq -n --arg ctx "$ctx" '{hookSpecificOutput:{hookEventName:"UserPromptSubmit",additionalContext:$ctx}}'
