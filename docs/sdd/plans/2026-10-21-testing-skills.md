# Навички тестування в pasadena — implementation plan

**Goal:** У плагіні є `leslie`, `bernie`, `stuart`. amy має правило «Verify before claiming», а wolowitz — фолбек без субагентів, передачу червоної verification у leslie і `security-review` перед ready-PR. Метадані плагіна (версія 0.7.0, README, notices) узгоджені, і це перевіряє `skills/skills.test.sh`.
**Spec:** docs/sdd/specs/2026-10-21-testing-skills.md
**Verification:** `bash skills/skills.test.sh && bash hooks/journal.test.sh && bash proto/server.test.sh && bash hooks/nudge.test.sh`. Остання лінія виводу — `All checks passed.`, exit 0. До хвилі 2 `hooks/nudge.test.sh` не існує, тож бейзлайн хвилі 2 рахується без нього.

## Waves
| Wave | Tasks | Why together |
|---|---|---|
| 1 | 1, 2, 3, 4, 5, 6 | Write-набори не перетинаються: метадані й тест, amy, leslie, bernie, stuart, wolowitz. Інтерфейси між задачами — це лише імена скілів, зафіксовані в Global constraints. |
| 2 | 7, 8 | Не перетинаються: `hooks/` (скрипт, тест, дві реєстрації) vs `README.md` і `README.uk.md`. README лише описує хук і нічого з Task 7 не споживає, крім імені `PASADENA_NUDGE` і події `UserPromptSubmit`, які тут зафіксовано. |

Серіалізувати нічого не треба: кожен файл належить рівно одній задачі. Хвиля 2 іде після хвилі 1 лише тому, що спеку 3.7 дописали після неї.

## Global constraints

- Скіли пишуться **англійською**, у стилі `skills/amy/SKILL.md`: H1-заголовок, коротке «core principle», таблиця `## Decision rules` (`| Situation | Rule |`), фінальний чекліст `- [ ]`. Жодних емодзі.
- Frontmatter: `---` / `name: <dir>` / `description: …` / `---`. `name` має збігатися з назвою каталогу, інакше `skills/skills.test.sh` падає.
- Точні імена для взаємних посилань: `pasadena:amy`, `pasadena:leslie`, `pasadena:bernie`, `pasadena:stuart`, скіл `security-review`. Скрізь у тексті пишеться «invoke … with the Skill tool, as `pasadena:<name>` (plain `<name>` where the host does not prefix plugin skills)», як в `implementer-prompt.md` правило 5.
- `leslie` і `bernie` **не мають** `disallowed-tools`, бо передають роботу в amy в тому ж ході. `stuart` теж не має `disallowed-tools`.
- Браузерні скіли (`bernie`, `stuart`) у `allowed-tools` перелічують `mcp__playwright` і `mcp__claude-in-chrome`, як `skills/penny/SKILL.md`.
- Текст адаптується, а не копіюється дослівно. Upstream читається через `gh api` (команди в задачах), а скіл переписується під правила pasadena.
- Ліцензії: obra/superpowers — MIT; anthropics/skills `skills/webapp-testing` — Apache-2.0; testdino-hq/playwright-skill — MIT; nikolasdehor/visual-eyes — MIT. trailofbits/skills не використовується зовсім (CC-BY-SA-4.0).
- **Ruling щодо спеки 6.1:** перевірка «кожен каталог має рядок у README» пропускає `pasadena` і `journal`. Це точки входу (роутер і аліас), і в таблиці README їх нема з 0.6.x. Якщо рішення хибне, у README бракуватиме двох рядків, і це не баг.
- Прозові задачі (2–6) теж ідуть через цикл amy. «Тест» тут — grep-перевірка обов'язкових рядків: вона падає до зміни (red) і проходить після (green). Потім треба отримати зелений `bash skills/skills.test.sh`.

---

### Task 1: метадані плагіна і перевірки в skills.test.sh

**Writes:** `skills/skills.test.sh`, `README.md`, `README.uk.md`, `THIRD_PARTY_NOTICES.md`, `.claude-plugin/plugin.json`, `.claude-plugin/marketplace.json`, `.codex-plugin/plugin.json`
**Reads:** `docs/sdd/specs/2026-10-21-testing-skills.md` (3.6, 6.1)
**Depends on:** —
**Interfaces:**
- Produces: `routers="pasadena journal leonard amy leslie bernie"`, `entrypoints="pasadena journal"`, `adapted="leslie bernie stuart"` у `skills/skills.test.sh`.

- [x] **Step 1: write the failing test.** У `skills/skills.test.sh`:
  - змінити `routers=` на `"pasadena journal leonard amy leslie bernie"`;
  - після циклу по скілах і до фінального `echo` додати три блоки з тими самими `fail`/`ok`:

  ```bash
  ROOT="$(cd "$SKILLS/.." && pwd)"
  entrypoints="pasadena journal"
  adapted="leslie bernie stuart"

  echo "README tables"
  for dir in "$SKILLS"/*/; do
    name="$(basename "$dir")"
    case " $entrypoints " in *" $name "*) continue ;; esac
    for readme in README.md README.uk.md; do
      grep -q "^| \`$name\` |" "$ROOT/$readme" ||
        fail "$name: no row in $readme skills table"
    done
  done
  ok "README tables checked"

  echo "Third-party notices"
  for name in $adapted; do
    grep -q "skills/$name/SKILL.md" "$ROOT/THIRD_PARTY_NOTICES.md" ||
      fail "$name: not credited in THIRD_PARTY_NOTICES.md"
  done
  ok "notices checked"

  echo "Manifest versions"
  versions="$(grep -h '"version"' "$ROOT/.claude-plugin/plugin.json" "$ROOT/.claude-plugin/marketplace.json" "$ROOT/.codex-plugin/plugin.json" | sed 's/[^0-9.]//g' | sort -u)"
  [ "$(wc -l <<<"$versions")" -eq 1 ] || fail "manifest versions differ: $(tr '\n' ' ' <<<"$versions")"
  ok "manifest versions checked"
  ```
- [x] **Step 2: run it, watch it fail.** `bash skills/skills.test.sh`. Очікується `FAILED: 3`: три рядки `not credited in THIRD_PARTY_NOTICES.md`.
- [x] **Step 3: implement.**
  - `README.md` — після рядка `amy` додати:
    - `` | `leslie` | Finds the root cause of a bug or unexpected failure in four phases before any fix, then fixes it through amy. | ``
    - `` | `bernie` | Checks a feature end-to-end in the browser with evidence, or adds a lasting Playwright e2e test. | ``
    - `` | `stuart` | Screenshots a page at several breakpoints, reports layout defects, and fixes them after your approval. | ``
  - `README.uk.md` — після рядка `amy` додати:
    - `` | `leslie` | Знаходить першопричину бага чи неочікуваного падіння за чотири фази, а потім виправляє через amy. | ``
    - `` | `bernie` | Перевіряє фічу end-to-end у браузері з доказами або додає сталий e2e-тест на Playwright. | ``
    - `` | `stuart` | Знімає сторінку на кількох брейкпоінтах, звітує про дефекти верстки й виправляє їх після вашої згоди. | ``
  - Обидва README: рядок про `amy` доповнити реченням про перевірку: EN — `… and refactors, and proof from a fresh run before anything is called done.`; UK — `… і рефакторингів, а також доказ свіжим прогоном, перш ніж щось назвати готовим.`
  - `THIRD_PARTY_NOTICES.md`:
    - у розділ `## obra/superpowers`, у список «Modified portions…», додати:
      - `` `skills/amy/SKILL.md` section "Verify before claiming" from `skills/verification-before-completion/SKILL.md` ``
      - `` `skills/leslie/SKILL.md` from `skills/systematic-debugging/SKILL.md` ``
    - після нього три нові розділи в тому самому форматі (заголовок, «Modified portions of these files derive from …», список, `Source:`, копірайт, текст ліцензії):
      - `## anthropics/skills`: `` `skills/bernie/SKILL.md` from `skills/webapp-testing/SKILL.md` `` і рядок `Changes: rewritten for Playwright MCP / Chrome MCP; the Python helper with_server.py is not included.` Текст ліцензії брати дослівно з `gh api repos/anthropics/skills/contents/skills/webapp-testing/LICENSE.txt --jq .content | base64 -d`.
      - `## testdino-hq/playwright-skill`: `` `skills/bernie/SKILL.md` `` (guidance on locators, assertions, isolation and auth condensed into rules). Копірайт і MIT брати з `gh api repos/testdino-hq/playwright-skill/contents/LICENSE --jq .content | base64 -d`.
      - `## nikolasdehor/visual-eyes`: `` `skills/stuart/SKILL.md` ``. Копірайт і MIT брати з `gh api repos/nikolasdehor/visual-eyes/contents/LICENSE --jq .content | base64 -d`.
      - Якщо назва файлу ліцензії інша, знайти її через `gh api repos/<repo>/contents --jq '.[].name'`.
  - `.claude-plugin/plugin.json` і `.claude-plugin/marketplace.json`:
    - `"version": "0.7.0"`;
    - `description` = `"Spec-driven development run by nine skills named after the Big Bang Theory cast: sheldon shapes the spec through questions, penny debugs a browser prototype before it is written, leonard plans in native plan mode, wolowitz builds the plan's independent tasks in parallel waves behind a draft PR, amy writes the failing test first and demands proof before done, leslie finds the root cause before any fix, bernie checks features end-to-end in the browser, stuart catches broken layouts, and raj keeps the session journal that holds the state between them"`;
    - до `keywords` додати `"debugging"`, `"e2e"`, `"visual-testing"`.
  - `.codex-plugin/plugin.json`:
    - `"version": "0.7.0"`;
    - `description` = `"Spec-driven development with a session journal and nine focused workflow skills."`;
    - `longDescription` = `"A nine-skill development workflow that preserves task context in a branch journal and backs every claim with tests."`;
    - до `keywords` додати `"debugging"`, `"e2e"`, `"visual-testing"`.
- [x] **Step 4: run it, watch it pass.** `bash skills/skills.test.sh`, очікується `All checks passed.` Якщо каталоги leslie, bernie, stuart ще не створені іншими задачами хвилі, перевірка README для них просто не спрацює, і це нормально.

### Task 2: amy — Verify before claiming

**Writes:** `skills/amy/SKILL.md`
**Reads:** `docs/sdd/specs/2026-10-21-testing-skills.md` (3.1); upstream: `gh api repos/obra/superpowers/contents/skills/verification-before-completion/SKILL.md --jq .content | base64 -d`
**Depends on:** —
**Interfaces:**
- Consumes: ім'я `pasadena:leslie` (Task 3 створює скіл, тут лише посилання).
- Produces: заголовок `## Verify before claiming`, на який посилаються Task 3, 4, 5, 6.

- [x] **Step 1: write the failing test.** `grep -q '^## Verify before claiming$' skills/amy/SKILL.md && grep -q 'pasadena:leslie' skills/amy/SKILL.md && grep -q 'The output of the latest run is shown, not summarised' skills/amy/SKILL.md && echo OK`
- [x] **Step 2: run it, watch it fail.** Порожній вивід, exit 1.
- [x] **Step 3: implement.**
  1. Перед `## Before calling the work done` вставити розділ `## Verify before claiming` з такими положеннями:
     - кожне твердження «passes», «fixed», «done» спирається на команду, запущену **в цьому ж повідомленні**, а її вивід показано, не переказано;
     - доказом **не** є: «should work», «probably», «looks right», результат попереднього прогону, звіт субагента без виводу;
     - порядок у вигляді блоку-коду, як Iron Law: `IDENTIFY the command that proves the claim → RUN it in full → READ the output and exit code → only then STATE the claim, with the evidence`;
     - міні-таблиця `| Claim | Requires | Not sufficient |` з рядками: tests pass / test output with 0 failures / a previous run, "should pass"; bug fixed / the reproducing test now passes / code changed, assumed fixed; build succeeds / build exit 0 / linter passing; delegated task done / the diff and its verification output / the agent's "success" report.
  2. У таблицю `## When stuck` додати рядок: `| The test fails for a reason you did not predict | Stop changing code and invoke \`leslie\` with the Skill tool, as \`pasadena:leslie\` (plain \`leslie\` where the host does not prefix plugin skills). |`
  3. У чекліст `## Before calling the work done` перед останнім пунктом додати `- [ ] The output of the latest run is shown, not summarised`.
- [x] **Step 4: run it, watch it pass.** Команда з Step 1 → `OK`. Потім `bash skills/skills.test.sh` → без FAIL щодо `amy`.

### Task 3: leslie — системний дебаг

**Writes:** `skills/leslie/SKILL.md`
**Reads:** `skills/amy/SKILL.md` (стиль), специфікація 3.2; upstream: `gh api repos/obra/superpowers/contents/skills/systematic-debugging/SKILL.md --jq .content | base64 -d`
**Depends on:** —
**Interfaces:**
- Consumes: `pasadena:amy` і її розділ `## Verify before claiming` (Task 2).
- Produces: скіл `pasadena:leslie`.

- [x] **Step 1: write the failing test.** `test -f skills/leslie/SKILL.md && grep -q '^name: leslie$' skills/leslie/SKILL.md && grep -q 'NO FIX WITHOUT A ROOT CAUSE' skills/leslie/SKILL.md && grep -q 'pasadena:amy' skills/leslie/SKILL.md && grep -q '^## Decision rules' skills/leslie/SKILL.md && echo OK`
- [x] **Step 2: run it, watch it fail.** Порожній вивід і exit 1, бо файлу немає.
- [x] **Step 3: implement.** Створити `skills/leslie/SKILL.md`:
  - frontmatter: `name: leslie`; `description: Use when the user reports a bug, a test fails for an unexpected reason, a build or verification is red, or behaviour differs from what was expected. Finds the root cause in four phases before any fix`; без `allowed-tools` і без `disallowed-tools`;
  - `# Systematic debugging`, core principle: випадкові фікси марнують час і породжують нові баги, тож спершу першопричина;
  - абзац, як в amy: «This skill declares no tool rules…» (скіл — техніка всередині того, хто його викликав, і передає роботу в amy в тому ж ході);
  - `## The Iron Law` з блоком `NO FIX WITHOUT A ROOT CAUSE`;
  - `## When it applies`: test failures, bugs, unexpected behaviour, build/verification failures; **особливо** під тиском часу, коли «очевидний швидкий фікс» або коли вже був невдалий фікс;
  - `## Phase 1 — Root cause`: повністю прочитати помилку й stack trace, стабільно відтворити, перевірити останні зміни (`git diff`, `git log`), у багатокомпонентній системі додати діагностику на кожній межі компонентів і запустити один раз, простежити погане значення назад до місця, де воно вперше хибне;
  - `## Phase 2 — Pattern`: знайти робочий аналог у тому ж репо, перелічити **всі** відмінності;
  - `## Phase 3 — Hypothesis`: одна гіпотеза письмово («X is the cause because Y»), одна мінімальна зміна на одну змінну; не підтвердилась — відкотити зміну й нова гіпотеза, а не друга зміна поверх першої;
  - `## Phase 4 — Fix`: invoke amy with the Skill tool, as `pasadena:amy` (plain `amy` …); тест, що відтворює баг, падає з передбаченої причини; один фікс першопричини; перевірка за amy `## Verify before claiming`;
  - `## The rule of three`: після трьох невдалих фіксів зупинитися, сказати, що проблема, ймовірно, в архітектурі, і запитати користувача перед четвертою спробою;
  - `## Decision rules`: щонайменше 6 рядків (наприклад: «the cause looks obvious» → Phase 1 still runs, it is fast for an obvious cause; «several fixes at once would save time» → one variable per change; «the error message is long» → read it in full, the answer is often in it; «it cannot be reproduced» → gather data, no guessing; «one more fix attempt» after 3 → stop and ask; «the fix works but the cause is unclear» → not done, return to Phase 1);
  - `## Before calling it fixed` — чекліст: root cause stated in one sentence; reproduction test failed for the predicted reason; one fix addressed that cause; full suite green with output shown.
- [x] **Step 4: run it, watch it pass.** Команда з Step 1 → `OK`. `bash skills/skills.test.sh` → для `leslie` лише `ok`, без FAIL. FAIL щодо README чи notices можливий, лише якщо Task 1 ще не завершена.

### Task 4: bernie — e2e у браузері

**Writes:** `skills/bernie/SKILL.md`
**Reads:** `skills/penny/SKILL.md` (frontmatter браузерних інструментів, запуск сервера), `skills/amy/SKILL.md`, специфікація 3.3; upstream: `gh api repos/anthropics/skills/contents/skills/webapp-testing/SKILL.md --jq .content | base64 -d`, `gh api repos/testdino-hq/playwright-skill/contents --jq '.[].name'` (далі SKILL.md і core-гайди)
**Depends on:** —
**Interfaces:**
- Consumes: `pasadena:amy` і `## Verify before claiming` (Task 2).
- Produces: скіл `pasadena:bernie`.

- [x] **Step 1: write the failing test.** `test -f skills/bernie/SKILL.md && grep -q '^name: bernie$' skills/bernie/SKILL.md && grep -q 'mcp__playwright' skills/bernie/SKILL.md && grep -q '^## One-off check' skills/bernie/SKILL.md && grep -q '^## Lasting e2e test' skills/bernie/SKILL.md && grep -q 'pasadena:amy' skills/bernie/SKILL.md && ! grep -q '^disallowed-tools:' skills/bernie/SKILL.md && echo OK`
- [x] **Step 2: run it, watch it fail.** Порожній вивід, exit 1.
- [x] **Step 3: implement.** Створити `skills/bernie/SKILL.md`:
  - frontmatter: `name: bernie`; `description: Use when the user asks to check a feature in the browser, run an end-to-end check, or write e2e tests. Drives the running app through Playwright and either reports evidence or adds a lasting e2e test`; `allowed-tools`: `Read`, `Grep`, `Glob`, `Edit`, `Write`, `Skill`, `AskUserQuestion`, `TodoWrite`, `mcp__playwright`, `mcp__claude-in-chrome`, `Bash(npm *)`, `Bash(pnpm *)`, `Bash(yarn *)`, `Bash(npx playwright *)`, `Bash(git status *)`, `Bash(git diff *)`; без `disallowed-tools`;
  - `# End-to-end in the browser`: запускається лише на запит користувача, сам пайплайн його не викликає;
  - `## Pick the mode`: «check / does it work / глянь» → one-off; «write / add an e2e test» → lasting; неоднозначно → одне питання через AskUserQuestion;
  - `## The server`: знайти команду dev-сервера в `package.json` або README; якщо порт не відповідає, підняти у фоні, дочекатися порту, після роботи погасити лише сервер, який bernie сам підняв;
  - `## Reconnaissance first`: відкрити сторінку, дочекатися networkidle, зняти snapshot або accessibility tree, селектори брати з відрендереного (role, label, text), класи не вгадувати;
  - `## One-off check`: пройти сценарій через Playwright MCP або Chrome MCP, скриншоти ключових станів, зібрати помилки консолі й упалі мережеві запити, звіт за amy `## Verify before claiming`; у репо не лишається жодного файлу;
  - `## Lasting e2e test`: раннер проєкту (Playwright Test, `@playwright/test` у `package.json`); якщо раннера немає, зупинитися й запропонувати рішення щодо залежності, нічого не встановлювати; invoke amy with the Skill tool, as `pasadena:amy` (plain `amy` …), і пройти red → green; правила тесту — локатори `getByRole`/`getByLabel`/`getByText`, web-first assertions (`await expect(locator).toBeVisible()`), без `waitForTimeout`, ізольований стан на тест, авторизація через збережений `storageState`, один сценарій поведінки на тест;
  - `## No browser`: якщо немає ні `mcp__playwright`, ні `mcp__claude-in-chrome`, один раз сказати про це і зупинитися;
  - `## Decision rules` (≥5 рядків) і `## Before reporting` (чекліст: server state restored; evidence shown — screenshots/console; for a lasting test, the red run was seen).
- [x] **Step 4: run it, watch it pass.** Команда з Step 1 → `OK`. `bash skills/skills.test.sh` → без FAIL щодо `bernie` (якщо Task 1 уже додала `bernie` в `routers`, перевірка `disallowed-tools` для нього обов'язкова).

### Task 5: stuart — візуальна перевірка верстки

**Writes:** `skills/stuart/SKILL.md`
**Reads:** `skills/penny/SKILL.md`, специфікація 3.4; upstream: `gh api repos/nikolasdehor/visual-eyes/contents --jq '.[].name'`, далі його SKILL.md (знайти шлях у дереві: `gh api 'repos/nikolasdehor/visual-eyes/git/trees/HEAD?recursive=1' --jq '.tree[].path' | grep -i skill`)
**Depends on:** —
**Interfaces:**
- Consumes: `## Verify before claiming` (Task 2), запуск сервера, як у bernie: та сама процедура, описана в цьому файлі заново.
- Produces: скіл `pasadena:stuart`.

- [x] **Step 1: write the failing test.** `test -f skills/stuart/SKILL.md && grep -q '^name: stuart$' skills/stuart/SKILL.md && grep -q '375, 768, 1280, 1920' skills/stuart/SKILL.md && grep -q 'mcp__playwright' skills/stuart/SKILL.md && grep -qi 'approval' skills/stuart/SKILL.md && echo OK`
- [x] **Step 2: run it, watch it fail.** Порожній вивід, exit 1.
- [x] **Step 3: implement.** Створити `skills/stuart/SKILL.md`:
  - frontmatter: `name: stuart`; `description: Use when the user says the layout is broken, asks to check responsiveness, or wants a visual check of a page. Screenshots the page at several breakpoints, reports defects with evidence, and fixes them only after approval`; `allowed-tools`: `Read`, `Grep`, `Glob`, `Edit`, `Write`, `AskUserQuestion`, `TodoWrite`, `mcp__playwright`, `mcp__claude-in-chrome`, `Bash(npm *)`, `Bash(pnpm *)`, `Bash(yarn *)`, `Bash(git status *)`, `Bash(git diff *)`; без `disallowed-tools`;
  - `# Visual layout check`: запускається лише на запит;
  - `## Breakpoints`: за замовчуванням `375, 768, 1280, 1920` px завширшки (саме цей рядок), користувач може задати свої;
  - `## What counts as a defect`: горизонтальний скрол сторінки; текст чи елемент виходить за межі контейнера; перекриття; зсунута чи розірвана сітка; обрізаний елемент; нечитабельний контраст; порожній стан там, де мав бути контент;
  - `## Procedure`: 1) сервер (знайти команду, підняти у фоні, погасити той, що підняв сам); 2) для кожного брейкпоінта задати розмір вікна, зняти full-page скриншот, перевірити `document.documentElement.scrollWidth > clientWidth`; 3) звіт таблицею `| Defect | Breakpoint | Screenshot | Likely CSS source |`; 4) **зупинитися й запитати approval** через AskUserQuestion; 5) після approval виправити, перезняти ті самі брейкпоінти, показати пари before/after;
  - `## Comparison`: before/after порівнює модель за скриншотами, піксельного diff немає, тож про зсув на 1–2 px так і сказати;
  - `## No browser` — як у bernie;
  - `## Decision rules` (≥5 рядків, зокрема «a fix looks obvious» → still report and wait for approval; «the defect appears only at one breakpoint» → fix with a media query scoped to it) і `## Before reporting` (чекліст: every breakpoint captured; each defect has a screenshot; no CSS changed without approval; after-screens shown).
- [x] **Step 4: run it, watch it pass.** Команда з Step 1 → `OK`. `bash skills/skills.test.sh` → без FAIL щодо `stuart`.

### Task 6: wolowitz — фолбек, leslie, security-review, доказ у звіті

**Writes:** `skills/wolowitz/SKILL.md`, `skills/wolowitz/implementer-prompt.md`
**Reads:** специфікація 3.5
**Depends on:** —
**Interfaces:**
- Consumes: `pasadena:amy`, `pasadena:leslie`, скіл `security-review`, amy `## Verify before claiming`.

- [x] **Step 1: write the failing test.** `grep -q '^## Without subagents' skills/wolowitz/SKILL.md && grep -q 'pasadena:leslie' skills/wolowitz/SKILL.md && grep -q 'security-review' skills/wolowitz/SKILL.md && grep -q 'exit code' skills/wolowitz/implementer-prompt.md && echo OK`
- [x] **Step 2: run it, watch it fail.** Порожній вивід, exit 1.
- [x] **Step 3: implement.**
  - `skills/wolowitz/SKILL.md`:
    1. Після `## Models` додати розділ `## Without subagents`. Якщо інструмента Agent немає в сесії, контролер сам виконує задачі хвилі, по одній, у порядку задач. Перед першою задачею він викликає amy через Skill tool, як `pasadena:amy` (plain `amy` …), і проходить кожну задачу за її циклом. Згадка amy в тексті не завантажує її. Рев'ю хвилі в цьому режимі контролер робить сам по `BASE..HEAD`, а коментар хвилі на PR зазначає «no subagents». Решта циклу — verify, commit, comment, close — без змін.
    2. У `### 3. Verify the wave yourself` додати абзац: якщо прогін червоний і причину не видно з одного рядка помилки, не латати навздогад, а викликати `leslie` через Skill tool, як `pasadena:leslie` (plain `leslie` …). Фікс іде через імплементера задачі (у режимі без субагентів — через amy), перевірка повторюється.
    3. У `## Finish` між пунктом 1 (whole-branch review) і `journal finish` вставити новий пункт: «**Security review.** Invoke the `security-review` skill with the Skill tool on the branch diff. Findings go to one fix dispatch under the same rules as review findings. When the skill is unavailable (for example in Codex), say so once and note the skip in the PR comment». Перенумерувати пункти.
    4. У `## Decision rules` додати два рядки: `| The Agent tool is unavailable | Run the wave yourself, invoking \`pasadena:amy\` before the first task. |` і `| Wave verification is red for an unclear reason | Invoke \`pasadena:leslie\` before any fix. |`.
    5. У `## Tools`: речення «Edit code directly only for a change small enough to state in one line» доповнити посиланням «— or for every task when the session has no subagents, see **Without subagents**».
  - `skills/wolowitz/implementer-prompt.md`: у `## Report back` замінити `- One line on what your verification command printed` на `- The last lines (up to 10) of your verification command's output and its exit code, pasted, not summarised`.
- [x] **Step 4: run it, watch it pass.** Команда з Step 1 → `OK`. `bash skills/skills.test.sh` → без FAIL щодо `wolowitz`.

---

### Task 7: хук `nudge` — скрипт, тест, реєстрація

**Writes:** `hooks/nudge.sh`, `hooks/nudge.test.sh`, `hooks/claude-hooks.json`, `hooks/hooks.json`
**Reads:** `hooks/journal.sh` (стиль: `set -uo pipefail`, `jq` на stdin, `.cwd`), `hooks/journal.test.sh` (`assert_contains`/`assert_empty`, тимчасові репо), специфікація 3.7
**Depends on:** —
**Interfaces:**
- Produces: подія `UserPromptSubmit` → `hooks/nudge.sh`; вимикач `PASADENA_NUDGE=0`.

- [ ] **Step 1: write the failing test.** Створити `hooks/nudge.test.sh`:

  ```bash
  #!/usr/bin/env bash
  # Self-check for the nudge hook. Run: bash hooks/nudge.test.sh
  set -uo pipefail

  DIR="$(cd "$(dirname "$0")" && pwd)"
  HOOK="$DIR/nudge.sh"
  fails=0

  assert_contains() {
    if [[ "$1" == *"$2"* ]]; then
      echo "  ok  — $3"
    else
      echo "  FAIL — $3"
      echo "        expected substring: $2"
      echo "        got: $1"
      fails=$((fails + 1))
    fi
  }

  assert_empty() {
    if [ -z "$1" ]; then
      echo "  ok  — $2"
    else
      echo "  FAIL — $2"
      echo "        expected empty output, got: $1"
      fails=$((fails + 1))
    fi
  }

  repo="$(mktemp -d)"
  git -C "$repo" init -q
  plain="$(mktemp -d)"

  run() { jq -n --arg p "$1" --arg c "${2:-$repo}" '{prompt:$p,cwd:$c}' | bash "$HOOK" 2>/dev/null; }

  echo "== bug prompts =="
  assert_contains "$(run 'Тести в price.test.sh падають. Полагодь.')" "pasadena:leslie" "Ukrainian bug prompt points to leslie"
  assert_contains "$(run 'the build is failing')" "pasadena:leslie" "English bug prompt points to leslie"
  assert_contains "$(run 'полагодь і додай тест')" "pasadena:leslie" "bug wins over feature"

  echo "== feature prompts =="
  out="$(run 'Додай функцію mul')"
  assert_contains "$out" "pasadena:amy" "feature prompt points to amy"
  assert_empty "$(grep -o leslie <<<"$out")" "feature prompt does not mention leslie"

  echo "== output shape =="
  assert_contains "$(run 'fix the crash' | jq -r '.hookSpecificOutput.hookEventName' 2>/dev/null)" "UserPromptSubmit" "valid JSON with the event name"

  echo "== silent cases =="
  assert_empty "$(run '/pasadena')" "slash command stays silent"
  assert_empty "$(run 'виклич pasadena:leslie і полагодь')" "named skill stays silent"
  assert_empty "$(run 'що таке монада?')" "unrelated prompt stays silent"
  assert_empty "$(PASADENA_NUDGE=0 run 'полагодь тест')" "PASADENA_NUDGE=0 turns it off"
  assert_empty "$(run 'полагодь тест' "$plain")" "silent outside a Git repo"

  echo "== registration =="
  assert_contains "$(jq -r '.hooks.UserPromptSubmit[0].hooks[0].command' "$DIR/claude-hooks.json")" \
    'hooks/nudge.sh' "Claude Code registers UserPromptSubmit"
  assert_contains "$(jq -r '.hooks.UserPromptSubmit[0].hooks[0].command' "$DIR/hooks.json")" \
    '[ -n "${CLAUDE_PLUGIN_ROOT:-}" ] || bash "${PLUGIN_ROOT}/hooks/nudge.sh"' "Codex registers UserPromptSubmit behind the guard"

  rm -rf "$repo" "$plain"

  echo
  if [ "$fails" -gt 0 ]; then
    echo "FAILED: $fails"
    exit 1
  fi
  echo "All checks passed."
  ```
- [ ] **Step 2: run it, watch it fail.** `bash hooks/nudge.test.sh` → `FAILED: 7`: чотири assert на leslie/amy, event name і дві реєстрації. Assert-и на мовчання проходять, бо скрипту ще немає і вивід порожній.
- [ ] **Step 3: implement.**
  - `hooks/nudge.sh` (виконуваний не обов'язково, викликається через `bash`):

    ```bash
    #!/usr/bin/env bash
    set -uo pipefail

    [ "${PASADENA_NUDGE:-1}" = "0" ] && exit 0

    export LC_ALL=C.UTF-8
    input="$(cat)"
    prompt="$(jq -r '.prompt // empty' <<<"$input" 2>/dev/null)"
    cwd="$(jq -r '.cwd // empty' <<<"$input" 2>/dev/null)"
    [ -n "$cwd" ] || cwd="$PWD"

    [ "$(git -C "$cwd" rev-parse --is-inside-work-tree 2>/dev/null)" = "true" ] || exit 0

    trimmed="${prompt#"${prompt%%[![:space:]]*}"}"
    [ "${trimmed:0:1}" = "/" ] && exit 0
    grep -qiE 'leslie|amy|pasadena:' <<<"$prompt" && exit 0

    bug='баг|помилк|падає|падають|впав|зламал|не працює|полагод|виправ|fix|bug|broken|failing|fails|error|crash|regression'
    feature='додай|реаліз|імплемент|зроби функц|нов(а|у|ий) фіч|implement|add (a |an )?(feature|function|endpoint|test)|build (a|the)'

    if grep -qiE "$bug" <<<"$prompt"; then
      ctx='This prompt looks like a bug or failing check. Before changing any code, invoke the leslie skill with the Skill tool, as pasadena:leslie, and follow it: root cause first, then the fix through amy.'
    elif grep -qiE "$feature" <<<"$prompt"; then
      ctx='This prompt looks like new behaviour. Before writing production code, invoke the amy skill with the Skill tool, as pasadena:amy: failing test first.'
    else
      exit 0
    fi

    jq -n --arg ctx "$ctx" '{hookSpecificOutput:{hookEventName:"UserPromptSubmit",additionalContext:$ctx}}'
    ```
  - `hooks/claude-hooks.json`: у `.hooks` додати після `SessionStart`:
    ```json
    "UserPromptSubmit": [
      {
        "hooks": [
          {
            "type": "command",
            "command": "bash \"${CLAUDE_PLUGIN_ROOT}/hooks/nudge.sh\"",
            "shell": "bash",
            "timeout": 5
          }
        ]
      }
    ],
    ```
  - `hooks/hooks.json`: у `.hooks` додати після `SessionStart`:
    ```json
    "UserPromptSubmit": [
      {
        "hooks": [
          {
            "type": "command",
            "command": "[ -n \"${CLAUDE_PLUGIN_ROOT:-}\" ] || bash \"${PLUGIN_ROOT}/hooks/nudge.sh\"",
            "timeout": 5
          }
        ]
      }
    ],
    ```
  - Обидва JSON мають лишитися валідними: `jq . hooks/claude-hooks.json hooks/hooks.json >/dev/null && echo JSON_OK`.
- [ ] **Step 4: run it, watch it pass.** `bash hooks/nudge.test.sh` → `All checks passed.`; `bash hooks/journal.test.sh` → `All checks passed.` (Codex-реєстрацію там теж перевіряють, і вона має лишитися зеленою).

### Task 8: README — хук nudge

**Writes:** `README.md`, `README.uk.md`
**Reads:** специфікація 3.7
**Depends on:** —
**Interfaces:**
- Consumes: подія `UserPromptSubmit`, вимикач `PASADENA_NUDGE=0`, тест `hooks/nudge.test.sh` (імена з Task 7, зафіксовані тут).

- [ ] **Step 1: write the failing test.** `grep -q 'Codex uses four hooks' README.md && grep -q '^| `UserPromptSubmit` |' README.md && grep -q 'PASADENA_NUDGE=0' README.md && grep -q '^bash hooks/nudge.test.sh$' README.md && grep -q 'Codex використовує чотири hooks' README.uk.md && grep -q '^| `UserPromptSubmit` |' README.uk.md && grep -q 'PASADENA_NUDGE=0' README.uk.md && grep -q '^bash hooks/nudge.test.sh$' README.uk.md && echo OK`
- [ ] **Step 2: run it, watch it fail.** Порожній вивід, exit 1.
- [ ] **Step 3: implement.**
  - `README.md`:
    - `Codex uses three hooks; Claude Code adds \`StopFailure\`:` → `Codex uses four hooks; Claude Code adds \`StopFailure\`:`;
    - у таблицю хуків після рядка `SessionStart` додати: `` | `UserPromptSubmit` | Reminds the agent to invoke leslie for a bug or amy for new behaviour; silent outside a Git repo. | Same | ``;
    - `Hooks read Git state and append to the journal. They do not modify Git history or the index.` → `Hooks read Git state and append to the journal; \`UserPromptSubmit\` only adds context to the prompt. They do not modify Git history or the index.`;
    - у `## Configuration` після абзацу про `PASADENA_TRUNK` і його JSON-прикладу додати абзац: ``PASADENA_NUDGE=0` turns off the `UserPromptSubmit` reminder.``;
    - у `## Checks` у блок bash додати третій рядок `bash hooks/nudge.test.sh`, а в абзац під ним додати речення: `The nudge checks cover bug and feature prompts, the silent cases, and hook registration.`
  - `README.uk.md`:
    - `Codex використовує три hooks; Claude Code додає \`StopFailure\`:` → `Codex використовує чотири hooks; Claude Code додає \`StopFailure\`:`;
    - у таблицю після рядка `SessionStart`: `` | `UserPromptSubmit` | Нагадує агенту викликати leslie для бага або amy для нової поведінки; поза Git-репозиторієм мовчить. | Те саме | ``;
    - `Хуки читають Git-стан і дописують журнал. Git-історію та індекс вони не змінюють.` → `Хуки читають Git-стан і дописують журнал; \`UserPromptSubmit\` лише додає контекст до промпту. Git-історію та індекс вони не змінюють.`;
    - у `## Конфігурація` (або відповідний розділ із `PASADENA_TRUNK`) після JSON-прикладу: ``PASADENA_NUDGE=0` вимикає нагадування `UserPromptSubmit`.``;
    - у `## Перевірки` у блок bash третім рядком `bash hooks/nudge.test.sh`, а в абзац: `Третя перевіряє промпти про баги й фічі, випадки мовчання та реєстрацію хука.`
- [ ] **Step 4: run it, watch it pass.** Команда з Step 1 → `OK`; `bash skills/skills.test.sh` → `All checks passed.`

---

## Після хвилі 2 (Finish у wolowitz)

Whole-branch review → security pass (скіл `security-review` падає без `origin/HEAD`, тоді вручну) → повторний headless-прогін сценарію 2 тричі (`behave-setup.sh` і `behave-run.sh` запускає користувач, бо ізоляція worktree не дає git поза ним). Очікування: у кожному прогоні `pasadena:leslie` — перший Skill до будь-якого Edit. Далі `journal finish` → `gh pr ready`.
