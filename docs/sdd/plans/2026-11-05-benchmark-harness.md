# Benchmark harness — implementation plan

**Goal:** `bench/` у корені репозиторію: дані задач і комірок, `run.sh`, `score.sh`, `calibrate.sh`, `matrix.sh`, `report.sh` і `bench.test.sh` на фейкових `claude`/`codex`. Калібрування (етап 0 з §3.8) виконане на реальному репозиторії, звіт лежить у PR. Після цього робота зупиняється до погодження етапу 1.
**Spec:** docs/sdd/specs/2026-11-05-benchmark-harness.md
**Verification:** `bash bench/bench.test.sh && bash skills/skills.test.sh`; останній рядок обох — `All checks passed.`

## Context

Pasadena не має виміру того, чи покращує вона роботу агента (spec §1). Пілот відтворює 7 власних задач з історії, оцінює їх тестами з PR і порівнює комірку без плагіна з чотирма plugin-комірками, що відрізняються однією зміною. Користувач хоче звіт після кожного етапу пілота й погодження перед наступним (§3.8), тож збірка закінчується етапом 0, а етапи 1–5 запускаються окремо, кожен після «так».

## Global constraints

- Bash з `set -uo pipefail`, `jq` для JSON. Жодних коментарів, крім обмежень, яких код не показує.
- Змінні середовища, усі з дефолтами, задаються в `bench/lib.sh`:
  - `BENCH_ROOT` — каталог `bench/`;
  - `BENCH_REPO=${BENCH_REPO:-$(git -C "$BENCH_ROOT" rev-parse --show-toplevel)}` — звідки беруться `git archive` і `git show` (свідоме рішення: тестам потрібен підставний репозиторій);
  - `BENCH_PLUGIN=${BENCH_PLUGIN:-$BENCH_REPO}`;
  - `BENCH_DIR=${BENCH_DIR:-${XDG_STATE_HOME:-$HOME/.local/state}/pasadena/bench}`;
  - `BENCH_TASKS=${BENCH_TASKS:-$BENCH_ROOT/tasks.tsv}`, `BENCH_CONFIGS=${BENCH_CONFIGS:-$BENCH_ROOT/configs.tsv}`;
  - `BENCH_BUDGET=${BENCH_BUDGET:-15}`, `BENCH_TIMEOUT=${BENCH_TIMEOUT:-5400}`, `BENCH_ORACLE_TIMEOUT=${BENCH_ORACLE_TIMEOUT:-600}`;
  - `BENCH_RUN=${BENCH_RUN:-$BENCH_ROOT/run.sh}` (свідоме рішення: тест `matrix.sh` підставляє фейк).
- Невідомий id задачі чи комірки → stderr `unknown task: <id>` / `unknown config: <name>`, exit 2.
- Каталог прогону: `$BENCH_DIR/runs/<plugin_rev>/<task>/<config>/<rep>`. Результати: `$BENCH_DIR/runs.jsonl`, `$BENCH_DIR/calibration.log`, `$BENCH_DIR/reports/`.
- Промпти з §3.4 — дослівно (тексти нижче, у Task 3).
- Версія плагіна піднімається з `0.23.0` до `0.24.0` у `.claude-plugin/plugin.json`, `.claude-plugin/marketplace.json` і в перевірці `skills/skills.test.sh:257`.
- Тести — частини `bench/test/NN-<name>.sh`, які `bench/bench.test.sh` підключає через `source` у порядку сортування. Свідоме рішення: так паралельні задачі не пишуть в один файл, а команда запуску лишається одна, `bash bench/bench.test.sh`. Частини користуються helper-ами раннера (`assert_eq`, `assert_contains`, `fresh_bench`, `last_run`) і лічильником `fails`.
- Codex: `off` у дайджесті, режим `auto` → `explore`. Усі задачі виконує `claude`, рядка `Codex budget:` немає.

## Review Focus

1. Перезапуск того самого `(rev, task, config, rep)` поверх наявного `<run>/`: `run.sh` спершу видаляє каталог, інакше лишаються старі `oracle-*.log`.
2. Stdout `claude` з не-JSON рядками (попередження) не повинен валити `score.sh`: розбір через `jq -R 'fromjson? // empty'`.
3. Порівняння шляху плагіна з init-події з `BENCH_PLUGIN`: обидва через `realpath`, щоб завершальний `/` чи symlink не давали хибний `plugin mismatch`.
4. Тест оракула, чий каталог відсутній на `base`: перед `git show` потрібен `mkdir -p "$(dirname …)"`.
5. Вкладений `claude -p` усередині сесії Claude Code: якщо Task 0 покаже, що він відмовляється через успадковані `CLAUDECODE`/`CLAUDE_CODE_*`, `run.sh` запускає його з `env -u CLAUDECODE -u CLAUDE_CODE_ENTRYPOINT`.

## Waves

| Wave | Tasks | Why together |
|---|---|---|
| 0 | 0 | сам — сухий прогін формату й приймальні тести, червоні до хвилі 3 |
| 1 | 1, 2, 7 | різні файли: `bench/lib.sh`+дані, `bench/score.sh`, README+маніфести; score читає лише `meta.json`, контракт якого задано в тексті |
| 2 | 3, 4, 5 | різні файли: `run.sh`, `calibrate.sh`, `matrix.sh`; усі споживають `lib.sh` з Task 1, `run.sh` — ще й `score.sh` з Task 2 |
| 3 | 6 | сам — `report.sh --next` викликає `matrix.sh --pending` з Task 5 |
| 4 | 8 | сам — етап 0 на реальному репозиторії, переписує `bench/tasks.tsv` з Task 1, після нього зупинка |

Послідовно лишається: Task 6 після Task 5 (`--pending`) і Task 8 після всіх, бо пише `bench/tasks.tsv` і запускає готовий `calibrate.sh`.

---

### Task 0: сухий прогін формату й приймальні тести

**Writes:** `bench/bench.test.sh`, `bench/test/00-acceptance.sh`, `bench/fixtures/init.json`, `bench/fixtures/assistant.json`, `bench/fixtures/result-success.json`, `bench/fixtures/result-budget.json`
**Executor:** claude
**Covers:**
- «`bash bench/bench.test.sh` проходить.»
- «Сухий прогін `bench/run.sh model-routing plugin 1`: у `runs.jsonl` рядок з ненульовими `cost_usd`, `duration_s`, `output_tokens`, вердиктом і `plugins`, де Pasadena завантажена з `BENCH_PLUGIN`… Якщо `enabledPlugins:false` блокує й `--plugin-dir` або встановлена копія завантажується замість нього, робота зупиняється й питання повертається користувачу.»
- «Сухий прогін `bench/run.sh model-routing baseline 1`: `plugins` не містить Pasadena.»
- «`bench/calibrate.sh` завершується, `calibration.log` пояснює кожне виключення.»
- «`bench/report.sh --next "--tasks model-routing --reps 1"` після сухих прогонів друкує таблицю з рядками `baseline` і `plugin`, рядок на кожен прогін, суму витрат і прогноз на 3 прогони етапу 2.»
- «Після кожного етапу з §3.8 у `$BENCH_DIR/reports/` лежить його звіт…» (`--out`; PR-коментар і зупинка — у Task 8 та в етапах після збірки)

- [x] **Step 1: звірити формат stream-json на реальному `claude`** (≈ $0.05). У `d=$(mktemp -d)`: `git -C "$d" init -q`, потім з `cd "$d"` три виклики на `--model haiku`, кожен з `--output-format stream-json --verbose --no-session-persistence --settings '{"enabledPlugins":{"pasadena@pasadena":false,"pasadena@synced":false}}'`:
  - `claude -p "Reply with the word OK." --max-budget-usd 0.5 --plugin-dir <корінь worktree> > plugin.jsonl`
  - той самий без `--plugin-dir` `> off.jsonl`
  - `claude -p "Write a 300-word story." --max-budget-usd 0.0001 > budget.jsonl`

  Звірити й записати у звіт задачі:
  - init: `type:"system", subtype:"init"`, де лежить список плагінів (очікується `.plugins[] | {name, path}`);
  - result: `type:"result"`, `.total_cost_usd`, `.duration_ms`, `.num_turns`, `.usage.input_tokens`, `.usage.output_tokens`, `.usage.cache_read_input_tokens`, `.usage.cache_creation_input_tokens`;
  - `subtype` результату при зупинці бюджетом (очікується `error_max_budget_usd`).

  **Стоп-умова:** якщо в `plugin.jsonl` Pasadena відсутня або її шлях не корінь worktree, або в `off.jsonl` Pasadena є — не писати тести, повернути питання користувачу. Якщо вкладений `claude` відмовився стартувати, повторити з `env -u CLAUDECODE -u CLAUDE_CODE_ENTRYPOINT` і записати це. Будь-яку розбіжність назв з очікуваними оркестратор вносить у текст Task 2 до його запуску.
- [x] **Step 2: фікстури.** З реальних подій через `jq -c` зберегти по одному рядку, лишивши лише поля, які читає `score.sh`, і замінивши шляхи на `/fixture/...`:
  - `init.json` — `{type, subtype, plugins}`;
  - `assistant.json` — `{"type":"assistant","message":{"content":[{"type":"tool_use","name":"Agent","input":{}}]}}`;
  - `result-success.json`, `result-budget.json` — `{type, subtype, is_error, total_cost_usd, duration_ms, num_turns, usage, modelUsage}` з реальними значеннями (у `modelUsage` лишити лише поля токенів).
- [x] **Step 3: раннер `bench/bench.test.sh`.** Заголовок як у `hooks/codex.test.sh:1-30` (`assert_eq`, `assert_contains`, `fails`), підсумок як у `hooks/codex.test.sh` (`FAILED: N` / `All checks passed.`). Раннер готує:
  - `tmp=$(mktemp -d)`, `bin=$tmp/bin` на початку `PATH`;
  - **репозиторій задач** `$tmp/repo`: коміт `base` додає `spec.md` і `src/a.sh` з `helper() { :; }`; коміт `oracle` додає `t/one.test.sh` (`grep -qx done feature.txt`) і `t/two.test.sh` (`grep -qx done feature2.txt`), а також `feature.txt` і `feature2.txt` з `done`. Хеші — в `BASE`, `ORACLE`;
  - **`$tmp/tasks.tsv`:** заголовок `id base spec oracle tests holdout`, далі `t1 $BASE spec.md $ORACLE t/one.test.sh,t/two.test.sh 0` і `t2 $BASE spec.md $ORACLE t/one.test.sh 1`;
  - **плагін** `$tmp/plugin`: git-репозиторій з одним комітом і `hooks/codex.sh`, де `available` повертає `exit ${FAKE_CODEX_AVAILABLE:-0}`, а `budget` друкує `weekly_left=$((100-${FAKE_CODEX_USED:-10})) weekly_used=${FAKE_CODEX_USED:-10} five_hour_left=90 five_hour_reset=0`;
  - **середовище:** `BENCH_REPO=$tmp/repo`, `BENCH_TASKS=$tmp/tasks.tsv`, `BENCH_CONFIGS=$ROOT/bench/configs.tsv`, `BENCH_PLUGIN=$tmp/plugin`, `BENCH_DIR=$tmp/bench`, `FAKE_LOG=$tmp/claude.args`;
  - **фейковий `$bin/claude`:**
    - пише аргументи (по одному на рядок) у `$FAKE_LOG`, а в `$FAKE_LOG.env` — `pwd`, `XDG_STATE_HOME`, `PASADENA_CODEX`, `PASADENA_REUSE` і вміст `$XDG_STATE_HOME/pasadena/codex-mode`;
    - для `FAKE_WRITES="feature.txt=done feature2.txt=done"` записує файли й комітить;
    - друкує `init.json`, де `plugins` замінено на `[{"name":"pasadena","path":<значення --plugin-dir>}]` або `[]`, потім `assistant.json` `${FAKE_AGENTS:-1}` разів і `result-success.json`;
    - режими `FAKE_CLAUDE`: `budget` (друкує `result-budget.json`), `hang` (`exec sleep 30`), `empty` (`exit 1` без виводу), `wrongplugin` (шлях `/elsewhere`);
  - **helper-и:** `fresh_bench` (`rm -rf "$BENCH_DIR"; : >"$FAKE_LOG"`) і `last_run <jq-filter>` (`tail -1 "$BENCH_DIR/runs.jsonl" | jq -r <filter>`);
  - **підключення частин:** `for part in "$ROOT"/bench/test/*.sh; do [ -e "$part" ] && source "$part"; done`, потім `rm -rf "$tmp"` і підсумок.
- [x] **Step 4: `bench/test/00-acceptance.sh`.**
  - `fresh_bench`; `FAKE_WRITES="feature.txt=done feature2.txt=done" bash "$ROOT/bench/run.sh" t1 plugin 1`: exit 0; `last_run .verdict` = `pass`; `.cost_usd`, `.duration_s`, `.output_tokens` > 0 (`jq -e '. > 0'`); `.plugins[] | select(.name=="pasadena") | .path` = `realpath $tmp/plugin`.
  - Те саме з `baseline`: `last_run '[.plugins[]|select(.name=="pasadena")]|length'` = `0`, verdict `pass`.
  - До `$tmp/tasks.tsv` додати `t3 $ORACLE spec.md $ORACLE t/one.test.sh 0` (на `base` тести вже проходять). `bash "$ROOT/bench/calibrate.sh"`: exit 0; `calibration.log` містить `t3` і `passes on base`; рядок t3 у `tasks.tsv` має `holdout` = `x`. Потім прибрати t3.
  - `out=$(bash "$ROOT/bench/report.sh" --tasks t1 --next "--tasks t1 --reps 1" --out "$BENCH_DIR/reports/01-dry.md")`: `$out` містить `| baseline |`, `| plugin |`, `## Runs`, два рядки з `| t1 |`, `## Spend`, `## Forecast` і `pending runs: 3`; файл `$BENCH_DIR/reports/01-dry.md` дорівнює `$out`.
- [x] **Step 5: побачити, що падає** — `bash bench/bench.test.sh`, очікувано `FAILED: N` (N > 0): скриптів ще немає.

### Task 1: `bench/lib.sh`, `tasks.tsv`, `configs.tsv`

**Writes:** `bench/lib.sh`, `bench/tasks.tsv`, `bench/configs.tsv`, `bench/test/10-lib.sh`
**Reads:** `hooks/codex.test.sh`, spec §3.1–§3.4
**Depends on:** Task 0
**Executor:** claude
**Complexity:** routine
**Satisfies:** — (підґрунтя для Task 3–6)
**Interfaces:**
- Produces (`source "$BENCH_ROOT/lib.sh"` після `BENCH_ROOT=$(cd "$(dirname "$0")" && pwd)`; змінні з Global constraints виставляються при підключенні):
  - `task_field <id> <field>` / `config_field <name> <field>` — друкує значення поля за назвою стовпця заголовка; невідомий id — повідомлення й `return 2`;
  - `task_ids <0|1>` — id з таким `holdout`, у порядку файлу (`x` ніколи); `config_names` — усі імена;
  - `plugin_rev` — `git -C "$BENCH_PLUGIN" rev-parse --short HEAD`, плюс `-dirty`, коли `git -C "$BENCH_PLUGIN" status --porcelain` непорожній;
  - `make_tree <commit> <dest>` — `mkdir -p dest; git -C "$BENCH_REPO" archive <commit> | tar -x -C dest`; `git -C dest init -q`; `add -A`; `git -C dest -c user.name=bench -c user.email=bench@localhost commit -qm "bench: base"`;
  - `put_oracle_tests <oracle> <csv> <tree>` — для кожного шляху `mkdir -p "$tree/$(dirname p)"; git -C "$BENCH_REPO" show "<oracle>:p" >"$tree/p"`;
  - `run_oracle <csv> <tree> <outdir>` — для n-го шляху (з 1): `(cd tree && timeout "$BENCH_ORACLE_TIMEOUT" bash p) >"$outdir/oracle-<n>.log" 2>&1`; у `$outdir/oracle.exit` дописує `p<TAB>code`; повертає 0.

- [x] **Step 1: тест `bench/test/10-lib.sh`.**
  - `source "$ROOT/bench/lib.sh"`: `task_field t1 oracle` = `$ORACLE`; `task_field nope base` повертає 2; `task_ids 0` = `t1`; `task_ids 1` = `t2`; `config_names | wc -l` = `5`; `config_field plugin-noreuse env` = `PASADENA_CODEX=0 PASADENA_REUSE=0`.
  - `plugin_rev` на чистому `$tmp/plugin` — 7+ hex без `-dirty`; після `touch $tmp/plugin/x` закінчується на `-dirty`; потім `rm`.
  - `make_tree $BASE $tmp/tr`: `git -C $tmp/tr rev-list --count HEAD` = `1`; автор `bench <bench@localhost>`; `src/a.sh` існує; `t/one.test.sh` відсутній.
  - `put_oracle_tests $ORACLE t/one.test.sh,t/two.test.sh $tmp/tr` + `run_oracle … $tmp/o`: `oracle.exit` має два рядки з ненульовим кодом, існують `oracle-1.log` і `oracle-2.log`.
- [x] **Step 2: побачити, що падає** — `bash bench/bench.test.sh`, очікувано `FAIL — … lib`.
- [x] **Step 3: реалізація.** `bench/tasks.tsv` — таблиця §3.1 через табуляцію (7 рядків, повні хеші не потрібні, короткі як у spec). `bench/configs.tsv` — таблиця §3.3. `lib.sh` — функції з Interfaces; парсинг TSV через `awk -F'\t'` з пошуком індексу стовпця за заголовком.
- [x] **Step 4: побачити, що проходить** — блок `lib` без `FAIL`.

### Task 2: `bench/score.sh <run-dir>`

**Writes:** `bench/score.sh`, `bench/test/20-score.sh`
**Reads:** `bench/fixtures/*.json`, spec §3.5
**Depends on:** Task 0
**Executor:** claude
**Complexity:** complex
**Satisfies:** частково приймальні тести 1–2 (поля рядка)
**Interfaces:**
- Consumes (усе пише `run.sh`, Task 3), у `<run>/`:
  - `meta.json` — `{"task","config","rep":<int>,"model","plugin_rev","mode":"off|plugin","plugin_path","budget":<num>,"base_commit","ts"}`;
  - `claude.jsonl`, `claude.err`;
  - `claude.exit` — число або `skipped`;
  - `error.txt` — опційно, готова причина, наприклад `codex unavailable`;
  - `diff.patch`;
  - `oracle.exit` — рядки `path<TAB>code`;
  - `base-symbols.txt` — імена функцій на base, по одному на рядок;
  - `codex-before.txt`, `codex-after.txt` — опційно, рядок `weekly_left=.. weekly_used=..`.
- Produces: stdout — один JSON-рядок з полями `task, config, rep, model, plugin_rev, ts, verdict, capped, tests_passed, tests_total, tests_failed (масив шляхів), input_tokens, cache_read, cache_write, output_tokens, cost_usd, cost_source:"cli-estimate", duration_s, num_turns, plugins, subagent_calls, diff_files, diff_lines, dup_symbols, codex_usage, error`. Exit 0; відсутній `meta.json` → exit 2.

- [x] **Step 1: тест `bench/test/20-score.sh`.** Helper `mkrun <dir>` пише валідний `meta.json` (mode `plugin`, `plugin_path=$tmp/plugin`, budget 15), `claude.exit` = `0`, `claude.jsonl` = init з pasadena@`$tmp/plugin` + 2× assistant + result-success, `diff.patch` з одним файлом, `oracle.exit` з двома кодами `0`, `base-symbols.txt` = `helper`. Випадки:
  - базовий → `pass`, `capped:false`, `tests_passed:2`, `subagent_calls:2`, `cost_usd` = `total_cost_usd` фікстури, `duration_s` = `duration_ms/1000`, `cost_source:"cli-estimate"`;
  - один код `1` → `partial`, `tests_failed` = `["t/two.test.sh"]`; обидва `1` → `fail`;
  - порожній `diff.patch` → `refused`;
  - порожній `claude.jsonl` → `error`; `error.txt`=`codex unavailable` і `claude.exit`=`skipped` → `error`, `.error`=`codex unavailable`;
  - init без pasadena при mode `plugin` → `error`/`plugin mismatch`; init з pasadena при mode `off` → те саме; шлях `/elsewhere` → те саме;
  - `claude.exit`=`124` без result → `capped:true`, `.error`=`timeout`, `cost_usd:null`, verdict за оракулом;
  - result-budget → `capped:true`, `.error`=`budget`; без result, але останній рядок `claude.err` містить `budget` → `cost_usd`=`15`;
  - `diff.patch` додає `+helper() {` у `.sh` і `+function fresh(` у `.js` → `dup_symbols:1`, `diff_files:2`;
  - `codex-before` used 10, `codex-after` used 14 → `codex_usage:4`; без файлів → `null`;
  - stdout містить рядок `warning: x` → розбір не падає;
  - два послідовні запуски дають байт-у-байт однаковий рядок.
- [x] **Step 2: побачити, що падає** — `bash bench/bench.test.sh`, `FAIL — … score`.
- [x] **Step 3: реалізація.** Події: `ev=$(jq -cR 'fromjson? // empty' claude.jsonl)`.
  - **init:** `select(.type=="system" and .subtype=="init") | .plugins`; збіг Pasadena — `.name | startswith("pasadena")`; шляхи порівнюються після `realpath -m`.
  - **result:** остання подія `type=="result"`. Токени — з `.usage.{input_tokens,output_tokens,cache_read_input_tokens,cache_creation_input_tokens}`; коли `.usage.output_tokens` дорівнює 0, а `.modelUsage` непорожній (так буває при зупинці бюджетом), токени — сума по `.modelUsage[]` полів `inputTokens`, `outputTokens`, `cacheReadInputTokens`, `cacheCreationInputTokens`. Тест: `result-budget.json` дає `output_tokens` > 0 з `modelUsage`.
  - **capped:** `claude.exit`==124 → `timeout`; `result.subtype=="error_max_budget_usd"` або (немає result і `claude.err` містить `budget`) → `budget`.
  - **verdict:** за пріоритетом §3.5.
  - **diff:** `diff_files` — кількість `^diff --git`; `diff_lines` — рядки `^[+-]` без `^(\+\+\+|---) `.
  - **dup_symbols:** awk відстежує поточний файл з `^\+\+\+ b/`; для `.sh` бере `^\+[[:space:]]*(function[[:space:]]+)?([A-Za-z_][A-Za-z0-9_]*)[[:space:]]*\(\)`, для `.js|.cjs` — `^\+[[:space:]]*function[[:space:]]+([A-Za-z_$][A-Za-z0-9_$]*)`; рахує унікальні імена, що є в `base-symbols.txt`.
  - **codex_usage:** `weekly_used` після мінус до.
  - **error:** `error.txt`, інакше `plugin mismatch`, інакше `no events` (порожньо), інакше `timeout`/`budget`, інакше перший рядок `claude.err`, інакше `null`.
  - Збирання одним `jq -n --arg/--argjson … -c`, тож порядок полів фіксований.
- [x] **Step 4: побачити, що проходить** — блок `score` без `FAIL`.

### Task 3: `bench/run.sh <task> <config> <rep>`

**Writes:** `bench/run.sh`, `bench/test/30-run.sh`
**Reads:** `bench/lib.sh`, `bench/score.sh`, spec §3.3–§3.4
**Depends on:** Task 1, Task 2
**Executor:** claude
**Complexity:** complex
**Satisfies:** приймальні тести 1–2
**Interfaces:**
- Consumes: `lib.sh` (Task 1), `score.sh` і контракт файлів `<run>/` (Task 2).
- Produces: дописує один рядок `score.sh` у `$BENCH_DIR/runs.jsonl`; exit 0 після будь-якого прогону, зокрема `error`; exit 2 при невідомому id або задачі з `holdout=x`.

- [x] **Step 1: тест `bench/test/30-run.sh`.**
  - **plugin:** `FAKE_WRITES=… run.sh t1 plugin 1`. `$FAKE_LOG` містить `-p`, `--output-format`, `stream-json`, `--verbose`, `--no-session-persistence`, `--permission-mode`, `bypassPermissions`, `--max-budget-usd`, `15`, `--model`, `sonnet`, `--settings`, `{"enabledPlugins":{"pasadena@pasadena":false,"pasadena@synced":false}}`, `--plugin-dir`, `$tmp/plugin`. Промпт починається з `/pasadena:leonard Plan the implementation of the agreed specification at spec.md`. `.env` має `PASADENA_CODEX=0`, `PASADENA_REUSE=` (порожньо), codex-mode `explore`, `XDG_STATE_HOME` = `<run>/state`.
  - **baseline:** немає `--plugin-dir`, промпт `Implement the specification at spec.md. …`, codex-mode порожній.
  - **plugin-noreuse:** `PASADENA_REUSE=0`. **plugin-haiku:** `--model haiku`.
  - **plugin-codexfull:** з `FAKE_CODEX_AVAILABLE=1` → `last_run .error` = `codex unavailable`, `$FAKE_LOG` порожній; з `0` і `FAKE_CODEX_USED=10` → `codex-before.txt` існує, codex-mode `full`.
  - **ізоляція:** `pwd` з `.env` — `<run>/tree`; фейк пише `$FAKE_LOG.count` = `git rev-list --count HEAD` до своїх змін → `1`.
  - **timeout:** `BENCH_TIMEOUT=1 FAKE_CLAUDE=hang` → `capped:true`, `error:"timeout"`, `oracle.exit` існує.
  - **після прогону:** `<run>/tree` видалено; `diff.patch`, `meta.json`, `base-symbols.txt` лишились; `base-symbols.txt` містить `helper`.
  - **повтор з тим самим ключем:** у `<run>` немає старого маркерного файлу.
  - **невідомі id:** `run.sh nope plugin 1` і `run.sh t1 nope 1` → exit 2.
- [x] **Step 2: побачити, що падає** — `FAIL — … run`.
- [x] **Step 3: реалізація** (порядок §3.4):
  1. `rev=$(plugin_rev)`; `run=…`; `rm -rf "$run"; mkdir -p "$run/state/pasadena"`.
  2. Пише `meta.json`.
  3. `make_tree "$base" "$run/tree"`.
  4. `base-symbols.txt`: `grep -rhoE '^[[:space:]]*(function[[:space:]]+)?[A-Za-z_][A-Za-z0-9_]*[[:space:]]*\(\)' --include='*.sh'` плюс `function name` у `*.js`/`*.cjs`, нормалізовані до імені, `sort -u`.
  5. `codex_mode` ≠ `-` → `printf '%s\n' "$cm" >"$run/state/pasadena/codex-mode"`.
  6. Для `full`: `bash "$BENCH_PLUGIN/hooks/codex.sh" available || { echo "codex unavailable" >"$run/error.txt"; echo skipped >"$run/claude.exit"; }`; інакше `codex.sh budget >codex-before.txt`.
  7. Промпти дослівно:
     - **plain:** `Implement the specification at <spec>. Work autonomously: do not ask questions, make reasonable decisions. Do not push or open pull requests. Commit your work.`
     - **workflow:** `/pasadena:leonard Plan the implementation of the agreed specification at <spec>, then implement the plan with /pasadena:wolowitz. Work autonomously: do not ask questions, take the recommended option at every decision point, treat the spec and plan as approved. Do not push or open pull requests. Commit your work.`
  8. Виклик з `(cd "$run/tree" && env XDG_STATE_HOME="$run/state" <env-пари> timeout "$BENCH_TIMEOUT" claude …) >claude.jsonl 2>claude.err; echo $? >claude.exit`; `-u CLAUDECODE`, якщо Task 0 цього вимагав.
  9. Для `full` — `codex-after.txt`.
  10. `git -C tree add -A && git -C tree diff --cached "$(git -C tree rev-list --max-parents=0 HEAD)" >diff.patch`.
  11. `put_oracle_tests` + `run_oracle "$tests" "$run/tree" "$run"`.
  12. `bash "$BENCH_ROOT/score.sh" "$run" >>"$BENCH_DIR/runs.jsonl"`; `rm -rf "$run/tree"`.

  Для `skipped` кроки 8–11 пропускаються, `diff.patch` порожній.
- [x] **Step 4: побачити, що проходить** — блоки `run` і приймальні тести 1–2 без `FAIL`.

### Task 4: `bench/calibrate.sh`

**Writes:** `bench/calibrate.sh`, `bench/test/40-calibrate.sh`
**Reads:** `bench/lib.sh`, spec §3.2
**Depends on:** Task 1
**Executor:** claude
**Complexity:** routine
**Satisfies:** приймальний тест 3
**Interfaces:**
- Consumes: `task_ids`, `task_field`, `make_tree`, `put_oracle_tests`, `run_oracle` (Task 1).
- Produces: переписує `$BENCH_TASKS` (поля `tests`, `holdout`), дописує `$BENCH_DIR/calibration.log` рядками `<ISO ts> <id> <kept|dropped-test <path>: fails on oracle|excluded: no tests left|excluded: passes on base|holdout moved to <id>>`. Exit 0.

- [x] **Step 1: тест `bench/test/40-calibrate.sh`.** Копія `$tmp/tasks.tsv` у `BENCH_TASKS=$tmp/cal.tsv`:
  - t1 лишається з обома тестами, у лозі `t1 kept`;
  - t4 з `t/missing.test.sh,t/one.test.sh` (missing на oracle не існує й падає) → `tests` = `t/one.test.sh`, лог `dropped-test t/missing.test.sh: fails on oracle`;
  - t5 лише з `t/missing.test.sh` → `holdout` `x`, `no tests left`;
  - t3 на `$ORACLE` як base → `x`, `passes on base`;
  - холдаут t2 з base=`$ORACLE` виключається → холдаутом стає останній рядок з `holdout=0` (t1), лог `holdout moved to t1`;
  - заголовок файлу збережено.
- [x] **Step 2: побачити, що падає.**
- [x] **Step 3: реалізація.** Для кожного id з `holdout` 0 або 1: дерево `oracle` у `mktemp -d` → `run_oracle` → лишити шляхи з кодом 0; дерево `base` + `put_oracle_tests` лишених → `run_oracle`; якщо всі 0 → `x`. «Остання за датою» — останній рядок файлу з `holdout=0` (файл упорядковано за датою spec). Запис — через тимчасовий файл і `mv`. Тимчасові дерева видаляються.
- [x] **Step 4: побачити, що проходить.**

### Task 5: `bench/matrix.sh`

**Writes:** `bench/matrix.sh`, `bench/test/50-matrix.sh`
**Reads:** `bench/lib.sh`, spec §3.6
**Depends on:** Task 1
**Executor:** claude
**Complexity:** routine
**Satisfies:** — (підґрунтя для Task 6 і етапів 2–5)
**Interfaces:**
- Consumes: `task_ids`, `config_names`, `plugin_rev` (Task 1); `$BENCH_RUN`.
- Produces: `matrix.sh [--tasks a,b] [--configs x,y] [--reps N] [--holdout] [--retry-errors] [--pending]`.
  - **Без `--pending`:** для кожного невиконаного `(task, config, rep)` з rep від 1 до N викликає `bash "$BENCH_RUN" task config rep`, послідовно. З `--retry-errors` перед перезапуском видаляє з `runs.jsonl` рядки з цим ключем і `verdict=="error"`.
  - **`--pending`** (свідоме рішення, споживає Task 6): друкує невиконані ключі рядками `task<TAB>config<TAB>rep` і нічого не запускає.
  - **Ключ виконаного прогону:** рядок `runs.jsonl` з тим самим `plugin_rev`, `task`, `config`, `rep`; для `config=="baseline"` — будь-який `plugin_rev`, бо `report.sh` теж бере baseline з будь-якої ревізії.
  - **Невідомий аргумент:** exit 2.

- [x] **Step 1: тест `bench/test/50-matrix.sh`.** `BENCH_RUN=$tmp/fakerun.sh` дописує `$1 $2 $3` у `$tmp/matrix.calls` і рядок `{"task":$1,"config":$2,"rep":$3,"plugin_rev":<rev>,"verdict":"pass"}` у `runs.jsonl`:
  - `--tasks t1 --configs plugin,baseline --reps 2` → 4 виклики;
  - повторний запуск → 0;
  - `--holdout --configs plugin --reps 1` → виклик `t2 plugin 1`;
  - рядок з `verdict:"error"` → не перезапускається без прапорця; з `--retry-errors` перезапускається, у `runs.jsonl` лишається один рядок цього ключа;
  - baseline з іншим `plugin_rev` вважається виконаним;
  - `--pending --tasks t1 --reps 1` на порожньому `runs.jsonl` → 5 рядків і 0 викликів;
  - `--bogus` → exit 2.
- [x] **Step 2: побачити, що падає.**
- [x] **Step 3: реалізація.** За замовчуванням: `task_ids 0` (або `task_ids 1` з `--holdout`), `config_names`, `N=3`. Множина виконаних — з `jq -r '[.plugin_rev,.task,.config,(.rep|tostring),.verdict]|@tsv' runs.jsonl`.
- [x] **Step 4: побачити, що проходить.**

### Task 6: `bench/report.sh`

**Writes:** `bench/report.sh`, `bench/test/60-report.sh`
**Reads:** `bench/lib.sh`, `bench/matrix.sh`, spec §3.7
**Depends on:** Task 1, Task 5
**Executor:** claude
**Complexity:** routine
**Satisfies:** приймальні тести 4–5
**Interfaces:**
- Consumes: `bash "$BENCH_ROOT/matrix.sh" <next args> --pending` (Task 5); рядки `runs.jsonl` з полями Task 2.
- Produces: `report.sh [--rev R] [--tasks a,b] [--configs x,y] [--next "<args>"] [--out <file>]` → markdown на stdout (і в `--out`, з `mkdir -p` каталогу). Розділи:
  - `## Cells` — таблиця `| cell | runs | pass | partial | fail | refused | error | capped | cost mean | cost p95 | time mean | time p95 | out tokens | subagents | dup | codex |`, частки у відсотках з цілими;
  - під нею рядки `<cell>: pass <±d> vs plugin` з ` (noise)` при `|d| ≤ 3` і нагадування: `Bias: oracle tests come from the original PRs; the plugin is current while tasks are historical (spec §5).`;
  - `## Runs` — `| task | config | rep | verdict | capped | cost | time | turns | subagents | diff lines | error | failed tests | run |`, де `run` — `$BENCH_DIR/runs/<rev>/<task>/<config>/<rep>`;
  - `## Spend` — `selection: $<sum> / <sum>s; all runs: $<sum> / <sum>s`;
  - `## Forecast` (лише з `--next`) — `pending runs: <k>`, потім по комірці `| cell | pending | cost mean | cost p95 | time mean | time p95 |` (кількість × середнє/p95 вибірки; без прогонів — `BENCH_BUDGET`/`BENCH_TIMEOUT` з позначкою `(upper bound)`) і рядок `total`.
  - **Ревізія за замовчуванням:** `plugin_rev` найновішого не-baseline рядка; baseline — з будь-якої ревізії.
  - **p95:** `sort_by(.) | .[(length*0.95|ceil)-1]`; `null` ігнорується.

- [x] **Step 1: тест `bench/test/60-report.sh`.** Підготувати `runs.jsonl` вручну: 4 рядки `plugin` (rev `aaa`, 3 pass, 1 fail, costs 1,2,3,10), 2 `baseline` (rev `old`, обидва fail), 1 `plugin` rev `zzz` раніше в файлі. Перевірити:
  - рядок `| plugin | 4 | 75% |`;
  - `baseline: pass -3 vs plugin (noise)`;
  - p95 вартості plugin = `10.00`;
  - `--rev zzz` → plugin runs `1`;
  - `--configs baseline` → немає `| plugin |`;
  - `## Runs` має 6 рядків даних;
  - `## Spend` показує `$16.00` для plugin+baseline;
  - `--next "--tasks t1 --reps 1"` → `pending runs:` з числом від `matrix.sh --pending`;
  - комірка без прогонів має `(upper bound)` і `15.00`;
  - `--out` створює файл, ідентичний stdout.
- [x] **Step 2: побачити, що падає.**
- [x] **Step 3: реалізація.** Фільтр і агрегати — одним `jq -s`; markdown — `jq -r`/`printf`.
- [x] **Step 4: побачити, що проходить** — разом із приймальними тестами 4–5 `bash bench/bench.test.sh` → `All checks passed.`

### Task 7: README і версія

**Writes:** `README.md`, `README.uk.md`, `.claude-plugin/plugin.json`, `.claude-plugin/marketplace.json`, `skills/skills.test.sh`
**Reads:** `README.md:211-224`, `README.uk.md:209-222`
**Depends on:** Task 0
**Executor:** claude
**Complexity:** routine
**Satisfies:** — (умова Verification `skills.test.sh`)

- [x] **Step 1: тест.** `skills/skills.test.sh:257`: `0.23.0` → `0.24.0` (і в повідомленні). Додати поруч:
  - `grep -qF 'bash bench/bench.test.sh' "$ROOT/$readme" || fail "$readme: no bench check"` у циклі по обох README;
  - `grep -qF '## Benchmarks' README.md`;
  - `grep -qF '## Бенчмарки' README.uk.md`.
- [x] **Step 2: побачити, що падає** — `bash skills/skills.test.sh`, `not on 0.24.0`.
- [x] **Step 3: реалізація.**
  - Версія `0.24.0` в обох маніфестах.
  - У README перед `## Checks` — розділ `## Benchmarks`: 4–6 речень (що міряє пілот, де результати, `BENCH_BUDGET`/`BENCH_TIMEOUT`, що прогони йдуть з `bypassPermissions`, етапи зі звітом після кожного) і блок `bash bench/calibrate.sh`, `bash bench/matrix.sh --tasks model-routing --reps 1`, `bash bench/report.sh --next "--reps 3" --out …`.
  - `bash bench/bench.test.sh` у блоці Checks і речення про bench-перевірки в абзаці під ним.
  - Дзеркально в `README.uk.md` (`## Бенчмарки`, `## Перевірки`).
- [x] **Step 4: побачити, що проходить** — `bash skills/skills.test.sh` → `All checks passed.`

### Task 8: етап 0 — калібрування на реальному репозиторії, потім зупинка

**Writes:** `bench/tasks.tsv`
**Reads:** `bench/calibrate.sh`, `$BENCH_DIR/calibration.log`
**Depends on:** Task 1–7
**Executor:** claude
**Complexity:** routine
**Satisfies:** «`bench/calibrate.sh` завершується, `calibration.log` пояснює кожне виключення» на реальних даних; перший звіт етапу з §3.8

- [x] **Step 1:** `bash bench/bench.test.sh && bash skills/skills.test.sh` — обидва `All checks passed.`
- [x] **Step 2:** `bash bench/calibrate.sh` (без змінних, реальний репозиторій; лише локальні тести, без `claude`). Exit 0.
- [x] **Step 3:** `mkdir -p $BENCH_DIR/reports && cp $BENCH_DIR/calibration.log $BENCH_DIR/reports/00-calibration-<plugin_rev>.md`; закомітити зміни `bench/tasks.tsv` (`chore(bench): calibrate oracles`), запушити.
- [x] **Step 4:** коментар у PR #36: вміст `calibration.log`, таблиця задач після калібрування (лишені тести, виключені й чому, холдаут), висновки агента і пропозиція етапу 1 (два сухі прогони, ≈ до $30 у найгіршому разі, з прогнозом). **Зупинка:** етап 1 не запускається без явного погодження користувача.

---

## Ревізія 2026-11-13

**Goal:** `bench/` оцінює прогони за окремими вимогами з `bench/checks.tsv` проти оракула на останньому коміті фічі; агент отримує спеку з оракула; кожен рядок має `bench_rev`; `meta.json` фіксує `ub_tools`; `score.sh` не шумить у stderr для `off`. Етап 0 повторено на реальному репозиторії, звіт у PR #36, далі зупинка до погодження етапу 1.
**Spec:** docs/sdd/specs/2026-11-05-benchmark-harness.md (Revised 2026-11-13, коміт 38eadcb)
**Verification:** `bash bench/bench.test.sh && bash hooks/ub-tools.test.sh && bash skills/skills.test.sh`; останній рядок кожного — `All checks passed.`

Задачі 9–18 дописуються в наявний план `docs/sdd/plans/2026-11-05-benchmark-harness.md` розділом «Ревізія 2026-11-13»; Task 9 — приймальні тести ревізії (роль Task 0).
dryer: `ub-tools.sh dryer bench hooks/ub-tools.sh` → `No source files to analyze` (bash не підтримується), дублікатів не знайдено.

### Context

Етап 1 (2026-11-13, $3.07) дав `fail` обом коміркам: оракул `d97c752` захопив чужу фічу, а `skills.test.sh` вимагає дослівних рядків, яких немає в спеці. Ревізія спеки (§3.1–3.9, §5, §6) міняє оракули, джерело спеки, одиницю оцінки й ключ серій. Причину `Error: invalid value for one of the arguments` уже знайдено під час планування: `bench/score.sh:36` викликає `realpath -m ''`, коли `plugin_path` порожній (комірка `off`); відтворюється `bash bench/score.sh <baseline-run>`.

### Global constraints

- Усе з «Global constraints» наявного плану чинне: bash `set -uo pipefail`, `jq`, без коментарів, тести — частини `bench/test/NN-*.sh` з helper-ами `assert_eq`, `assert_contains`, `fresh_bench`, `last_run` і лічильником `fails`.
- Нова змінна в `bench/lib.sh`: `BENCH_CHECKS="${BENCH_CHECKS:-$BENCH_ROOT/checks.tsv}"`. `bench/bench.test.sh` експортує `BENCH_CHECKS="$tmp/checks.tsv"`, щоб тести не читали справжній файл.
- Формат `bench/checks.tsv`: заголовок `task\ttest\tcheck\tstatus\treason`; `status` ∈ `target|excluded`; `reason` порожній для автоматичної цілі, `literal not in spec: "<s>"` для автоматичного виключення, `manual: <чому>` для ручного рішення. Табуляція в `check` замінюється пробілом.
- Нормалізація назви вимоги: шлях дерева, де запускався тест, замінюється на `<tree>`; ведучі пробіли й префікс `FAIL — ` відкидаються.
- Файл тесту **дійшов до кінця**, коли його вивід має рядок `All checks passed.` або `FAILED: <N>`.
- `bench_rev` = `cat "$BENCH_TASKS" "$BENCH_CHECKS" 2>/dev/null | sha256sum | cut -c1-12`.
- Задача без жодного рядка `target` у `checks.tsv` оцінюється, як до ревізії, за кодами файлів; `checks_total` = 0, `score` = `null`. Свідоме рішення: так тести без `ok/FAIL`-виводу й нова, ще не калібрована задача лишаються оцінюваними.
- Версія плагіна `0.24.0` → `0.25.0`: `.claude-plugin/plugin.json`, `.claude-plugin/marketplace.json`, `skills/skills.test.sh:257` і `:380`.
- Codex: `off`, режим `explore` — усі задачі `claude`.

### Review Focus

1. Назва вимоги з абсолютним шляхом дерева (`<tree>/skills/wolowitz/SKILL.md: 20000 bytes…`): ключ має збігатися між калібруванням (`$work/<id>/base`) і прогоном (`$run/tree`).
2. Тестовий файл, що впав до підсумкового рядка (синтаксична помилка, тайм-аут оракула), не може зарахувати жодної цілі, хоч `FAIL`-рядків у ньому й немає.
3. Повторне калібрування зберігає `manual:`-рядок і не дублює його автоматичним.
4. Вимога з лапками, що не є літералом (`expected one "version" line`), автоматично виключається — це очікувано; ручне `manual:` може повернути її в `target`.
5. Рядки `runs.jsonl` без `bench_rev` (старі) не стають «виконаними» для `matrix.sh` і не потрапляють у `report.sh`.

### Waves

| Wave | Tasks | Why together |
|---|---|---|
| 0 | 9 | сам — приймальні тести ревізії, червоні до хвилі 3 |
| 1 | 10, 11, 17 | різні файли: `lib.sh`+`tasks.tsv`; `hooks/ub-tools.sh`; маніфести+README+`skills.test.sh` |
| 2 | 12, 13, 14, 15 | різні файли: `calibrate.sh`, `score.sh`, `run.sh`, `matrix.sh`; усі споживають `lib.sh` з Task 10, `run.sh` — ще й `available` з Task 11 |
| 3 | 16 | сам — `report.sh --next` спирається на ключі `matrix.sh --pending` з Task 15 і поля з Task 13 |
| 4 | 18 | сам — етап 0 на реальному репозиторії, пише `tasks.tsv` і `checks.tsv`, потім зупинка |

Послідовно: Task 16 після 13 і 15; Task 18 після всіх, бо запускає готовий `calibrate.sh` і переписує файли з Task 10.

---

### Task 9: приймальні тести ревізії

**Writes:** `bench/bench.test.sh`, `bench/test/70-revision.sh`
**Executor:** claude
**Covers:**
- «`bash bench/bench.test.sh` проходить.»
- «`bench/calibrate.sh` завершується, `calibration.log` пояснює кожне виключення, `bench/checks.tsv` має хоча б одну ціль на кожну невиключену задачу…»
- «Причину рядка `Error: invalid value for one of the arguments`… знайдено на фейковому `claude` і усунено до повтору етапу 1.»
- §3.4 крок 2 (спека з `oracle`, `ub_tools`), §3.5 (`checks_*`, `score`, `bench_rev`), §3.6 (ключ з `bench_rev`), §3.7 (`score mean`, `checks`, відсів `bench_rev`).

- [x] **Step 1: `bench/bench.test.sh`** — після `export BENCH_DIR=…` додати `export BENCH_CHECKS="$tmp/checks.tsv"`. У фейковий плагін `$plugin` скопіювати `hooks/ub-tools.sh` з `$ROOT` (перед його `git commit`). У фейковий `claude` після запису `$FAKE_LOG.env` додати `cat spec.md >"$FAKE_LOG.spec" 2>/dev/null`; `fresh_bench` видаляє й `$FAKE_LOG.spec`. В основному фейковому репозиторії перед комітом `oracle` додати `echo amended >>"$repo/spec.md"`, щоб спека в `oracle` відрізнялась від `base`.
- [x] **Step 2: `bench/test/70-revision.sh`** — власний репозиторій `$tmp/rrepo` (через `gitc`):
  - коміт base: `spec.md` з текстом `alpha "beta"` і `t/c.test.sh` відсутній;
  - коміт oracle: `spec.md` дописує рядок `amended`, `feature.txt` = `alpha`, `literal.txt` = `gamma`, і `t/c.test.sh`, що друкує `ok  — `/`FAIL — ` у форматі репозиторію з підсумком `All checks passed.` / `FAILED: N`, з трьома вимогами: `feature: missing "alpha"` (`grep -qx alpha feature.txt`), `literal: missing "gamma"` (`grep -qx gamma literal.txt`), `path: $(pwd)/feature.txt absent` (`[ -f feature.txt ]`).
  - `rtasks=$tmp/rtasks.tsv` з задачами `r1` (base, oracle, `t/c.test.sh`, holdout 0) і `r0` (base=oracle — без цілей, holdout 0).
  Перевірки (кожна — `assert_*` з окремою назвою):
  1. `BENCH_REPO=$tmp/rrepo BENCH_TASKS=$rtasks bash bench/calibrate.sh` → exit 0; у `$BENCH_CHECKS` рядок `r1\tt/c.test.sh\tfeature: missing "alpha"\ttarget\t`; рядок `literal: missing "gamma"` має `excluded` і `literal not in spec: "gamma"`; рядок `path: <tree>/feature.txt absent` — `target`; `r0` у `$rtasks` має `holdout` `x`, лог містить ` r0 excluded:`.
  2. Додати в `$BENCH_CHECKS` ручне рішення: замінити рядок `path: …` на `status=excluded`, `reason=manual: test`; повторний `calibrate.sh` лишає саме цей рядок з `manual: test` і не додає дубль.
  3. `FAKE_WRITES="feature.txt=alpha" BENCH_REPO=… BENCH_TASKS=… bash bench/run.sh r1 plugin 1` → `last_run .checks_total` = `1`, `.checks_passed` = `1`, `.score` = `1`, `.verdict` = `pass`, `.bench_rev` — 12 hex-символів і дорівнює `cat $rtasks $BENCH_CHECKS | sha256sum | cut -c1-12`.
  4. У тому ж прогоні `$FAKE_LOG.spec` містить `amended` (агент бачив спеку з oracle), `diff.patch` не згадує `spec.md`, а `jq -r .ub_tools.dryer <run>/meta.json` непорожній.
  5. Прогін `r1 baseline 1` з `FAKE_WRITES="other.txt=x"`: stderr `run.sh` (`2>$tmp/r.err`) не містить `invalid value`; `last_run .verdict` = `fail`, `.checks_passed` = `0`.
  6. `BENCH_TASKS=$rtasks bash bench/report.sh --tasks r1` містить заголовок стовпця `score mean` і `| 1/1 |` у рядку прогону `plugin`.
  7. Дописати в `runs.jsonl` копію останнього рядка без `bench_rev` і з `config:"plugin-haiku"`; `BENCH_TASKS=$rtasks bash bench/report.sh` не містить `plugin-haiku`; `BENCH_TASKS=$rtasks bash bench/matrix.sh --tasks r1 --configs plugin --reps 1 --pending` друкує порожньо (прогін з поточним `bench_rev` виконаний).
  Усі змінні (`BENCH_REPO`, `BENCH_TASKS`) задаються префіксом команди, щоб не протекти в інші частини.
- [x] **Step 3: побачити, що падає** — `bash bench/bench.test.sh`, очікувано `FAILED: N` з провалами лише в блоці `== revision ==`.

### Task 10: `lib.sh` — `BENCH_CHECKS`, `bench_rev`, спека з оракула; оракули в `tasks.tsv`

**Writes:** `bench/lib.sh`, `bench/tasks.tsv`, `bench/test/10-lib.sh`
**Reads:** spec §3.1, §3.4 крок 2
**Depends on:** Task 9
**Executor:** claude
**Complexity:** routine
**Satisfies:** частина приймальних 3–4, 7
**Interfaces:**
- Produces: `BENCH_CHECKS`; `bench_rev` (друкує 12 hex); `make_tree <commit> <dest> [<oracle> <spec>]` — з двома додатковими аргументами перезаписує `<dest>/<spec>` вмістом `git -C "$BENCH_REPO" show "<oracle>:<spec>"` до `git add -A`, решта як було.

- [ ] **Step 1: тест у `bench/test/10-lib.sh`:** `bench_rev` — 12 символів `[0-9a-f]` і змінюється після дописування рядка в копію `checks.tsv`; `make_tree "$BASE" "$tmp/mt" "$ORACLE" spec.md` дає `spec.md`, ідентичний `git -C "$repo" show "$ORACLE:spec.md"`, і рівно один коміт; без двох аргументів `spec.md` — з `$BASE`.
- [ ] **Step 2: побачити, що падає** — `bash bench/bench.test.sh`.
- [ ] **Step 3: реалізація** у `bench/lib.sh`: рядок `BENCH_CHECKS=…` після `BENCH_CONFIGS`; функція `bench_rev`; у `make_tree` після `tar -x`: `if [ -n "${3:-}" ]; then git -C "$BENCH_REPO" show "$3:$4" >"$dest/$4" || return; fi`. У `bench/tasks.tsv`: `model-routing` oracle `d97c752` → `fbdd4ae`, `reuse-first` oracle `74bf39c` → `8c0f8f8`.
- [ ] **Step 4: побачити, що проходить** — блок `lib` без `FAIL`.

### Task 11: `ub-tools.sh available <tool>`

**Writes:** `hooks/ub-tools.sh`, `hooks/ub-tools.test.sh`
**Depends on:** Task 9
**Executor:** claude
**Complexity:** routine
**Satisfies:** частина приймального 4
**Interfaces:**
- Produces: `bash hooks/ub-tools.sh available <dryer|crapper|mutator>` — друкує `<tool>: <команда>` (елементи `RUN` через пробіл) і exit 0, або рядок `<tool>: unavailable (<причина>)` з наявної `resolve` і exit 1; інше ім'я → usage, exit 2.

- [ ] **Step 1: тест у `hooks/ub-tools.test.sh`** у стилі файлу: з `PASADENA_DRYER` на фейковий виконуваний файл → `dryer: <шлях>`, exit 0; `PASADENA_CRAPPER=/nonexistent` → `crapper: unavailable (PASADENA_CRAPPER is not executable)`, exit 1; з порожнім `XDG_DATA_HOME` і без `mutator` у PATH → `mutator: unavailable (not installed; run ub-tools.sh install)`, exit 1; `available foo` → exit 2.
- [ ] **Step 2: побачити, що падає** — `bash hooks/ub-tools.test.sh`.
- [ ] **Step 3: реалізація:** функція `cmd_available` викликає `resolve "$1"` і друкує `$1: ${RUN[*]}`; гілка `available) case "${1:-}" in dryer|crapper|mutator) cmd_available "$1"; exit $? ;; *) usage; exit 2 ;; esac ;;` до загального `exit 0`; usage доповнити `| available <tool>`.
- [ ] **Step 4: побачити, що проходить** — `All checks passed.`

### Task 12: `calibrate.sh` — цілі в `checks.tsv`

**Writes:** `bench/calibrate.sh`, `bench/test/40-calibrate.sh`
**Reads:** spec §3.2, `bench/lib.sh`
**Depends on:** Task 10
**Executor:** claude
**Complexity:** complex
**Satisfies:** приймальні 1–2
**Interfaces:**
- Consumes: `make_tree <commit> <dest> <oracle> <spec>`, `BENCH_CHECKS` (Task 10).
- Produces: `$BENCH_CHECKS` у форматі з Global constraints; лог-рядки `excluded: no target checks` і `check-excluded <test>: <check>: <reason>`.

- [ ] **Step 1: тест у `40-calibrate.sh`** — наявні перевірки лишаються зеленими (їхні тести не друкують `FAIL —`, тож у задач t1/t4 цілей немає: для фейкового репозиторію без `ok/FAIL`-виводу задача з кодами `≠0` на base лишається `kept` за старим правилом). Нові: задача, у якої base-файли друкують `FAIL —`-рядки, усі з літералами поза спекою → `x`, `excluded: no target checks`; кожен виключений рядок має запис `check-excluded` у лозі.
- [ ] **Step 2: побачити, що падає.**
- [ ] **Step 3: реалізація.**
  - Обидва дерева через `make_tree "<commit>" "<dir>" "$oracle" "$spec"`; `spec` з `task_field`. Текст спеки — `git -C "$BENCH_REPO" show "$oracle:$spec" >"$dir/spec.txt"`.
  - Після `run_oracle` на base для кожного лишеного файла `n`: awk по `$dir/base-out/oracle-$n.log` — збирати рядки `^[[:space:]]*FAIL — `, відкидати префікс, замінювати `"$dir/base"` на `<tree>` (через `index`/`substr`, не regex), табуляцію на пробіл; для кожного FAIL збирати літерали: усі `"…"` з назви плюс значення наступних рядків `^[[:space:]]+expected substring: ` і `^[[:space:]]+expected: ` до наступного `ok  —`/`FAIL —`. Те саме для oracle-логів → множина назв; ціль = base-FAIL, якого немає в oracle-FAIL.
  - Літерал відсутній у `spec.txt` (`grep -qF -- "$s"`) → `excluded`, `literal not in spec: "<s>"` (перший відсутній).
  - Ручні рядки: перед записом прочитати наявний `$BENCH_CHECKS` і зберегти рядки, чий `reason` починається з `manual:`, за ключем `task\ttest\tcheck`; при генерації такий ключ бере статус і reason з ручного рядка; ручні рядки без згенерованої пари відкидаються.
  - Задача з `kept`-файлами, що друкують `FAIL —`-рядки, але без жодного `target` → `exclude … "no target checks"`. Задачі без жодного `FAIL —` у base-виводі — правило «passes on base» за кодами, як було.
  - Запис `$BENCH_CHECKS` атомарно (`.tmp.$$` + `mv`), рядки лише невиключених задач, порядок задач — як у `tasks.tsv`.
- [ ] **Step 4: побачити, що проходить** — блоки `calibrate` і приймальні 1–2 без `FAIL`.

### Task 13: `score.sh` — `checks_*`, `score`, `bench_rev`, тиша в stderr для `off`

**Writes:** `bench/score.sh`, `bench/test/20-score.sh`
**Reads:** spec §3.5, `bench/lib.sh`
**Depends on:** Task 10
**Executor:** claude
**Complexity:** complex
**Satisfies:** приймальні 3, 5
**Interfaces:**
- Consumes: `BENCH_CHECKS`, `bench_rev` (Task 10); `score.sh` починає `source "$BENCH_ROOT/lib.sh"` з `BENCH_ROOT="$(cd "$(dirname "$0")" && pwd)"`.
- Produces: нові поля рядка `bench_rev` (рядок), `checks_passed`, `checks_total` (числа), `score` (число з 2 знаками або `null`).

- [ ] **Step 1: тести в `20-score.sh`:** для `mkrun` з `oracle.exit` = `t/c.test.sh\t1` і `oracle-1.log`, де є `FAIL — a`, `FAIL — <tree>/x`-подібна назва з шляхом `$dir/tree` і рядок `FAILED: 2`, та `checks.tsv` з цілями `a`, `b`, `<tree>/x` → `checks_total` 3, `checks_passed` 1, `score` 0.33, `verdict` `partial`; лог без підсумкового рядка → `checks_passed` 0; задача без рядків у `checks.tsv` → `checks_total` 0, `score` null, вердикт за кодами (наявні перевірки); `meta.mode=off` з `plugin_path:""` → stderr `score.sh` порожній; `bench_rev` = значенню `bench_rev` з `lib.sh`.
- [ ] **Step 2: побачити, що падає.**
- [ ] **Step 3: реалізація.**
  - `want_path` рахувати лише коли `mode != off` і `plugin_path` непорожній — це усуває `realpath -m ''`.
  - Цілі: `awk -F'\t' -v t="$task" 'NR>1 && $1==t && $4=="target"' "$BENCH_CHECKS"`. Індекс файла — номер рядка `oracle.exit` з цим шляхом. Для кожної цілі: лог `oracle-<n>.log` з `"$run/tree"` → `<tree>`; пройдена, коли лог має `All checks passed.` або `FAILED: <N>` і не має рядка, що після обрізання ведучих пробілів дорівнює `FAIL — <check>`. Порівняння рядків — фіксоване (awk `==`), не regex.
  - `verdict`: якщо `checks_total > 0`, то `pass`/`partial`/`fail` за `checks_passed`; інакше — за кодами, як було. `error`/`refused` мають пріоритет, як було.
  - `score`: `(passed*100/total | round)/100` при `total>0`, інакше `null`.
- [ ] **Step 4: побачити, що проходить** — блок `score` і приймальні 3, 5.

### Task 14: `run.sh` — спека з оракула і `ub_tools`

**Writes:** `bench/run.sh`, `bench/test/30-run.sh`
**Reads:** spec §3.4
**Depends on:** Task 10, Task 11
**Executor:** claude
**Complexity:** routine
**Satisfies:** приймальний 4
**Interfaces:**
- Consumes: `make_tree … "$oracle" "$spec"` (Task 10); `ub-tools.sh available` (Task 11).
- Produces: `meta.json.ub_tools = {dryer, crapper, mutator}` — рядок виводу `available`; `"unknown"`, якщо в `$BENCH_PLUGIN` немає `hooks/ub-tools.sh`.

- [ ] **Step 1: тести в `30-run.sh`:** після `run.sh t1 plugin 1` файл `$FAKE_LOG.spec` (його пише фейк з Task 9) дорівнює `git -C "$repo" show "$ORACLE:spec.md"` і містить `amended`; `ub_tools.crapper` для комірки з `env` `PASADENA_CRAPPER=/nonexistent` — `crapper: unavailable (PASADENA_CRAPPER is not executable)` (тестова `configs.tsv` у `$tmp`, передана через `BENCH_CONFIGS=` префіксом); `ub_tools.dryer` = `unknown`, коли в плагіні немає `hooks/ub-tools.sh` (тимчасовий `BENCH_PLUGIN`).
- [ ] **Step 2: побачити, що падає.**
- [ ] **Step 3: реалізація:** розбір `env_pairs` у `pairs` перенести до запису `meta.json`; `ub_tools` — `jq -n` з трьох `env "${pairs[@]}" bash "$BENCH_PLUGIN/hooks/ub-tools.sh" available <tool> 2>/dev/null` (ігнорувати exit 1) і `--argjson ub_tools` у наявний `jq -n`; `make_tree "$base" "$run/tree" "$oracle" "$spec"`.
- [ ] **Step 4: побачити, що проходить.**

### Task 15: `matrix.sh` — ключ з `bench_rev`

**Writes:** `bench/matrix.sh`, `bench/test/50-matrix.sh`
**Reads:** spec §3.6
**Depends on:** Task 10
**Executor:** claude
**Complexity:** routine
**Satisfies:** приймальний 7 (частина `--pending`)
**Interfaces:**
- Consumes: `bench_rev` (Task 10); поле рядка `.bench_rev` (Task 13; рядок без нього має `null`).

- [ ] **Step 1: тести в `50-matrix.sh`:** рядок `runs.jsonl` з іншим `bench_rev` (або без нього) не вважається виконаним; `--retry-errors` видаляє лише `error`-рядок з поточним `bench_rev`.
- [ ] **Step 2: побачити, що падає.**
- [ ] **Step 3: реалізація:** `brev="$(bench_rev)"`; у читанні `jq -r '[.plugin_rev,(.bench_rev // ""),.task,…]|@tsv'` пропускати рядки з `bench_rev != $brev`; `drop_errors` додає умову `$o.bench_rev == $brev`.
- [ ] **Step 4: побачити, що проходить.**

### Task 16: `report.sh` — `score mean`, `checks`, відсів `bench_rev`

**Writes:** `bench/report.sh`, `bench/test/60-report.sh`
**Reads:** spec §3.7
**Depends on:** Task 13, Task 15
**Executor:** claude
**Complexity:** routine
**Satisfies:** приймальні 6–7
**Interfaces:**
- Consumes: поля `bench_rev`, `score`, `checks_passed`, `checks_total` (Task 13); `bench_rev` з `lib.sh`.

- [ ] **Step 1: тести в `60-report.sh`:** стовпець `score mean` у таблиці комірок (`0.50` для двох прогонів зі `score` 1 і 0, `-` без значень); рядок `<cell>: score +0.25 vs plugin (noise)` при <3 прогонах у будь-якій з двох комірок і без `(noise)` при ≥3 в обох; стовпець `checks` у таблиці прогонів (`k/n`, `-` при `checks_total` 0); рядки з іншим `bench_rev` не враховуються ні у вибірці, ні у визначенні найновішого `plugin_rev`.
- [ ] **Step 2: побачити, що падає.**
- [ ] **Step 3: реалізація:** `--arg brev "$(bench_rev)"` і `select(.bench_rev == $brev)` над `$all` до вибору `$r`; `cellrow` + `score_mean: ($rs | vals("score") | mean)`; `cellline` — стовпець після `fail`… розмістити після `runs`: `| cell | runs | score mean | pass | …`; `delta` дописує другий рядок для `score` з форматуванням `dec2` (новий `def dec2`, аналог `money` без `$`); `runline` замінює стовпець `failed tests` на `checks`. Заголовки таблиць оновити відповідно.
- [ ] **Step 4: побачити, що проходить** — `bash bench/bench.test.sh` → `All checks passed.` (приймальні 1–7 зелені).

### Task 17: версія 0.25.0 і README

**Writes:** `.claude-plugin/plugin.json`, `.claude-plugin/marketplace.json`, `skills/skills.test.sh`, `README.md`, `README.uk.md`
**Depends on:** Task 9
**Executor:** claude
**Complexity:** routine
**Satisfies:** — (умова Verification `skills.test.sh`)

- [ ] **Step 1: тест** — `skills/skills.test.sh:257` і `:380`: `0.24.0` → `0.25.0` (і в повідомленнях).
- [ ] **Step 2: побачити, що падає** — `bash skills/skills.test.sh`, `not on 0.25.0`.
- [ ] **Step 3: реалізація.** Версія `0.25.0` в обох маніфестах. У `## Benchmarks` після речення про `calibration.log`: «Calibration also writes `bench/checks.tsv`: the individual checks that fail at the base commit and pass at the oracle, minus those whose expected text the spec never states; a run's `score` is the share of those checks it passes.» У абзаці про quality gates: «`bash hooks/ub-tools.sh available <tool>` prints where a tool resolves to, or why it is unavailable.» Дзеркально в `README.uk.md` («Калібрування також пише `bench/checks.tsv`: окремі перевірки, що падають на базовому коміті й проходять на оракулі, без тих, чий очікуваний текст спека не називає; `score` прогону — частка цих перевірок, які він пройшов.» і «`bash hooks/ub-tools.sh available <tool>` друкує, куди резолвиться інструмент, або чому він недоступний.»).
- [ ] **Step 4: побачити, що проходить** — `All checks passed.`

### Task 18: етап 0 — повторне калібрування, потім зупинка

**Writes:** `bench/tasks.tsv`, `bench/checks.tsv`
**Depends on:** Task 9–17
**Executor:** claude
**Complexity:** routine
**Satisfies:** §6 «`bench/calibrate.sh` завершується… кожна ціль без літералів має `manual:`-рішення або лишилась `target` після перегляду», «На `model-routing` з оракулом `fbdd4ae` кінчик проходить усі цілі, а `base` — жодної»

- [ ] **Step 1:** Verification-команда плану — усі три `All checks passed.`
- [ ] **Step 2:** `bash bench/calibrate.sh` на реальному репозиторії. Exit 0.
- [ ] **Step 3:** переглянути кожну ціль без лапок і без `expected`-рядка в `bench/checks.tsv`; ту, яку неможливо виконати зі спеки задачі, позначити `excluded` / `manual: <чому>`; повторити `calibrate.sh`, переконатися, що ручні рядки лишились.
- [ ] **Step 4:** для `model-routing`: дерево `fbdd4ae` з тестами проходить усі цілі, дерево `4ab6c1c` (зі спекою з `fbdd4ae`) — жодної (через `make_tree` + `run_oracle` + той самий підрахунок, що в `score.sh`, у scratchpad).
- [ ] **Step 5:** `cp $BENCH_DIR/calibration.log $BENCH_DIR/reports/00-calibration-<plugin_rev>.md` з дописаним зведенням `checks.tsv` (цілі/виключені на задачу, ручні рішення); коміт `chore(bench): recalibrate with per-check targets`; push.
- [ ] **Step 6:** коментар у PR #36: зведення, висновки, пропозиція етапу 1 (`run.sh model-routing plugin 1`, `run.sh model-routing baseline 1`, оцінка ~$3 еквівалента за замірами 2026-11-13). **Зупинка:** етап 1 — лише після явного погодження користувача.
