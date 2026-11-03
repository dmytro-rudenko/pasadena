# Перевикористання наявного коду — design

**Date:** 2026-11-03
**Status:** agreed

## 1. Problem

Агент пише з нуля те, що в проєкті вже є. Типові випадки:

- на сторінці вже є input з налаштованою валідацією й нотифікаціями, а на новій сторінці агент робить такий самий з нуля;
- у проєкті є верхня панель сторінки або шаблон сторінки, що підходить для нової, а агент верстає їх заново.

Причин дві:

1. Агент не бачить, що вже існує, а пошук для нього дорогий. Тому він пише, а не шукає.
2. Правила «спершу перевикористай» pasadena не дає ніде, окрім планування: `skills/leonard/SKILL.md:72-73` вимагає назвати хелпери в задачах плану. Ні `skills/wolowitz/implementer-prompt.md`, ні ad-hoc сесії без `/pasadena` цього правила не отримують.

Вплив: дублікати компонентів розходяться в поведінці (валідація, тексти помилок, стилі), а виправлення доводиться робити в кількох місцях.

## 2. Constraint that shapes the solution

**Карту коду вже будує tokeneconomizer, але субагенти її не отримують.**

tokeneconomizer (`repomap=on`, увімкнено глобально 2026-11-03) підкладає в основну сесію repomap від aider: tree-sitter, ранжування PageRank і під перший промпт, бюджет 2048 токенів, кеш на кожен коміт. Хука `SubagentStart` у нього немає. А саме субагенти пишуть код у `wolowitz`.

Через це відкинуто два очевидні варіанти:

- **Власна карта в pasadena на кшталт `ponytail-map.js`** (regex по `git ls-files`) дублює роботу tokeneconomizer гіршою якістю: лише верхній рівень, без ранжування.
- **Правило лише в скілах workflow** не охоплює ad-hoc сесії, а користувач хоче охоплення в кожній сесії.

Отже, pasadena додає лише те, чого бракує: правило в кожну сесію і кожен субагент, а субагентам ще й кешовану карту з `te`. Без tokeneconomizer правило працює саме по собі: агент шукає через `grep`.

## 3. Solution

### 3.1. Хук `hooks/reuse.sh`

Bash, `set -uo pipefail`, як `hooks/nudge.sh`. Читає JSON події зі stdin. Режим береться з першого аргументу: `session-start` або `subagent-start`.

- `PASADENA_REUSE=0` вимикає хук: порожній вивід, `exit 0`.
- `cwd` береться з поля `.cwd` вхідного JSON, а якщо його немає, то `$PWD`. Поза git-репозиторієм хук нічого не виводить, як `nudge.sh`.
- Хук завжди завершується з `exit 0`. Його збій не повинен ламати старт сесії чи субагента.

**Пошук `te`:** спершу `command -v te`, потім `$HOME/.tokeneconomizer/bin/te`. Якщо нічого не знайдено або файл не виконуваний, вважається, що `te` немає.

**Режим `session-start`** виводить правило (3.2). Окремим абзацом після нього йде підказка (3.3), коли виконано обидві умови:

- `PASADENA_REUSE_HINT` не дорівнює `0`;
- `te` немає, або `te --host claude config | jq -r '.other.repomap // .repomap // empty'` повертає не `on` і не `start`. `te config` віддає ефективні налаштування (репозиторій плюс глобальні) як вкладений JSON, і ключ лежить у секції `other`. Запасний `.repomap` потрібен на випадок, якщо tokeneconomizer змінить структуру. Це рішення будівельника, з користувачем не погоджувалося.

Карту в основну сесію хук не додає, бо це робить tokeneconomizer.

**Режим `subagent-start`** виводить правило. Далі, якщо `te` знайдено, хук виконує `timeout 3 te --host claude repomap` у `cwd` (`cd "$cwd"`, бо `te` визначає репозиторій за поточною тікою). Якщо `timeout` немає (macOS без coreutils), команда йде без нього, і від зависання захищає `"timeout": 10` у реєстрації хука. Це теж рішення будівельника. Із результату хук бере вивід, починаючи з рядка `# Repository map` і до кінця. Перший службовий рядок (`<repo>: ~N tokens …`) відкидається. Якщо такого рядка у виводі немає (`no map cached for …`), або `te` завершився з таймаутом чи помилкою, карта не додається. Хук нічого не генерує: `refresh` не викликається ніколи.

Підказка (3.3) у субагентах не показується, бо її вже бачила основна сесія.

**Формат виводу** такий самий, як у `nudge.sh`, тільки з `jq -n`:

```json
{"hookSpecificOutput":{"hookEventName":"SessionStart","additionalContext":"<текст>"}}
```

У режимі `subagent-start` поле `hookEventName` має значення `"SubagentStart"`.

### 3.2. Текст правила

Англійською, як решта контексту, який pasadena передає моделі:

```
Reuse before you write. Before creating a component, helper, hook, layout, page or page template:
1. Find the closest existing one: check the repository map if one is in context, otherwise grep by role (input, form, field, header, toolbar, layout, page, template) and by the name you were about to give it. Read what you find.
2. Use it the way the neighbouring code does. If it lacks something, extend it instead of copying it.
3. Write new code only when nothing fits, and say in one line of your reply what you checked and why it did not fit.
```

### 3.3. Текст підказки

```
pasadena: no repository map in context. Enable it with tokeneconomizer: `te config set repomap=on --global` (needs aider). Silence this with PASADENA_REUSE_HINT=0.
```

### 3.4. Реєстрація в `hooks/claude-hooks.json`

- До наявного запису `SessionStart` (matcher `startup|resume|clear|compact|fork`) додається другий хук: `bash "${CLAUDE_PLUGIN_ROOT}/hooks/reuse.sh" session-start`, `"shell": "bash"`, `"timeout": 10`.
- З'являється новий розділ `SubagentStart` без matcher з хуком `bash "${CLAUDE_PLUGIN_ROOT}/hooks/reuse.sh" subagent-start`, `"shell": "bash"`, `"timeout": 10`.

### 3.5. Версія

`version` змінюється з `0.20.0` на `0.21.0` у `.claude-plugin/plugin.json:4` і `.claude-plugin/marketplace.json:12`. Обидва файли перевіряє `skills/skills.test.sh`.

### 3.6. Документація

В обох README, `README.md` і `README.uk.md`:

- У таблиці хуків (`README.md:91-99`) «five hooks» стає «six hooks». До рядка `SessionStart` додається: «and adds the reuse-first rule». З'являється новий рядок `SubagentStart`: «Gives every subagent the reuse-first rule and the cached tokeneconomizer repository map, when there is one».
- Поруч із рядком про `PASADENA_NUDGE=0` (`README.md:122`) з'являється рядок: `PASADENA_REUSE=0` вимикає правило й карту, `PASADENA_REUSE_HINT=0` вимикає лише підказку про repomap.
- До списку тестових команд (`README.md:177-180`) додається `bash hooks/reuse.test.sh`, а до опису перевірок — одне речення про них.

`README.uk.md` змінюється так само, в рядках 91, 120 і 175-181.

## 4. Out of scope

- Власна карта коду в pasadena, зокрема запасна regex-карта.
- Блокування `Write` нових файлів у папках компонентів через `PreToolUse` (так званий варіант B). Його можна додати поверх, якщо правило ігноруватимуть.
- Перевірка дублікатів у `skills/wolowitz/reviewer-prompt.md`.
- Implementer-и, яких делегують у Codex через `codex.sh`. `SubagentStart` Claude Code до них не доходить.
- Зміни в tokeneconomizer.
- Ручний реєстр компонентів (`reuse.md`).

## 5. Trade-offs accepted

- Правило лише підштовхує, а не забороняє. Агент може його проігнорувати. Ціна жорсткого бар'єра (хибні блокування легітимних нових компонентів) поки вища за користь.
- Кожен субагент отримує до 2048 токенів карти, зокрема й субагенти, яким вона не потрібна (наприклад, `Explore`). Фільтрувати за `agent_type` поки не варто, бо дублікати пишуть саме ті субагенти, які не відомо наперед.
- Карта субагента відповідає закешованому стану, а не поточному: новий коміт без перегенерації дає карту попереднього коміту. tokeneconomizer оновлює кеш у фоні при зміні `HEAD`, тож відставання короткочасне.
- Semantics («input з валідацією») карта бачить лише за іменем та сигнатурою. Решту агент знаходить, читаючи файл за правилом 3.2.1.

## 6. Verification

Автоматично: `bash hooks/reuse.test.sh` у стилі `hooks/nudge.test.sh`, з фейковим `te`, що підкладається через тимчасовий `HOME` і `PATH`.

1. `session-start` у git-репозиторії: вивід містить `Reuse before you write` і `"hookEventName":"SessionStart"`.
2. `session-start` без `te`: є підказка. З `PASADENA_REUSE_HINT=0` підказки немає.
3. `session-start` з фейковим `te`, що в `config` повертає `{"other":{"repomap":"on"}}`: підказки немає. Якщо повертає `{"other":{"repomap":"off"}}`, підказка є.
4. `subagent-start` з фейковим `te`, що в `repomap` повертає службовий рядок і `# Repository map` з тілом: вивід містить карту, але не службовий рядок, а `hookEventName` дорівнює `SubagentStart`.
5. `subagent-start` з фейковим `te`, що повертає `no map cached for x`: є правило, карти немає.
6. `subagent-start` без `te`: є лише правило.
7. `PASADENA_REUSE=0` в обох режимах: порожній вивід, `exit 0`.
8. Поза git-репозиторієм: порожній вивід, `exit 0`.
9. Фейковий `te`, що «висить» 5 с: хук завершується менш ніж за 4 с і віддає правило без карти.
10. `hooks/claude-hooks.json` реєструє `reuse.sh session-start` під `SessionStart` і `reuse.sh subagent-start` під `SubagentStart`. Перевірка через `jq`, як у `nudge.test.sh`.

Вручну: у проєкті з JS/TS-компонентами запустити субагента, наприклад `wolowitz` або «створи сторінку X» через `Agent`, і переконатися через `claude --debug` або транскрипт субагента, що в його контексті є правило й карта.
