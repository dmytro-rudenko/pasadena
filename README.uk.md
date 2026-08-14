> [English](README.md) · Українська

# pasadena

`pasadena`: плагін для Claude Code і Codex, що тримає контекст задачі в гілці, перетворює узгоджений дизайн на план і виконує незалежні задачі паралельно.

## Яку проблему він вирішує

Спека каже, що ви хочете побудувати. Git-історія каже, що ви змерджили. Жодна не каже, де зупинилась робота, що вже перевірили й який файл відкрити далі.

Pasadena зберігає цей контекст у `.pasadena/journal/<гілка>.md`. Журнал живе в гілці задачі та видаляється перед мерджем, коли його корисний підсумок уже перенесено в pull request. Наявні файли `.claude/journal/` лишаються legacy-журналами для читання.

## Процес

У Codex запустіть `$pasadena`, у Claude Code — `/pasadena`, щоб продовжити з поточного етапу гілки. `/bazinga` лишається Claude Code-аліасом.

| Скіл | Робота |
| --- | --- |
| `sheldon` | Визначає обсяг, ставить короткі запитання та пише узгоджену спеку. Для архітектурної роботи спершу створює worktree, журнал і draft PR. |
| `penny` | Збирає два-чотири браузерні прототипи для UI-рішення, перевіряє обраний варіант разом із вами та фіксує рішення. |
| `leonard` | Використовує plan mode Claude Code, щоб перетворити спеку на виконувані задачі та безпечні паралельні хвилі. |
| `wolowitz` | Виконує кожну хвилю, перевіряє результат, рев'ює diff, комітить задачі й пише прогрес у PR. |
| `amy` | Вимагає тест, що падає, перед production-кодом для фіч, багфіксів і рефакторингів. |
| `raj` | Заводить, оновлює, відновлює, передає та закриває журнал сесії. |

Front matter журналу та чекбокси плану містять стан процесу. Pasadena не веде окремий файл статусу.

## Встановлення в Codex

З GitHub додай marketplace і встанови Pasadena:

```bash
codex plugin marketplace add dmytro-rudenko/pasadena
codex plugin add pasadena@pasadena
```

Після встановлення відкрий нову задачу. У `/hooks` переглянь і довір hooks
Pasadena: до цього Codex бачить скіли, але не запускає автоматичне відновлення
журналу, облік commit чи pause-marker. Оновлення:

```bash
codex plugin marketplace upgrade pasadena
codex plugin add pasadena@pasadena
```

## Встановлення в Claude Code

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

У Codex керуйте журналом через `$journal start`, `$journal note`, `$journal pause` або `$journal finish`; у Claude Code лишається `/journal`.

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

Codex використовує три hooks; Claude Code додає `StopFailure`:

| Подія | Codex | Claude Code |
| --- | --- | --- |
| `SessionStart` | Відновлює контекст журналу й пропонує його завести в гілці задачі. | Те саме |
| `PostToolUse` | Додає коміти, що з'явилися після останнього запису. | Те саме |
| `SessionEnd` | Додає паузу з HEAD і брудними файлами. | Те саме |
| `StopFailure` | — | Додає тип помилки. |

Хуки читають Git-стан і дописують журнал. Git-історію та індекс вони не змінюють.

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

## Браузерні прототипи

`penny` підіймає локальний Node-сервер без залежностей лише на час рев'ю прототипа. Він слухає loopback, вимагає ключ сесії для першого запиту та зберігає рантайм-стан у git-ігнорованій `.sdd/`. Файли прототипів і рішення лишаються в `docs/sdd/proto/` для рев'ю.

Сервер використовує `fetch` для виборів і опитування раз на секунду для оновлень. Так він обходиться без WebSocket-залежності.

## Перевірки

```bash
bash hooks/journal.test.sh
bash proto/server.test.sh
```

Перша перевірка створює тимчасові Git-репозиторії та покриває визначення гілки, контекст продовження, коміти, паузи й формат журналу. Друга перевіряє автентифікацію сервера, захист від обходу каталогу, події, опитування та зупинку.

Повний дизайн: [docs/design.md](docs/design.md).

## Ліцензія

Pasadena ліцензований під MIT. Модифіковані частини `proto/server.cjs` і `proto/frame.css` походять з obra/superpowers; дивіться [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md).
