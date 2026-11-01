# Маршрутизація моделей та effort у skills — design

**Date:** 2026-11-01
**Status:** agreed

## 1. Problem

`wolowitz` запускає implementer на моделі сесії (`skills/wolowitz/SKILL.md:70`), а
ревʼю — на `sonnet` з `effort: "xhigh"`. Звідси три проблеми:

- Той самий тариф отримують і рутинна задача, і складна, і написання тестів.
- Implementer dispatch не задає `effort`. На Opus 5.5 і Sonnet 5.5 дефолт — `medium`,
  тож сесія на `--model sonnet` дала б implementer на Sonnet medium.
- Правила «тести пише Opus high» зараз немає де виразити: один implementer веде
  весь цикл `amy`.

Користувач хоче три комбінації — Sonnet xhigh, Opus medium, Opus high — без Haiku
і з Opus high для написання тестів.

## 2. Constraint that shapes the solution

Очевидний шлях — `claude --model sonnet --advisor opus` плюс `model`/`effort` у
frontmatter skills. Обидві частини не підходять як основа.

**Advisor** (https://code.claude.com/docs/en/advisor):

- вмикається лише на рівні сесії (`--advisor`, `advisorModel`, `/advisor`), skill
  його ввімкнути не може;
- момент виклику обирає модель, ліміту чи примусового виклику немає;
- кожен виклик читає весь transcript без кешу за тарифом advisor;
- субагенти його успадковують;
- недоступний на Bedrock, Vertex і Foundry.

**Frontmatter skill** діє лише до кінця поточного ходу, тому діалоги `sheldon` і
`leonard` втрачають override після першої відповіді користувача. Крім того, `effort`
у `amy` опустив би effort усередині implementer на Sonnet xhigh.

Єдиний механізм, що детерміновано діє на всю делеговану роботу, — явні `model` і
`effort` у виклику Agent. Головна сесія лишається на налаштуваннях користувача.

Твердження «Sonnet xhigh ≈ Opus medium» документацією не підтверджене і в цьому
дизайні є робочою гіпотезою: на нього нічого не спирається, крім вибору Sonnet xhigh
для рутини.

## 3. Solution

### 3.1. Матриця моделей

Таблиця в `## Models` файлу `skills/wolowitz/SKILL.md` не залежить від моделі сесії.
Кожен dispatch задає обидва параметри явно.

| Dispatch | `model` | `effort` |
|---|---|---|
| Task 0 (acceptance-тести) | `opus` | `high` |
| `routine`-задача, весь цикл `amy` | `sonnet` | `xhigh` |
| `complex`-задача, red | `opus` | `high` |
| `complex`-задача, green | `opus` | `medium` |
| Round 3, fresh implementer, зокрема після Codex | `opus` | `medium` |
| Fix dispatch після whole-branch review і security review | `opus` | `medium` |
| Wave reviewer і whole-branch review | `sonnet` | `xhigh` |
| `Explore`, коли `codex.sh available` не виходить з 0 | `sonnet` | `xhigh` |

`haiku` не використовується ніде. Рядок `opus on Opus, fable on Fable` зникає: на
сесії Fable implementers теж ідуть за таблицею.

### 3.2. `leonard`: поле Complexity

Кожна задача, крім Task 0, отримує рядок поруч із `**Executor:**`:

    **Complexity:** routine | complex

`complex` ставиться, коли виконується хоч одна умова:

- задача зачіпає конкурентність, збережений стан або міграції, безпеку;
- задача створює контракт, названий у `**Depends on:**` інших задач, і його форму
  не повністю задано в тексті задачі;
- для її тесту в репозиторії немає зразка.

У разі сумніву ставиться `complex`. Користувач бачить розподіл під час затвердження
плану, як і `**Executor:**`.

До умов `**Executor:** codex` додається одна: `**Complexity:** routine`. Решта умов
не змінюється.

### 3.3. `wolowitz`: виконання

Читання поля:

- `routine` — один implementer, як зараз, на Sonnet xhigh;
- `complex` — два dispatch, описані нижче;
- поля немає — це `complex`. Так поводиться план, написаний до цієї зміни;
- `**Executor:** codex` — розділ **Codex tasks** без змін, Codex сам пише тести.

Хвиля з `complex`-задачами проходить етапами: усі Claude implementers і всі red
паралельно, потім gates, потім усі green паралельно, потім Codex-задачі, як зараз.

Складна задача:

1. **Red.** Dispatch на Opus high. Implementer пише всі тести задачі, виконує її
   verification command і показує red. Production-код не чіпає.
2. **Gate red.** Контролер сам перевіряє те саме, що в **Codex tasks**: змінені
   шляхи — лише тестові файли з `**Writes:**`, команда червона, кожне падіння має
   передбачену планом причину. Записує `sha256sum` тестів і копіює їх у scratchpad.
3. **Green.** Новий dispatch на Opus medium. Implementer отримує шляхи тестів і
   заборону їх змінювати, пише мінімум, щоб вони пройшли.
4. **Gate green.** `sha256sum` збігається, змінені шляхи лежать у `**Writes:**`,
   команда зелена. Далі — звичайні suite, review, commit, коментар у PR.

Збої:

- Gate red не пройшов: зауваження йдуть red-implementer через `SendMessage`, не
  більше двох спроб, далі fresh implementer за рядком Round 3.
- Green вважає тест хибним: звіт `BLOCKED` із причиною, контролер надсилає зауваження
  red-implementer. Після виправлення Gate red виконується знову, а контрольні суми
  записуються заново. Це рахується як раунд.
- Контрольна сума не збігається: контролер відновлює тести з копії в scratchpad, і
  це рахується як раунд.
- Findings ревʼю у fix loop: щодо коду йдуть green-implementer, щодо тестів —
  red-implementer. Раунди 1–2 лишаються на моделі того implementer, якому написано.

`**Without subagents**` не змінюється: контролер працює на моделі сесії без поділу
red/green.

### 3.4. Шаблони implementer

`skills/wolowitz/implementer-prompt.md` отримує два додаткові блоки: **Red dispatch**
(лише тести, зупинитися на red, показати вивід) і **Green dispatch** (тести не
змінювати, `BLOCKED`, якщо тест хибний). Для `routine` і Task 0 шаблон не змінюється.

### 3.5. Документація

`README.md` і `README.uk.md` отримують таблицю моделей і примітку про advisor:

- він необовʼязковий і Pasadena на нього не спирається;
- його три типові моменти вже закриті затвердженням плану, `leslie` і whole-branch
  review;
- субагенти його успадковують, тому Opus-субагент з Opus-advisor дублює витрати.

### 3.6. Версія

`version` стає `0.14.0` у `.claude-plugin/plugin.json` і `.claude-plugin/marketplace.json`.

## 4. Out of scope

- Вбудовування advisor у skills, включно з інструкціями «consult the advisor».
- `model` і `effort` у frontmatter будь-якого skill.
- Зміни `hooks/codex.sh`, модель і effort самого Codex: вони й далі беруться з
  `PASADENA_CODEX_MODEL` або `~/.codex/config.toml`.
- Green на Codex для `complex`-задач.
- Перемикання моделі головної сесії за фазами.
- Зміни моделі для `leslie`, `bernie`, `stuart`, `penny`: вони працюють у сесії.

## 5. Trade-offs accepted

- `complex`-задача коштує двох запусків і подовжує хвилю. Плата за те, що автор
  тестів не підганяє їх під код.
- Тести `routine`-задач пише Sonnet xhigh або Codex, не Opus high. Правило
  «тести — Opus high» діє для Task 0 і `complex`, бо Task 0 фіксує всі критерії
  готовності зі специфікації.
- Усі тести `complex`-задачі пишуться наперед, а не по одному на крок. Це відступ від
  кроків `amy`, прийнятий заради поділу виконавців.
- План без `**Complexity:**` коштує дорожче, зате не втрачає поточної поведінки.
- На сесії Fable implementers працюють нижче моделі сесії.
- На Bedrock, Vertex і Foundry `sonnet` означає Sonnet 4.5 без підтримки effort, тож
  `xhigh` там не діє.

## 6. Verification

1. `bash skills/skills.test.sh` зелений і перевіряє:
   - `skills/wolowitz/SKILL.md` містить кожен рядок матриці з 3.1 і не містить
     `opus on Opus, fable on Fable`;
   - `skills/leonard/SKILL.md` містить `**Complexity:** routine | complex` і умову
     `**Complexity:** routine` для `**Executor:** codex`;
   - `skills/wolowitz/implementer-prompt.md` містить `Red dispatch` і `Green dispatch`;
   - жоден `skills/*/SKILL.md` не має рядка frontmatter `model:` чи `effort:`;
   - обидва README містять таблицю моделей;
   - `plugin.json` і `marketplace.json` мають `0.14.0`.
2. `bash hooks/codex.test.sh` і `bash hooks/journal.test.sh` зелені без змін цих тестів.
3. Ручний прогін: план із Task 0, однією `routine` і однією `complex` задачею.
   Перевірити у виклику Agent, що `model` і `effort` збігаються з таблицею, а зміна
   тесту під час green відновлюється контролером і рахується як раунд.
