# Режими Codex: `/codex-mode explore | full | auto` — design

**Date:** 2026-11-03
**Status:** agreed

## 1. Problem

Частка роботи, яку Pasadena віддає Codex, зараз зашита в skills і не
налаштовується:

- читання — `codex.sh explore` у `sheldon`, `leonard`, `leslie`, `wolowitz`;
- фінальне ревʼю гілки — `codex.sh review` у **Finish** `wolowitz`;
- реалізація — лише завдання, які `leonard` позначив `**Executor:** codex`,
  а це можливо тільки коли збігаються всі пʼять умов
  (`skills/leonard/SKILL.md`, абзац «`**Executor:** codex | claude`»):
  ≤3 файли, без залежних завдань, повні сигнатури, `routine`, Codex доступний.

На практиці майже весь код пише Claude. Користувач, який хоче заощадити
Claude-використання, не може сказати «нехай Codex виконує, а Claude лише
планує й рецензує». Немає й способу дати Pasadena самій вибрати міру
делегування залежно від ризику задачі.

## 2. Constraint that shapes the solution

Звіт Codex не є доказом, і Codex не може завантажити `amy`. Тому навіть у
режимі максимального делегування Claude лишається тим, хто запускає гейти:
Gate red, Gate green, хеші тестів, набір `**Writes:**`. Він же робить
фінальне ревʼю. Для цього вже є перевірений цикл у
`skills/wolowitz/references/codex-tasks.md`, тож `full` його розширює і
не заводить нового протоколу.

Другий чинник: режим `auto` треба знати ще до того, як зʼявиться журнал.
`sheldon` класифікує задачу першим кроком, а Bounded-задача журналу не має
взагалі. Тому типовий режим зберігається глобально, а журнал гілки містить
уже конкретний режим, `explore` або `full`.

Очевидну альтернативу, «просто дозволити `leonard` ставити `codex` частіше»,
відкинуто: вона нічого не дає Bounded-задачам і не дає користувачу
явного перемикача.

## 3. Solution

### 3.1 Режими

| Режим | Читання | Реалізація | Фінальне ревʼю |
|---|---|---|---|
| `explore` | Codex (`codex.sh explore`) | як зараз: Codex лише для завдань, що проходять пʼять умов `leonard` | Claude `sonnet` + Codex review, як зараз |
| `full` | Codex | Codex для кожного завдання, крім Task 0; Bounded теж через Codex | лише Claude: `sonnet` `xhigh` + `security-review` |
| `auto` | — | `sheldon` перетворює на `explore` або `full` (3.4) | — |

`explore` — це рівно поточна поведінка, без жодних змін.

### 3.2 Зберігання

- **Глобальний типовий режим:** файл
  `${XDG_STATE_HOME:-$HOME/.local/state}/pasadena/codex-mode`, один рядок
  `explore`, `full` або `auto`. Відсутній файл або інший вміст означає
  `explore`.
- **Режим гілки:** рядок `codex-mode: explore|full` у frontmatter журналу,
  після `plan:`. Може бути лише конкретним, `auto` там бути не може.
  Відсутній рядок означає, що діє глобальний режим.
- **Ефективний режим:** режим гілки, якщо він є, інакше глобальний.

### 3.3 Інтерфейси

**`hooks/codex.sh mode [get | set <explore|full|auto>]`**
- `get` (або без аргументу) друкує глобальний режим у stdout і виходить з
  кодом 0.
- `set` записує файл, створюючи теку, як це вже робиться для `codex.log`.
- Недопустиме значення дає `usage` і код виходу 2.
- Підкоманда `mode` не пише в `codex.log`, не створює `work` і не ставить
  `trap`. Вона обробляється в першому `case` поруч з `available` і завершує
  скрипт.
- `usage` отримує `| mode [get | set <mode>]`.

**`hooks/journal.sh codex-mode <explore|full>`**
- Встановлює або замінює рядок `codex-mode:` у frontmatter журналу поточної
  гілки. Якщо рядка немає, він вставляється після `plan:`.
- Без журналу команда друкує в stderr `no journal for <branch>` і виходить з
  кодом 1.
- Інше значення, зокрема `auto`, дає код 2.
- Записує `✎`-рядок `codex-mode: <mode>` через той самий механізм, що й
  `note`.

**Session-start digest** (`codex_line` у `hooks/journal.sh`): після рядка
`Codex: available …` або `Codex: off …` додається
`Codex mode: <effective> (<branch|global>).` Наприклад:
`Codex mode: full (branch).` або `Codex mode: auto (global).`. Рядок
друкується і тоді, коли Codex недоступний: режим описує намір, а відкат на
Claude діє як і зараз.

**`commands/codex-mode.md`**, `argument-hint: [explore|full|auto] [--branch]`:
- Без аргументів показує глобальний режим, режим гілки (або `-`) і результат
  `codex.sh available`.
- `<mode>` викликає `codex.sh mode set <mode>`.
- `<mode> --branch` викликає `journal.sh codex-mode <mode>`. Для `auto` з
  `--branch` команда відповідає, що гілка приймає лише `explore` або `full`.
- Скрипти команда знаходить через `${CLAUDE_PLUGIN_ROOT}/hooks/`, як у
  `allowed-tools` skills.

### 3.4 `auto` у `sheldon`

Коли digest каже `Codex mode: auto`, `sheldon` одразу після класифікації
називає режим уголос разом зі шляхом:

- **Spike** → `explore`, бо реалізації немає.
- **Bounded** → `full`.
- **Architectural**, що зачіпає хоча б одне з: concurrency, збережений стан
  або міграції, security, інтерфейс, від якого залежать інші компоненти →
  `explore`.
- **Architectural** без жодного з них → одне питання через `AskUserQuestion`:
  `explore` чи `full`, з рекомендацією `full`.

Для Architectural `sheldon` викликає `raj`, щоб той записав рядок у журнал:
`raj` запускає `journal.sh codex-mode <mode>` одразу після створення журналу
на кроці 0. Для Bounded режим живе в розмові й передається в `amy` разом із
затвердженим дизайном. У `full` дизайн у чаті перелічує точні шляхи всіх
файлів, які змінюються, включно з тестовим: з них `amy` складає
`**Writes:**`.

Коли класифікація посилюється (Bounded → Architectural), режим перераховується
за тими самими правилами. Явний режим `explore` або `full` (глобальний або
гілки) `sheldon` не змінює й не перепитує.

### 3.5 `full` у `leonard`

Коли ефективний режим `full` і `codex.sh available` повертає 0, кожне
завдання, крім Task 0, отримує `**Executor:** codex`. Пʼять умов відбору тоді
не діють. Ще одна вимога: текст кожного такого завдання самодостатній,
бо Codex не бачить ні розмови, ні специфікації, лише свій промпт.
`**Complexity:**` пишеться як і зараз: від неї залежить модель
Claude-відкату. В `explore` правило без змін.

### 3.6 `full` у `wolowitz`

- **Executor під час build:** коли ефективний режим `full`, кожне завдання,
  крім Task 0, іде через **Codex tasks**, навіть якщо в плані стоїть
  `claude`, бо режим могли змінити після планування. Коли
  `codex.sh available` повертає не 0, діє поточний відкат: завдання робить
  Claude, а коментар хвилі це називає.
- **Порядок:** як і зараз, Codex-виклики йдуть по одному, після всіх
  Claude-імплементерів хвилі. У `full` хвиля з кількох Codex-завдань
  виконується послідовно.
- **Гейти й фікс-раунди:** без змін (`references/codex-tasks.md`).
- **Finish:** у `full` Codex-ревʼю не запускається. Whole-branch review
  `sonnet` `xhigh` і `security-review` лишаються. У фінальному коментарі PR
  стоїть рядок `codex review: skipped (codex-mode full)`. У `explore`
  **Finish** без змін.

### 3.7 `full` для Bounded у `amy`

Застосовується, коли `amy` викликано після затвердженого Bounded-дизайну з
ефективним режимом `full` (явним або виведеним `sheldon` з `auto`), і
`codex.sh available` повертає 0:

1. Набір файлів, який називає затверджений дизайн, стає `**Writes:**`,
   разом із тестовим файлом. Команда перевірки — та, якою `amy` і так
   запускала б тести.
2. Далі той самий цикл, що в `skills/wolowitz/references/codex-tasks.md`:
   `codex.sh red`, Gate red, `codex.sh green`, Gate green; фікс-раунди 1–2
   йдуть до `codex.sh green`, після цього `amy` реалізує сама. Промпт —
   текст `amy` плюс дизайн із чату замість `implementer-prompt-codex.md`.
3. Після зеленого Gate green Claude-рецензент на `sonnet` з
   `skills/wolowitz/reviewer-prompt.md` переглядає diff задачі. Його знахідки
   `amy` виправляє сама. Далі як завжди: **Verify before claiming**.
4. `codex.sh` повертає не 0 → `amy` робить усе сама; на коді 75 вона
   один раз каже, що Codex вимкнено.

`amy`, викликана напряму, без `sheldon`, з ефективним `auto`, працює як
`explore`, бо класифікації немає *(моє рішення)*. Імплементери, яких
`amy` запускає з `wolowitz`, цього розділу не застосовують: там режимом
керує сам `wolowitz`.

### 3.8 Тести, документація, версія

- `hooks/codex.test.sh`: `mode get` без файлу → `explore`; `set full`, потім
  `get` → `full`; `set bogus` → код 2; `mode` не створює `codex.log`.
- `hooks/journal.test.sh`: `codex-mode full` вставляє рядок після `plan:`;
  повторний виклик замінює, а не дублює; `auto` → код 2; без журналу → код 1;
  digest показує `Codex mode: full (branch).` і
  `Codex mode: auto (global).`.
- `skills/skills.test.sh`, `require`:
  - `sheldon "Codex mode: auto"`
  - `leonard "Codex mode: full"`
  - `wolowitz "codex-mode full"`
  - `amy "codex.sh red"`
  - `raj "journal.sh codex-mode"`
  - наявність `commands/codex-mode.md`.
- `README.md` і `README.uk.md`, розділ «Codex delegation»: три режими,
  команда, таблиця з 3.1.
- Версія `0.20.0` → `0.21.0` у `.claude-plugin/plugin.json` і
  `.claude-plugin/marketplace.json`.

## 4. Out of scope

- Режим для окремого завдання поза полем `**Executor:**` плану.
- Автоматичне перемикання режиму посеред build.
- Codex-ревʼю в `full`, як окремий прапорець чи будь-як інакше.
- Змінна середовища для режиму; `PASADENA_CODEX=0` лишається вимикачем
  усього Codex.
- `leslie`, `bernie`, `stuart`, `penny`: їхня поведінка не змінюється
  (виправлення від `leslie` іде через `amy` за 3.7).

## 5. Trade-offs accepted

- `full` повільніший за wall-clock: Codex-виклики послідовні, а паралельні
  хвилі Claude-імплементерів зникають. Ціна прийнятна, бо мета — економія
  Claude-використання, а не швидкість.
- У `full` немає незалежної другої думки від Codex на фінальному ревʼю.
  Рецензувати власний код — гірше, ніж не рецензувати.
- Bounded у `full` отримує новий шлях в `amy`, який треба підтримувати.
  Його звужує повторне використання циклу `codex-tasks.md`.
- Межу «середньої» задачі визначає судження `sheldon` щодо ризиків. Це
  мʼякша межа, ніж формальне правило, але решту вирішує питання користувачу.

## 6. Verification

- `bash hooks/codex.test.sh`, `bash hooks/journal.test.sh`,
  `bash skills/skills.test.sh` → усі зелені.
- Вручну: `/codex-mode` показує `explore`, `-`, доступність; `/codex-mode full`,
  нова сесія → digest `Codex mode: full (global).`;
  `/codex-mode explore --branch` у гілці з журналом → журнал має
  `codex-mode: explore`, digest `Codex mode: explore (branch).`.
- Вручну, `auto`: `/pasadena` з Bounded-задачею → `sheldon` каже «Bounded,
  codex-mode full», і `amy` запускає `codex.sh red`.
