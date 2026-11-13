# Benchmark harness — design

**Date:** 2026-11-05
**Status:** agreed
**Revised:** 2026-11-13 — після етапу 1: оракул як останній коміт фічі, спека
з оракула, оцінка за окремими вимогами, `bench_rev`, поле `ub_tools`.

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
- Тестовий файл — занадто грубий вимірювач: етап 1 показав, що
  `skills/skills.test.sh` падає в обох комірках через перевірки чужої фічі й
  дослівні рядки еталону, яких немає в спеці. Тому оцінка рахується за
  окремими перевірками, що відрізняють `base` від оракула, а перевірки, які
  неможливо пройти зі спеки, виключаються під час калібрування.

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
- `oracle` — останній коміт власної лінійної історії фічі: без злиттів з
  `main` і без наступної фічі в тій самій гілці. Кінчик PR не годиться:
  гілка `model-routing` продовжилась фічею upstream adoption, а
  `reuse-first` злив у себе codex-mode. З `oracle` беруться тестові файли і
  фінальний текст `spec`.
- `tests` — шляхи тестових файлів через кому; кожен запускається `bash <path>`.

| id | base | spec | oracle | tests | holdout |
|---|---|---|---|---|---|
| testing-skills | 8b98483 | docs/sdd/specs/2026-10-21-testing-skills.md | 4ade52f | hooks/nudge.test.sh,skills/skills.test.sh | 0 |
| codex-exec | fb50e05 | docs/sdd/specs/2026-10-23-codex-exec-delegation.md | 3f598a7 | hooks/codex.test.sh,skills/skills.test.sh | 0 |
| model-routing | 4ab6c1c | docs/sdd/specs/2026-11-01-skill-model-routing.md | fbdd4ae | skills/skills.test.sh | 0 |
| frontmatter-models | ab745d2 | docs/sdd/specs/2026-11-02-skill-frontmatter-models.md | 0ce2564 | skills/skills.test.sh | 0 |
| faster-review | 1fd091f | docs/sdd/specs/2026-11-02-faster-review.md | f4e6979 | skills/skills.test.sh | 0 |
| codex-mode | 5818fd3 | docs/sdd/specs/2026-11-03-codex-mode.md | 93daf54 | hooks/codex.test.sh,hooks/journal.test.sh,skills/skills.test.sh | 0 |
| reuse-first | 5035f55 | docs/sdd/specs/2026-11-03-reuse-first.md | 8c0f8f8 | hooks/reuse.test.sh,skills/skills.test.sh | 1 |

Холдаут не запускають, поки налаштовуються конфігурації й промпти; лише у
фінальному прогоні.

### 3.2 `bench/calibrate.sh`

Для кожної задачі в ізольованому дереві (§3.4, крок 1–2):

1. на `oracle` кожен файл з `tests` має вийти з 0;
2. на `base` з тестами з `oracle` хоча б один файл має вийти ненулем.

Тестовий файл, що падає на `oracle`, прибирається з `tests` у `tasks.tsv`.

Далі — цільові перевірки. Одиниця — окрема вимога, тобто рядок
`FAIL — <name>`: у `skills/skills.test.sh` рядки `ok  — …` друкуються лише
як підсумок цілої секції (`model routing checked` — коли пройшли всі 13
вимог секції), тож окрему вимогу видно тільки через її `FAIL`. Абсолютний
шлях дерева в `<name>` замінюється на `<tree>`. Тестовий файл **дійшов до
кінця**, коли його вивід містить підсумковий рядок `All checks passed.` або
`FAILED: <N>` (формат усіх `*.test.sh` репозиторію).

**Ціль** — `FAIL — <name>` з виводу `base`, якого немає у виводі `oracle`
(на `oracle` кожен файл з `tests` проходить, тож це всі `FAIL` з `base`).
Цілі пишуться в `bench/checks.tsv`:

| task | test | check | status | reason |
|---|---|---|---|---|

- `status` — `target` або `excluded`.
- **Фільтр дослівного:** літерали вимоги — підрядки в лапках `"…"` у `check`
  і значення рядків `expected substring: …` / `expected: …` одразу під
  `FAIL` (формат `assert_*` у `hooks/*.test.sh`). Якщо хоч одного літерала
  немає (`grep -F`) у `spec` з `oracle`, рядок отримує `excluded` і `reason`
  `literal not in spec: "<s>"`. Таку вимогу можна пройти, лише вгадавши
  формулювання еталону.
- **Ручні рішення:** рядки, чий `reason` починається з `manual:`, переживають
  повторне калібрування й мають пріоритет над автоматичними. Агент
  переглядає цілі без літералів після калібрування й виключає ту, яку
  неможливо виконати зі спеки (`manual: <чому>`); решта лишається `target`.

Задача, у якої не лишилось тестів або жодної цілі зі `status=target`,
отримує `holdout=x` (виключена) і причину в `$BENCH_DIR/calibration.log`;
туди ж іде кожен виключений рядок `checks.tsv` з причиною.
Якщо виключено холдаут, холдаутом стає остання за датою задача з `holdout=0`.
`run.sh` і `matrix.sh` пропускають задачі з `holdout=x`. Калібрування
виконується один раз перед пілотом і повторно лише після зміни `tasks.tsv`;
його зміни до `tasks.tsv` і `checks.tsv` комітяться. Дерево `base` для
калібрування будується так само, як у `run.sh` (§3.4, крок 2), зі `spec` з
`oracle`.

### 3.3 `bench/configs.tsv`

Поля: `name`, `mode`, `prompt`, `env`, `codex_mode`, `model`.

- `mode`:
  - `off` — Pasadena вимкнена: `--settings '{"enabledPlugins":{"pasadena@pasadena":false,"pasadena@synced":false}}'`;
  - `plugin` — та сама вимкнена встановлена копія плюс
    `--plugin-dir "$BENCH_PLUGIN"`.
  Встановлена копія завантажується з джерела `pasadena@synced`, тому
  вимикаються обидва ключі; сухий прогін показав, що з одним
  `pasadena@pasadena` Pasadena лишається в `off`.
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

Гейти dryer, crapper і mutator (spec `2026-11-13-ub-mode-quality-gates.md`)
активні в усіх plugin-комірках з інструментами, встановленими в
користувача. Комірку без них (`plugin-noub`: `PASADENA_<TOOL>` на
невиконуваний шлях) відкладено: інструменти аналізують Clojure, Java, Go,
TypeScript, Rust і Python, а всі 7 задач — bash і Markdown, тож комірка
виміряла б холості виклики. Вона повертається разом із першою задачею на
підтримуваній мові. Що бачив кожен прогін, фіксує `ub_tools` у `meta.json`
(§3.4).

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
2. Ізоляція історії: `git archive <base>` розпаковується в `<run>/tree`,
   `<spec>` перезаписується вмістом `git show <oracle>:<spec>` (фінальна
   погоджена версія з доповненнями, зробленими під час реалізації), там
   `git init` і один коміт `bench: base` від імені `bench <bench@localhost>`.
   Агент не бачить ні історії, ні гілок, ні готових реалізацій.
   У `<run>/meta.json` пишеться `ub_tools`: для `dryer`, `crapper` і
   `mutator` — вивід `bash "$BENCH_PLUGIN/hooks/ub-tools.sh" available <tool>`
   з env комірки (шлях або `<tool>: unavailable (<причина>)`). Підкоманда
   `available` додається в `hooks/ub-tools.sh` і перевикористовує його
   наявний пошук інструмента; без аргументів поведінка хука не змінюється.
3. Запускає в `<run>/tree` з `timeout "$BENCH_TIMEOUT"`:

   ```
   claude -p "<prompt>" --output-format stream-json --verbose \
     --no-session-persistence --permission-mode bypassPermissions \
     --max-budget-usd "$BENCH_BUDGET" --model <model> \
     --settings '{"enabledPlugins":{"pasadena@pasadena":false,"pasadena@synced":false}}' \
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
- `bench_rev` — перші 12 символів `sha256sum` вмісту `bench/tasks.tsv` і
  `bench/checks.tsv`: версія визначення задач і оцінки;
- `capped` — `true`, якщо `claude` зупинився через тайм-аут або
  `--max-budget-usd`;
- `verdict`, за пріоритетом:
  - `error` — `claude` не стартував, у `claude.jsonl` немає подій, або набір
    плагінів з init-події не відповідає комірці (Pasadena є в `off`, відсутня
    в `plugin`, або завантажена не з `BENCH_PLUGIN`);
  - `refused` — `diff.patch` порожній;
  - `pass` — пройдено всі цілі задачі;
  - `partial` — частину;
  - `fail` — жодної.
  Обірвані прогони (`capped: true`) оцінюються за деревом, як решта; `capped`
  показує, що робота не завершена.
- `checks_passed`, `checks_total`, `score` — цілі задачі зі `status=target` у
  `bench/checks.tsv`; ціль пройдена, коли лог її тестового файла
  (`oracle-<n>.log`, шлях дерева замінено на `<tree>`) дійшов до кінця
  (§3.2) і не містить `FAIL — <check>`. Файл, що не дійшов до кінця, не
  проходить жодної своєї цілі. `score = checks_passed / checks_total`, два знаки після
  коми. Зміна `checks.tsv` і повторний `score.sh` переоцінюють прогін без
  генерації;
- `tests_passed`, `tests_total` — довідково, за кодами виходу файлів;
- `input_tokens`, `cache_read`, `cache_write`, `output_tokens`, `cost_usd`,
  `duration_s`, `num_turns` — з події `result`; для обірваного прогону без неї
  `cost_usd = BENCH_BUDGET` при зупинці бюджетом і `null` при тайм-ауті;
  `cost_source: "cli-estimate"`. При зупинці бюджетом `usage` у `result`
  нульовий, тож токени тоді беруться сумою з `modelUsage.<model>`
  (`inputTokens`, `outputTokens`, `cacheReadInputTokens`,
  `cacheCreationInputTokens`);
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
`holdout=1`. Ключ виконаного прогону — `(plugin_rev, bench_rev, task, config,
rep)`: зміна плагіна, задач чи оцінки автоматично дає нову серію, а
перерваний запуск продовжується.
Рядки з `verdict: error` вважаються виконаними; `--retry-errors` перезапускає
їх і замінює рядок. Прогони послідовні, тож знімки Codex-ліміту не
перетинаються.

### 3.7 `bench/report.sh [--rev <plugin_rev>] [--tasks a,b] [--configs x,y] [--next "<matrix args>"] [--out <file>]`

З `runs.jsonl` (за замовчуванням — найновіший `plugin_rev`, плюс рядки
`baseline` будь-якої ревізії плагіна, бо вони від нього не залежать; усі
рядки — лише з поточним `bench_rev`, тож рядки старої оцінки, зокрема без
`checks_total`, у звіт не потрапляють; `--tasks` і
`--configs` звужують вибірку так само, як у `matrix.sh`) друкує markdown у
чотирьох розділах:

1. **Комірки** — таблиця на комірку:
   - кількість прогонів і частки `pass` / `partial` / `fail` / `refused` /
     `error`, частка `capped`;
   - середній `score`;
   - середні й p95 `cost_usd` та `duration_s`, середні `output_tokens`,
     `subagent_calls` і `dup_symbols`, сума `codex_usage`.

   Під таблицею — для кожної комірки різниця кількості `pass` від `plugin` і
   позначка `noise`, коли різниця не перевищує 3 прогонів; різниця
   середнього `score` від `plugin` з позначкою `noise`, коли в будь-якій з
   двох комірок менше 3 прогонів; нагадування про упередження з §5.
2. **Прогони** — рядок на прогін: `task`, `config`, `rep`, `verdict`,
   `checks` (`k/n`), `capped`, `cost_usd`, `duration_s`, `num_turns`,
   `subagent_calls`, `diff_lines`, `error` і шлях `<run>`, щоб відкрити
   `claude.jsonl`, `diff.patch` і логи оракула конкретного прогону.
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
виключено й чому, куди перенесено холдаут) і зведення `checks.tsv` (цілі й
виключені перевірки на задачу, ручні рішення) замість `report.sh`.

Ревізія 2026-11-13 змінює `tasks.tsv` і `plugin_rev`, тож етапи 0 і 1
повторюються; прогони етапу 1 на `d8450dd-dirty` у звіти не потрапляють. Етап 5
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
  що проходить на `base`, і перенесення холдауту; цілі в `checks.tsv`
  (зокрема перевірка, відсутня у виводі `base`), заміна шляху дерева на
  `<tree>`, фільтр дослівного, збереження й пріоритет `manual:`-рядка,
  виключення задачі без цілей;
- що `<spec>` у дереві прогону — версія з `oracle`;
- `checks_passed`, `checks_total`, `score` і `verdict` за цілями, зокрема
  переоцінка після зміни `checks.tsv`;
- поле `ub_tools` у `meta.json`, зокрема `unavailable` з env комірки;
- `bench_rev` у рядку і в ключі `matrix.sh`, відсіювання в `report.sh`
  рядків з іншим `bench_rev`;
- пропуск виконаних прогонів за ключем з `plugin_rev`, `--holdout`,
  `--retry-errors`;
- що `score.sh`, запущений повторно, дає той самий рядок;
- агрегати, середній `score`, фільтри ревізії, `--tasks` і `--configs`,
  обидві позначки `noise`, таблицю прогонів зі стовпцем `checks`, суму витрат, прогноз `--next`
  (зокрема верхню межу для комірки без прогонів) і `--out` у `report.sh`;
- що дерево прогону видаляється.

README отримує розділ «Benchmarks» з командами `bench/calibrate.sh`,
`bench/matrix.sh` і `bench/report.sh` і рядок `bash bench/bench.test.sh` у
списку тестів. `hooks/ub-tools.test.sh` перевіряє `available` для
знайденого, невиконуваного й невстановленого інструмента. Версія плагіна в
`.claude-plugin/plugin.json` і `marketplace.json` піднімається на мінорну
відносно `main` (0.24.0 → 0.25.0).

## 4. Out of scope

Розмітка пояснень агента, LLM-оцінювач, зовнішні датасети, дашборд,
CI-інтеграція, паралельні прогони, порівняння з іншими агентами, переведення
Codex-ліміту в USD, перепис frontmatter для комірки Haiku, комірка з
нейтральним промптом для плагіна, LLM-оцінка відповідності перевірок спеці,
переписування історичних спек під дослівні рядки тестів.

## 5. Trade-offs accepted

- 6 задач на налаштування і 1 холдаут (менше, якщо калібрування виключить
  частину): пілот показує напрям, а не доводить ефект. Різниця до 3 прогонів
  позначається `noise`.
- Оракул — тести з PR, дописані під конкретну реалізацію. Перевірки з
  дослівним рядком, якого немає в спеці, виключаються; лишаються перевірки
  без лапок, які оцінює лише ручний перегляд (`manual:`), і тому частина
  неможливих цілей може пропасти повз фільтр. Залишкова упередженість
  однакова для всіх комірок, тож порівняння `score` лишається чесним, а
  абсолютне значення — ні.
- Спека з `oracle` містить доповнення, зроблені вже під час реалізації
  (ухвали рев'ю тощо). Це більше, ніж мав автор на старті, але саме цей текст
  описує те, що перевіряє оракул.
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
  `--max-budget-usd` перевіряється після ходу, тож прогін може перевищити
  `BENCH_BUDGET` на вартість одного ходу (сухий прогін: $0.0063 при межі
  $0.0001).
- Повний пілот — 6 задач × 5 комірок × 3 повтори = 90 прогонів, холдаут —
  ще до 15. `BENCH_BUDGET` — запобіжник, а не гроші: прогони йдуть на
  підписці, а `--max-budget-usd` зупиняє сесію, коли оцінка CLI за
  API-цінами досягне межі, тож 90 × $15 = $1350 — стеля цієї оцінки.
  Реальне обмеження — ліміти підписки (5-годинне вікно й тиждень); прогін,
  що вперся в ліміт, дає `error` і перезапускається через `--retry-errors`.
  Сухий етап 1 (2026-11-13) дав $2.51 для `plugin` і $0.56 для `baseline`
  на `model-routing`. Етапи з §3.8 і зупинка на погодження після
  кожного обмежують ризик: до етапу 4 виконується не більше 15 прогонів, а
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
  виключення, `bench/checks.tsv` має хоча б одну ціль на кожну невиключену
  задачу, і кожна ціль без літералів має `manual:`-рішення або лишилась
  `target` після перегляду.
- На `model-routing` з оракулом `fbdd4ae` кінчик проходить усі цілі, а
  `base` — жодної.
- Причину рядка `Error: invalid value for one of the arguments` у
  stdout/stderr самого `run.sh` під час сухого прогону `baseline` (етап 1,
  2026-11-13; у `claude.err`, `claude.jsonl` і логах оракула його немає,
  `claude.exit=0`) знайдено на фейковому `claude` і усунено до повтору
  етапу 1.
- `bench/report.sh --next "--tasks model-routing --reps 1"` після сухих
  прогонів друкує таблицю з рядками `baseline` і `plugin`, рядок на кожен
  прогін, суму витрат і прогноз на 3 прогони етапу 2.
- Після кожного етапу з §3.8 у `$BENCH_DIR/reports/` лежить його звіт, у PR —
  коментар з ним, і наступний етап не запускався без погодження.
