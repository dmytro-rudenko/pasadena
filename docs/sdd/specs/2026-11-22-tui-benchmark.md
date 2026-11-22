# Бенчмарк у справжньому TUI Claude Code — design

**Date:** 2026-11-22
**Status:** agreed
**Supersedes:** розділи про агента в `docs/sdd/specs/2026-11-22-real-benchmark.md` (§3.5, обидва arm). Решта тієї спеки — Terminal-Bench 2.0 через Harbor 0.27.0, `bench/config.json`, `select`, `compare.py`, resume — лишається чинною.

## 1. Problem

Обидва arm зараз запускаються агентом Harbor `claude-code`, тобто headless `claude --print`. У такій сесії Claude Code не показує `EnterPlanMode`, `ExitPlanMode` і `AskUserQuestion` (перевірено за init-подією smoke-trial: 23 інструменти, цих трьох немає). Pasadena спирається саме на них: `leonard` планує в plan mode, `sheldon` питає через `AskUserQuestion`. У smoke-логу агент пише «`EnterPlanMode` isn't exposed in this session, so I'm using the chat fallback». Отже, бенчмарк міряє не той workflow, яким користується людина. Зібрані дані (baseline 18 trial, pasadena 4) отримано в headless-режимі; у порівнянні вони не використовуються.

## 2. Constraint that shapes the solution

Агент мусить працювати в тому самому інтерактивному TUI, що й у людини, з усіма інструментами. Людини в бенчмарку немає, тому її замінює скриптований «користувач», який читає екран tmux і відповідає за фіксованими правилами. Модель у ролі користувача відкинуто: вона дорожча, недетермінована і додає другу змінну в порівняння.

Harbor лишається: він дає контейнер задачі, verifier, resume і `trajectory.json`. Замінюється лише агент. Писати власний запуск контейнерів і перевірку означало б переробити те, що вже працює, не наблизивши середовище до реального.

Spike (throwaway, у контейнері `alexgshaw/polyglot-rust-c:20251031`, Claude Code 2.1.330, tmux 3.4) підтвердив:

- `claude --dangerously-skip-permissions` під root працює лише з `IS_SANDBOX=1`.
- Перший старт показує онбординг (вибір теми), діалог довіри до теки і попередження bypass-режиму. Їх прибирає наперед записаний конфіг: у `.claude.json` — `"hasCompletedOnboarding": true`, `"theme": "dark"`, `"projects": {"<cwd>": {"hasTrustDialogAccepted": true, "hasCompletedProjectOnboarding": true}}`; у `settings.json` — `"skipDangerousModePermissionPrompt": true`.
- `AskUserQuestion` малює пронумерований список; рекомендований варіант має текст `(Recommended)`; клавіша з номером варіанта обирає його.
- `ExitPlanMode` малює «Would you like to proceed?» і варіант `1. Yes, and switch to BYPASS PERMISSIONS …`; клавіша `1` підтверджує план, після чого агент виконує його.
- `tmux load-buffer` + `paste-buffer -p` (bracketed paste) вставляє багаторядковий текст одним повідомленням; `send-keys Enter` відправляє.
- Хук `Stop` у `settings.json` отримує на stdin JSON з `last_assistant_message`, `transcript_path`, `background_tasks`. Це надійний сигнал кінця ходу; у полі вводу TUI буває підказка-привид (`❯ cat a.txt`), тож за екраном кінець ходу не визначається.
- `EnterPlanMode` у bypass-режимі не показує окремого діалогу згоди: після вибору варіанта `AskUserQuestion` наступним екраном одразу був план із «Would you like to proceed?».

Знімки екранів spike, на яких побудовано правила (тексти дослівно, порожні рядки прибрано):

```
 ☐ File name
Which file name should I use?
❯ 1. a.txt (Recommended)
     Write the file as a.txt
  2. b.txt
     Write the file as b.txt
  3. Type something.
  4. Chat about this
Enter to select · ↑/↓ to navigate · Esc to cancel
```

```
   Claude has written up a plan and is ready to execute. Would you like to proceed?
   ❯ 1. Yes, and switch to BYPASS PERMISSIONS (no further prompts) for this session
     2. Yes, manually approve edits
     3. Tell Claude what to change
        shift+tab to approve with this feedback
```

```
✻ Crunched for 5s · done 4:32 PM
❯ cat a.txt
  ⏵⏵ bypass permissions on (shift+tab to cycle)
```

## 3. Solution

### 3.1 Що прибирається

- Arm baseline більше не використовує вбудований агент Harbor `claude-code`.
- З преамбули pasadena зникають інструкції «treat every approval gate as approved / answer with the recommended option»: тепер це робить скриптований користувач, так само для обох arm.

### 3.2 Модулі

**`bench/tui_policy.py`** — чиста функція рішення, без I/O.
- `decide(screen: str, stop: dict | None, failure: dict | None, nudges: int, idle_s: float) -> Action`. `stop` — останній ще не оброблений рядок `stops.jsonl`; `failure` — останній рядок `failures.jsonl` (хук `StopFailure`); `idle_s` — секунд від появи `stop`.
- `Action` — один із: `Keys(keys: str)`, `Paste(text: str)`, `Wait()`, `Done()`, `Fail(reason: str)`.
- Правила, у порядку перевірки:
  0. `failure is not None` → `Fail(failure["error"])` (рішення builder check: збій API чи ліміт — infra error, а не fail задачі).
  1. На екрані є рядок, що містить `(Recommended)` і починається з номера варіанта (`❯ 1.` або `  2.` тощо) → `Keys("<номер>")`.
  2. На екрані є `Would you like to proceed?` → `Keys("1")`.
  3. На екрані є `Enter to select` або `Enter to confirm` (інше меню без рекомендації) → `Keys("Enter")`.
  4. `stop is None` → `Wait()`.
  5. `stop["background_tasks"]` непорожній і `idle_s < BACKGROUND_WAIT_S` → `Wait()`.
  6. `stop["last_assistant_message"]` просить відповіді і `nudges < MAX_NUDGES` → `Paste(NUDGE)`. «Просить відповіді» — останній непорожній рядок містить `?`, або текст повідомлення (без урахування регістру) містить одну з фраз `ASK_PHRASES`. Правило однакове для обох arm.
  7. Інакше → `Done()`.
- Константи: `MAX_NUDGES = 5`; `BACKGROUND_WAIT_S = 600`; `ASK_PHRASES = ("let me know", "tell me", "your approval", "approve", "would you like", "shall i", "should i", "ready to proceed", "before we move on", "before i continue")`; `NUDGE = "No human is available to answer. Take that as approval: continue with the recommended option until the task is finished and verified."`

**`bench/tui_agent.py`** — агент Harbor `TuiClaudeCode(ClaudeCode)`, `name()` → `"tui-claude-code"`.
- `install` = `ClaudeCode.install` плюс `apt-get install -y tmux` (або `apk add tmux` на Alpine — та сама гілка дистрибутивів, що в `ClaudeCode.install`).
- `run(instruction, environment, context)`:
  1. Пише в `CLAUDE_CONFIG_DIR=/logs/agent/sessions` файли `.claude.json` і `settings.json` з §2, де `<cwd>` — робоча тека задачі, а хук `Stop` дописує свій stdin одним рядком у `/logs/agent/stops.jsonl`.
  2. Запускає `tmux new-session -d -s cc -x 200 -y 50` з env `IS_SANDBOX=1`, `CLAUDE_CONFIG_DIR`, змінними автентифікації (`_resolve_auth_env()`), командою `claude --dangerously-skip-permissions --model <model>`.
  3. Чекає, поки на екрані з'явиться `bypass permissions on` (до 60 с, інакше `TuiStartError`).
  4. Надсилає перше повідомлення: `self.command()` (рядок без переносів, напр. `/pasadena:pasadena `) — набором клавіш `send-keys -l`, далі `self.prompt(instruction)` — bracketed paste, потім Enter. Slash-команда набирається, а не вставляється, бо довгу вставку TUI може згорнути в `[Pasted text #1]` (рішення builder check; перевіряється smoke §6.3).
  5. Цикл кожні 2 с: `capture-pane -p`, нові рядки `stops.jsonl` і `failures.jsonl`, `decide(...)`; виконує дію; кожну дію разом зі знімком екрана пише в `/logs/agent/driver.log`. Кожен `stop` обробляється один раз: після будь-якої дії, крім `Wait`, він вважається спожитим. `Paste` збільшує лічильник `nudges`. `Done` завершує цикл. `Fail` піднімає `TuiApiError(reason)`.
  6. Таймаут задачі обмежує цикл ззовні (Harbor), як і для headless-агента.
- `command()` у `TuiClaudeCode` повертає `""`, `prompt(instruction)` — інструкцію без змін.
- Хуки в `settings.json`: `Stop` → `/logs/agent/stops.jsonl`, `StopFailure` → `/logs/agent/failures.jsonl` (один JSON-рядок на подію).
- Метрики: `populate_context_post_run` успадковується; Harbor бере транскрипт сесії з `/logs/agent/sessions/projects/…` і оцінює токени й вартість із нього.

**`bench/pasadena_agent.py`** — `PasadenaClaudeCode(TuiClaudeCode)`, `name()` → `"pasadena-claude-code"`. Перед стартом TUI встановлює плагін так само, як зараз (`install_command`, `PasadenaPluginMissingError`). `command()` = `"/pasadena:pasadena "`, `prompt(instruction)` = `instruction + "\n\n" + PREAMBLE`; `wrap()` зникає.

**`bench/pasadena_wrap.py`** — `PREAMBLE` скорочується до операційних обмежень контейнера:
```
Run the full workflow: pasadena:sheldon with the Architectural path, then pasadena:leonard, then pasadena:wolowitz.
Invoke each skill with the Skill tool and do not skip a phase, however
small the task looks.
Work in the current directory without creating a worktree. Keep every
workflow file (spec, plan, journal) under /tmp/pasadena, outside the task
directory; if git is unavailable there, skip commits and the journal.
Do not open pull requests or push.
```

**`bench/run.sh`** — `baseline` → `-a bench.tui_agent:TuiClaudeCode`. У хеш job для обох arm додаються `bench/tui_agent.py` і `bench/tui_policy.py`; для pasadena, як і досі, ще плагін і `bench/pasadena_{wrap,agent}.py`. Нові job отримують нові імена, тож старі headless-job не продовжуються.

**`bench/artifacts.py`** — читає також транскрипти сесії `*/agent/sessions/projects/*/*.jsonl` (той самий формат `message.content[].tool_use`).

### 3.3 Дані

- `bench/tasks.txt` — ті самі 10 задач.
- Старі job (`full-baseline-1301285b`, `full-pasadena-8cfd7396`, `select-*`) лишаються на диску і в порівняння не потрапляють: `compare.py` бере найновіший `full-<arm>-*`.
- `compare.py` додатково відмовляється порівнювати пару, якщо агенти arm різних типів: у `bench-meta.json` з'являється поле `"agent"` (`"tui"`), і різні значення → exit 1 з `agent` у stderr.

### 3.4 Збої

- TUI не стартував за 60 с → `TuiStartError`; збій API, rate limit чи вичерпаний ліміт підписки (хук `StopFailure`) → `TuiApiError`. Обидва — infra error: `compare.py` додає їх до `INFRA_TYPES`.
- Невідомий діалог, що не підпадає під правила 1–3, зависне до таймауту задачі й буде звичайним fail; знімки в `driver.log` покажуть, який екран його спричинив.

## 4. Out of scope

- Модель у ролі користувача, правки до спеки чи плану від «користувача».
- Повторне використання headless-даних.
- Точна вартість: лише оцінка Harbor за транскриптом.
- Звільнення диска Docker Desktop.

## 5. Trade-offs accepted

- Скриптований користувач завжди схвалює й обирає рекомендоване; живий рецензент міг би покращити або погіршити результат. Обидва arm мають ту саму політику.
- Нагадування на питання в кінці ходу (до 5) може змусити baseline зробити зайву роботу; вони однакові для обох arm і записуються в `driver.log`.
- Розбір екрана залежить від тексту TUI версії 2.1.330; версія зафіксована в `bench/config.json`.
- Цикл опитування кожні 2 с додає кілька секунд до trial.

## 5a. Платні прогони

Як і в попередній спеці: налаштування преамбули, нагадувань і правил — не більше 3 платних smoke-ітерацій на arm; після третьої невдалої — зупинка і питання користувачу. Повний прогін (§6.4) окремого підтвердження не потребує: користувач погодив повний прогін і попросив не зупинятися (рішення builder check).

## 6. Verification

1. `npm run bench:test` — `All checks passed.`; серед тестів — таблиця `decide` для кожного правила §3.2 на записаних знімках екрана з spike.
2. `npm run bench:baseline -- --task build-pmars -k 1` — trial з `reward_valid: true`; `agent/driver.log` містить вставку інструкції і `Done`.
3. `npm run bench:pasadena -- --task build-pmars -k 1 --fresh` — trial з `reward_valid: true`; у транскрипті є виклики `EnterPlanMode` і `ExitPlanMode`; `driver.log` містить `Keys("1")` на екрані `Would you like to proceed?`.
4. Повний прогін обох arm на `bench/tasks.txt`, `npm run bench:compare` — `summary.md` з обома arm без `УВАГА: плагін pasadena не встановився`.
