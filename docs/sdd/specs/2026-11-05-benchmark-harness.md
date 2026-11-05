# Benchmark harness — design

**Date:** 2026-11-05
**Status:** agreed

## 1. Problem

Pasadena не має жодного виміру того, чи вона покращує роботу агента. Наявні
`hooks/*.test.sh` і `skills/skills.test.sh` детерміновано перевіряють, що хуки
й маніфести не зламані, але не відповідають на питання «чи краще з плагіном,
ніж без нього». Заяви README — економія Claude usage через Codex
(`codex-mode`), reuse-first (`PASADENA_REUSE`), маршрутизація моделей у
frontmatter, швидший review — нічим не підтверджені. Єдині сліди виміру —
`codex-cost.tsv` і `codex.log` під станом плагіна, і вони стосуються лише
Codex.

Наслідок: кожен новий етап конвеєра (хук, субагент, reviewer) додається без
доказу виграшу, хоча стаття DOU 62922 («Як оцінити RAG-систему», частина 2)
показує, що додатковий етап може спрацювати на відібраних проблемних випадках
і погіршити результат на ширшій вибірці (реранкер: 59→57 і 53→51 із 69).

## 2. Constraint that shapes the solution

Оцінка має бути **детермінованою і дешевою в розмітці**, а прогони —
**контрольованими за одним перемикачем**. Тому:

- Задачі беремо з власної історії: 7 spec, кожна з PR, де лежать тести,
  написані під цю spec. Ці тести — оракул; ручна чи LLM-розмітка не потрібна.
- Спостереження за реальними сесіями (дешевша альтернатива) відкинуто: задачі
  різні, перемикачі не контрольовані, тож причину різниці не встановити.
- Кожна plugin-комірка відрізняється від `plugin` рівно однією зміною —
  правило «одна зміна за раз» зі статті.
- Оракул, що не відрізняє `base` від готової реалізації, нічого не вимірює,
  тому кожна задача проходить калібрування до першого прогону.

## 3. Solution

Каталог `bench/` у корені репозиторію. Bash, як решта тестів репозиторію;
`jq` для JSON.

`BENCH_DIR=${BENCH_DIR:-${XDG_STATE_HOME:-~/.local/state}/pasadena/bench}` —
усі результати поза git. `BENCH_PLUGIN` за замовчуванням — корінь репозиторію,
з якого запущено `bench/` (поточна версія плагіна).

### 3.1 `bench/tasks.tsv`

Табуляція, заголовок у першому рядку. Поля: `id`, `base`, `spec`, `oracle`,
`tests`, `holdout`.

- `base` — коміт, що додав spec (spec уже в дереві, реалізації ще немає).
- `oracle` — кінчик гілки PR (другий батько merge-коміту на `main`); з нього
  беруться тестові файли.
- `tests` — шляхи тестових файлів через кому; кожен запускається `bash <path>`.

| id | base | spec | oracle | tests | holdout |
|---|---|---|---|---|---|
| testing-skills | 8b98483 | docs/sdd/specs/2026-10-21-testing-skills.md | 4ade52f | hooks/nudge.test.sh,skills/skills.test.sh | 0 |
| codex-exec | fb50e05 | docs/sdd/specs/2026-10-23-codex-exec-delegation.md | 3f598a7 | hooks/codex.test.sh,skills/skills.test.sh | 0 |
| model-routing | 4ab6c1c | docs/sdd/specs/2026-11-01-skill-model-routing.md | d97c752 | skills/skills.test.sh | 0 |
| frontmatter-models | ab745d2 | docs/sdd/specs/2026-11-02-skill-frontmatter-models.md | 0ce2564 | skills/skills.test.sh | 0 |
| faster-review | 1fd091f | docs/sdd/specs/2026-11-02-faster-review.md | f4e6979 | skills/skills.test.sh | 0 |
| codex-mode | 5818fd3 | docs/sdd/specs/2026-11-03-codex-mode.md | 93daf54 | hooks/codex.test.sh,hooks/journal.test.sh,skills/skills.test.sh | 0 |
| reuse-first | 5035f55 | docs/sdd/specs/2026-11-03-reuse-first.md | 74bf39c | hooks/reuse.test.sh,skills/skills.test.sh | 1 |

Холдаут не запускають, поки налаштовуються конфігурації й промпти; лише у
фінальному прогоні.

### 3.2 `bench/calibrate.sh`

Для кожної задачі в ізольованому дереві (§3.4, крок 1–2):

1. на `oracle` кожен файл з `tests` має вийти з 0;
2. на `base` з тестами з `oracle` хоча б один файл має вийти ненулем.

Тестовий файл, що падає на `oracle`, прибирається з `tests` у `tasks.tsv`.
Задача, у якої після цього не лишилось тестів або яка проходить на `base`,
отримує `holdout=x` (виключена) і причину в `$BENCH_DIR/calibration.log`.
Якщо виключено холдаут, холдаутом стає остання за датою задача з `holdout=0`.
`run.sh` і `matrix.sh` пропускають задачі з `holdout=x`. Калібрування
виконується один раз перед пілотом і повторно лише після зміни `tasks.tsv`;
його зміни до `tasks.tsv` комітяться.

### 3.3 `bench/configs.tsv`

Поля: `name`, `mode`, `prompt`, `env`, `codex_mode`, `model`.

- `mode`:
  - `off` — Pasadena вимкнена: `--settings '{"enabledPlugins":{"pasadena@pasadena":false}}'`;
  - `plugin` — та сама вимкнена встановлена копія плюс
    `--plugin-dir "$BENCH_PLUGIN"`.
  Решта плагінів і глобальні інструкції користувача однакові в усіх комірках.
  `--bare` не використовується: він приймає лише `ANTHROPIC_API_KEY` і не
  читає OAuth, тож не працює з підпискою.
- `prompt`: `plain` або `workflow` (тексти в §3.4).
- `env`: пари `KEY=VALUE` через пробіл або `-`.
- `codex_mode`: `explore`, `full` або `-` (не записувати).
- `model`: значення для `--model`.

| name | mode | prompt | env | codex_mode | model |
|---|---|---|---|---|---|
| baseline | off | plain | - | - | sonnet |
| plugin | plugin | workflow | PASADENA_CODEX=0 | explore | sonnet |
| plugin-noreuse | plugin | workflow | PASADENA_CODEX=0 PASADENA_REUSE=0 | explore | sonnet |
| plugin-codexfull | plugin | workflow | - | full | sonnet |
| plugin-haiku | plugin | workflow | PASADENA_CODEX=0 | explore | haiku |

Codex вимкнений у всіх plugin-комірках, крім `plugin-codexfull`, щоб
доступність і ліміт Codex не були неконтрольованим фактором. Тому
`plugin-codexfull` порівнює «Codex full» із «без Codex».

Кожен прогін отримує власний `XDG_STATE_HOME=<run>/state`, щоб глобальний стан
користувача (режим Codex, `codex-exhausted`, історія вартості) не впливав на
результат і не змінювався. `codex_mode` записується у
`<run>/state/pasadena/codex-mode`, звідки його читає `hooks/codex.sh`.
Для комірки з `codex_mode=full` `run.sh` спершу викликає
`bash "$BENCH_PLUGIN/hooks/codex.sh" available`; ненульовий вихід дає
`verdict: error`, `error: "codex unavailable"` без запуску `claude`.

`plugin-haiku`: модель сесії — Haiku; задачі, які скіли маршрутизують
через frontmatter на інші моделі, лишаються як є. Це вимірює «дешевша модель
оркестратора», а не перепис frontmatter.

### 3.4 `bench/run.sh <task-id> <config-name> <rep>`

`<run> = $BENCH_DIR/runs/<plugin_rev>/<task>/<config>/<rep>`, де
`plugin_rev` — `git -C "$BENCH_PLUGIN" rev-parse --short HEAD` з суфіксом
`-dirty`, якщо робоче дерево плагіна має незакомічені зміни.

1. Читає рядки з `tasks.tsv` і `configs.tsv`; невідомий id — exit 2.
2. Ізоляція історії: `git archive <base>` розпаковується в `<run>/tree`, там
   `git init` і один коміт `bench: base` від імені `bench <bench@localhost>`.
   Агент не бачить ні історії, ні гілок, ні готових реалізацій.
3. Запускає в `<run>/tree` з `timeout "$BENCH_TIMEOUT"`:

   ```
   claude -p "<prompt>" --output-format stream-json --verbose \
     --no-session-persistence --permission-mode bypassPermissions \
     --max-budget-usd "$BENCH_BUDGET" --model <model> \
     --settings '{"enabledPlugins":{"pasadena@pasadena":false}}' \
     [--plugin-dir "$BENCH_PLUGIN"]
   ```

   `BENCH_BUDGET` за замовчуванням `15`, `BENCH_TIMEOUT` — `5400` секунд;
   однакові для всіх комірок. Промпти:

   - `plain`: «Implement the specification at `<spec>`. Work autonomously:
     do not ask questions, make reasonable decisions. Do not push or open
     pull requests. Commit your work.»
   - `workflow`: «/pasadena:leonard Plan the implementation of the agreed
     specification at `<spec>`, then implement the plan with
     /pasadena:wolowitz. Work autonomously: do not ask questions, take the
     recommended option at every decision point, treat the spec and plan as
     approved. Do not push or open pull requests. Commit your work.»

   Stdout (JSON-рядки подій) — у `<run>/claude.jsonl`, stderr — у
   `<run>/claude.err`, код виходу — у `<run>/claude.exit`.
4. До і після кроку 3 для `plugin-codexfull` зберігає
   `bash "$BENCH_PLUGIN/hooks/codex.sh" budget` у `<run>/codex-before.txt` і
   `<run>/codex-after.txt`.
5. `git diff <base-commit>` у `<run>/tree` разом із незакоміченим →
   `<run>/diff.patch`.
6. Тестові файли з `oracle` беруться з репозиторію `bench/`
   (`git -C <repo> show <oracle>:<path>`) і кладуться поверх `<run>/tree`.
   Кожен запускається, вивід — у `<run>/oracle-<n>.log`, коди — у
   `<run>/oracle.exit`. Оракул запускається завжди, зокрема після тайм-ауту чи
   вичерпаного бюджету.
7. Викликає `score.sh <run>`, дописує результат одним рядком у
   `$BENCH_DIR/runs.jsonl`.
8. Видаляє `<run>/tree`. Решта артефактів у `<run>/` лишається.

### 3.5 `bench/score.sh <run-dir>`

Будує JSON-рядок лише зі збережених файлів `<run>/`; генерації немає, тож його
можна перезапустити після зміни правил оцінки. Поля:

- `task`, `config`, `rep`, `model`, `plugin_rev`, `ts`;
- `capped` — `true`, якщо `claude` зупинився через тайм-аут або
  `--max-budget-usd`;
- `verdict`, за пріоритетом:
  - `error` — `claude` не стартував, у `claude.jsonl` немає подій, або набір
    плагінів з init-події не відповідає комірці (Pasadena є в `off`, відсутня
    в `plugin`, або завантажена не з `BENCH_PLUGIN`);
  - `refused` — `diff.patch` порожній;
  - `pass` — усі тестові файли вийшли з 0;
  - `partial` — частина вийшла з 0;
  - `fail` — жоден.
  Обірвані прогони (`capped: true`) оцінюються за деревом, як решта; `capped`
  показує, що робота не завершена.
- `tests_passed`, `tests_total`;
- `input_tokens`, `cache_read`, `cache_write`, `output_tokens`, `cost_usd`,
  `duration_s`, `num_turns` — з події `result`; для обірваного прогону без неї
  `cost_usd = BENCH_BUDGET` при зупинці бюджетом і `null` при тайм-ауті;
  `cost_source: "cli-estimate"`;
- `plugins` — імена й шляхи плагінів з події `type: "system", subtype: "init"`;
- `subagent_calls` — кількість викликів інструмента `Agent` (або `Task`) у
  подіях `assistant`;
- `diff_files`, `diff_lines` — з `diff.patch`;
- `dup_symbols` — кількість функцій (`name()` у `.sh`, `function name` у
  `.js`/`.cjs`), доданих у диффі, ім'я яких уже існувало на `base`;
- `codex_usage` — різниця тижневого ліміту між `codex-before.txt` і
  `codex-after.txt`, або `null`;
- `error` — причина для `verdict: error` (наприклад `"plugin mismatch"`,
  `"codex unavailable"`), інакше `"timeout"` / `"budget"` для обірваних, інакше
  перший рядок `claude.err` або `null`.

Назви полів подій `stream-json` (`usage.*`, `total_cost_usd`, `duration_ms`,
плагіни в init, `subtype` при зупинці бюджетом) звіряються з реальним виводом
у сухому прогоні до написання `score.sh`; фейковий `claude` у тестах
відтворює саме звірений формат.

### 3.6 `bench/matrix.sh [--tasks a,b] [--configs x,y] [--reps N] [--holdout] [--retry-errors]`

Перебирає задачі × комірки × повтори (за замовчуванням: усі задачі з
`holdout=0`, усі комірки, `N=3`). З `--holdout` запускаються лише задачі з
`holdout=1`. Ключ виконаного прогону — `(plugin_rev, task, config, rep)`: зміна
плагіна автоматично дає нову серію, а перерваний запуск продовжується.
Рядки з `verdict: error` вважаються виконаними; `--retry-errors` перезапускає
їх і замінює рядок. Прогони послідовні, тож знімки Codex-ліміту не
перетинаються.

### 3.7 `bench/report.sh [--rev <plugin_rev>] [--tasks a,b] [--configs x,y] [--next "<matrix args>"] [--out <file>]`

З `runs.jsonl` (за замовчуванням — найновіший `plugin_rev`, плюс рядки
`baseline` будь-якої ревізії, бо вони від плагіна не залежать; `--tasks` і
`--configs` звужують вибірку так само, як у `matrix.sh`) друкує markdown у
чотирьох розділах:

1. **Комірки** — таблиця на комірку:
   - кількість прогонів і частки `pass` / `partial` / `fail` / `refused` /
     `error`, частка `capped`;
   - середні й p95 `cost_usd` та `duration_s`, середні `output_tokens`,
     `subagent_calls` і `dup_symbols`, сума `codex_usage`.

   Під таблицею — різниця кількості `pass` кожної комірки від `plugin` і
   позначка `noise`, коли різниця не перевищує 3 прогонів, та нагадування про
   упередження з §5.
2. **Прогони** — рядок на прогін: `task`, `config`, `rep`, `verdict`, `capped`,
   `cost_usd`, `duration_s`, `num_turns`, `subagent_calls`, `diff_lines`,
   `error`, назви тестів оракула, що впали, і шлях `<run>`, щоб відкрити
   `claude.jsonl` і `diff.patch` конкретного прогону.
3. **Витрати** — сума `cost_usd` і `duration_s` вибірки та всього
   `runs.jsonl`.
4. **Прогноз** (лише з `--next`) — кількість прогонів, яку `matrix.sh` з цими
   аргументами ще не виконав, помножена на середню й p95 `cost_usd` і
   `duration_s` вибірки по кожній комірці; для комірки без прогонів —
   `BENCH_BUDGET` і `BENCH_TIMEOUT` як верхня межа.

`--out` додатково пише звіт у файл.

### 3.8 Етапи пілота і ворота

Пілот запускається етапами. Після кожного етапу агент запускає
`report.sh --tasks … --configs … --next "<аргументи наступного етапу>" --out
$BENCH_DIR/reports/<NN>-<етап>-<plugin_rev>.md`, публікує звіт коментарем у
PR, додає свої висновки (що здивувало, які прогони варто відкрити, чи є
`error`, які треба перезапустити) і **зупиняється**. Наступний етап
починається лише після явного погодження користувача; користувач може змінити
його склад, і тоді `--next` перераховується.

| # | Етап | Команда | Прогонів |
|---|---|---|---|
| 0 | Калібрування | `bench/calibrate.sh` | 0 |
| 1 | Сухі прогони | `run.sh model-routing plugin 1`, `run.sh model-routing baseline 1` | 2 |
| 2 | Одна задача, усі комірки | `matrix.sh --tasks model-routing --reps 1` | +3 |
| 3 | Одна задача, повтори | `matrix.sh --tasks model-routing --reps 3` | +10 |
| 4 | Усі задачі налаштування | `matrix.sh --reps 3` | до +75 |
| 5 | Холдаут | `matrix.sh --holdout --reps 3` | до 15 |

Звіт етапу 0 — це `calibration.log` (які тести прибрано, які задачі
виключено й чому, куди перенесено холдаут) замість `report.sh`. Етап 5
запускається один раз і лише після того, як висновки етапу 4 записано в
журнал: холдаут перевіряє їх, а не підказує.

Зміна плагіна між етапами дає новий `plugin_rev`; тоді звіт порівнює лише
прогони поточної ревізії, а агент у висновках каже, які етапи треба
повторити.

### 3.9 `bench/bench.test.sh`

У стилі `hooks/codex.test.sh`: тимчасовий git-репозиторій з комітами `base` і
`oracle`, фейковий `claude` і `codex` у `PATH`. Фейковий `claude` пише заданий
`stream-json` і (або не) змінює файли. Перевіряє:

- кожен `verdict` і пріоритет між ними, `capped` для тайм-ауту й бюджету, і що
  оракул запускається після обриву;
- поля токенів, вартості, `plugins` і `subagent_calls` з `claude.jsonl`;
- `verdict: error` при невідповідності плагінів комірці;
- `dup_symbols`;
- що дерево прогону не має історії, крім одного коміту;
- що `--settings`, `--plugin-dir`, `--model`, промпт `plain` / `workflow` і
  `env` передаються згідно з комірками;
- що кожен прогін має власний `XDG_STATE_HOME`, а `codex-mode` там містить
  значення з `codex_mode`;
- що `codex_mode=full` при недоступному Codex дає `error` без виклику `claude`;
- `calibrate.sh`: прибирання тесту, що падає на `oracle`, виключення задачі,
  що проходить на `base`, і перенесення холдауту;
- пропуск виконаних прогонів за ключем з `plugin_rev`, `--holdout`,
  `--retry-errors`;
- що `score.sh`, запущений повторно, дає той самий рядок;
- агрегати, фільтри ревізії, `--tasks` і `--configs`, позначку `noise`,
  таблицю прогонів з тестами оракула, що впали, суму витрат, прогноз `--next`
  (зокрема верхню межу для комірки без прогонів) і `--out` у `report.sh`;
- що дерево прогону видаляється.

README отримує розділ «Benchmarks» з командами `bench/calibrate.sh`,
`bench/matrix.sh` і `bench/report.sh` і рядок `bash bench/bench.test.sh` у
списку тестів. Версія плагіна в `.claude-plugin/plugin.json` і
`marketplace.json` піднімається на мінорну.

## 4. Out of scope

Розмітка пояснень агента, LLM-оцінювач, зовнішні датасети, дашборд,
CI-інтеграція, паралельні прогони, порівняння з іншими агентами, переведення
Codex-ліміту в USD, перепис frontmatter для комірки Haiku, комірка з
нейтральним промптом для плагіна.

## 5. Trade-offs accepted

- 6 задач на налаштування і 1 холдаут (менше, якщо калібрування виключить
  частину): пілот показує напрям, а не доводить ефект. Різниця до 3 прогонів
  позначається `noise`.
- Оракул — тести з PR, які могли бути дописані під конкретну реалізацію, і
  `skills.test.sh` із точними рядками README та версіями. Слушна реалізація
  може частково не пройти їх. Упередженість однакова для всіх комірок, тож
  порівняння лишається чесним, а абсолютний pass-rate — ні.
- `baseline` і plugin-комірки мають різні промпти: без цього plugin-комірки
  виміряли б лише пасивні хуки. Різниця `baseline` → `plugin` — це «Claude
  Code» проти «Pasadena-workflow», а не внесок окремого хука. Внески окремих
  перемикачів дають лише порівняння plugin-комірок між собою.
- Інші плагіни, хуки й глобальні інструкції користувача активні в усіх
  комірках. Базова лінія — «Claude Code цього користувача без Pasadena», а не
  чистий Claude Code. Зате прогони працюють на підписці.
- Плагін під тестом — поточна версія, а задачі — історичні. Частина задач
  будувала функції, які вже є в поточному плагіні, тож агент із плагіном має
  «підказку з майбутнього» у вигляді поведінки скілів. Це упереджує результат
  на користь `plugin`; звіт це згадує.
- `bypassPermissions` у тимчасовому дереві: агент може виконувати будь-що
  від імені користувача. Прийнятно лише для локального запуску на машині
  автора; `BENCH_BUDGET` і `BENCH_TIMEOUT` обмежують витрати, але не доступ.
- Повний пілот — 6 задач × 5 комірок × 3 повтори = 90 прогонів до `$15`
  кожен, у найгіршому разі $1350. Етапи з §3.8 і зупинка на погодження після
  кожного обмежують ризик: до етапу 4 витрачається не більше 15 прогонів, а
  прогноз у звіті показує вартість наступного етапу до його запуску. Ціна —
  пілот триває стільки, скільки відповідає користувач.

## 6. Verification

- `bash bench/bench.test.sh` проходить.
- Сухий прогін `bench/run.sh model-routing plugin 1`: у `runs.jsonl` рядок з
  ненульовими `cost_usd`, `duration_s`, `output_tokens`, вердиктом і
  `plugins`, де Pasadena завантажена з `BENCH_PLUGIN`. Поля вартості
  звіряються з `<run>/claude.jsonl` вручну. Якщо `enabledPlugins:false` блокує
  й `--plugin-dir` або встановлена копія завантажується замість нього, робота
  зупиняється й питання повертається користувачу.
- Сухий прогін `bench/run.sh model-routing baseline 1`: `plugins` не містить
  Pasadena.
- `bench/calibrate.sh` завершується, `calibration.log` пояснює кожне
  виключення.
- `bench/report.sh --next "--tasks model-routing --reps 1"` після сухих
  прогонів друкує таблицю з рядками `baseline` і `plugin`, рядок на кожен
  прогін, суму витрат і прогноз на 3 прогони етапу 2.
- Після кожного етапу з §3.8 у `$BENCH_DIR/reports/` лежить його звіт, у PR —
  коментар з ним, і наступний етап не запускався без погодження.
