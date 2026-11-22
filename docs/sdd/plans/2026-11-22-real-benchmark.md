# Real benchmark (Pasadena vs baseline) — implementation plan

**Goal:** `npm run bench:*` проганяє Terminal-Bench 2.0 через Harbor 0.27.0 двома arm (`baseline`, `pasadena`), а `bench/results/summary.md` показує різницю pass rate з інтервалами Wilson, таблицю Δ по задачах і вердикт.
**Spec:** docs/sdd/specs/2026-11-22-real-benchmark.md
**Verification:** `bash bench/acceptance.test.sh && npm run --silent bench:test` → останній рядок `All checks passed.`; далі платні кроки Task 7–8.
Codex budget: weekly 59% left, reserve 10%, 6/8 tasks to codex (estimate 6%). Task 7–8 віддано claude: їм потрібні Docker, мережа і токен.

## Context

Ми хочемо дізнатися, чи покращують skills Pasadena результат агента. Спеку погоджено, draft PR #42 відкрито. Що Harbor 0.27.0 уміє, звірено за кодом у venv:
- `ClaudeCode.run(instruction, environment, context)` (`agents/installed/claude_code.py:2109`) ставить `CLAUDE_CONFIG_DIR=/logs/agent/sessions` (`:2139`) і передає інструкцію в `claude --print` (`:2198`).
- `environment.upload_dir(src, dst)` (`environments/base.py:1202`) і `self.exec_as_agent(environment, command=, env=)` (`agents/installed/base.py:1117`) потрібні для встановлення плагіна.
- `--agent-import-path` застарів (`cli/trials.py:728`). Свій агент передається як `-a module:Class`, модуль імпортується з `PYTHONPATH`.
- Job лежить у `<jobs-dir>/<job-name>/`, там `config.json` і по теці на кожен trial з `result.json` (`models/trial/paths.py:291`).
- Поля trial `result.json`: `task_name`, `reward_valid` (computed, `models/trial/result.py:144`), `verifier_result.rewards` (dict), `agent_result.{n_input_tokens,n_cache_tokens,n_output_tokens,cost_usd}`, `agent_execution.{started_at,finished_at}`, `exception_info.exception_type`.
- Resume: ім'я є і `config.json` збігається → resume. Конфіг інший → `FileExistsError` (`job.py:316`). Файли, що не є теками, в job dir ігноруються (`job.py:322`).
- Невідомий виняток має `has_valid_reward=True` (`models/trial/error_policy.py:31`). Через це падіння через відсутній плагін окремо ловить `compare.py`.

## Global constraints

- Обидва arm читають один `bench/config.json`:
  `{"dataset":"terminal-bench@2.0","model":"anthropic/claude-opus-5-5","attempts":3,"concurrency":4,"agentTimeoutMultiplier":1.0,"hardSetMax":15,"retries":2,"harborVersion":"0.27.0","claudeCodeVersion":"2.1.330"}`.
- Python: тільки stdlib, `python3` системний. Harbor живе лише в `.bench/venv`.
- Shell-скрипти: `#!/usr/bin/env bash`, `set -euo pipefail`. Тести: `set -uo pipefail` і `assert_*`, як у `hooks/journal.test.sh:9-38`; наприкінці `FAILED: N` / `All checks passed.`.
- Env-перевизначення для тестів: `BENCH_DIR` (дефолт `<repo>/.bench`), `BENCH_CONFIG`, `BENCH_TASKS`, `BENCH_PLUGIN_ROOT` (дефолт `<repo>`).
- Плагін-теки: `.claude-plugin skills hooks commands proto`. Marketplace і plugin звуться `pasadena` (`.claude-plugin/marketplace.json:2,10`), тому команда встановлення `claude plugin install pasadena@pasadena`.
- Коментарі в коді: нуль, крім неочевидних обмежень.
- Версію плагіна не бампаємо: `bench/` і `package.json` не входять у плагін-теки, тож установлена копія не змінюється.
- Infra error — це `reward_valid == false` або `exception_info.exception_type == "PasadenaPluginMissingError"`.

## Review Focus

1. Збій установки плагіна в усіх trial не має перетворитися на «pasadena 0%». `compare.py` рахує такі trial як infra error і пише `УВАГА` в шапку.
2. `-k` після `--` має потрапити і в команду, і в `bench-meta.json.attempts`, інакше пара arm хибно пройде валідацію.
3. Задача з одним валідним trial і другим infra не має ділити на 2.
4. `--fresh` має давати нове ім'я, а не продовжувати старий job.
5. `select.sh` не має чіпати `tasks.txt`, якщо baseline-job нічого не повернув (немає trial).

## Waves

| Wave | Tasks | Why together |
|---|---|---|
| 0 | 0 | alone — acceptance tests, red until the last wave |
| 1 | 1 | alone — `common.sh`, `config.json` і `package.json` читають усі |
| 2 | 2, 3, 4, 5 | disjoint: `setup.sh` / `run.sh` / `compare.py`+fixtures / `pasadena_*.py` |
| 3 | 6 | `select.sh` споживає `run.sh --print-job-name` (Task 3) і `compare.py --failed` (Task 4) |
| 4 | 7 | smoke: потрібні всі скрипти і агент |
| 5 | 8 | повний прогін тільки після smoke і погодження вартості |

Серіалізовано: Task 6 після 3 і 4 (інтерфейси); Task 7–8 послідовно, бо вони платні і друга спирається на вартість першої.

---

### Task 0: acceptance tests

**Writes:** `bench/acceptance.test.sh`
**Executor:** claude
**Covers:** «`npm run bench:test` завершується з кодом `0`»; «`npm run bench:setup` … без токена виходить з кодом `1` та поясненням»; «`npm run bench:pasadena -- --dry-run` друкує команду з `-a bench.pasadena_agent:PasadenaClaudeCode` і тими самими `-m/-k/-n/-i`, що й `npm run bench:baseline -- --dry-run`»; «після `npm run bench` файл `bench/results/summary.md` містить обидва arm, таблицю Δ і рядок вердикту» (на fixture-jobs). Smoke (Verification 4) перевіряє Task 7, бо він платний.

- [x] **Step 1: write the acceptance tests** — `bench/acceptance.test.sh`:
```bash
#!/usr/bin/env bash
set -uo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
fails=0
ok()   { echo "  ok  — $1"; }
bad()  { echo "  FAIL — $1"; fails=$((fails + 1)); }
tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT

(cd "$ROOT" && npm run --silent bench:test >/dev/null 2>&1) && ok "bench:test exits 0" || bad "bench:test exits 0"

mkdir -p "$tmp/venv/bin" "$tmp/stub"
printf '#!/usr/bin/env bash\necho 0.27.0\n' >"$tmp/venv/bin/harbor"; chmod +x "$tmp/venv/bin/harbor"
printf '#!/usr/bin/env bash\nexit 0\n' >"$tmp/stub/docker"; chmod +x "$tmp/stub/docker"
out="$(cd "$ROOT" && env -u ANTHROPIC_API_KEY -u CLAUDE_CODE_OAUTH_TOKEN PATH="$tmp/stub:$PATH" BENCH_DIR="$tmp" BENCH_ENV_FILE="$tmp/none.env" npm run --silent bench:setup 2>&1)"; rc=$?
[ "$rc" = 1 ] && ok "setup without token exits 1" || bad "setup without token exits 1 (rc=$rc)"
[[ "$out" == *"CLAUDE_CODE_OAUTH_TOKEN"* ]] && ok "setup explains the token" || bad "setup explains the token: $out"

printf 'task-a\ntask-b\n' >"$tmp/tasks.txt"
b="$(cd "$ROOT" && BENCH_TASKS="$tmp/tasks.txt" BENCH_DIR="$tmp" npm run --silent bench:baseline -- --dry-run 2>&1)"
p="$(cd "$ROOT" && BENCH_TASKS="$tmp/tasks.txt" BENCH_DIR="$tmp" npm run --silent bench:pasadena -- --dry-run 2>&1)"
[[ "$p" == *"-a bench.pasadena_agent:PasadenaClaudeCode"* ]] && ok "pasadena dry-run uses the custom agent" || bad "pasadena dry-run uses the custom agent: $p"
[[ "$b" == *"-a claude-code"* ]] && ok "baseline dry-run uses claude-code" || bad "baseline dry-run uses claude-code: $b"
norm() { sed -E 's/ -a [^ ]+//; s/ --job-name [^ ]+//' <<<"$1"; }
[ "$(norm "$b")" = "$(norm "$p")" ] && ok "arms share -m/-k/-n/-i" || bad "arms differ beyond -a/--job-name"

(cd "$ROOT" && python3 bench/compare.py --jobs-dir bench/fixtures/jobs --out "$tmp/summary.md" >/dev/null 2>&1)
s="$(cat "$tmp/summary.md" 2>/dev/null)"
for want in "| baseline |" "| pasadena |" "| задача | baseline x/k | pasadena x/k | Δ |" "**Вердикт:**"; do
  [[ "$s" == *"$want"* ]] && ok "summary has $want" || bad "summary has $want"
done

echo
[ "$fails" -gt 0 ] && { echo "FAILED: $fails"; exit 1; }
echo "All checks passed."
```
- [x] **Step 2: run them, watch them fail** — `bash bench/acceptance.test.sh`, expect a last line starting with `FAILED:`, because `package.json` and `bench/*` don't exist yet.

---

### Task 1: каркас — config, npm-скрипти, common.sh, runner тестів

**Writes:** `package.json`, `bench/config.json`, `bench/tasks.txt`, `bench/common.sh`, `bench/bench.test.sh`, `bench/tests/common.test.sh`, `.gitignore`, `docs/sdd/specs/2026-11-22-real-benchmark.md`
**Reads:** `hooks/journal.test.sh`
**Depends on:** Task 0
**Executor:** codex
**Complexity:** routine
**Satisfies:** — (основа для інших; acceptance лишається червоним)
**Interfaces:**
- Produces: `bench/common.sh` з `BENCH_ROOT`, `REPO_ROOT`, `BENCH_DIR`, `BENCH_CONFIG`, `BENCH_TASKS`, `BENCH_PLUGIN_ROOT`, `BENCH_ENV_FILE`, `HARBOR`, функціями `cfg <key>`, `require_venv`, `load_env`. `bench/bench.test.sh` по черзі запускає кожен `bench/tests/*.test.sh` і падає, якщо впав хоч один.

- [x] **Step 1: write the failing test** — `bench/tests/common.test.sh`:
```bash
#!/usr/bin/env bash
set -uo pipefail
HERE="$(cd "$(dirname "$0")/.." && pwd)"; fails=0
assert_eq() { if [ "$1" = "$2" ]; then echo "  ok  — $3"; else echo "  FAIL — $3 (expected '$2', got '$1')"; fails=$((fails+1)); fi; }
. "$HERE/common.sh"
assert_eq "$(cfg harborVersion)" "0.27.0" "cfg reads harborVersion"
assert_eq "$(cfg attempts)" "3" "cfg reads attempts"
out="$(BENCH_DIR="$(mktemp -d)" bash -c ". '$HERE/common.sh'; require_venv" 2>&1)"; rc=$?
assert_eq "$rc" "1" "require_venv fails without venv"
[[ "$out" == *"npm run bench:setup"* ]] && echo "  ok  — require_venv names bench:setup" || { echo "  FAIL — require_venv hint"; fails=$((fails+1)); }
echo; [ "$fails" -gt 0 ] && { echo "FAILED: $fails"; exit 1; }; echo "All checks passed."
```
- [x] **Step 2: run it, watch it fail** — `bash bench/tests/common.test.sh`, expect `No such file` for `common.sh`.
- [x] **Step 3: implement**
  - `bench/config.json`: точно JSON з Global constraints, з відступом у 2 пробіли.
  - `bench/tasks.txt`: порожній файл.
  - `package.json`:
```json
{
  "name": "pasadena-bench",
  "private": true,
  "scripts": {
    "bench:setup": "bash bench/setup.sh",
    "bench:select": "bash bench/select.sh",
    "bench:baseline": "bash bench/run.sh --arm baseline",
    "bench:pasadena": "bash bench/run.sh --arm pasadena",
    "bench:compare": "python3 bench/compare.py",
    "bench:test": "bash bench/bench.test.sh",
    "bench": "npm run bench:baseline && npm run bench:pasadena && npm run bench:compare"
  }
}
```
  - `bench/common.sh`:
```bash
BENCH_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$BENCH_ROOT/.." && pwd)"
BENCH_DIR="${BENCH_DIR:-$REPO_ROOT/.bench}"
BENCH_CONFIG="${BENCH_CONFIG:-$BENCH_ROOT/config.json}"
BENCH_TASKS="${BENCH_TASKS:-$BENCH_ROOT/tasks.txt}"
BENCH_PLUGIN_ROOT="${BENCH_PLUGIN_ROOT:-$REPO_ROOT}"
BENCH_ENV_FILE="${BENCH_ENV_FILE:-$BENCH_ROOT/.env}"
HARBOR="$BENCH_DIR/venv/bin/harbor"

cfg() { python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))[sys.argv[2]])' "$BENCH_CONFIG" "$1"; }
require_venv() { [ -x "$HARBOR" ] || { echo "bench: $BENCH_DIR/venv is missing — run: npm run bench:setup" >&2; exit 1; }; }
load_env() { if [ -f "$BENCH_ENV_FILE" ]; then set -a; . "$BENCH_ENV_FILE"; set +a; fi; }
```
  - `bench/bench.test.sh`:
```bash
#!/usr/bin/env bash
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"; failed=0
for t in "$HERE"/tests/*.test.sh; do echo "== ${t##*/}"; bash "$t" || failed=$((failed+1)); done
echo; [ "$failed" -gt 0 ] && { echo "FAILED: $failed"; exit 1; }; echo "All checks passed."
```
  - `.gitignore`: дописати `.bench/` і `bench/.env`.
  - Спека: у §3.5 рядок `- pasadena: \`--agent-import-path bench.pasadena_agent:PasadenaClaudeCode\`.` замінити на `- pasadena: \`-a bench.pasadena_agent:PasadenaClaudeCode\` з \`PYTHONPATH=<repo>\` (\`--agent-import-path\` застарів у Harbor 0.27).`; у §6 п.3 `--agent-import-path` замінити на `-a`.
- [x] **Step 4: run it, watch it pass** — `bash bench/tests/common.test.sh`, expect `All checks passed.`

---

### Task 2: `bench/setup.sh`

**Writes:** `bench/setup.sh`, `bench/tests/setup.test.sh`
**Depends on:** Task 1
**Executor:** codex
**Complexity:** routine
**Satisfies:** acceptance «setup without token exits 1», «setup explains the token»
**Interfaces:**
- Consumes: `bench/common.sh` (`cfg`, `HARBOR`, `BENCH_DIR`, `load_env`, `BENCH_ENV_FILE`).

- [x] **Step 1: write the failing test** — `bench/tests/setup.test.sh` (стиль `hooks/journal.test.sh`). Кожен кейс у тимчасовому `BENCH_DIR`, з `BENCH_ENV_FILE=$tmp/none.env` і стабами в `PATH`:
  1. стаб `docker`, що виходить з кодом `1` → rc `1`, stderr містить `Docker`;
  2. стаб `docker` з кодом `0`, фейковий `$BENCH_DIR/venv/bin/harbor`, що друкує `0.27.0`, без токенів (`env -u ANTHROPIC_API_KEY -u CLAUDE_CODE_OAUTH_TOKEN`) → rc `1`, stderr містить `CLAUDE_CODE_OAUTH_TOKEN` і `claude setup-token`;
  3. те саме з `CLAUDE_CODE_OAUTH_TOKEN=x` → rc `0`, stdout `bench: ready (harbor 0.27.0)`;
  4. токен у файлі `BENCH_ENV_FILE` (`CLAUDE_CODE_OAUTH_TOKEN=x`) → rc `0`.
- [x] **Step 2: run it, watch it fail** — `bash bench/tests/setup.test.sh`, expect `FAILED: 4`.
- [x] **Step 3: implement** — `bench/setup.sh`:
```bash
#!/usr/bin/env bash
set -euo pipefail
. "$(cd "$(dirname "$0")" && pwd)/common.sh"
if ! command -v docker >/dev/null 2>&1 || ! docker info >/dev/null 2>&1; then
  echo "bench: Docker is not available or not running" >&2; exit 1
fi
want="$(cfg harborVersion)"
if [ ! -x "$HARBOR" ] || [ "$("$HARBOR" --version 2>/dev/null)" != "$want" ]; then
  python3 -m venv "$BENCH_DIR/venv"
  "$BENCH_DIR/venv/bin/pip" install -q "harbor==$want"
fi
load_env
if [ -z "${ANTHROPIC_API_KEY:-}" ] && [ -z "${CLAUDE_CODE_OAUTH_TOKEN:-}" ]; then
  echo "bench: set ANTHROPIC_API_KEY or CLAUDE_CODE_OAUTH_TOKEN (get one with 'claude setup-token') in the environment or $BENCH_ENV_FILE" >&2
  exit 1
fi
echo "bench: ready (harbor $want)"
```
- [x] **Step 4: run it, watch it pass** — expect `All checks passed.`

---

### Task 3: `bench/run.sh`

**Writes:** `bench/run.sh`, `bench/tests/run.test.sh`
**Depends on:** Task 1
**Executor:** codex
**Complexity:** complex
**Satisfies:** acceptance «pasadena dry-run uses the custom agent», «baseline dry-run uses claude-code», «arms share -m/-k/-n/-i»
**Interfaces:**
- Consumes: `bench/common.sh`.
- Produces: CLI `run.sh --arm baseline|pasadena [--kind full|select] [--all-tasks] [--task NAME] [--fresh] [--dry-run] [--print-job-name] [passthrough...]`. Ім'я job: `<kind>-<arm>-<hash8>[-<YYYYmmddHHMMSS>]`; `--task` ставить kind `smoke`. Перед `harbor run` пише `$BENCH_DIR/jobs/<job>/bench-meta.json`:
  `{"arm","kind","hash","args":[passthrough],"tasks":[...] або ["*"],"attempts":int,"claudeCodeVersion","pluginContentHash":str|null,"gitSha","gitDirty":bool,"createdAt":"<UTC ISO, Z>"}`.

- [x] **Step 1: write the failing test** — `bench/tests/run.test.sh`. `BENCH_DIR`, `BENCH_TASKS` і `BENCH_PLUGIN_ROOT` тимчасові; plugin root — копія `.claude-plugin skills hooks commands proto` з репо. Кейси:
  1. `--arm baseline --dry-run` містить `-a claude-code`, `-d terminal-bench@2.0`, `-m anthropic/claude-opus-5-5`, `-k 3`, `-n 4`, `-r 2`, `--agent-timeout-multiplier 1.0`, `--ak version=2.1.330`, `-o $BENCH_DIR/jobs`, `--job-name full-baseline-`, `-i task-a -i task-b`;
  2. `--arm pasadena --dry-run` містить `-a bench.pasadena_agent:PasadenaClaudeCode` і `--job-name full-pasadena-`;
  3. два однакові виклики `--print-job-name` дають однакове ім'я; зміна `tasks.txt` дає інше;
  4. дописування рядка у файл `skills/` в plugin root змінює ім'я pasadena і не змінює ім'я baseline;
  5. `--fresh --print-job-name` дає ім'я з суфіксом `-[0-9]{14}`;
  6. `--task x --dry-run` містить рівно один `-i x` і `--job-name smoke-`;
  7. порожній `tasks.txt` → rc `1`, stderr `npm run bench:select`;
  8. `-- -k 1 --dry-run`… (passthrough `-k 1`) → у команді `-k 1`, а не `-k 3`;
  9. `--kind select --all-tasks --dry-run` без `-i`, з `--job-name select-baseline-`;
  10. без venv і без `--dry-run`/`--print-job-name` → rc `1` з `npm run bench:setup`;
  11. з фейковим `$BENCH_DIR/venv/bin/harbor` (стаб пише argv у файл і виходить з `0`) запуск пише `bench-meta.json` з `"attempts": 3`, `"arm": "pasadena"` і непорожнім `pluginContentHash`.
- [x] **Step 2: run it, watch it fail** — expect `FAILED:`.
- [x] **Step 3: implement** — `bench/run.sh`:
```bash
#!/usr/bin/env bash
set -euo pipefail
. "$(cd "$(dirname "$0")" && pwd)/common.sh"

arm=""; kind="full"; all_tasks=0; task=""; fresh=0; dry=0; print_name=0; pass=()
attempts="$(cfg attempts)"
while [ $# -gt 0 ]; do
  case "$1" in
    --arm) arm="$2"; shift 2 ;;
    --kind) kind="$2"; shift 2 ;;
    --all-tasks) all_tasks=1; shift ;;
    --task) task="$2"; kind="smoke"; shift 2 ;;
    --fresh) fresh=1; shift ;;
    --dry-run) dry=1; shift ;;
    --print-job-name) print_name=1; shift ;;
    -k|--n-attempts) attempts="$2"; shift 2 ;;
    --) shift ;;
    *) pass+=("$1"); shift ;;
  esac
done
case "$arm" in baseline|pasadena) ;; *) echo "bench: --arm baseline|pasadena is required" >&2; exit 2 ;; esac

tasks=()
if [ -n "$task" ]; then tasks=("$task")
elif [ "$all_tasks" = 0 ]; then
  while IFS= read -r t; do [ -n "$t" ] && tasks+=("$t"); done <"$BENCH_TASKS"
  [ "${#tasks[@]}" -gt 0 ] || { echo "bench: $BENCH_TASKS is empty — run: npm run bench:select" >&2; exit 1; }
fi

plugin_hash=""
if [ "$arm" = pasadena ]; then
  plugin_hash="$(cd "$BENCH_PLUGIN_ROOT" && find .claude-plugin skills hooks commands proto -type f -print0 | sort -z | xargs -0 sha256sum | sha256sum | cut -c1-64)"
fi
hash="$({ cat "$BENCH_CONFIG"; printf '%s\n' "${tasks[@]:-*}"; echo "$attempts"; printf '%s\n' "${pass[@]:-}"; echo "$plugin_hash"; } | sha256sum | cut -c1-8)"
job="$kind-$arm-$hash"; [ "$fresh" = 1 ] && job="$job-$(date -u +%Y%m%d%H%M%S)"
[ "$print_name" = 1 ] && { echo "$job"; exit 0; }

if [ "$arm" = baseline ]; then agent=(-a claude-code); else agent=(-a bench.pasadena_agent:PasadenaClaudeCode); fi
cmd=("$HARBOR" run -d "$(cfg dataset)" -m "$(cfg model)" -k "$attempts" -n "$(cfg concurrency)" -r "$(cfg retries)"
     --agent-timeout-multiplier "$(cfg agentTimeoutMultiplier)" --ak "version=$(cfg claudeCodeVersion)"
     -o "$BENCH_DIR/jobs" --job-name "$job" "${agent[@]}")
for t in "${tasks[@]:-}"; do [ -n "$t" ] && cmd+=(-i "$t"); done
cmd+=("${pass[@]:-}"); [ -z "${cmd[-1]}" ] && unset 'cmd[-1]'

if [ "$dry" = 1 ]; then echo "${cmd[*]}"; exit 0; fi
require_venv; load_env
mkdir -p "$BENCH_DIR/jobs/$job"
python3 - "$BENCH_DIR/jobs/$job/bench-meta.json" "$arm" "$kind" "$hash" "$attempts" "$(cfg claudeCodeVersion)" "$plugin_hash" \
  "$(git -C "$REPO_ROOT" rev-parse HEAD)" "$(git -C "$REPO_ROOT" status --porcelain | head -c1)" "${#tasks[@]}" "${tasks[@]:-}" "--" "${pass[@]:-}" <<'PY'
import json, sys, datetime
a = sys.argv[1:]; out, arm, kind, h, att, ccv, ph, sha, dirty, n = a[:10]
rest = a[10:]; n = int(n); tasks = [t for t in rest[:n] if t]; args = [x for x in rest[n + 1:] if x]
json.dump({"arm": arm, "kind": kind, "hash": h, "args": args, "tasks": tasks or ["*"], "attempts": int(att),
           "claudeCodeVersion": ccv, "pluginContentHash": ph or None, "gitSha": sha, "gitDirty": bool(dirty),
           "createdAt": datetime.datetime.now(datetime.UTC).strftime("%Y-%m-%dT%H:%M:%SZ")}, open(out, "w"), indent=2)
PY
PYTHONPATH="$REPO_ROOT${PYTHONPATH:+:$PYTHONPATH}" exec "${cmd[@]}"
```
  Пастка порожніх масивів під `set -u`: якщо `${arr[@]:-}` дає порожній елемент, його відкидати, як показано вище. Тест 8 це перевіряє.
- [x] **Step 4: run it, watch it pass** — `bash bench/tests/run.test.sh`, expect `All checks passed.`

---

### Task 4: `bench/compare.py` + fixtures

**Writes:** `bench/compare.py`, `bench/tests/compare.test.sh`, `bench/fixtures/jobs/**`, `bench/fixtures/jobs-mismatch/**`
**Depends on:** Task 1
**Executor:** codex
**Complexity:** complex
**Satisfies:** acceptance «summary has | baseline | / | pasadena | / таблиця Δ / **Вердикт:**»
**Interfaces:**
- Consumes: layout `bench-meta.json` з Task 3, trial `result.json` Harbor (поля в Context).
- Produces: `python3 bench/compare.py [--jobs-dir D=.bench/jobs] [--out F=bench/results/summary.md]` і `python3 bench/compare.py --failed <jobdir> --max N`. Останній друкує по рядку назви задач, у яких є ≥1 валідний trial і жоден не пройшов, відсортовані, не більше N. Exit `1`, якщо trial немає.

- [x] **Step 1: fixtures** — у `bench/fixtures/jobs/`:
  - `full-baseline-aaaa1111/bench-meta.json`: `{"arm":"baseline","kind":"full","hash":"aaaa1111","args":[],"tasks":["task-a","task-b","task-c"],"attempts":2,"claudeCodeVersion":"2.1.330","pluginContentHash":null,"gitSha":"abc1234","gitDirty":false,"createdAt":"2026-11-22T10:00:00Z"}`;
  - `full-pasadena-bbbb2222/bench-meta.json`: те саме, але `arm:"pasadena"`, `hash:"bbbb2222"`, `pluginContentHash:"ff"`, `createdAt:"2026-11-22T11:00:00Z"`;
  - `smoke-pasadena-cccc3333/bench-meta.json`: `kind:"smoke"`, `tasks:["task-a"]`, `createdAt:"2026-11-22T12:00:00Z"` і один trial з reward 0. Він має ігноруватися.
  - trial-теки `<task>__<n>/result.json` мінімального вигляду:
    `{"task_name":"task-a","reward_valid":true,"verifier_result":{"rewards":{"reward":1}},"agent_result":{"n_input_tokens":1000,"n_cache_tokens":0,"n_output_tokens":100,"cost_usd":0.5},"agent_execution":{"started_at":"2026-11-22T10:00:00Z","finished_at":"2026-11-22T10:01:40Z"},"exception_info":null}`.
    baseline: task-a 0,0; task-b 1,0; task-c 0 і один infra (`reward_valid:false`, `verifier_result:null`, `exception_info.exception_type:"ApiRateLimitError"`).
    pasadena: task-a 1,1; task-b 1,1; task-c 0,0.
  - `bench/fixtures/jobs-mismatch/`: копія двох full-job, у pasadena `tasks:["task-a","task-b"]`.
  - `bench/fixtures/jobs-plugin-missing/`: baseline як вище; pasadena з одним trial `exception_info.exception_type:"PasadenaPluginMissingError"`, `reward_valid:true`, reward 0.
- [x] **Step 2: write the failing test** — `bench/tests/compare.test.sh` запускає `compare.py --jobs-dir bench/fixtures/jobs --out $tmp/s.md` і перевіряє rc `0` та підрядки:
  `| baseline | 1/5 (20.0%) | 3.6–62.4% |`, `| pasadena | 4/6 (66.7%) | 30.0–90.3% |`, `Δ pass rate (pasadena − baseline): +46.7 п.п.`, `| task-a | 0/2 | 2/2 | + |`, `| task-c | 0/1 | 0/2 | = |`, `Виграші: 2, програші: 0, нічиї: 1`, `infra error` з `1` для baseline, `УВАГА: кількість валідних trial різниться (5 проти 6)`, `**Вердикт:** різниця в межах шуму при N=11 валідних trial.`; рядок `smoke` не з'являється. Далі:
  - `--jobs-dir bench/fixtures/jobs-mismatch` → rc `1`, stderr `tasks`;
  - `--jobs-dir bench/fixtures/jobs-plugin-missing` → rc `0`, summary містить `УВАГА: плагін pasadena не встановився в 1 trial`;
  - порожній jobs dir → rc `1`, stderr `npm run bench:baseline`;
  - `--failed bench/fixtures/jobs/full-baseline-aaaa1111 --max 15` → stdout рівно `task-a\ntask-c`;
  - `--failed … --max 1` → `task-a`.
- [x] **Step 3: run it, watch it fail** — expect `FAILED:`.
- [x] **Step 4: implement** — `bench/compare.py` (stdlib):
```python
#!/usr/bin/env python3
import argparse, json, math, statistics, sys
from datetime import datetime
from pathlib import Path

REPO = Path(__file__).resolve().parent.parent
INFRA_TYPES = {"PasadenaPluginMissingError"}

def wilson(k, n, z=1.96):
    if n == 0:
        return 0.0, 0.0
    p = k / n; d = 1 + z * z / n
    c = (p + z * z / (2 * n)) / d
    h = z * math.sqrt(p * (1 - p) / n + z * z / (4 * n * n)) / d
    return c - h, c + h

def load_trials(job):
    trials = []
    for rp in sorted(job.glob("*/result.json")):
        r = json.loads(rp.read_text())
        exc = (r.get("exception_info") or {}).get("exception_type")
        valid = bool(r.get("reward_valid")) and exc not in INFRA_TYPES
        rewards = (r.get("verifier_result") or {}).get("rewards") or {}
        val = rewards.get("reward", next(iter(rewards.values()), 0))
        ar = r.get("agent_result") or {}
        ex = r.get("agent_execution") or {}
        secs = None
        if ex.get("started_at") and ex.get("finished_at"):
            secs = (datetime.fromisoformat(ex["finished_at"].replace("Z", "+00:00")) - datetime.fromisoformat(ex["started_at"].replace("Z", "+00:00"))).total_seconds()
        trials.append({"task": r["task_name"], "valid": valid, "passed": valid and float(val) >= 1.0,
                       "plugin_missing": exc in INFRA_TYPES, "in": ar.get("n_input_tokens") or 0,
                       "out": ar.get("n_output_tokens") or 0, "cost": ar.get("cost_usd"), "secs": secs,
                       "models": model_usage(rp.parent)})
    return trials

def model_usage(trial_dir):
    log = trial_dir / "agent" / "claude-code.txt"
    if not log.is_file():
        return {}
    usage = {}
    for line in log.read_text(errors="replace").splitlines():
        try:
            ev = json.loads(line)
        except ValueError:
            continue
        if ev.get("type") == "result" and isinstance(ev.get("modelUsage"), dict):
            for m, u in ev["modelUsage"].items():
                usage[m] = usage.get(m, 0) + (u.get("inputTokens") or 0) + (u.get("outputTokens") or 0)
    return usage

def pick(jobs_dir, arm):
    metas = []
    for d in jobs_dir.glob(f"full-{arm}-*"):
        mp = d / "bench-meta.json"
        if mp.is_file():
            metas.append((json.loads(mp.read_text()), d))
    if not metas:
        sys.exit(f"bench: no full {arm} job in {jobs_dir} — run: npm run bench:{arm}")
    return max(metas, key=lambda m: m[0]["createdAt"])
```
  Далі `main()`:
  - argparse з прапорцями зі специфікації інтерфейсу. Гілка `--failed` групує trial за задачею і друкує задачі, де `any(valid) and not any(passed)`, `sorted()[:max]`; без trial — `sys.exit("bench: no trials in <dir>")`.
  - Пара: `pick` для обох arm. Вихід `1`, якщо різняться `set(tasks)`, `attempts` чи `claudeCodeVersion` (stderr називає поле: `tasks`, `attempts`, `claudeCodeVersion`).
  - Звіт у `--out` (створити батьківську теку), рядки точно так:
    - `# Pasadena vs baseline`; далі `- дата: <now UTC ISO>`, `- dataset: …, model: …, attempts: …, claude code: …` (з `bench/config.json`), `- плагін: pasadena <version з .claude-plugin/plugin.json> (git <gitSha[:7]>[, dirty])`, `- задач: <len(tasks)>`;
    - попередження в шапці, кожне з префіксом `УВАГА: `: dirty, незавершений job (`trial < len(tasks)*attempts`: `job <name> незавершений (x з y trial)`), `плагін pasadena не встановився в N trial`, `кількість валідних trial різниться (a проти b)`, якщо `abs(a-b)/max(a,b) > 0.10`;
    - `## Arms`, таблиця з шапкою `| arm | pass rate | 95% Wilson | pass@1 | pass@k | infra error | токени in/out | вартість, $ | медіана trial, с |` і рядками `| baseline | 1/5 (20.0%) | 3.6–62.4% | <pass@1 %> | <pass@k %> | 1 | <in>/<out> | <sum cost або —> | <median secs або —> |`. pass@1 — середня по задачах частка пройдених серед валідних trial; задачі без валідних trial не враховуються. pass@k — частка задач з ≥1 пройденим trial;
    - `Δ pass rate (pasadena − baseline): +46.7 п.п.` (знак `+` або `−`, один знак після коми);
    - `## Задачі`, шапка `| задача | baseline x/k | pasadena x/k | Δ |`, рядок на задачу (sorted), `x/k` = пройдені/валідні, Δ `+` / `−` / `=` за порівнянням часток (0/0 = частка 0); далі `Виграші: W, програші: L, нічиї: T`;
    - `## Моделі`, для кожного arm `- <arm>: model=tokens, …` або `- <arm>: недоступно`;
    - останній рядок `**Вердикт:** різниця значуща (інтервали Wilson не перетинаються).` або `**Вердикт:** різниця в межах шуму при N=<a+b> валідних trial.`
  - Друкує шлях до звіту.
- [x] **Step 5: run it, watch it pass** — `bash bench/tests/compare.test.sh`, expect `All checks passed.`

---

### Task 5: агент Pasadena

**Writes:** `bench/pasadena_wrap.py`, `bench/pasadena_agent.py`, `bench/tests/agent.test.sh`
**Depends on:** Task 1
**Executor:** codex
**Complexity:** complex
**Satisfies:** — (Verification 4 перевіряє Task 7)
**Interfaces:**
- Produces: `bench.pasadena_wrap` з `PREAMBLE`, `PLUGIN_DIRS = (".claude-plugin", "skills", "hooks", "commands", "proto")`, `REMOTE_ROOT = "/opt/pasadena"`, `wrap(instruction) -> str`, `install_command(config_dir) -> str`; `bench.pasadena_agent.PasadenaClaudeCode` (підклас `harbor.agents.installed.claude_code.ClaudeCode`); виняток `PasadenaPluginMissingError`.

- [x] **Step 1: write the failing test** — `bench/tests/agent.test.sh`, з кореня репо через `PYTHONPATH=.`:
  - `python3 -c 'from bench.pasadena_wrap import wrap; print(wrap("fix X"))'` починається з `/pasadena:pasadena fix X` і містить `No human is available during this run.` та `Do not open pull requests or push.`;
  - `install_command("/logs/agent/sessions")` містить `export CLAUDE_CONFIG_DIR=/logs/agent/sessions`, `claude plugin marketplace add /opt/pasadena`, `claude plugin install pasadena@pasadena`, `claude plugin list`;
  - якщо є `.bench/venv/bin/python`: `.bench/venv/bin/python -c 'from bench.pasadena_agent import PasadenaClaudeCode; from harbor.agents.installed.claude_code import ClaudeCode; assert issubclass(PasadenaClaudeCode, ClaudeCode)'` виходить з `0`; інакше рядок `  skip — harbor venv absent`.
- [x] **Step 2: run it, watch it fail** — expect `FAILED:`.
- [x] **Step 3: implement**
  - `bench/pasadena_wrap.py`:
```python
import shlex

PLUGIN_DIRS = (".claude-plugin", "skills", "hooks", "commands", "proto")
REMOTE_ROOT = "/opt/pasadena"
PREAMBLE = (
    "No human is available during this run. Treat every approval gate as\n"
    "approved, answer every question with the recommended option, and carry\n"
    "the workflow through to a finished, verified result in this environment.\n"
    "Do not open pull requests or push."
)

def wrap(instruction: str) -> str:
    return f"/pasadena:pasadena {instruction}\n\n{PREAMBLE}"

def install_command(config_dir: str) -> str:
    q = shlex.quote(config_dir)
    return (
        'export PATH="$HOME/.local/bin:$PATH"; '
        f"export CLAUDE_CONFIG_DIR={q}; mkdir -p \"$CLAUDE_CONFIG_DIR\" && "
        f"claude plugin marketplace add {REMOTE_ROOT} && "
        "claude plugin install pasadena@pasadena && "
        "claude plugin list | grep -q pasadena"
    )
```
  - `bench/pasadena_agent.py`:
```python
from pathlib import Path

from harbor.agents.installed.claude_code import ClaudeCode

from bench.pasadena_wrap import PLUGIN_DIRS, REMOTE_ROOT, install_command, wrap

REPO = Path(__file__).resolve().parent.parent


class PasadenaPluginMissingError(RuntimeError):
    pass


class PasadenaClaudeCode(ClaudeCode):
    @staticmethod
    def name() -> str:
        return "pasadena-claude-code"

    async def run(self, instruction, environment, context) -> None:
        for d in PLUGIN_DIRS:
            await environment.upload_dir(REPO / d, f"{REMOTE_ROOT}/{d}")
        sessions = (self.environment_logs_dir / "sessions").as_posix()
        try:
            await self.exec_as_agent(environment, command=install_command(sessions), env=self._resolve_auth_env())
        except Exception as e:
            raise PasadenaPluginMissingError(f"pasadena plugin not installed: {e}") from e
        await super().run(wrap(instruction), environment, context)
```
  Якщо `name()` у базовому класі має інший декоратор або сигнатуру (`claude_code.py:309`), повторити його.
- [x] **Step 4: run it, watch it pass** — expect `All checks passed.`

---

### Task 6: `bench/select.sh`

**Writes:** `bench/select.sh`, `bench/tests/select.test.sh`
**Depends on:** Task 3, Task 4
**Executor:** codex
**Complexity:** routine
**Interfaces:**
- Consumes: `run.sh --arm baseline --kind select --all-tasks -k 1 [--print-job-name|--dry-run]` (Task 3); `compare.py --failed <jobdir> --max N` (Task 4).

- [x] **Step 1: write the failing test** — `bench/tests/select.test.sh`:
  1. `bash bench/select.sh --dry-run` друкує команду з `--job-name select-baseline-`, `-k 1`, без `-i`;
  2. тимчасовий `BENCH_DIR` зі стабом `venv/bin/harbor`, що виходить з `0`; заздалегідь у `$BENCH_DIR/jobs/<ім'я з run.sh --print-job-name>` скопійовано trial-теки з `bench/fixtures/jobs/full-baseline-aaaa1111/`. Тоді `BENCH_TASKS=$tmp/tasks.txt bash bench/select.sh` пише `task-a\ntask-c`;
  3. те саме з порожнім job (стаб не створює trial) → rc `1`, а наявний `$tmp/tasks.txt` (`keep`) лишається незмінним.
- [x] **Step 2: run it, watch it fail** — expect `FAILED:`.
- [x] **Step 3: implement**
```bash
#!/usr/bin/env bash
set -euo pipefail
. "$(cd "$(dirname "$0")" && pwd)/common.sh"
args=(--arm baseline --kind select --all-tasks -k 1)
for a in "$@"; do [ "$a" = --dry-run ] && exec bash "$BENCH_ROOT/run.sh" "${args[@]}" "$@"; done
job="$(bash "$BENCH_ROOT/run.sh" "${args[@]}" "$@" --print-job-name)"
bash "$BENCH_ROOT/run.sh" "${args[@]}" "$@"
tmp="$(mktemp)"
python3 "$BENCH_ROOT/compare.py" --failed "$BENCH_DIR/jobs/$job" --max "$(cfg hardSetMax)" >"$tmp" || { rm -f "$tmp"; exit 1; }
mv "$tmp" "$BENCH_TASKS"
echo "bench: $(wc -l <"$BENCH_TASKS") tasks written to $BENCH_TASKS"
```
- [x] **Step 4: run it, watch it pass** — expect `All checks passed.`

---

### Task 7: README + smoke обох arm (платно, ≤4 trial)

**Writes:** `bench/README.md`, `bench/pasadena_wrap.py`, `bench/tests/agent.test.sh`, `bench/run.sh`, `bench/tests/run.test.sh`, `bench/results/summary.md` (останні п'ять — лише якщо smoke вимагає налаштування)
**Depends on:** Task 2, 3, 4, 5, 6
**Executor:** claude (Docker, мережа, токен)
**Complexity:** complex
**Satisfies:** acceptance «bench:test exits 0» (тепер усе зелене); Verification 2, 4

- [x] **Step 1: README** — `bench/README.md` українською:
  - що міряємо, два arm і чому auto-approve;
  - підготовка: Docker, `claude setup-token` → `CLAUDE_CODE_OAUTH_TOKEN=…` у `bench/.env`, `npm run bench:setup`;
  - порядок `bench:select` → `bench` (або `bench:baseline`/`bench:pasadena`/`bench:compare`);
  - `--task`, `--fresh`, `--dry-run`, `-- -k N`, resume;
  - що таке infra error;
  - як читати `summary.md`;
  - обмеження малого N.
- [x] **Step 2: acceptance зелений** — `bash bench/acceptance.test.sh`, expect `All checks passed.`
- [x] **Step 3: setup** — `npm run bench:setup`. Без токена очікується rc `1` з поясненням (Verification 2). Тоді один `AskUserQuestion`: попросити користувача виконати `! claude setup-token` і покласти токен у `bench/.env`. Після цього повторити: expect `bench: ready (harbor 0.27.0)`.
- [x] **Step 4: smoke-задача** — `.bench/venv/bin/harbor datasets` / `harbor tasks list -d terminal-bench@2.0` (точну підкоманду дивитися в `--help`). Взяти першу за алфавітом задачу з категорією software-engineering і записати її назву в README як smoke-приклад.
- [x] **Step 5: smoke baseline** — `npm run bench:baseline -- --task <smoke> -k 1`; переконатися, що trial має `result.json` з `reward_valid: true`. Записати `cost_usd`.
- [x] **Step 6: smoke pasadena (≤3 ітерації)** — `npm run bench:pasadena -- --task <smoke> -k 1 --fresh`. Зараховано, якщо в `agent/claude-code.txt` trial видно все це:
  - вивід `claude plugin list` з `pasadena` (у логах setup);
  - виклик `/pasadena:pasadena`;
  - пройдений перший gate: створено `docs/sdd/specs/*` або викликано `pasadena:leonard`/`pasadena:wolowitz`, і є зміни коду задачі.

  Якщо workflow зупинився на gate:
  - правити `PREAMBLE` у `bench/pasadena_wrap.py` разом з `bench/tests/agent.test.sh`;
  - за потреби додати `--ak append_system_prompt=<той самий текст>` у `run.sh` лише для pasadena — окремим комітом, з оновленням тесту 2 у `run.test.sh`;
  - повторити.

  Після 3 невдач записати факт у `bench/results/summary.md` (розділ `## Smoke`) і зупинитися з `AskUserQuestion`.
- [x] **Step 7: run it, watch it pass** — `npm run --silent bench:test`, expect `All checks passed.`

---

### Task 8: повний прогін і звіт (платно)

**Writes:** `bench/tasks.txt`, `bench/results/summary.md`
**Depends on:** Task 7
**Executor:** claude
**Complexity:** complex

- [ ] **Step 1: оцінка вартості** — з smoke: `c_b` = `cost_usd` baseline, `c_p` = `cost_usd` pasadena. Оцінка = `89·c_b + 15·3·c_b + 15·3·c_p`. Показати користувачу одним `AskUserQuestion`: «запустити повний прогін (~$X, ~Y год при `-n 4`)» з рекомендованою опцією «так». Без «так» далі не йти.
- [ ] **Step 2: select** — `npm run bench:select`; expect `bench: N tasks written`, 1 ≤ N ≤ 15. Закомітити `bench/tasks.txt`.
- [ ] **Step 3: arms** — `npm run bench:baseline`, потім `npm run bench:pasadena`. Якщо щось перервалося, повторний виклик продовжує той самий job.
- [ ] **Step 4: compare** — `npm run bench:compare`; expect, що `bench/results/summary.md` має обидва arm, таблицю Δ і `**Вердикт:**`, без `УВАГА: плагін pasadena не встановився`.
- [ ] **Step 5: commit** — `bench/results/summary.md`; коротко викласти вердикт у PR-коментарі.
