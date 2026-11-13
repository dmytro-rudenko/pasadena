# ub-mode і quality gates (dryer, crapper, mutator) — design

**Date:** 2026-11-13
**Status:** agreed

## 1. Problem

Правила про TDD і дублювання в pasadena розкидані й короткі: в `skills/amy/SKILL.md:168-171` весь REFACTOR це один рядок «Remove duplication, improve names, extract helpers», а перевірка якості в `skills/wolowitz/reviewer-prompt.md:33` спирається на око рев'юера («duplication that will drift»). Детермінованих перевірок дублювання, складності й сили тестів у workflow немає.

[ub-mode](https://github.com/unclebob/ub-mode) формулює ці принципи жорсткіше й явніше («First Make it Work, Then Make it Right, Follow Practice») і спирається на три детерміновані інструменти того ж автора: [dryer](https://github.com/unclebob/dryer) (структурні дублікати), [crapper](https://github.com/unclebob/crapper) (CRAP = складність × непокритість) і [mutator](https://github.com/unclebob/mutator) (mutation testing).

## 2. Constraint that shapes the solution

**Інструменти не рівні щодо Node.js, а плагін не може вимагати від користувача ні Python-venv, ні нову команду.**

Перевірено 2026-11-13 на чистій системі (Python 3.14, Node 26):

- **TypeScript:** dryer, crapper і mutator підтримують `.ts/.tsx/.mts/.cts`.
- **Чистий JS (`.js/.jsx/.mjs/.cjs`):** crapper і mutator підтримують (`discover.py` відображає їх на `typescript`; тести через `npm test`, Vitest, c8). **dryer не підтримує:** його `EXTENSIONS` JS не містить, і файли пропускаються мовчки, без попередження. Експеримент: два ідентичні `.ts` знайдено зі score 1.00, чотири ідентичні `.js/.mjs/.cjs/.jsx` не знайдено взагалі. dryer пропускає також `.d.ts`, тести та `node_modules`, `dist`, `build`, `target`, `coverage`.
- **Запуск:** лаунчери `./dryer`, `./crapper`, `./mutator` роблять `python3 -m venv` і падають на Debian/Ubuntu без пакета `python3-venv` (перевірено: `ensurepip is not available`). `pip install --target <dir>` без venv працює. mutator вимагає, щоб crapper був або встановлений, або лежав поруч у `../crapper`.
- **Побічні ефекти:** інструменти пишуть `.metrics/`, `target/`, `coverage/` у корінь проєкту. crapper видаляє попередні coverage-звіти і для Vitest доставляє `@vitest/coverage-v8` у `node_modules` (без змін `package.json`). Перший запуск тягне граматики tree-sitter з мережі.

Через це відкинуто:

- **Вендорити інструменти в плагін:** ~100 КБ Python на інструмент і залежності, розбіжність з upstream.
- **Окремий скіл `ub-mode` поруч із нашим флоу:** дублює TDD/DRY у двох місцях з різними формулюваннями.
- **Чекати, поки dryer навчиться JS:** користувач вирішив обмежитися TypeScript, а JS-файли лише попереджати.

## 3. Solution

### 3.1. `hooks/ub-tools.sh`

Bash, `set -uo pipefail`, у стилі `hooks/reuse.sh`. Завжди завершується з `exit 0`: збій інструмента не ламає сесію, результат читається з виводу. Підкоманди: `install`, `dryer`, `crapper`, `mutator`.

**Пошук інструмента** (для кожного з трьох, у порядку): змінна `PASADENA_DRYER` / `PASADENA_CRAPPER` / `PASADENA_MUTATOR` (шлях до виконуваного файлу), потім `command -v <імʼя>`, потім копія в `${XDG_DATA_HOME:-$HOME/.local/share}/pasadena/ub-tools/`. Якщо не знайдено або немає `python3` ≥ 3.11, підкоманда друкує один рядок `<tool>: unavailable (<причина>)` і виходить з 0.

**`install`.** Клонує три репозиторії `unclebob/dryer`, `unclebob/crapper`, `unclebob/mutator` на SHA, зафіксовані константами в скрипті, у `…/ub-tools/src/`, і ставить їх `python3 -m pip install --target …/ub-tools/lib <три шляхи>` (без venv). Запускає інструменти через `PYTHONPATH=…/lib python3 -m <tool>`. Скіл викликає `install` лише після явної згоди користувача, бо це завантаження й виконання стороннього коду. Якщо немає `git` чи мережі, `install` друкує причину й виходить з 0.

**`dryer <path>...`.** Запускає `--threshold 0.8` (поріг ub-mode, а не дефолтні 0.82) з `--root <scratchpad-каталог>`, тому `.metrics/dry.edn` не потрапляє в репозиторій. Вивід dryer передається без змін. Додатково скрипт рахує у переданих шляхах файли `.js/.jsx/.mjs/.cjs` (поза `node_modules`, `dist`, `build`, `coverage`, `target`, тестами) і, коли їх N > 0, друкує останнім рядком `unchecked: N JS files (dryer supports TypeScript only)`. Це єдине, що відрізняє наш запуск від upstream, і єдина відповідь на JS-прогалину.

**`crapper <path>... [-- <test-command>]`** і **`mutator <path>... [-- <test-command>]`.** Запускаються з `--root <worktree>`, бо coverage-прогін потребує проєкту. `crapper` додає `--threshold 10` (exit 2 від crapper при гіршому score), `mutator` лишає свої exit-коди. Хвіст після `--` передається як `--test-command` (для mutator) / `--coverage-command` (для crapper), щоб використати команду верифікації плану, а не вгадувати. Перед запуском скрипт перевіряє `git check-ignore -q .metrics target coverage`; коли щось не ігнорується, друкує `warning: <dir> is not gitignored; do not commit it`. `mutator` додає `--max-workers 3`.

Шляхи завжди передаються явно: `git diff --name-only <merge-base>..HEAD`, відфільтровані до наявних файлів, а не `--changed` (той читає лише незакомічені правки, а наші зміни вже закомічені).

### 3.2. Де запускаємо

**dryer №1: `leonard`, перед plan mode.** Після затвердженої спеки `leonard` запускає `ub-tools.sh dryer` на файлах і каталогах, які спека зачіпає. Пари зі score ≥ 0.8 потрапляють у задачі плану формулюванням «перевикористати або злити X, а не копіювати» з посиланням на обидва місця. Це доповнює `hooks/reuse.sh` (правило «спершу знайди наявне»), який діє до написання коду; `reuse.sh` лишається без змін.

**Make it Right gate: `wolowitz` Finish, до whole-branch review.** Після закриття останньої хвилі:

1. `crapper` на змінених файлах гілки і `dryer №2` на них же. Функції з CRAP ≥ 10 і пари з score ≥ 0.8 ідуть в один dedupe-wave через `amy`: pin (характеризаційний тест) → change → prove (набір зелений). Коміт `refactor(<scope>): crapper and dryer findings`.
2. `mutator` на змінених файлах (після кроку 1, бо рефакторинг скидає результати). Нероздані мутанти і непокритий код: тести пише test writer першим, далі implementer видаляє мертвий код. Коміт `test(<scope>): mutator survivors`.
3. Тільки потім стартують whole-branch review і security-review з поточного кроку 1 Finish.

Кожен крок один раунд, без циклу: що лишилося, потрапляє в підсумковий PR-коментар з номером рядка. Якщо інструмент `unavailable`, крок пропускається з однорядковою приміткою в PR-коментарі, як зараз із `security-review`. Якщо mutator попереджає про завелику кількість covered-сайтів (`--mutation-warning`), `wolowitz` запускає його лише на найменших файлах гілки й каже про це в коментарі. Текст кроків живе в новому `skills/wolowitz/references/make-it-right.md`, бо `skills/wolowitz/SKILL.md` має 19 958 байт із ліміту 20 000 (`skills/skills.test.sh:310`). У `SKILL.md` додається лише двостроковий вказівник, і для місця будівельник виносить у `references/finish.md` рівно стільки наявного тексту Finish, скільки потрібно. Поведінка наявних кроків не змінюється.

### 3.3. Принципи ub-mode по етапах

Принципи переформульовані своїми словами (не копія) і додаються як коротка секція в наявний `SKILL.md` або `references/` скіла. Умовні позначки «ub» у тексті не використовуються: правило звучить як частина самого скіла.

| Скіл | Додається |
|---|---|
| `sheldon` | У design: Attack the Premise (записати передумову одним реченням, коли два рішення впали на одній), Redesign From First Principles, Subtract Before You Add, Model the Domain з глосарієм, Boundary Discipline і Type System Discipline (дані перевіряються на вході, всередині довіряємо), Idempotent operations, Separate Before Serializing Shared State. У spec секція Verification формулюється як перевірюваний кінцевий стан (Outcome-Oriented). |
| `leonard` | Foundational Thinking: форма даних першою, те, що допомагає всім наступним фазам, у ранні хвилі. Sequence work into verifiable units. Build the Lever: нетривіальну роботу робить інструмент, а не вручну. Запуск dryer №1 (3.2). |
| `amy` | Laziness Protocol (одне рішення в одному місці, найменша правка). «Чесний тест або ніякого»: якщо чесний тест непрактичний, поганий не пишемо. Test Behavior, Not Implementation: тест, що проходить, коли кожна функція повертає порожнє, викидаємо. Refactoring: pin → change → prove. Рядок REFACTOR «Remove duplication» замінюється: дублювання ≥ 0.8 знаходить `ub-tools.sh dryer`, а не око. |
| `wolowitz` | Implementer: Subtract Before You Add, повідомлення коміту каже чому, що змінилось і чим доведено. Make it Right gate (3.2). |
| `leslie` | Fix Root Causes (guard, що ховає крах, не виправлення). Attack the Premise: два виправлення з однією передумовою провалили один gate, спершу записати передумову. |

`reviewer-prompt.md` рядок про дублікати («duplication that will drift») лишається: рев'юер ловить семантичні дублікати, яких структурний score не бачить.

### 3.4. Супровід

- `.claude-plugin/plugin.json`: `version` 0.23.1 → 0.24.0 (мінорна: нові можливості); скіли власних `version` не мають.
- `THIRD_PARTY_NOTICES.md`: розділ `unclebob/ub-mode` (MIT, © 2026 Robert C. Martin) для переформульованих принципів і розділ про dryer, crapper, mutator (0BSD, виконуються, не поширюються).
- `README.md` і `README.uk.md`: опис кроків, `install`, змінні `PASADENA_DRYER|CRAPPER|MUTATOR`, обмеження JS у dryer.
- `hooks/ub-tools.test.sh` у стилі `hooks/reuse.test.sh` з фальшивими інструментами через `PASADENA_*`.
- `skills/skills.test.sh`: перевіряє, що `leonard` і `wolowitz` посилаються на `ub-tools.sh`, а `wolowitz/SKILL.md` менший за 20 000 байт.

### 3.5. Дрібні рішення, ухвалені без користувача

- **SHA** трьох інструментів: поточні `HEAD` upstream на момент реалізації, записані константами в `hooks/ub-tools.sh`.
- **Scratchpad для `--root` dryer:** `mktemp -d`, видаляється при виході зі скрипта.
- **«Найменші файли» для mutator:** скрипт спершу рахує сайти через `mutator --scan`; `wolowitz` запускає мутацію лише на файлах, які не викликають `--mutation-warning`, решту називає в PR-коментарі.
- **Bounded-шлях** (`amy` без `wolowitz`): gate і dryer №1 не запускаються, лише принципи в `amy` і `leslie`. Gate належить до Finish плану.
- **Задачі dedupe-wave і mutator-wave** отримують `**Writes:**` з файлів, які назвав інструмент, плюс їхні тестові файли; `wolowitz` складає їх на льоту, у `plan` вони не потрапляють.
- **Команда тестів** для `--test-command`/`--coverage-command` береться з верифікації плану; без неї скрипт лишає дефолт інструмента.

## 4. Out of scope

- Підтримка JS у dryer: ні форк, ні PR в upstream (але crapper вже відображає `.js` на `typescript` тим самим рядком, тож PR із двох рядків у `discover.py` реальний наступний крок).
- uml-viewer.
- «Push to the main line» і «Worktree Cleanup» з ub-mode: суперечать нашому draft-PR флоу.
- Автозапуск `install` без згоди користувача.
- Підтримка Clojure/Java/Go/Rust/Python як окремої роботи: інструменти їх уміють, але ми їх не тестуємо й не документуємо.
- Зміни в `reuse.sh` і `reviewer-prompt.md`.
- Цикли «запускай, доки зелено»: gate один раунд.

## 5. Trade-offs accepted

- З'являється залежність від Python ≥ 3.11 і `git`; без них gate пропускається з приміткою, а не зупиняє роботу.
- Перший `install` і перший запуск потребують мережі (клон і граматики tree-sitter).
- SHA у скрипті треба підіймати вручну, коли upstream покращується.
- У чистому JS-проєкті dryer нічого не перевіряє, лише попереджає; crapper і mutator працюють.
- crapper змінює `node_modules` (Vitest coverage) і перезаписує coverage-звіти; mutator повільний на великих гілках. Gate на змінених файлах і з одним раундом це обмежує, а не прибирає.
- Whole-branch review стартує пізніше на тривалість gate.

## 6. Verification

- `bash hooks/ub-tools.test.sh` зелений. Він перевіряє:
  - **TS:** два дублікати в `.ts` дають `DUPLICATE score=…` ≥ 0.8.
  - **JS:** `.js/.mjs/.cjs/.jsx` дають `unchecked: 4 JS files (dryer supports TypeScript only)`.
  - **Пропуски:** `.d.ts`, тести, `node_modules` не рахуються.
  - **Деградація:** без інструмента вивід `<tool>: unavailable (…)`, exit 0.
  - **Gitignore:** без `.metrics` в `.gitignore` є `warning:`.
  - **Test-command:** хвіст після `--` потрапляє в `--test-command`.
- `bash skills/skills.test.sh` зелений, зокрема 20 000-байтний ліміт для `wolowitz/SKILL.md`.
- Вручну на Node-проєкті з TS: `ub-tools.sh install`, далі `ub-tools.sh dryer src` знаходить штучний дублікат, а `ub-tools.sh crapper src -- npm test` друкує таблицю з coverage з `npm test`.
- `git grep -n "Remove duplication" skills/amy/SKILL.md` порожній.
- `.claude-plugin/plugin.json` має `"version": "0.24.0"`.
