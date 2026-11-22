# Real benchmark: Pasadena проти baseline — design

**Date:** 2026-11-22
**Status:** agreed

## 1. Problem

Ми не знаємо, чи skills Pasadena покращують результат агента на реальних
задачах розробки. Єдине, що в нас є, це `skills/skills.test.sh`, а він перевіряє
лише структуру skills. Опубліковані бенчмарки, як-от Terminal-Bench і SWE-bench
Pro, міряють Claude Code без плагінів. Їхні числа отримано на інших версіях,
моделях і харнесах, тож напряму порівняти з ними не можна. Будь-яке рішення
про те, чи workflow вартий ціни, поки що спирається лише на враження.

## 2. Constraint that shapes the solution

Порівняння має сенс, лише коли обидва arm однакові в усьому, крім skills:
та сама модель, версія CLI, задачі, таймаути, кількість спроб і перевірка.
Тому опублікований baseline слугує тільки орієнтиром, а baseline ми міряємо
самі тим самим харнесом.

Готовий харнес для цього вже існує: Harbor. Це офіційний запускальник
Terminal-Bench. Він уже має агента `claude-code`, `--skill`, фільтр задач,
`-k` і `--jobs-dir`, підтримує `CLAUDE_CODE_OAUTH_TOKEN` (перевірено на
`harbor` 0.27.0). Власний харнес на Node означав би переписати ізоляцію в
Docker і верифікатори, тож від нього відмовились.

Друге обмеження стосується людини. Pasadena інтерактивна і спирається на
схвалення людини, а в бенчмарку людини немає. Arm pasadena працює з
явною політикою auto-approve і завжди обирає рекомендований варіант. Саме
цей режим ми й міряємо.

## 3. Solution

### 3.1 Glossary

- **arm**: конфігурація агента, `baseline` або `pasadena`.
- **trial**: одна спроба одного arm на одній задачі, reward `0` або `1`.
- **infra error**: trial, що завершився винятком середовища (збірка Docker,
  мережа, setup агента), а не відповіддю верифікатора.
- **hard set**: заморожений список задач у `bench/tasks.txt`.

### 3.2 Layout

```
package.json                  npm-скрипти, без залежностей
bench/
  config.json                 зафіксовані параметри запуску
  tasks.txt                   hard set, одна назва задачі на рядок
  run.sh                      arm → команда harbor run
  setup.sh                    venv із Harbor + перевірка автентифікації
  select.sh                   будує tasks.txt з baseline-прогону
  pasadena_agent.py           Harbor-агент: claude-code + плагін Pasadena
  compare.py                  jobs → bench/results/summary.md
  bench.test.sh               shell-тести на фікстурах
  fixtures/                   приклади result.json для тестів
  results/summary.md          останній звіт, коммітиться
  README.md                   як запускати
.bench/                       venv і jobs, у .gitignore
```

### 3.3 `bench/config.json`

```json
{
  "dataset": "terminal-bench@2.0",
  "model": "anthropic/claude-opus-5-5",
  "attempts": 3,
  "concurrency": 4,
  "agentTimeoutMultiplier": 1.0,
  "hardSetMax": 15,
  "retries": 2,
  "harborVersion": "0.27.0",
  "claudeCodeVersion": "2.1.330"
}
```

`claudeCodeVersion` передається обом arm через `--ak version=<v>`. Без нього
Harbor ставить `latest`, і версія CLI між прогонами непомітно розійшлася б.

Обидва arm читають той самий файл. Жоден параметр не можна задати окремо
для одного arm. Аргументи після `--` (наприклад, `-k`) перекривають значення
для обох arm однаково, бо їх передає той самий `run.sh`.

### 3.4 npm-скрипти

| скрипт | дія |
|---|---|
| `bench:setup` | `bench/setup.sh`: створює `.bench/venv`, ставить `harbor==<harborVersion>`, перевіряє Docker і наявність `ANTHROPIC_API_KEY` або `CLAUDE_CODE_OAUTH_TOKEN` (у середовищі або в `bench/.env`) |
| `bench:select` | `bench/select.sh`: baseline на всьому датасеті з `-k 1`, далі пише в `tasks.txt` задачі з reward `0`, не більше `hardSetMax`, за алфавітом |
| `bench:baseline` | `bench/run.sh --arm baseline` |
| `bench:pasadena` | `bench/run.sh --arm pasadena` |
| `bench:compare` | `bench/compare.py` → `bench/results/summary.md` |
| `bench` | `bench:baseline`, потім `bench:pasadena`, потім `bench:compare` |

Кожен скрипт без `bench:setup` спершу перевіряє, що `.bench/venv` існує, і
підказує `npm run bench:setup`, якщо його немає.

### 3.5 `bench/run.sh`

Будує одну команду:

```
.bench/venv/bin/harbor run -d <dataset> -m <model> -k <attempts>
  -n <concurrency> -r <retries> --agent-timeout-multiplier <m>
  --ak version=<claudeCodeVersion>
  -o .bench/jobs --job-name <kind>-<arm>-<hash>
  -i <task> ... (з tasks.txt)
  <arm-specific> <passthrough args>
```

- baseline: `-a claude-code`.
- pasadena: `--agent-import-path bench.pasadena_agent:PasadenaClaudeCode`.
- `<kind>` дорівнює `full`. `--task <name>` замінює весь список `-i` однією
  задачею і ставить `<kind>` = `smoke`. `select.sh` використовує
  `<kind>` = `select`.
- `<hash>` береться як перші 8 символів sha256 від `config.json`,
  `tasks.txt`, passthrough args, а для pasadena ще й від хешу вмісту
  завантажуваних тек плагіна (§3.6). Повторний запуск з тим самим входом
  продовжує job. Зміна skills, аргументів чи задач дає новий job, тож
  застарілі trial не підхоплюються. З `--fresh` до назви додається timestamp.
- Перед `harbor run` скрипт пише `.bench/jobs/<job>/bench-meta.json` з полями
  `arm`, `kind`, `hash`, `args`, `tasks`, `attempts`, `claudeCodeVersion`,
  `pluginContentHash` (pasadena), `gitSha` і `gitDirty`. Саме з цього файлу
  `compare.py` дізнається про походження job.
- `--dry-run` друкує команду і виходить з кодом `0`. Цей режим потрібен для
  тестів.
- Порожній `tasks.txt` дає вихід `1` з підказкою `npm run bench:select`.

### 3.6 `bench/pasadena_agent.py`

`PasadenaClaudeCode` є підкласом Harbor `ClaudeCode` і змінює три речі:

1. **Встановлення.** Після стандартного setup агента він завантажує в
   контейнер `/opt/pasadena` такі файли з кореня репозиторію:
   `.claude-plugin/`, `skills/`, `hooks/`, `commands/`, `proto/`. Потім
   виконує `claude plugin marketplace add /opt/pasadena` і
   `claude plugin install pasadena@pasadena`. Так встановлюються і skills, і
   hooks.
2. **Конфіг-тека.** Harbor під час `run()` примусово задає
   `CLAUDE_CONFIG_DIR=/logs/agent/sessions`. Тому встановлення з п. 1
   виконується з тим самим `CLAUDE_CONFIG_DIR`, інакше плагін під час
   запуску не видно. Перед інструкцією агент виконує `claude plugin list`.
   Якщо `pasadena` там немає, trial падає з помилкою агента. Тихого
   деградування до `--skill` немає: це моє рішення, бо деградований arm дав
   би хибний вердикт.
3. **Інструкція.** Текст задачі обгортається:

   ```
   /pasadena:pasadena <instruction задачі>

   No human is available during this run. Treat every approval gate as
   approved, answer every question with the recommended option, and carry
   the workflow through to a finished, verified result in this environment.
   Do not open pull requests or push.
   ```

Модель, effort, змінні середовища та таймаути успадковуються без змін.

**Pasadena міряється як є (моє рішення).** Frontmatter skills (`model:`,
`effort:`) і маршрутизація subagent у wolowitz лишаються без змін. Arm
pasadena може використовувати `sonnet`/`opus` alias поряд із `-m`. Це
частина того, що ми міряємо. `compare.py` показує розподіл токенів за
моделями для кожного arm, якщо Harbor його віддає.

**Робочий текст обгортки (моє рішення).** Текст вище є стартовим. План
містить цикл налаштування: щонайбільше 3 платні smoke-прогони на одній
задачі (`--task`). Дозволено правити текст обгортки й додати
`--append-system-prompt`. Smoke зараховується, коли trial пройшов перший
gate, тобто у транскрипті видно створену спеку або виклик `leonard`/`wolowitz`
і зміни в коді задачі. Якщо після 3 спроб workflow усе ще зупиняється на
gate, це фіксується як результат у `summary.md`, а повний прогін не
запускається без рішення користувача.

### 3.7 `bench/compare.py`

Бере для кожного arm найновіший job з `.bench/jobs/full-<arm>-*`. Job
`smoke-*` і `select-*` ігноруються. Читає `bench-meta.json` і trial-level
`result.json` (точні шляхи визначає план за реальним виводом Harbor 0.27).

Валідність пари (моє рішення):
- різні `tasks`, `attempts` чи `claudeCodeVersion` між arm дають вихід `1`
  з поясненням;
- `gitDirty: true` чи незавершений job (trial менше ніж `tasks × attempts`)
  дає попередження в шапці звіту, і звіт усе одно пишеться.
Пише в `bench/results/summary.md`:

- шапку з датою, `config.json`, версією Harbor, версією плагіна з
  `.claude-plugin/plugin.json` і кількістю задач;
- для кожного arm: pass rate за всіма trial з 95% інтервалом Wilson,
  середній pass@1 і pass@k по задачах, кількість infra error, токени й
  вартість (якщо Harbor їх віддає) та медіанний час trial;
- різницю pass rate (pasadena − baseline) і таблицю по задачах з колонками
  `задача | baseline x/k | pasadena x/k | Δ`, а також підсумок
  виграшів, програшів і нічиїх;
- один рядок вердикту: «різниця значуща», якщо інтервали Wilson не
  перетинаються, інакше «різниця в межах шуму при N=…».

Infra error — це trial, у якого Harbor ставить `reward_valid = false`
(`models/trial/error_policy.py`). Сюди входять і помилки API: rate-limit,
overloaded, usage-limit, connection. Timeout агента, ненульовий exit і
переповнення контексту мають валідний reward і рахуються як fail. Infra
error не входить у знаменник, його показано окремо по кожному arm. Якщо
кількість валідних trial у двох arm відрізняється більш ніж на 10%, у
вердикті з'являється попередження. Harbor сам повторює trial, що впали,
до `retries` разів. Якщо для arm немає job, вихід `1` з назвою скрипта,
який треба запустити.

### 3.8 Тести: `bench/bench.test.sh`

У стилі `hooks/*.test.sh`, без мережі та Docker:

- `run.sh --dry-run --arm baseline` і `--arm pasadena` друкують очікувані
  прапорці, одні й ті самі `-m`, `-k`, `-n` і `-i` для обох arm;
- той самий конфіг дає ту саму назву job, а змінений `tasks.txt` дає іншу;
- порожній `tasks.txt` завершується з кодом `1`;
- `--task x` дає рівно один `-i x` і назву `smoke-…`;
- зміна вмісту `skills/` змінює hash pasadena і не змінює hash baseline;
- `compare.py` ігнорує `smoke-*`/`select-*` і завершується з кодом `1` на парі
  з різними `tasks`;
- `compare.py` на `bench/fixtures/` дає очікувані pass rate, Wilson,
  лічильник infra error і таблицю Δ;
- `compare.py` без job завершується з кодом `1`.

Скрипт `bench:test` у `package.json` запускає `bench/bench.test.sh`.

## 4. Out of scope

SWE-bench Pro та інші датасети; інші моделі й порівняння кількох моделей;
запуск у CI або в хмарі (Daytona); відправка на лідерборд; UI чи дашборд;
змішані arm з окремими skills.

## 5. Trade-offs accepted

- **Вартість.** `bench:select` проходить усі ~89 задач, а потім кожен arm ще
  `15 × 3` trial. Це реальні токени. План оцінює вартість до першого
  запуску.
- **Auto-approve змінює Pasadena.** Ми міряємо workflow без людини, а не
  з живим рецензентом gate. Інший режим поза межами.
- **Однаковий таймаут.** Церемонія Pasadena може частіше впиратися в
  `agentTimeoutMultiplier: 1.0`. Цю ціну workflow ми й хочемо побачити, тому
  таймаут не послаблюємо для одного arm.
- **Малий N.** 15 задач × 3 спроби помітять лише великий ефект, і звіт
  чесно про це каже.
- **Різний набір моделей.** Pasadena може передавати частину роботи
  `sonnet` через свою маршрутизацію. Pass rate тоді частково залежить від
  моделі, тому звіт показує токени за моделями.
- **Python у Node-репо.** Harbor написаний на Python, тому npm лише
  викликає скрипти, а залежності живуть у `.bench/venv`.

## 6. Verification

1. `npm run bench:test` завершується з кодом `0`.
2. `npm run bench:setup` у чистому checkout створює `.bench/venv` з
   `harbor 0.27.0` і без токена виходить з кодом `1` та поясненням.
3. `npm run bench:pasadena -- --dry-run` друкує команду з
   `--agent-import-path bench.pasadena_agent:PasadenaClaudeCode` і тими самими
   `-m/-k/-n/-i`, що й `npm run bench:baseline -- --dry-run`.
4. Smoke: `npm run bench:pasadena -- --task <перша з tasks.txt> -k 1`. У
   логах trial видно, що `claude plugin list` показує `pasadena`, викликано
   `/pasadena:pasadena`, і workflow пройшов перший gate (§3.6).
5. Після `npm run bench` файл `bench/results/summary.md` містить обидва arm,
   таблицю Δ і рядок вердикту.
