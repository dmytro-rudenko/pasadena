# Model і effort у frontmatter skills, окремий test writer — design

**Date:** 2026-11-02
**Status:** agreed
**Supersedes:** розділ 2 і рядок «`routine`-задача, весь цикл `amy`» у `docs/sdd/specs/2026-11-01-skill-model-routing.md`

## 1. Problem

Специфікація `2026-11-01-skill-model-routing.md` (PR #22) заборонила `model:` і `effort:`
у frontmatter skills, і `skills/skills.test.sh:161-165` цю заборону перевіряє. Через це
жоден `SKILL.md` не каже, на якій моделі він працює: модель задають лише виклики `Agent`
у `wolowitz`, а skill, викликаний у головній сесії, працює на тому, що вибрав користувач.

Друга причина заборони — `amy` усередині implementer-субагентів. Routine implementer
(`sonnet`/`xhigh`) і complex green (`opus`/`medium`) обидва викликають `amy`, тож фіксоване
значення в її frontmatter перебило б параметри dispatch. Implementer-и завантажують `amy`
з однієї причини: щоб писати тести за її правилами.

## 2. Constraint that shapes the solution

За документацією (https://code.claude.com/docs/en/skills) frontmatter `model` і `effort`
діють до кінця поточного ходу, а наступне повідомлення користувача повертає сесію на її
модель. Повернення на модель користувача вважаємо нормою: skill задає модель для своєї
роботи, а не для сесії.

Конфлікт з `amy` знімається не винятком у frontmatter, а розподілом ролей: тести пише
окремий субагент, який викликає `amy` і працює на її моделі, а код пише implementer, який
`amy` не викликає і працює на моделі зі свого виклику `Agent`. Логіка маршрутизації PR #22
(рівень implementer-а за `**Complexity:**`, тести на Opus high, рев'ю на Sonnet xhigh)
лишається без змін.

Документація не каже, що перемагає всередині субагента: `model` з виклику `Agent` чи
frontmatter skill, який субагент викликав. Тому параметри dispatch test writer-а дорівнюють
frontmatter `amy`, і результат від відповіді не залежить.

## 3. Solution

### 3.1. Frontmatter

Кожен `skills/*/SKILL.md` має у frontmatter рядки `model:` і `effort:` одразу після
`description:`:

| Skill | `model` | `effort` |
|---|---|---|
| `amy` | `opus` | `high` |
| `sheldon` | `opus` | `high` |
| `leonard` | `opus` | `high` |
| `leslie` | `opus` | `high` |
| `wolowitz` | `opus` | `medium` |
| `penny` | `opus` | `medium` |
| `bernie` | `sonnet` | `xhigh` |
| `stuart` | `sonnet` | `xhigh` |
| `pasadena` | `sonnet` | `medium` |
| `raj` | `sonnet` | `medium` |
| `journal` | `sonnet` | `medium` |

Поведінка під час виконання, за документацією:

- override діє до кінця ходу; наступне повідомлення користувача повертає модель сесії;
- коли за один хід викликано кілька skills, діє останній: `pasadena` → `sheldon` іде на
  `opus`/`high`, а `wolowitz` після виклику `leslie` лишається на `opus`/`high` до кінця ходу;
- в auto mode модель, яку auto mode не підтримує, ігнорується, і сесія лишається на своїй.

### 3.2. Ролі в `wolowitz`

Кожна Claude-задача плану виконується двома ролями:

- **Test writer** — `skills/wolowitz/test-writer-prompt.md`. Викликає `pasadena:amy` через
  Skill tool, пише лише тестові файли зі свого `**Writes:**`, запускає verification-команду
  задачі й зупиняється на red, вставивши її вивід у звіт. Production-код не чіпає, навіть щоб
  тест скомпілювався. Зелені кроки й done checklist `amy` належать implementer-у. У раунді
  виправлення тестів production-код уже існує, тож виправлений тест може пройти: test writer
  звітує результат як є і red не домагається. Зміст блоку `## Red dispatch` з поточного
  `implementer-prompt.md` переходить сюди.
- **Implementer** — `skills/wolowitz/implementer-prompt.md`. **Не** викликає `amy` і не
  згадує її. Тести за названими шляхами написав інший субагент, їх checksum записано: він їх
  не редагує й пише мінімум, з яким вони проходять. Якщо тест хибний або для поведінки, яку
  треба написати, тесту немає — звітує `BLOCKED` з тестом і причиною. Правила 1–4 і 6
  поточного промпту лишаються, правило 5 (виклик `amy`) і блоки `## Red dispatch` та
  `## Green dispatch` зникають.

Обидва промпти мають однаковий розділ `## Report back` з поточного `implementer-prompt.md`.

### 3.3. Форми задач

| Форма | Dispatch |
|---|---|
| Task 0 (acceptance-тести) | лише test writer, зупиняється на red, без gates: його red перевіряє верифікація хвилі |
| Звичайна задача: тест і код у `**Writes:**` | test writer → Gate red → implementer → Gate green |
| У `**Writes:**` немає тестового файлу (робить наявні тести зеленими) | лише implementer, без gates |
| Лише покриває наявний код (тести проходять одразу) | лише test writer, за правилами `amy` для наявного коду, без gates |
| `**Executor:** codex` | без змін, `references/codex-tasks.md` |
| `**Executor:** codex`, коли `codex.sh available` повертає ненульовий код | звичайна пара, implementer на рядку `routine` |

Задача mutation-форми (лише покриває наявний код) зберігає поточне правило: її тести
проходять одразу, тож замість зупинки на red test writer доводить кожен тест тимчасовою
мутацією за правилами `amy` для наявного коду і звітує зелену verification-команду. У dispatch під
**Context** сказано, що, всупереч правилу 1, її тимчасова мутація може торкатися коду поза
`**Writes:**`, має бути відкочена до звіту, а файл, який пише інша задача хвилі, — це
`BLOCKED`. Вона йде окремо, після іншої Claude-роботи хвилі й перед Codex-задачами.

### 3.4. Порядок хвилі

Протокол живе в `skills/wolowitz/references/two-dispatch.md`; файл
`references/complex-tasks.md` перейменовано й узагальнено на всі задачі. `SKILL.md` посилається
на `two-dispatch.md` і читає його перед першою хвилею та після compaction. Розділ
`## Complex tasks` у `SKILL.md` стає `## Test writer and implementer` (рішення builder check).

1. Одним повідомленням: усі test writer-и хвилі та задачі форми «лише implementer».
2. **Gate red** для кожної задачі з парою, як зараз у `complex-tasks.md`:
   - звітовані файли — лише тестові файли з `**Writes:**` задачі, а `git status --porcelain`
     не показує змін в інших її файлах;
   - verification-команда червона з причини, яку передбачає план, або з помилки toolchain
     на те, що задача ще має створити; помилка в самому тестовому файлі не рахується;
   - записати `sha256sum` тестових файлів і скопіювати їх у scratchpad.
   Невдалий gate повертається test writer-у через `SendMessage`, не більше двох повторів;
   далі задача йде на round 3 замість свого implementer-а, на тому ж етапі.
3. Одним повідомленням: усі implementer-и задач, що пройшли Gate red, з назвами тестових файлів.
4. **Gate green**: `sha256sum` тестів збігається із записаним; звітовані файли — лише з
   `**Writes:**` задачі, без тестових; verification-команда зелена. При невідповідності
   checksum спершу відновити тести з копії і сказати наступному implementer-у, що їх
   редагували й відновили.
5. Задачі mutation-форми, потім Codex-задачі.
6. Решта хвилі — suite, рев'ю, commit, коментар у PR — без змін.

### 3.5. Fix loop

Один лічильник на задачу рахує кожен невдалий Gate green, звіт `BLOCKED` і раунд рев'ю.

- **Раунди 1–2.** Знахідки щодо коду — implementer-у через `SendMessage`; щодо тестів (хибний
  чи відсутній тест) — test writer-у. Після виправлення тестів: записати checksum заново,
  замінити копію в scratchpad, надіслати implementer-у змінені тести, Gate green. Звітовані
  файли test writer-а знову мають бути лише тестовими. `BLOCKED` з іншої причини, як-от файл
  поза `**Writes:**`, вирішується ruling і раунду не коштує.
- **Фікс від `leslie`** розходиться так само і рахується як раунд.
- **Round 3 — свіжа пара.** Новий test writer отримує поточні тести, відкриті знахідки й
  чесне формулювання «дві попередні спроби на цій задачі не вдалися, ось що пробували».
  Код уже існує, тож red не вимагається: gate перевіряє лише, що змінено тільки тестові файли,
  і записує checksum. Потім новий implementer під Gate green. Задача однієї ролі отримує в
  round 3 свіжого субагента тієї ж ролі.
- `BLOCKED`, що лишився після round 3, — stop gate «broken plan»: тести й код не можуть
  погодитися, пауза й питання користувачу.

### 3.6. Finish

Знахідки whole-branch review і security review, які можна виправити в коді гілки:

- якщо знахідка потребує нового чи зміненого тесту — один test writer отримує всі такі
  знахідки, далі checksum тестів, далі один implementer під Gate green з усіма знахідками;
- якщо знахідки стосуються лише коду — одразу один implementer.

Це єдина whole-branch fix-хвиля. Решта Finish без змін.

### 3.7. Matrix `## Models`

Таблиця в `## Models` файлу `skills/wolowitz/SKILL.md`. Кожен dispatch задає обидва
параметри явно:

| Dispatch | `model` | `effort` |
|---|---|---|
| Test writer: Task 0, red кожної задачі, фікси тестів, round 3, Finish | `opus` | `high` |
| Implementer, `routine` | `sonnet` | `xhigh` |
| Implementer: `complex`, round 3, Finish | `opus` | `medium` |
| Wave reviewer і whole-branch review | `sonnet` | `xhigh` |
| `Explore`, коли `codex.sh available` повертає ненульовий код | `sonnet` | `xhigh` |

`**Complexity:**` з плану `leonard` визначає лише рівень implementer-а; задача без цього
рядка — `complex`. `haiku` не використовується. Builder check у `sheldon` лишається на
`sonnet`/`xhigh`.

### 3.8. Тести

`skills/skills.test.sh`:

- замість заборони на рядках 161-165: frontmatter кожного `SKILL.md` має `model:` зі значенням
  `opus` або `sonnet` і `effort:` зі значенням `low`, `medium`, `high`, `xhigh` або `max`;
- точні значення кожного skill з таблиці 3.1;
- `wolowitz` містить рядки matrix 3.7 і не містить ``whole `amy` cycle``;
- `test-writer-prompt.md` існує й містить `pasadena:amy`; `implementer-prompt.md` не містить
  `amy`, `## Red dispatch` і `## Green dispatch`;
- `wolowitz` посилається на `references/two-dispatch.md`, який містить `Gate red` і
  `Gate green`; `references/complex-tasks.md` не існує;
- `"version": "0.15.0"` у `.claude-plugin/plugin.json` і `.claude-plugin/marketplace.json`;
- рядки таблиць моделей в обох README;
- наявна межа 20 000 байт для `SKILL.md` лишається.

### 3.9. Документи й версія

- `README.md` і `README.uk.md`, розділ `## Models`: дві таблиці — frontmatter (3.1) і
  matrix dispatch (3.7); речення про те, що головна сесія лишається на налаштуваннях
  користувача, прибрати; речення про advisor лишити.
- `docs/sdd/specs/2026-11-01-skill-model-routing.md`: рядок `**Status:**` отримує посилання на
  цю специфікацію як таку, що замінює її розділ 2 і рядок про весь цикл `amy`.
- Версія плагіна `0.15.0`.

## 4. Out of scope

- Codex-задачі, `implementer-prompt-codex.md`, `references/codex-tasks.md`, `hooks/codex.sh`.
- `reviewer-prompt.md` і рев'ю.
- Розділ «Without subagents» у `wolowitz`: головна сесія сама проходить цикл `amy`.
- Формат плану `leonard`, зокрема поле `**Complexity:**` і його критерії, хоча один із них
  («у репозиторії немає прикладу для тесту») тепер стосується test writer-а, а не рівня
  implementer-а (рішення builder check).
- Advisor, `haiku`, `context: fork` для skills.

## 5. Trade-offs accepted

- Кожна routine-задача тепер іде двома dispatch з gates, а всі тести пишуться на
  `opus`/`high` замість `sonnet`/`xhigh`: хвиля довша й дорожча. Натомість тести завжди пише
  сильніша модель під правилами `amy`, а код не може підігнати тест під себе.
- Frontmatter перемикає модель головної сесії на хід: `bernie` переведе сесію на `sonnet`,
  навіть якщо користувач на `opus`.
- Правило «діє останній викликаний skill» означає, що `wolowitz` після `leslie` до кінця ходу
  працює на `opus`/`high`.
- Що перемагає в субагенті — `Agent` чи frontmatter — не перевірено; ризик закрито
  однаковими значеннями для test writer-а.
- В auto mode і на Bedrock, Vertex та Foundry значення можуть ігноруватися або
  не підтримувати `xhigh`.

## 6. Verification

1. `bash skills/skills.test.sh`, `bash hooks/journal.test.sh`, `bash hooks/codex.test.sh`,
   `bash hooks/nudge.test.sh` — зелені.
2. Вручну після встановлення `0.15.0`:
   - у сесії на `sonnet` викликати `/pasadena:sheldon`: індикатор моделі показує `opus`, а
     після наступного повідомлення — знову `sonnet`;
   - план із Task 0, однією `routine` і однією `complex` задачею, що створює новий код:
     у кожному виклику `Agent` `model`/`effort` збігаються з 3.7; test writer викликав `amy`,
     implementer — ні; тест, змінений implementer-ом, відновлено з копії.
