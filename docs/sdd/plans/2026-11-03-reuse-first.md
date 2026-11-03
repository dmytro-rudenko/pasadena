# Reuse-first hook — implementation plan

**Goal:** `hooks/reuse.sh` дає правило «Reuse before you write» у кожну сесію (`SessionStart`) і в кожного субагента, який пише код (`SubagentStart`). Субагентам він додає ще й кешовану tokeneconomizer repomap. Плагін піднято до 0.21.0, README описує хук.
**Spec:** docs/sdd/specs/2026-11-03-reuse-first.md
**Verification:** `bash hooks/reuse.test.sh && bash hooks/nudge.test.sh && bash hooks/journal.test.sh && bash skills/skills.test.sh`, остання рядок кожного: `All checks passed.`

## Waves
| Wave | Tasks | Why together |
|---|---|---|
| 0 | 0 | alone: acceptance tests, червоні до кінця wave 1 |
| 1 | 1, 2, 3 | disjoint: `hooks/reuse.sh` / `hooks/claude-hooks.json` / маніфести + README + `skills/skills.test.sh` |

Серіалізувати нічого не потрібно: жоден файл не пишуть дві задачі, а інтерфейс між задачами один (шлях `hooks/reuse.sh` і його аргументи), і він повністю заданий нижче.

## Global constraints
- Bash, `set -uo pipefail`, без Node чи Python. Стиль як у `hooks/nudge.sh` (вимикач через env, `cwd` з `.cwd` вхідного JSON, мовчання поза git, вивід через `jq -n`).
- Хук завжди завершується з `exit 0`. Його збій не ламає старт сесії чи субагента.
- Пошук `te`: `command -v te`, далі `$HOME/.tokeneconomizer/bin/te`, файл має бути виконуваним.
- `te` викликається завжди так: `cd "$cwd"`, `timeout 3` (якщо `timeout` є), `--host claude`. `te repomap refresh` не викликається ніколи.
- Змінні оточення: `PASADENA_REUSE=0` вимикає все; `PASADENA_REUSE_HINT=0` вимикає підказку; `PASADENA_REUSE_SKIP` задає regex типів субагентів для пропуску. Значення за замовчуванням `Explore|Plan|claude-code-guide|statusline-setup|web-fetch`, збіг повний (`grep -qixE`), порожнє значення вимикає фільтр, відсутній `agent_type` фільтр не зачіпає.
- Нова версія плагіна: `0.21.0`.
- Без коментарів у коді, крім обмежень, які код показати не може.
- Не комітити `hooks/journal.sh`: там чужі незакомічені зміни.

Правило (рядок у рядок):
```
Reuse before you write. Before creating a component, helper, hook, layout, page or page template:
1. Find the closest existing one: check the repository map if one is in context, otherwise grep by role (input, form, field, header, toolbar, layout, page, template) and by the name you were about to give it. Read what you find.
2. Use it the way the neighbouring code does. If it lacks something, extend it instead of copying it.
3. Write new code only when nothing fits, and say in one line of your reply what you checked and why it did not fit.
```
Підказка:
```
pasadena: no repository map in context. Enable it with tokeneconomizer: `te config set repomap=on --global` (needs aider). Silence this with PASADENA_REUSE_HINT=0.
```

## Review Focus
- `te`, що повертає `{"other":{"repomap":"start"}}`: підказки бути не повинно, так само як для `on`.
- `te config`, що повертає не-JSON або порожній рядок: хук не падає й показує підказку.
- `cwd` з пробілом у шляху: `cd "$cwd"` і `git -C "$cwd"` у лапках, хук працює.
- `agent_type`, що лише містить слово зі списку (наприклад, `Explorer-custom`): фільтр не спрацьовує, бо збіг має бути повним.
- Карта зі спецсимволами (`"`, `\`, `│`): `jq --arg` екранує, і вивід залишається валідним JSON.

### Task 0: acceptance tests

**Writes:** `hooks/reuse.test.sh`
**Executor:** claude
**Covers:** spec §6, пункти 1–10 і 6a: «session-start … містить `Reuse before you write`», «без `te`: є підказка; з `PASADENA_REUSE_HINT=0` її немає», «`{"other":{"repomap":"on"}}`: підказки немає; `off`: є», «subagent-start … карта без службового рядка, `hookEventName` = `SubagentStart`», «`no map cached for x`: правило без карти», «без `te`: лише правило», «Explore / plan: порожньо; general-purpose: правило+карта; `PASADENA_REUSE_SKIP=` + Explore: правило+карта; без agent_type: правило», «`PASADENA_REUSE=0`: порожньо», «поза git: порожньо», «`te`, що висить 5 с: < 4 с, правило без карти», «реєстрація в `claude-hooks.json`».
Вирішить рев'ю Focus: додати в цей файл також перевірки `start`, не-JSON-конфігу, `cwd` з пробілом, `Explorer-custom` і спецсимволів у карті (код нижче вже їх містить).

- [x] **Step 1: write the acceptance tests** — створити `hooks/reuse.test.sh`:
```bash
#!/usr/bin/env bash
# Self-check for the reuse hook. Run: bash hooks/reuse.test.sh
set -uo pipefail

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
fakebin="$(mktemp -d)"
cat >"$fakebin/te" <<'EOF'
#!/usr/bin/env bash
[ -n "${FAKE_TE_SLEEP:-}" ] && exec sleep "$FAKE_TE_SLEEP"
case "${3:-}" in
  config) printf '%s\n' "${FAKE_TE_CONFIG:-}" ;;
  repomap) printf '%s\n' "${FAKE_TE_MAP:-}" ;;
esac
EOF
chmod +x "$fakebin/te"

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
with_te() { payload "${CWD:-$repo}" "${2:-}" | HOME="$home" PATH="$fakebin:$no_te_path" bash "$HOOK" "$1" 2>/dev/null; }
without_te() { payload "${CWD:-$repo}" "${2:-}" | HOME="$home" PATH="$no_te_path" bash "$HOOK" "$1" 2>/dev/null; }
event() { jq -r '.hookSpecificOutput.hookEventName' 2>/dev/null <<<"$1"; }
context() { jq -r '.hookSpecificOutput.additionalContext' 2>/dev/null <<<"$1"; }

echo "== session-start =="
out="$(FAKE_TE_CONFIG="$ON" with_te session-start)"
assert_contains "$(context "$out")" "$RULE" "session-start gives the rule"
assert_contains "$(event "$out")" "SessionStart" "session-start event name"
assert_not_contains "$(context "$out")" "$HINT" "repomap on: no hint"
assert_not_contains "$(context "$(FAKE_TE_CONFIG='{"other":{"repomap":"start"}}' with_te session-start)")" "$HINT" "repomap start: no hint"
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
assert_contains "$(event "$out")" "SubagentStart" "subagent-start event name"
ctx="$(context "$(FAKE_TE_MAP='no map cached for x' with_te subagent-start general-purpose)")"
assert_contains "$ctx" "$RULE" "no cached map: rule"
assert_not_contains "$ctx" "no map cached" "no cached map: no te message"
assert_contains "$(context "$(without_te subagent-start general-purpose)")" "$RULE" "no te: rule only"
assert_not_contains "$(context "$(without_te subagent-start general-purpose)")" "$HINT" "subagent never gets the hint"

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
assert_contains "$(context "$(CWD="$spaced" FAKE_TE_MAP="$MAP" with_te subagent-start general-purpose)")" "FormInput" "cwd with a space works"

echo "== exit code =="
FAKE_TE_SLEEP=5 with_te subagent-start general-purpose >/dev/null
assert_contains "$?" "0" "exit 0 even when te hangs"

echo "== registration =="
assert_contains "$(jq -r '.hooks.SessionStart[0].hooks[1].command' "$DIR/claude-hooks.json")" \
  'hooks/reuse.sh" session-start' "SessionStart registers reuse.sh session-start"
assert_contains "$(jq -r '.hooks.SessionStart[0].hooks[0].command' "$DIR/claude-hooks.json")" \
  'hooks/journal.sh" session-start' "journal.sh stays first in SessionStart"
assert_contains "$(jq -r '.hooks.SubagentStart[0].hooks[0].command' "$DIR/claude-hooks.json")" \
  'hooks/reuse.sh" subagent-start' "SubagentStart registers reuse.sh subagent-start"
assert_contains "$(jq -r '.hooks.SubagentStart[0].hooks[0].timeout' "$DIR/claude-hooks.json")" \
  '10' "SubagentStart timeout is 10"
rm -rf "$repo" "$(dirname "$spaced")" "$plain" "$home" "$fakebin"

echo
if [ "$fails" -gt 0 ]; then
  echo "FAILED: $fails"
  exit 1
fi
echo "All checks passed."
```
- [x] **Step 2: run them, watch them fail** — `bash hooks/reuse.test.sh`, останній рядок починається з `FAILED:`, бо `hooks/reuse.sh` і реєстрації ще немає. Порожні перевірки (silent cases, Explore) можуть пройти вже зараз, і це нормально.

### Task 1: хук `hooks/reuse.sh`

**Writes:** `hooks/reuse.sh`
**Reads:** `hooks/nudge.sh`, `hooks/reuse.test.sh`, `docs/sdd/specs/2026-11-03-reuse-first.md`
**Depends on:** Task 0
**Executor:** claude
**Complexity:** complex
**Satisfies:** усі перевірки `hooks/reuse.test.sh`, крім розділу `== registration ==`
**Interfaces:**
- Produces: `bash hooks/reuse.sh session-start|subagent-start`, stdin = JSON події Claude Code (`.cwd`, `.agent_type`), stdout = `{"hookSpecificOutput":{"hookEventName":"SessionStart"|"SubagentStart","additionalContext":"…"}}` або нічого.

- [x] **Step 1: run the acceptance tests, watch them fail** — `bash hooks/reuse.test.sh`, останній рядок `FAILED: …`, падають session-start і subagent-start.
- [x] **Step 2: implement** — створити `hooks/reuse.sh`:
```bash
#!/usr/bin/env bash
set -uo pipefail

[ "${PASADENA_REUSE:-1}" = "0" ] && exit 0

mode="${1:-}"
input="$(cat)"
cwd="$(jq -r '.cwd // empty' <<<"$input" 2>/dev/null)"
[ -n "$cwd" ] || cwd="$PWD"
[ "$(git -C "$cwd" rev-parse --is-inside-work-tree 2>/dev/null)" = "true" ] || exit 0

rule='Reuse before you write. Before creating a component, helper, hook, layout, page or page template:
1. Find the closest existing one: check the repository map if one is in context, otherwise grep by role (input, form, field, header, toolbar, layout, page, template) and by the name you were about to give it. Read what you find.
2. Use it the way the neighbouring code does. If it lacks something, extend it instead of copying it.
3. Write new code only when nothing fits, and say in one line of your reply what you checked and why it did not fit.'
hint='pasadena: no repository map in context. Enable it with tokeneconomizer: `te config set repomap=on --global` (needs aider). Silence this with PASADENA_REUSE_HINT=0.'

te_bin="$(command -v te 2>/dev/null)"
[ -n "$te_bin" ] || te_bin="$HOME/.tokeneconomizer/bin/te"
[ -x "$te_bin" ] || te_bin=""

run_te() {
  if command -v timeout >/dev/null 2>&1; then
    (cd "$cwd" && timeout 3 "$te_bin" --host claude "$@") 2>/dev/null
  else
    (cd "$cwd" && "$te_bin" --host claude "$@") 2>/dev/null
  fi
}

emit() {
  jq -n --arg e "$1" --arg ctx "$2" '{hookSpecificOutput:{hookEventName:$e,additionalContext:$ctx}}'
}

case "$mode" in
  session-start)
    ctx="$rule"
    if [ "${PASADENA_REUSE_HINT:-1}" != "0" ]; then
      state=""
      [ -n "$te_bin" ] && state="$(run_te config | jq -r '.other.repomap // .repomap // empty' 2>/dev/null)"
      case "$state" in
        on | start) ;;
        *) ctx="$ctx"$'\n\n'"$hint" ;;
      esac
    fi
    emit SessionStart "$ctx"
    ;;
  subagent-start)
    agent="$(jq -r '.agent_type // empty' <<<"$input" 2>/dev/null)"
    skip="${PASADENA_REUSE_SKIP-Explore|Plan|claude-code-guide|statusline-setup|web-fetch}"
    if [ -n "$skip" ] && [ -n "$agent" ] && grep -qixE -- "$skip" <<<"$agent"; then
      exit 0
    fi
    ctx="$rule"
    if [ -n "$te_bin" ]; then
      map="$(run_te repomap | sed -n '/^# Repository map/,$p')"
      [ -n "$map" ] && ctx="$ctx"$'\n\n'"$map"
    fi
    emit SubagentStart "$ctx"
    ;;
esac
exit 0
```
Fake `te` у тесті робить `exec sleep`, тож `timeout` убиває саме процес, що тримає pipe. Якщо тест таймауту займає ≥ 4 с, причина в дочірньому процесі, який тримає stdout. Тоді треба шукати першопричину через `leslie`, а не піднімати поріг.
- [x] **Step 3: run them, watch them pass** — `bash hooks/reuse.test.sh`: усі перевірки, крім розділу `== registration ==`, мають `ok`. Останній рядок `FAILED: 7`, якщо Task 2 ще не злитий у worktree (усі перевірки розділу `== registration ==`, крім `journal.sh stays first`), і `All checks passed.`, якщо злитий.

### Task 2: реєстрація хуків

**Writes:** `hooks/claude-hooks.json`
**Reads:** `hooks/reuse.test.sh`
**Depends on:** Task 0
**Executor:** claude
**Complexity:** routine
**Satisfies:** розділ `== registration ==` у `hooks/reuse.test.sh`
**Interfaces:**
- Consumes: шлях і аргументи `hooks/reuse.sh session-start|subagent-start` (Task 1).

- [x] **Step 1: run the acceptance tests, watch registration fail** — `bash hooks/reuse.test.sh 2>&1 | grep -A1 'registers reuse.sh'`, очікувано `FAIL`.
- [x] **Step 2: implement** — у `hooks/claude-hooks.json`:
  1. У `.hooks.SessionStart[0].hooks` після наявного об'єкта `journal.sh session-start` додати другий елемент:
```json
          {
            "type": "command",
            "command": "bash \"${CLAUDE_PLUGIN_ROOT}/hooks/reuse.sh\" session-start",
            "shell": "bash",
            "timeout": 10
          }
```
  2. Після масиву `"SessionStart"` (перед `"UserPromptSubmit"`) додати:
```json
    "SubagentStart": [
      {
        "hooks": [
          {
            "type": "command",
            "command": "bash \"${CLAUDE_PLUGIN_ROOT}/hooks/reuse.sh\" subagent-start",
            "shell": "bash",
            "timeout": 10
          }
        ]
      }
    ],
```
- [x] **Step 3: watch it pass** — `jq . hooks/claude-hooks.json >/dev/null && bash hooks/reuse.test.sh 2>&1 | sed -n '/== registration ==/,$p' | grep -c 'FAIL —'` → `0`; `bash hooks/nudge.test.sh` і `bash hooks/journal.test.sh` → `All checks passed.`

### Task 3: версія 0.21.0 і документація

**Writes:** `.claude-plugin/plugin.json`, `.claude-plugin/marketplace.json`, `skills/skills.test.sh`, `README.md`, `README.uk.md`
**Reads:** `docs/sdd/specs/2026-11-03-reuse-first.md`
**Depends on:** Task 0
**Executor:** claude
**Complexity:** routine
**Satisfies:** нічого з Task 0. Перевірку задача додає в `skills/skills.test.sh` сама.

- [x] **Step 1: write the failing test** — у `skills/skills.test.sh`:
  - рядок 215: `'"version": "0.20.0"'` → `'"version": "0.21.0"'`, повідомлення `not on 0.20.0` → `not on 0.21.0`;
  - одразу після рядка 139 (`[ "$fails" -eq "$before" ] && ok "codex delegation documented"`) додати:
```bash

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
```
- [x] **Step 2: run it, watch it fail** — `bash skills/skills.test.sh`, останній рядок `FAILED: …`, серед помилок `not on 0.21.0` і `missing "PASADENA_REUSE="`.
- [x] **Step 3: implement**
  - `.claude-plugin/plugin.json:4` і `.claude-plugin/marketplace.json:12`: `"version": "0.20.0"` → `"version": "0.21.0"`.
  - `README.md`:
    - `Pasadena uses five hooks:` → `Pasadena uses six hooks:`;
    - рядок `SessionStart` у таблиці: `| \`SessionStart\` | Restores the journal context and offers to start one on a task branch; adds the reuse-first rule. |`;
    - одразу після рядка `UserPromptSubmit` додати `| \`SubagentStart\` | Gives every subagent that writes code the reuse-first rule and the cached tokeneconomizer repository map, when there is one. |`;
    - після рядка `` `PASADENA_NUDGE=0` turns off the `UserPromptSubmit` reminder. `` додати порожній рядок і: `` `PASADENA_REUSE=0` turns off the reuse-first rule and the subagent map. `PASADENA_REUSE_HINT=0` hides only the hint to enable tokeneconomizer's repomap. `PASADENA_REUSE_SKIP` is a regex of subagent types that get neither (default `Explore|Plan|claude-code-guide|statusline-setup|web-fetch`; empty turns the filter off). ``;
    - у блоці `## Checks` після `bash hooks/nudge.test.sh` додати `bash hooks/reuse.test.sh`;
    - в абзаці під ним після речення про nudge додати: `The reuse checks run \`hooks/reuse.sh\` against a fake \`te\` and cover the rule, the hint, the subagent map and filter, the timeout, the silent cases, and hook registration.`
  - `README.uk.md` дзеркально:
    - `Pasadena використовує п'ять hooks:` → `Pasadena використовує шість hooks:`;
    - рядок `SessionStart`: `| \`SessionStart\` | Відновлює контекст журналу й пропонує його завести в гілці задачі; додає правило перевикористання. |`;
    - після рядка `UserPromptSubmit`: `| \`SubagentStart\` | Дає кожному субагенту, що пише код, правило перевикористання й кешовану repomap з tokeneconomizer, якщо вона є. |`;
    - після `` `PASADENA_NUDGE=0` вимикає нагадування `UserPromptSubmit`. `` додати: `` `PASADENA_REUSE=0` вимикає правило перевикористання й карту для субагентів. `PASADENA_REUSE_HINT=0` ховає лише підказку ввімкнути repomap у tokeneconomizer. `PASADENA_REUSE_SKIP` — regex типів субагентів, які не отримують ні того, ні іншого (за замовчуванням `Explore|Plan|claude-code-guide|statusline-setup|web-fetch`; порожнє значення вимикає фільтр). ``;
    - після `bash hooks/nudge.test.sh` додати `bash hooks/reuse.test.sh`;
    - після речення про четверту перевірку: `Перевірки reuse запускають \`hooks/reuse.sh\` з фейковим \`te\` і покривають правило, підказку, карту й фільтр субагентів, таймаут, випадки мовчання та реєстрацію хука.`
- [x] **Step 4: run it, watch it pass** — `bash skills/skills.test.sh` → `All checks passed.`
