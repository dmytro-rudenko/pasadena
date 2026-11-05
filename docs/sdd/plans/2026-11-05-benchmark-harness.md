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

- [ ] **Step 1: тест `bench/test/30-run.sh`.**
  - **plugin:** `FAKE_WRITES=… run.sh t1 plugin 1`. `$FAKE_LOG` містить `-p`, `--output-format`, `stream-json`, `--verbose`, `--no-session-persistence`, `--permission-mode`, `bypassPermissions`, `--max-budget-usd`, `15`, `--model`, `sonnet`, `--settings`, `{"enabledPlugins":{"pasadena@pasadena":false,"pasadena@synced":false}}`, `--plugin-dir`, `$tmp/plugin`. Промпт починається з `/pasadena:leonard Plan the implementation of the agreed specification at spec.md`. `.env` має `PASADENA_CODEX=0`, `PASADENA_REUSE=` (порожньо), codex-mode `explore`, `XDG_STATE_HOME` = `<run>/state`.
  - **baseline:** немає `--plugin-dir`, промпт `Implement the specification at spec.md. …`, codex-mode порожній.
  - **plugin-noreuse:** `PASADENA_REUSE=0`. **plugin-haiku:** `--model haiku`.
  - **plugin-codexfull:** з `FAKE_CODEX_AVAILABLE=1` → `last_run .error` = `codex unavailable`, `$FAKE_LOG` порожній; з `0` і `FAKE_CODEX_USED=10` → `codex-before.txt` існує, codex-mode `full`.
  - **ізоляція:** `pwd` з `.env` — `<run>/tree`; фейк пише `$FAKE_LOG.count` = `git rev-list --count HEAD` до своїх змін → `1`.
  - **timeout:** `BENCH_TIMEOUT=1 FAKE_CLAUDE=hang` → `capped:true`, `error:"timeout"`, `oracle.exit` існує.
  - **після прогону:** `<run>/tree` видалено; `diff.patch`, `meta.json`, `base-symbols.txt` лишились; `base-symbols.txt` містить `helper`.
  - **повтор з тим самим ключем:** у `<run>` немає старого маркерного файлу.
  - **невідомі id:** `run.sh nope plugin 1` і `run.sh t1 nope 1` → exit 2.
- [ ] **Step 2: побачити, що падає** — `FAIL — … run`.
- [ ] **Step 3: реалізація** (порядок §3.4):
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
- [ ] **Step 4: побачити, що проходить** — блоки `run` і приймальні тести 1–2 без `FAIL`.

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

- [ ] **Step 1: тест `bench/test/40-calibrate.sh`.** Копія `$tmp/tasks.tsv` у `BENCH_TASKS=$tmp/cal.tsv`:
  - t1 лишається з обома тестами, у лозі `t1 kept`;
  - t4 з `t/missing.test.sh,t/one.test.sh` (missing на oracle не існує й падає) → `tests` = `t/one.test.sh`, лог `dropped-test t/missing.test.sh: fails on oracle`;
  - t5 лише з `t/missing.test.sh` → `holdout` `x`, `no tests left`;
  - t3 на `$ORACLE` як base → `x`, `passes on base`;
  - холдаут t2 з base=`$ORACLE` виключається → холдаутом стає останній рядок з `holdout=0` (t1), лог `holdout moved to t1`;
  - заголовок файлу збережено.
- [ ] **Step 2: побачити, що падає.**
- [ ] **Step 3: реалізація.** Для кожного id з `holdout` 0 або 1: дерево `oracle` у `mktemp -d` → `run_oracle` → лишити шляхи з кодом 0; дерево `base` + `put_oracle_tests` лишених → `run_oracle`; якщо всі 0 → `x`. «Остання за датою» — останній рядок файлу з `holdout=0` (файл упорядковано за датою spec). Запис — через тимчасовий файл і `mv`. Тимчасові дерева видаляються.
- [ ] **Step 4: побачити, що проходить.**

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

- [ ] **Step 1: тест `bench/test/50-matrix.sh`.** `BENCH_RUN=$tmp/fakerun.sh` дописує `$1 $2 $3` у `$tmp/matrix.calls` і рядок `{"task":$1,"config":$2,"rep":$3,"plugin_rev":<rev>,"verdict":"pass"}` у `runs.jsonl`:
  - `--tasks t1 --configs plugin,baseline --reps 2` → 4 виклики;
  - повторний запуск → 0;
  - `--holdout --configs plugin --reps 1` → виклик `t2 plugin 1`;
  - рядок з `verdict:"error"` → не перезапускається без прапорця; з `--retry-errors` перезапускається, у `runs.jsonl` лишається один рядок цього ключа;
  - baseline з іншим `plugin_rev` вважається виконаним;
  - `--pending --tasks t1 --reps 1` на порожньому `runs.jsonl` → 5 рядків і 0 викликів;
  - `--bogus` → exit 2.
- [ ] **Step 2: побачити, що падає.**
- [ ] **Step 3: реалізація.** За замовчуванням: `task_ids 0` (або `task_ids 1` з `--holdout`), `config_names`, `N=3`. Множина виконаних — з `jq -r '[.plugin_rev,.task,.config,(.rep|tostring),.verdict]|@tsv' runs.jsonl`.
- [ ] **Step 4: побачити, що проходить.**

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

- [ ] **Step 1: тест `bench/test/60-report.sh`.** Підготувати `runs.jsonl` вручну: 4 рядки `plugin` (rev `aaa`, 3 pass, 1 fail, costs 1,2,3,10), 2 `baseline` (rev `old`, обидва fail), 1 `plugin` rev `zzz` раніше в файлі. Перевірити:
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
- [ ] **Step 2: побачити, що падає.**
- [ ] **Step 3: реалізація.** Фільтр і агрегати — одним `jq -s`; markdown — `jq -r`/`printf`.
- [ ] **Step 4: побачити, що проходить** — разом із приймальними тестами 4–5 `bash bench/bench.test.sh` → `All checks passed.`

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

- [ ] **Step 1:** `bash bench/bench.test.sh && bash skills/skills.test.sh` — обидва `All checks passed.`
- [ ] **Step 2:** `bash bench/calibrate.sh` (без змінних, реальний репозиторій; лише локальні тести, без `claude`). Exit 0.
- [ ] **Step 3:** `mkdir -p $BENCH_DIR/reports && cp $BENCH_DIR/calibration.log $BENCH_DIR/reports/00-calibration-<plugin_rev>.md`; закомітити зміни `bench/tasks.tsv` (`chore(bench): calibrate oracles`), запушити.
- [ ] **Step 4:** коментар у PR #36: вміст `calibration.log`, таблиця задач після калібрування (лишені тести, виключені й чому, холдаут), висновки агента і пропозиція етапу 1 (два сухі прогони, ≈ до $30 у найгіршому разі, з прогнозом). **Зупинка:** етап 1 не запускається без явного погодження користувача.
