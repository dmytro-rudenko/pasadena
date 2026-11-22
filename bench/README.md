# Pasadena benchmark

Чи покращують skills Pasadena результат агента? Цей харнес проганяє Claude Code
на складних задачах [Terminal-Bench 2.0](https://tbench.ai) через
[Harbor](https://github.com/harbor-framework/harbor) двома arm:

- **baseline** — інтерактивний `claude` без skills;
- **pasadena** — той самий `claude` із встановленим плагіном Pasadena. Задача
  передається як `/pasadena:pasadena <instruction>` з короткою преамбулою
  (повний workflow, файли workflow у `/tmp/pasadena`, без push і PR).

Обидва arm запускають справжній TUI Claude Code у tmux у контейнері задачі
(`bench/tui_agent.py`), тож доступні plan mode і `AskUserQuestion`, як у
людини. Arm відрізняються лише плагіном. Модель, версія Claude Code, задачі,
таймаути і `-k` беруться з одного `bench/config.json`.

Людини в бенчмарку немає, її замінює скриптований користувач
(`bench/tui_policy.py`), однаковий для обох arm:

- у списку з `(Recommended)` натискає номер рекомендованого варіанта;
- на «Would you like to proceed?» (схвалення плану) натискає `1`;
- в інших меню натискає Enter;
- коли Claude закінчив хід і питає (`?` в останньому рядку або фрази на кшталт
  «let me know», «shall I»), відповідає «continue with the recommended option»,
  не більше 5 разів;
- чекає до 10 хв, поки працюють фонові задачі; збій API чи ліміт — infra error.

Тож бенчмарк міряє workflow без живого рецензента. Кожна дія користувача зі
знімком екрана пишеться в `agent/driver.log` trial, транскрипт сесії — в
`agent/sessions/projects/`. Старі job із headless `claude --print` у
порівняння не потрапляють.

Дизайн: `docs/sdd/specs/2026-11-22-real-benchmark.md`,
`docs/sdd/specs/2026-11-22-tui-benchmark.md`.

## Підготовка

1. Docker. Якщо Docker Desktop вимкнено, а системний демон працює, додайте
   до команд `DOCKER_CONTEXT=default`.
2. Токен: виконайте `claude setup-token` і покладіть результат у `bench/.env`:

   ```
   CLAUDE_CODE_OAUTH_TOKEN=...
   ```

   Підійде й `ANTHROPIC_API_KEY=...`. Файл `bench/.env` у `.gitignore`.
3. Диск: кожна задача тягне свій образ `alexgshaw/<task>` (0.1–1.5 GB), і
   Harbor не видаляє скачані образи. Для `bench:select` (89 задач) потрібно
   ~40 GB або періодичне `docker rmi` образів задач, чиї trial уже мають
   `result.json`.
4. `npm run bench:setup` ставить Harbor 0.27.0 у `.bench/venv` і перевіряє
   Docker і токен. Якщо все гаразд, друкує `bench: ready (harbor 0.27.0)`.

## Запуск

```
npm run bench:select     # один раз: baseline на всіх 89 задачах (-k 1) → bench/tasks.txt
npm run bench            # baseline, потім pasadena, потім compare
```

Або по кроках: `npm run bench:baseline`, `npm run bench:pasadena`,
`npm run bench:compare`. Звіт пишеться в `bench/results/summary.md`.
`npm run bench:artifacts` витягує з логів останнього pasadena-job спеки, плани
й інші файли, які агент записав у `/tmp/pasadena` контейнера, у
`bench/results/artifacts/<trial>/`.

Опції `bench:baseline` / `bench:pasadena` (після `--`):

| опція | що робить |
|---|---|
| `--task <name>` | одна задача, job `smoke-…`; `compare` його ігнорує |
| `-k N` | кількість спроб замість `attempts` з конфігу |
| `--fresh` | новий job замість продовження старого |
| `--dry-run` | надрукувати команду `harbor run` і вийти |

Smoke-приклад: `npm run bench:pasadena -- --task build-pmars -k 1`.

**Resume.** Назва job — це хеш конфігу, задач, аргументів і, для pasadena,
вмісту плагіна та `bench/pasadena_{wrap,agent}.py`. Повторний виклик з тими самими входами продовжує той самий
job: готові trial не перераховуються. Зміна skills дає новий job, тож старі
trial не змішуються з новими.

Тести харнесу, без мережі й Docker: `npm run bench:test`.

## Як читати `summary.md`

- **pass rate** — пройдені trial / валідні trial, з 95% інтервалом Wilson.
- **infra error** — trial без валідного reward. Сюди входять збій Docker чи
  setup, помилки API (rate limit, overload) і невстановлений плагін
  (`PasadenaPluginMissingError`). Infra error не входить у знаменник і
  показаний окремо. Таймаут агента — це звичайний fail.
- **Задачі** — по кожній задачі `x/k` для обох arm і знак Δ.
- **Вердикт** — «різниця значуща», лише коли інтервали Wilson не
  перетинаються.
- Рядки `УВАГА:` — брудне дерево git, незавершений job, невстановлений
  плагін, помітно різна кількість валідних trial.

На ~15 задачах по 3 спроби інтервали широкі, тож бенчмарк помітить лише
великий ефект. Відсутність значущої різниці не доводить, що ефекту немає.
