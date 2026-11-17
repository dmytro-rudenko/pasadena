# Згортання субагентів — design

**Date:** 2026-11-17
**Status:** agreed

## 1. Problem

Стаття Anthropic «Building agents: when to fold subagents into your main agent
loop» (2026-10-22) показує: субагенти, що працюють ланцюжком на результаті один
одного, повертають «lossy summary» на кожній передачі і додають затримку;
один цикл зі skills часто дає кращу якість дешевше. Субагенти виправдані лише
для паралельної роботи з контекстами, що відкидаються, виміряного роздуття
контексту та black-box перевірки.

У Pasadena три місця суперечать цьому:

- `skills/wolowitz/references/two-dispatch.md`: кожна задача — пара test
  writer → implementer, тобто два субагенти поспіль на одних і тих самих
  тестах. Implementer отримує тести без міркувань, з якими їх писали.
- `skills/sheldon/SKILL.md:189`: дизайн розбивається на секції, по субагенту
  на кожну, потім їх треба зливати й звіряти інтерфейси — ціна передачі без
  паралельного виграшу, бо відповіді користувача живуть в основному контексті.
- `skills/wolowitz/SKILL.md:47`: «All code edits live in the wave's subagents»
  діє і для хвилі з однією задачею, де паралелізму немає.

## 2. Constraint that shapes the solution

Розділення test writer / implementer існує, щоб implementer не підганяв тести
під реалізацію. Злиття контексту не сміє послабити цей захист. Тому злитий
агент зупиняється на red, контролер незалежно перевіряє і фіксує тести
(Gate red, sha256), і лише потім той самий агент через `SendMessage`
продовжує до green. Субагент лишається доступним після звіту — Gate red уже
так повертає проблеми test writer'у. Оскільки той самий агент тепер знає
реалізацію, яку збирається писати, додається mutation-перевірка на Gate green:
вона ловить тести, слабкі настільки, що реалізація проходить їх і в мутованому
вигляді.

Окремий новий `builder-prompt.md` відкинуто: поведінка та сама, а переписування
двох prompt-файлів і їхніх тестів нічого не дає.

## 3. Solution

### 3.1 Злитий субагент задачі

Файл: `skills/wolowitz/references/two-dispatch.md`.

Прибирається: другий dispatch, стадія «send every paired implementer in one
message», передача тестів новому агенту.

Потік парної задачі:

1. **Red.** Dispatch з `test-writer-prompt.md`, як зараз. Агент зупиняється на
   red і звітує.
2. **Gate red** — без змін: файли звіту — лише тестові файли з `**Writes:**`,
   верифікація червона з передбаченої причини, `sha256sum` записано, копія в
   scratchpad.
3. **Green.** Контролер надсилає тому самому агенту через `SendMessage`
   заповнений `implementer-prompt.md`.
4. **Gate green**: checksum збігається; файли звіту — у `**Writes:**`, без
   тестових; верифікація зелена; потім **mutation**:
   `ub-tools.sh mutator <production-файли задачі з **Writes:**> -- "<команда верифікації задачі>"`.
   Перед цим `ub-tools.sh mutator --scan` відкидає файли з понад 50 sites,
   вони названі в PR-коментарі хвилі.
   - `mutator exit: 0` — gate пройдено.
   - `mutator exit: 3` (survivors) — тестовий фікс тому самому агенту, рахується
     як раунд.
   - `mutator exit: 2` — базові тести впали: `pasadena:leslie`.
   - `unavailable` — крок пропускається, PR-коментар хвилі несе
     `mutator: skipped (<reason>)`. Питання про `ub-tools.sh install` ставиться
     не тут, а один раз у make-it-right, як зараз.

Стадії хвилі: усі злиті агенти й однорольові задачі йдуть одним
повідомленням; коли всі звітували на red — Gate red для кожного; потім
`SendMessage` «green» кожному пройденому агенту (одним повідомленням);
потім Gate green і фікси; потім задачі покриття наявного коду; потім Codex.

**Фікси, раунди 1–2** — тому самому агенту через `SendMessage`:
- кодовий фікс → Gate green;
- тестовий фікс (після `BLOCKED`, review-знахідки, survivors) завжди
  закінчується чекпоінтом: агент змінює лише тести і звітує; контролер
  перевіряє, що файли звіту — лише тести, записує checksum і копію наново,
  потім надсилає «green» → Gate green.

**Раунд 3** — свіжий злитий агент на `opus/high`, отримує поточні тести,
відкриті знахідки і що пробували; далі той самий потік.

Однорольові форми (Task 0, задача без тестового файлу, покриття наявного
коду) лишаються однорольовими. Whole-branch fix wave на Finish і фікс-хвилі
`references/make-it-right.md` переходять на один злитий агент: тестова частина,
чекпоінт, кодова частина. `references/grouped-review.md`: знахідки до задачі
йдуть її злитому агенту; недосяжний агент → свіжий злитий агент.

### 3.2 Моделі

Таблиця **Models** у `skills/wolowitz/SKILL.md`:

| Dispatch | `model` | `effort` |
|---|---|---|
| Злитий агент, `routine` | `sonnet` | `xhigh` |
| Злитий агент, `complex`; раунд 3; Finish | `opus` | `high` |
| Test writer сам: Task 0, покриття наявного коду, тестова половина Codex-задачі | `opus` | `high` |
| Implementer сам (задача без тестового файлу), `routine` | `sonnet` | `xhigh` |
| Implementer сам, `complex` | `opus` | `medium` |
| Wave 0 review і grouped wave review | `sonnet` | `high` |
| Whole-branch review | `sonnet` | `xhigh` |
| `Explore`, коли `codex.sh available` ≠ 0 | `sonnet` | `xhigh` |

### 3.3 Хвиля з однією задачею — inline

`skills/wolowitz/SKILL.md`: хвиля, в якій рівно одна задача з
`**Executor:**` не `codex`, виконується контролером сам через
`pasadena:amy`, без субагента. Контролер застосовує до себе ті самі гейти:
після red — Gate red із checksum і копією, після green — Gate green з
mutation. Раунди 1–2 — його власні, раунд 3 — свіжий злитий агент. Решта
циклу хвилі (verification, review за розкладом, commit, PR-коментар)
незмінна; PR-коментар хвилі каже `inline`. Однорольові форми (Task 0,
покриття наявного коду) теж ідуть inline за правилами amy *(рішення
builder check)*. Правило «All code edits live in
the wave's subagents» отримує цей виняток поруч із **Without subagents**.

`skills/amy/SKILL.md:112–114`: опис «test writer runs your red steps …
implementer who does not load you» замінюється на злитий агент, що виконує
red, стоп на чекпоінті, потім green.

### 3.4 Sheldon без fan-out

`skills/sheldon/SKILL.md`, «Present the design»: кроки 1–2 (outline, по
субагенту на секцію) і рядок «When the design is one or two sections…»
видаляються. Новий порядок: написати секції inline; зібрати відкриті
питання, відповідь на які змінює, що будується; поставити їх одним
`AskUserQuestion`, найважливіше першим (виняток з «one question per
message» лишається); переписати зачеплені секції; показати дизайн і
попросити одне погодження.

### 3.5 Тести і версія

`skills/skills.test.sh`:
- `require sheldon 'one subagent per section, all in parallel'` → перевірка,
  що цього рядка немає;
- `require_ref two-dispatch.md 'SendMessage'` і `'mutator'`;
- `require wolowitz` для правила inline-хвилі з однією задачею.

Версія `0.24.1` → `0.25.0` у `.claude-plugin/plugin.json` і
`.claude-plugin/marketplace.json`.

## 4. Out of scope

- Eval-набір для порівняння до/після злиття.
- Mutation у make-it-right на Finish — лишається як є і ловить міжзадачні
  прогалини.
- Шлях Codex-implementer (`references/codex-tasks.md`,
  `implementer-prompt-codex.md`).
- Builder check у sheldon, reviewer-и в amy і wolowitz — це black-box
  перевірка, вона лишається субагентом.
- Зміст `test-writer-prompt.md` і `implementer-prompt.md`, крім вказівки, що
  implementer-частина може прийти тому самому агенту через `SendMessage`.

## 5. Trade-offs accepted

- Routine-тести пише `sonnet`, не `opus`. Компенсація — mutation на Gate green.
- Кожна парна задача повільніша на прогін mutator.
- Хвиля з однією задачею наповнює контекст контролера; стаття радить
  відокремлювати лише при виміряному роздутті.
- Sheldon пише довший дизайн послідовно — повільніше на кілька секцій, зате
  без звірки інтерфейсів між чернетками.

## 6. Verification

- `bash skills/skills.test.sh` — зелений.
- `grep -n 'one subagent per section' skills/sheldon/SKILL.md` — нічого.
- `grep -n 'SendMessage' skills/wolowitz/references/two-dispatch.md` — потік
  green через `SendMessage`; `grep -n 'mutator' …/two-dispatch.md` — mutation
  на Gate green.
- `grep -n '"version": "0.25.0"' .claude-plugin/*.json` — два рядки.
