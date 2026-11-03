#!/usr/bin/env bash
set -uo pipefail

[ "${PASADENA_NUDGE:-1}" = "0" ] && exit 0

charmap="$(locale charmap 2>/dev/null)"
case "$charmap" in UTF-8) ;; *) export LC_ALL=C.UTF-8 2>/dev/null ;; esac
input="$(cat)"
prompt="$(printf "%s" "$input" | jq -r '.prompt // empty' 2>/dev/null)"
cwd="$(printf "%s" "$input" | jq -r '.cwd // empty' 2>/dev/null)"
[ -n "$cwd" ] || cwd="$PWD"

inside="$(git -C "$cwd" rev-parse --is-inside-work-tree 2>/dev/null)"
[ "$inside" = "true" ] || exit 0

shopt -s nocasematch
slash_re='^[[:space:]]*/'
[[ $prompt =~ $slash_re ]] && exit 0
skills_re='leslie|amy|pasadena:|sheldon|leonard|wolowitz|penny|bernie|stuart|(^|[^[:alnum:]_])raj([^[:alnum:]_]|$)'
[[ $prompt =~ $skills_re ]] && exit 0

bug='баг|помилк|падає|падають|впав|зламал|не працює|полагод|виправ([^д]|$)|(^|[^[:alnum:]_])(fix(ed|es|ing)?|bug|broken|fail(s|ed|ing)?|crash(es|ed)?|regression)([^[:alnum:]_]|$)|error|does ?n.t work|not working'
feature='додай|реаліз|імплемент|зроби функц|нов(а|у|ий) фіч|implement|add (a |an )?(feature|function|endpoint|test)|build (a|the)'

if [[ $prompt =~ $bug ]]; then
  ctx='This prompt looks like a bug or failing check. Before changing any code, invoke the leslie skill (pasadena:leslie with the Skill tool) and follow it: root cause first, then the fix through amy.'
elif [[ $prompt =~ $feature ]]; then
  ctx='This prompt looks like new behaviour. Before writing production code, invoke the amy skill (pasadena:amy with the Skill tool): failing test first.'
else
  exit 0
fi

jq -n --arg ctx "$ctx" '{hookSpecificOutput:{hookEventName:"UserPromptSubmit",additionalContext:$ctx}}'
