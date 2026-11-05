> [English](README.md) · Українська

# pasadena

`pasadena`: плагін для Claude Code, що тримає контекст задачі в гілці, перетворює узгоджений дизайн на план і виконує незалежні задачі паралельно.

## Яку проблему він вирішує

Спека каже, що ви хочете побудувати. Git-історія каже, що ви змерджили. Жодна не каже, де зупинилась робота, що вже перевірили й який файл відкрити далі.

Pasadena зберігає цей контекст у `.pasadena/journal/<гілка>.md`. Журнал живе в гілці задачі та видаляється перед мерджем, коли його корисний підсумок уже перенесено в pull request. Наявні файли `.claude/journal/` лишаються legacy-журналами для читання.

## Якщо ви з obra/superpowers

Pasadena виросла з щоденної роботи з [obra/superpowers](https://github.com/obra/superpowers). Ідея та сама: скіли, що спрямовують агента. Змінено те, чого мені бракувало:

- **Plan mode для плану.** Після узгодження спеки `leonard` пише план у нативному plan mode Claude Code.
- **Codex як помічник.** Якщо встановлено Codex CLI, скіли віддають йому пошук по коду, другий рев'ю гілки й позначені задачі. Claude перевіряє кожен результат.
- **Spec-driven плюс test-driven.** Спершу `sheldon` узгоджує спеку, потім `amy` пише тести, що падають, до будь-якого робочого коду.
- **Паралельні субагенти.** `leonard` оголошує набори файлів для кожної задачі й групує незалежні задачі у хвилі; `wolowitz` виконує кожну хвилю паралельно.

Відгуки вітаються: відкрийте [issue](https://github.com/dmytro-rudenko/pasadena/issues/new/choose).

## Процес

Запустіть `/pasadena`, щоб продовжити з поточного етапу гілки. `/bazinga` лишається аліасом.

| Скіл | Робота |
| --- | --- |
| `sheldon` | Визначає обсяг, ставить короткі запитання та пише узгоджену спеку. Секції дизайну пишуться паралельно й подаються на одне погодження. Для архітектурної роботи спершу створює worktree, журнал і draft PR. |
| `penny` | Збирає два-чотири браузерні прототипи для UI-рішення, перевіряє обраний варіант разом із вами та фіксує рішення. |
| `leonard` | Використовує plan mode Claude Code, щоб перетворити спеку на виконувані задачі та безпечні паралельні хвилі. |
| `wolowitz` | Виконує кожну хвилю, перевіряє результат, комітить задачі, рев'ює кожну третю хвилю і всю гілку, пише прогрес у PR. |
| `amy` | Спершу пише приймальні тести на всю задачу, потім тест, що падає, перед production-кодом для кожного кроку фічі, багфіксу, рефакторингу чи задачі лише з тестами, і вимагає доказ свіжим прогоном, перш ніж щось назвати готовим. |
| `leslie` | Знаходить першопричину бага чи неочікуваного падіння за чотири фази, а потім виправляє через amy. |
| `bernie` | Перевіряє фічу end-to-end у браузері з доказами або додає сталий e2e-тест на Playwright. |
| `stuart` | Знімає сторінку на кількох брейкпоінтах, звітує про дефекти верстки й виправляє їх після вашої згоди. |
| `raj` | Заводить, оновлює, відновлює, передає та закриває журнал сесії. |

Front matter журналу та чекбокси плану містять стан процесу. Pasadena не веде окремий файл статусу.

## Встановлення

Запуск із локального checkout:

```bash
claude --plugin-dir /шлях/до/pasadena
```

Або встановлення через GitHub marketplace:

```
/plugin marketplace add dmytro-rudenko/pasadena
/plugin install pasadena@pasadena
```

Для локальної розробки скопіюйте плагін у директорію скілів Claude Code і перезавантажте плагіни після змін:

```bash
cp -r /шлях/до/pasadena ~/.claude/skills/pasadena
/reload-plugins
```

Потрібні `bash`, `git`, `jq` і Node.js для браузерних прототипів.

Перевірка структури плагіна:

```bash
claude plugin validate .
```

## Журнал сесії

Керуйте журналом через `/journal start`, `/journal note`, `/journal pause` або `/journal finish`.

```markdown
---
branch: port/0021-stuck-calls-recovery
spec: docs/specs/0021-stuck-calls-recovery.md
plan: docs/plans/2026-08-05-st-patches-port.md
status: in-progress
started: 2026-08-10
---

## Goal
Не давати QUEUE_FULL задачам автоматично падати. Готово, коли проходить backend-тест і відкрито PR.

## Now
Фаза 2 з 3. Для `deferQueueJob` є тест. Далі: `backend/src/queue/transcribe.ts:212`, потім `pnpm --filter backend test`.

## Timeline
### 2026-08-10
- 14:20 ▶ start · port/0021 @ 12a9a4b
- 15:02 ● a1b2c3d feat: defer queue job on QUEUE_FULL
- 15:40 ✎ Фаза 2/3: deferQueueJob покрито тестом
```

Залишайте `## Goal`, `## Now` і `## Timeline` англійською: хуки парсять ці заголовки. Вміст секцій пишіть мовою користувача.

Змінюється лише `## Now`. Там мають бути поточна фаза, блокер за наявності та конкретний наступний крок із командою перевірки. `## Timeline` лише доповнюється.

Pasadena використовує шість hooks:

| Подія | Що робить |
| --- | --- |
| `SessionStart` | Відновлює контекст журналу й пропонує його завести в гілці задачі; додає правило перевикористання. |
| `UserPromptSubmit` | Нагадує агенту викликати leslie для бага або amy для нової поведінки; поза Git-репозиторієм мовчить. |
| `SubagentStart` | Дає кожному субагенту, що пише код, правило перевикористання й кешовану repomap з tokeneconomizer, якщо вона є. |
| `PostToolUse` | Додає коміти, що з'явилися після останнього запису. |
| `SessionEnd` | Додає паузу з HEAD і брудними файлами. |
| `StopFailure` | Додає тип помилки. |

Хуки читають Git-стан і дописують журнал; `UserPromptSubmit` лише додає контекст до промпту. Git-історію та індекс вони не змінюють.

> Журнал сесії (`.pasadena/journal/<гілка>.md`) живе лише в task-гілці. Перед merge перенесіть підсумок в опис PR, видаліть файл і закомітьте видалення.

```bash
git rm .pasadena/journal/<гілка>.md
git commit -m "chore(journal): close <task>"
```

## Налаштування

`PASADENA_TRUNK` містить гілки, для яких журнал не створюється. Дефолт: `main master dev develop trunk`.

Задайте змінну у профілі shell або в `.claude/settings.json`:

```json
{ "env": { "PASADENA_TRUNK": "main staging" } }
```

`PASADENA_NUDGE=0` вимикає нагадування `UserPromptSubmit`.

`PASADENA_REUSE=0` вимикає правило перевикористання й карту для субагентів. `PASADENA_REUSE_HINT=0` ховає лише підказку ввімкнути repomap у tokeneconomizer. `PASADENA_REUSE_SKIP` — regex типів субагентів, які не отримують ні того, ні іншого (за замовчуванням `Explore|Plan|claude-code-guide|statusline-setup|web-fetch`; порожнє значення вимикає фільтр).

## Браузерні прототипи

`penny` підіймає локальний Node-сервер без залежностей лише на час рев'ю прототипа. Він слухає loopback, вимагає ключ сесії для першого запиту та зберігає рантайм-стан у git-ігнорованій `.sdd/`. Файли прототипів і рішення лишаються в `docs/sdd/proto/` для рев'ю.

Сервер використовує `fetch` для виборів і опитування раз на секунду для оновлень. Так він обходиться без WebSocket-залежності.

## Моделі

Кожен skill задає `model` і `effort` у своєму frontmatter. Override діє до вашого наступного повідомлення, після чого сесія повертається на вашу модель; коли за один хід викликано кілька skills, діє останній.

| Skill | Модель | Effort |
|---|---|---|
| `amy`, `sheldon`, `leonard`, `leslie` | `opus` | `high` |
| `wolowitz`, `penny` | `opus` | `medium` |
| `bernie`, `stuart` | `sonnet` | `xhigh` |
| `pasadena`, `raj`, `journal` | `sonnet` | `medium` |

`wolowitz` також задає `model` і `effort` у кожному dispatch. Claude-задача йде спершу до test writer-а, який викликає `amy` і пише лише тести, а потім до implementer-а, який пише лише код; задача, що пише тільки тести або тільки код, іде лише до одного з них. `leonard` позначає кожну задачу в плані як `routine` або `complex`.

| Dispatch | Модель | Effort |
|---|---|---|
| Test writer | `opus` | `high` |
| Implementer, `routine`-задача | `sonnet` | `xhigh` |
| Implementer, `complex`-задача, раунд 3, фінальний fix | `opus` | `medium` |
| Ревʼю Wave 0 і груп хвиль | `sonnet` | `high` |
| Ревʼю всієї гілки, fallback `Explore` | `sonnet` | `xhigh` |

Advisor (`--advisor opus`) необовʼязковий, і Pasadena від нього не залежить: його типові моменти вже закривають затвердження плану, `leslie` і ревʼю всієї гілки. Субагенти його успадковують, тому Opus-субагент з Opus-advisor двічі платить за ту саму перевірку.

## Делегування в Codex

Якщо Codex CLI встановлено і в ньому виконано вхід, skills віддають частину роботи в `codex exec`, щоб заощадити ліміти Claude. Claude лишається оркестратором і сам перевіряє кожен результат. Codex тут виконавець, а не хост плагіна.

Кожен виклик `codex.sh` задає власний `model_reasoning_effort`. Модель береться з `~/.codex/config.toml`, якщо її не задає одна зі змінних нижче.

| Виклик | Claude-роль | Effort |
|---|---|---|
| `explore` | `Explore` | `medium` |
| `review` | рецензія хвилі | `high` |
| `red` | test writer | `xhigh` |
| `green … routine` | implementer `routine`-задачі | `high` |
| `green … complex` | implementer `complex`-задачі | `xhigh` |

- **explore** — `leonard`, `leslie`, `sheldon` і `wolowitz` віддають Codex об'ємні read-only пошуки й отримують факти з `file:line`.
- **review** — `wolowitz` запускає одне Codex-ревʼю всієї гілки у фіналі, поруч із ревʼюером `sonnet`; зараховуються лише знахідки, які підтвердив Claude.
- **implement** — задачі плану з `**Executor:** codex` Codex пише у два виклики: спершу тести, потім код, а Claude між ними сам запускає тести.

### Режими

`/codex-mode` показує поточний режим; `/codex-mode explore|full|auto` задає глобальний, він зберігається в `pasadena/codex-mode` у `${XDG_STATE_HOME:-~/.local/state}`; `/codex-mode explore|full --branch` задає режим поточної гілки рядком `codex-mode:` у журналі, і на цій гілці він має перевагу. Digest на старті сесії називає чинний режим.

| Режим | Читання | Реалізація | Фінальне ревʼю |
|---|---|---|---|
| `explore` (типовий) | Codex | Codex лише для задач з `**Executor:** codex` | Claude `sonnet` + Codex |
| `full` | Codex | Codex для кожної задачі, крім Task 0, і для bounded-правок, у межах лімітів | лише Claude |
| `auto` | — | обирає `sheldon`: spike → `explore`, bounded → `full`, architectural з concurrency, збереженим станом, security чи спільним інтерфейсом → `explore`, інші architectural → питає | — |

У `full` команда `bash hooks/codex.sh budget` читає залишок 5-годинного і тижневого лімітів із власних session-файлів Codex у `${CODEX_HOME:-~/.codex}/sessions`. `leonard` віддає Codex стільки задач, скільки вміщається в тижневий ліміт мінус 10% резерву, і показує розподіл рядком `Codex budget:` у плані; `wolowitz` перевіряє ще раз перед кожною Codex-задачею і віддає решту Claude, коли ліміту бракує. Вартість задачі визначається з того, наскільки зрушив тижневий ліміт: історія лежить у `pasadena/codex-cost.tsv` у теці стану, а оцінка — медіана останніх десяти задач (3% routine, 6% complex, поки історії немає).

Поки Codex працює, `hooks/codex.sh` дописує стислий лог сесії в `pasadena/codex.log` у `${XDG_STATE_HOME:-~/.local/state}`: заголовок `== ` на кожен виклик, далі по рядку `codex › ` на кожну команду, ненульовий код виходу, зміну файлів, підсумок міркувань, повідомлення чи помилку, обрізаний до 200 символів. Стежити за ним можна через `tail -f`. Лог не потрапляє у вивід скрипта, тож Claude читає лише фінальну відповідь у stdout і рядки `codex usage:`, `codex changed:` та помилки в stderr. Коли лог перевищує 1 МБ, він переїжджає в `codex.log.1`. У ньому є команди, які запускав Codex, і його повідомлення, тому файл створюється з доступом лише для вас.

| Змінна | За замовчуванням | Дія |
|---|---|---|
| `PASADENA_CODEX` | `1` | `0` вимикає делегування |
| `PASADENA_CODEX_IDLE` | `120` | секунд без подій від Codex, після яких виклик зупиняється |
| `PASADENA_CODEX_CMD_IDLE` | `600` | той самий ліміт, поки Codex виконує команду |
| `PASADENA_CODEX_MODEL` | — | передається в Codex як `-m` |
| `PASADENA_CODEX_MODEL_COMPLEX` | `PASADENA_CODEX_MODEL` | модель для `red` і `complex` `green`, аналог `opus` |
| `PASADENA_CODEX_MODEL_ROUTINE` | `PASADENA_CODEX_MODEL` | модель для `routine` `green`, аналог `sonnet` |
| `PASADENA_CODEX_LOG` | `pasadena/codex.log` у каталозі стану | куди пишеться лог сесії |

Codex витрачає ліміти вашого ChatGPT-плану. Коли вони закінчуються, `hooks/codex.sh` завершується з кодом `75`, skills один раз про це кажуть, і делегування вимикається на шість годин або доки ви не видалите `pasadena/codex-exhausted` у `${XDG_STATE_HOME:-~/.local/state}`.

## Бенчмарки

`bench/` вимірює, чи змінює робочий процес Pasadena результат на реальних задачах з історії цього репозиторію. Кожен прогін запускає headless-сесію `claude -p` у тимчасовому дереві на коміті, що додав специфікацію, а потім оцінює результат тестами з PR, який її реалізував. Комірка `baseline` виконує ту саму задачу з вимкненими `pasadena@pasadena` і `pasadena@synced`. Результати лежать поза git у `BENCH_DIR` (`${XDG_STATE_HOME:-~/.local/state}/pasadena/bench`): `runs.jsonl`, `calibration.log` і `reports/`. Кожен прогін обмежують `BENCH_BUDGET` (USD, за замовчуванням 15) і `BENCH_TIMEOUT` (секунди, за замовчуванням 5400), але він працює з `bypassPermissions`, тож агент може робити будь-що від вашого імені; запускайте його лише на машині, де ви на це згодні. Пілот іде етапами: після кожного `bench/report.sh` пише звіт із прогнозом вартості наступного етапу, і нічого далі не стартує, доки ви не погодите.

```bash
bash bench/calibrate.sh
bash bench/matrix.sh --tasks model-routing --reps 1
bash bench/report.sh --next "--reps 3" --out "$BENCH_DIR/reports/02-one-task.md"
```

## Перевірки

```bash
bash skills/skills.test.sh
bash hooks/journal.test.sh
bash proto/server.test.sh
bash hooks/nudge.test.sh
bash hooks/reuse.test.sh
bash hooks/codex.test.sh
bash bench/bench.test.sh
```

Перша перевіряє frontmatter скілів, рядки в README, атрибуцію сторонніх джерел і версії маніфестів. Друга створює тимчасові Git-репозиторії та покриває визначення гілки, контекст продовження, коміти, паузи й формат журналу. Третя перевіряє автентифікацію сервера, захист від обходу каталогу, події, опитування та зупинку. Четверта перевіряє промпти про баги й фічі, випадки мовчання та реєстрацію хука. Перевірки reuse запускають `hooks/reuse.sh` з фейковим `te` і покривають правило, підказку, карту й фільтр субагентів, таймаут, випадки мовчання та реєстрацію хука. Перевірки Codex запускають `hooks/codex.sh` з фейковим `codex` і покривають доступність, прапорці кожної підкоманди, лог сесії, зупинку за простоєм і маркер вичерпаного ліміту. Перевірки bench запускають `bench/` з фейковими `claude` і `codex` та покривають вердикти, оцінювання, калібрування, відновлення матриці й звіт.

Специфікації та плани кожної зміни лежать у [docs/sdd/specs](docs/sdd/specs) і [docs/sdd/plans](docs/sdd/plans).

## Ліцензія

Pasadena ліцензований під MIT. Модифіковані частини `proto/server.cjs` і `proto/frame.css` походять з obra/superpowers; дивіться [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md).
