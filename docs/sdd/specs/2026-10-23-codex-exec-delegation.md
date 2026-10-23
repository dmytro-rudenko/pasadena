# Делегування в `codex exec` — design

**Date:** 2026-10-23
**Status:** agreed

## 1. Problem

Уся робота skills Pasadena зараз виконується моделями Claude: контролер,
read-only `Explore`-пошуки, implementer'и хвиль `wolowitz` і ревʼюери. Саме
вони витрачають ліміти Claude. Значна частина цієї роботи механічна: пошук по
коду і стислий переказ файлів у `leonard`/`leslie`/`sheldon`, прості задачі
плану з чітко заданими значеннями, друга думка по diff хвилі.

На машині користувача вже є `codex-cli` 0.164.0 із неінтерактивним режимом
`codex exec`. Ліміти Codex окремі від лімітів Claude, тож частину роботи можна
віддати Codex, якщо Claude лишається оркестратором і сам перевіряє результат.

PR #14 прибрав Codex як **хост** плагіна. Ця специфікація додає Codex як
**виконавця** під Claude Code і тому з тим рішенням не конфліктує.

## 2. Constraint that shapes the solution

**TDD-дисципліна `amy` має діяти для Codex так само суворо, як для
Claude-субагентів, хоча Codex не може викликати `pasadena:amy` і його звіту
«тест падав» вірити не можна.** Тому TDD забезпечує контролер механічно: два
окремі виклики Codex (лише тести → лише код) і gate'и між ними, на яких
контролер сам запускає тести й перевіряє diff.

Звідси випливають три перевірені спайками факти, які визначають реалізацію:

- Продовжувати implementer'а треба за конкретним id сесії:
  `codex exec resume <thread_id>` продовжує саме ту сесію. `thread_id`
  береться з першої JSONL-події `{"type":"thread.started","thread_id":…}`.
  Сторонній плагін `openai-codex/codex` уміє лише `--resume-last` (останній job
  Claude-сесії, `codex-companion.mjs:299-303`, `:471`), а в паралельній хвилі
  це продовжить чужу сесію. Саме тому обрано власну обгортку, а не цей плагін.
- `codex exec resume` не має прапорця `-s`, тож сандбокс для нього задається
  через `-c sandbox_mode="workspace-write"`.
- `codex exec review --base <sha>` порівнює коміти через GitHub MCP
  (`codex_apps` → `github.compare_commits`), а не через локальний git. Коміти
  хвилі локальні, бо push — це stop gate, тому review будується на локальному
  `git diff`, переданому в stdin.

## 3. Solution

### 3.1. `hooks/codex.sh`

Новий скрипт поруч із `journal.sh`. Skills викликають його через Bash за тим
самим шляхом плагіна, що й `journal.sh`. Stdout кожної підкоманди містить лише
корисний результат, JSONL-подій там немає.

| Підкоманда | Поведінка | Виклик Codex |
|---|---|---|
| `available` | exit 0, коли делегування можливе; інакше 1, без виводу | перевіряє `PASADENA_CODEX` ≠ `0`, `command -v codex`, `codex login status` з exit 0 |
| `explore <prompt-file>` | stdout — фінальна відповідь агента | `codex exec -s read-only -C "$PWD" --json -o <tmp> - < <prompt-file>` |
| `review <base-sha> <prompt-file>` | stdout — звіт ревʼюера | `git diff <base-sha>` (робоче дерево проти base, бо review хвилі йде до коміту) плюс кожен untracked файл як `git diff --no-index /dev/null <file>` → stdin `codex exec -s read-only -C "$PWD" --json -o <tmp> "$(cat <prompt-file>)"`; порожній diff → exit 1 без виклику Codex |
| `red <prompt-file>` | рядок 1 stdout — `thread_id`, далі фінальне повідомлення | `codex exec -s workspace-write -C "$PWD" --json -o <tmp> - < <prompt-file>` |
| `green <thread-id> <prompt-file>` | stdout — фінальне повідомлення | `codex exec resume <thread-id> -c sandbox_mode="workspace-write" --json -o <tmp> - < <prompt-file>` |

Правила для всіх підкоманд:

- Промпт передається **файлом**: у `red`/`green` він містить повний текст
  `skills/amy/SKILL.md`.
- Якщо задано `PASADENA_CODEX_MODEL`, додається `-m "$PASADENA_CODEX_MODEL"`.
  Інакше модель і effort береться з `~/.codex/config.toml`.
- **Таймаут простою, а не загальний.** Скрипт читає JSONL-потік і вбиває
  процес Codex, коли нових подій немає довше за ліміт:
  - `PASADENA_CODEX_IDLE`, за замовчуванням `120` с, коли незакритих команд
    немає;
  - `PASADENA_CODEX_CMD_IDLE`, за замовчуванням `600` с, поки відкрито
    `command_execution` (є `item.started` без парного `item.completed`), щоб
    повільні тести не вбивали живу сесію.
  Після вбивства скрипт завершується з кодом `124`. Замір на задачі з
  `high` effort показав 19 подій за 61 с і найбільшу паузу 9,4 с, тож поріг 120 с
  дає запас приблизно в 13 разів.
- Exit Codex ≠ 0 або порожній файл `-o` → скрипт виходить з кодом ≠ 0 і пише
  причину в stderr. Скрипт нічого не повторює сам: це рішення контролера.
- **Вичерпаний ліміт ChatGPT-плану.** Якщо в потоці є подія `error` або
  `turn.failed`, повідомлення якої відповідає регулярному виразу
  `usage limit|insufficient_quota` без урахування регістру (тимчасовий
  `rate limit` Codex повторює сам, а голе `quota` ловило б і
  `Disk quota exceeded`), скрипт виходить з
  кодом `75` і створює маркер
  `${XDG_STATE_HOME:-$HOME/.local/state}/pasadena/codex-exhausted`. Маркер
  лежить поза репозиторієм, бо ліміт належить акаунту, а не проєкту. Поки маркер
  існує, `available` повертає 1. Його видаляє користувач або сам `available`,
  якщо маркер старший за 6 годин.
- Після кожного виклику скрипт пише в stderr один рядок з `usage` із події
  `turn.completed`:
  `codex usage: input=<input_tokens> cached=<cached_input_tokens> output=<output_tokens>`.
- Промпти `explore` і `review` вимагають працювати лише з локальними файлами
  та stdin і вказувати факти з посиланнями `file:line`.

### 3.2. TDD-цикл Codex-implementer'а у `wolowitz`

Стосується задач плану з `**Executor:** codex`. Codex-задачі хвилі стартують
після того, як відзвітували всі її Claude-implementer'и, і виклики Codex ідуть
по одному. Тоді під час виклику інших авторів змін немає, і рядок
`codex changed: <шляхи>`, який `codex.sh red`/`green` друкує в stderr за
хешами файлів до і після виклику, механічно атрибутує кожну зміну цьому
виклику. Кожен виклик `codex.sh` контролер запускає через Bash з
`run_in_background`.

1. **Red.** Контролер збирає prompt-файл із трьох частин: повний текст
   `skills/amy/SKILL.md`, `skills/wolowitz/implementer-prompt-codex.md` і
   номер задачі з шляхом до плану. Codex-варіант промпту замість «invoke
   `pasadena:amy`» каже, що правила amy вкладено вище, і вимагає на цьому кроці
   писати **лише тести** задачі, не чіпаючи код. Далі `codex.sh red <file>`.
2. **Gate red** (контролер сам):
   - усі шляхи з `codex changed:` — тестові файли з `**Writes:**`;
   - verification-команда задачі червона, **і причина та, що передбачає план**.
     Падіння через синтаксис чи імпорт не зараховується;
   - контролер зберігає `sha256sum` тестових файлів задачі і їхню копію в
     scratchpad. Коли пізніший gate бачить невідповідність checksum, тести
     спершу відновлюються з копії, а наступний implementer дізнається, що їх
     було змінено й відновлено.
   Якщо gate не пройдено, контролер викликає `codex.sh green <thread-id>` з
   описом проблеми, щоб виправити тести, і повторює gate red.
3. **Green.** `codex.sh green <thread-id> <file>` з інструкцією «мінімальний
   код, тести не змінюй».
4. **Gate green:**
   - `sha256sum` тестових файлів збігається зі збереженим;
   - шляхи з `codex changed:` ⊆ `**Writes:**`, і тестових файлів серед них
     немає;
   - verification-команда зелена.
   Провал Gate green одразу після кроку 3 зараховується як fix round 1.
5. Далі звичайний цикл хвилі без змін: suite, review, commit, PR-коментар.

**Fix loop і фолбек.** Fix loop має ті самі три раунди, що й зараз. Раунди 1–2 —
це `codex.sh green <thread-id> <prompt-file>` у ту саму сесію з дослівними
знахідками, і після кожного раунду Gate green проходить знову: будь-який його
провал забирає раунд. Раунд 3 — свіжий Claude-implementer на моделі сесії,
тобто задачу забирають у Codex. Gate red має не більше двох повторів, після
чого задача теж переходить до Claude.
Якщо `codex.sh` повертає ≠ 0 (зокрема `124`), задача одразу переходить до
Claude-implementer'а, і PR-коментар хвилі називає причину. Код `75` (ліміт)
контролер ще й **одним рядком у чаті** повідомляє користувачу, бо з цього
моменту Codex до кінця сесії не використовується і економія лімітів Claude
припиняється. PR-коментар хвилі містить суму рядків `codex usage`, які дали
виклики цієї хвилі.

### 3.3. Explore

Коли `codex.sh available` = 0, read-only дослідження делегується в
`codex.sh explore`:

- `leonard`, «Explore before decomposing»: стек, конвенції, хелпери, файли для
  `**Writes:**`/`**Reads:**`;
- `leslie`, Phase 1 «Root cause» і Phase 2 «Pattern»: збір фактів;
- `sheldon`, «Understand the idea»: огляд поточного стану;
- `wolowitz`, таблиця Models: рядок «Read-only `Explore` lookup» стає
  «`codex.sh explore`, коли `available`; інакше `Explore` на `sonnet`».

Codex приносить факти з `file:line`; висновки, гіпотези й рішення формує
Claude. Факт, на який спирається план або фікс (сигнатура, назва, шлях), Claude
перевіряє одним `Read` або `grep`, перш ніж використати.

### 3.4. Review (друга думка)

У `wolowitz`, крок 4 «Review the wave», `codex.sh review <BASE>
<prompt-file>` запускається паралельно з `fable`-ревʼюером. `<prompt-file>` —
заповнена копія `skills/wolowitz/reviewer-prompt.md` у scratchpad, де рядок
про diff замінено на «diff надходить через stdin як блок `<stdin>`», бо
review хвилі йде до її коміту. Те саме робиться для whole-branch review у Finish з
`git merge-base <trunk> HEAD`.

Як контролер зводить знахідки:
- у fix loop іде все від `fable`, а також знахідки Codex, які контролер
  перевірив сам за `file:line`;
- неперевірені знахідки Codex відкидаються з однорядковою приміткою в
  PR-коментарі хвилі.

Вердикт `fable` лишається основним.

### 3.5. `**Executor:**` у `leonard`

Блок кожної задачі отримує рядок `**Executor:** codex | claude` після
`**Depends on:**`. `codex` ставиться лише тоді, коли виконано **всі** умови:

- `**Writes:**` має ≤ 3 файли, і серед них є тест;
- жодна інша задача не залежить від неї через `**Depends on:**`;
- усі імена, рядки, числа й сигнатури задано в тексті задачі;
- `codex.sh available` повертає 0 у момент планування.

Інакше ставиться `claude`. Task 0 (acceptance tests) завжди має
`**Executor:** claude`. Розподіл видно в плані, який затверджує користувач.
Якщо на момент build `available` ≠ 0, `wolowitz` виконує `codex`-задачі як
`claude` і пише про це в PR-коментарі хвилі.

Коли `available` ≠ 0, усі skills працюють рівно так, як до цієї зміни.

### 3.6. Версія та документація

- `.claude-plugin/plugin.json` і `.claude-plugin/marketplace.json`:
  `0.9.0` → `0.10.0`.
- `README.md` і `README.uk.md` отримують розділ «Codex delegation» (укр.
  «Делегування в Codex»):
  - Codex опційний і є виконавцем, а не хостом, на відміну від PR #14;
  - три режими: explore, review, implement;
  - змінні `PASADENA_CODEX`, `PASADENA_CODEX_IDLE`, `PASADENA_CODEX_CMD_IDLE`,
    `PASADENA_CODEX_MODEL`;
  - рядок `bash hooks/codex.test.sh` у розділі «Checks».

## 4. Out of scope

- Codex як хост плагіна (`.codex-plugin/`), прибраний у PR #14.
- Codex у `penny`, `stuart` і `bernie`, тобто в задачах із браузером.
- Codex як основний ревʼюер замість `fable`.
- Підрахунок і звітність зекономлених токенів.
- Фолбек через сторонній плагін `openai-codex/codex`.
- Codex як виконавець Task 0 (acceptance tests) і задач, від яких залежать
  інші.

## 5. Trade-offs accepted

- Codex-задача займає більше wall-clock часу, ніж Claude-задача: два виклики
  і два gate'и. Це компенсується тим, що задача взагалі не витрачає лімітів
  Claude на написання коду.
- Контролер витрачає Claude-токени на тести, diff і перевірку фактів із
  explore. Це суттєво менше, ніж написання коду чи повний пошук, і без цього
  TDD та достовірність фактів не гарантовані.
- Якість review залежить від того, як контролер зводить дві думки. Тому
  основним лишається `fable`, а Codex може лише додати перевірені знахідки.
- Codex витрачає ліміти ChatGPT-плану, і вони теж скінченні. Спайк із
  простим read-only питанням (≈1 хв) спожив 444 661 вхідний токен, з них
  368 768 із кешу. Тому explore вмикається лише там, де дослідження об'ємне, а
  вичерпаний ліміт (код `75`) видно користувачу і він вимикає Codex до кінця
  сесії, а не призводить до тихих повторних спроб.
- Таймаут простою не ловить Codex, який зациклився і активно шле події. Такий
  випадок ловить gate або fix loop із трьох раундів.

## 6. Verification

1. `bash hooks/codex.test.sh` з фейковим `codex` у `PATH` покриває:
   - `available` для `PASADENA_CODEX=0`, відсутнього `codex` і login status ≠ 0;
   - прапорці кожної підкоманди, зокрема `-c sandbox_mode="workspace-write"`
     у `green` і stdin-diff у `review`;
   - розбір `thread_id` з першої події в `red`;
   - idle-kill з кодом `124` при `PASADENA_CODEX_IDLE=1`;
   - те, що поки відкрито `command_execution`, діє `PASADENA_CODEX_CMD_IDLE`;
   - вихід ≠ 0, коли файл `-o` порожній;
   - код `75` і маркер `$XDG_STATE_HOME/pasadena/codex-exhausted` (у тесті
     `XDG_STATE_HOME` — тимчасовий каталог) на події `turn.failed` з
     «usage limit», після чого `available` повертає 1, а з маркером, старшим за
     6 годин, знову 0;
   - рядок `codex usage: …` у stderr з полів `turn.completed`.
2. `bash skills/skills.test.sh` отримує нові перевірки:
   - `leonard/SKILL.md` описує `**Executor:**`;
   - `wolowitz/SKILL.md` згадує `codex.sh red`, `codex.sh green`, gate red і
     gate green;
   - `wolowitz/implementer-prompt-codex.md` існує і не містить «Skill tool»;
   - версії в маніфестах збігаються (ця перевірка вже є).
3. Наявні `bash hooks/journal.test.sh`, `bash hooks/nudge.test.sh` і
   `bash proto/server.test.sh` лишаються зеленими.
4. Ручна наскрізна перевірка на тимчасовому репозиторії з однією
   `codex`-задачею і справжнім `codex`:
   - цикл red → gate red → green → gate green;
   - доказом є вивід verification-команди на обох gate'ах і незмінний
     `sha256sum` тестових файлів;
   - той самий сценарій з `PASADENA_CODEX=0` виконує задачу Claude-implementer.
