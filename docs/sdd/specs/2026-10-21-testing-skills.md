# Навички тестування в pasadena — design

**Date:** 2026-10-21
**Status:** agreed

## 1. Problem

amy вже реалізує дисципліну `test-driven-development` з obra/superpowers: Iron Law, RED → GREEN → Refactor, перевірка причини падіння. Аналіз п'яти architect-сесій 2026-10-20 (pasadena 0.6.7) показав, що імплементери wolowitz стабільно викликають `pasadena:amy` першим кроком і проходять red → green. Прогалини лежать поруч із TDD:

- **amy випадає, коли субагентів немає.** У сесії verbum `1a8549de` інструмент Agent був недоступний. Контролер wolowitz сам писав код («Субагенти недоступні… виконаю хвилі сам») і amy через Skill tool не викликав, лише згадав у тексті. Почав із типів, а не з тесту. `skills/wolowitz/SKILL.md` такий випадок не описує.
- **Немає системного дебагу.** Коли тест падає з непередбаченої причини або verification хвилі червона, агент латає навздогад.
- **Немає правила «доказ перед "готово"».** Імплементер звітує одним рядком про verification, але явної вимоги показати свіжий вивід перед будь-яким твердженням про успіх немає.
- **Немає e2e у браузері, візуальної перевірки верстки й кроку безпеки.** penny працює з браузером лише для прототипів, а пайплайн закінчується без security-review.

## 2. Constraint that shapes the solution

Навички **вбудовуються в плагін pasadena як адаптовані копії**, а не підключаються як зовнішні залежності. Pasadena має працювати після одного `plugin install` без додаткових маркетплейсів. Звідси два наслідки:

- Брати можна лише з джерел під дозвільною ліцензією: superpowers (MIT), anthropics/skills webapp-testing (Apache-2.0), testdino-hq/playwright-skill (MIT), nikolasdehor/visual-eyes (MIT). **trailofbits/skills має ліцензію CC-BY-SA-4.0** (copyleft), тож його текст у MIT-плагін не копіюємо. Безпеку покриває вбудований скіл `security-review` з Claude Code, якому не потрібні ні ліцензія, ні встановлення.
- Браузером керуємо так само, як penny: через Playwright MCP або Chrome MCP. Python-хелпер `with_server.py` з webapp-testing не переносимо, щоб не додавати Python і Playwright for Python як залежність. З нього беремо лише ідею: скіл сам піднімає сервер і сам його гасить.

Окремий скіл для verification-before-completion відхилено. Правило «доказ перед "готово"» стосується кожного кроку amy, тож воно живе в amy, а не чекає окремого тригера.

## 3. Solution

### 3.1 amy — зміни в `skills/amy/SKILL.md`

1. Новий розділ **`## Verify before claiming`** (за мотивами superpowers verification-before-completion), розміщений перед `## Before calling the work done`:
   - Будь-яке твердження «пройшло», «виправлено», «готово» спирається на прогін команди **в поточному повідомленні**. Вивід показується, а не переказується.
   - Ці формулювання доказом не вважаються: «має працювати», «мабуть», «виглядає правильно», результат попереднього прогону, звіт субагента без виводу.
   - Порядок: визначити команду, яка доводить твердження → запустити її повністю → прочитати вивід і exit code → лише тоді формулювати твердження разом із доказом.
2. У таблицю `## When stuck` додається рядок: «The test fails for a reason you did not predict → invoke `leslie` before changing code».
3. До чекліста `## Before calling the work done` додається пункт: `- [ ] The output of the latest run is shown, not summarised`.

### 3.2 leslie — новий `skills/leslie/SKILL.md`

Системний дебаг, адаптований із superpowers `systematic-debugging`.

- **frontmatter `description`:** `Use when the user reports a bug, a test fails for an unexpected reason, a build or verification is red, or behaviour differs from what was expected. Finds the root cause in four phases before any fix`.
- **Iron Law:** `NO FIX WITHOUT A ROOT CAUSE`.
- **Фази:**
  1. **Root cause:** прочитати помилку повністю, стабільно відтворити, перевірити останні зміни (`git diff`, `git log`), простежити дані до місця, де вони вперше стають хибними. У багатокомпонентній системі додати діагностику на межах компонентів.
  2. **Pattern:** знайти робочий аналог у тому ж репо й перелічити всі відмінності.
  3. **Hypothesis:** одна гіпотеза, сформульована явно («X є причиною, бо Y»), перевіряється однією мінімальною зміною. Якщо не підтвердилася — нова гіпотеза, а не друга зміна поверх першої.
  4. **Fix:** викликати `amy` (`pasadena:amy`): тест, що відтворює баг, має впасти з передбаченої причини, потім один фікс першопричини і перевірка за правилом `Verify before claiming`.
- **Правило трьох:** після трьох невдалих фіксів leslie зупиняється, повідомляє, що проблема, ймовірно, архітектурна, і питає користувача, перш ніж пробувати четвертий.
- Наприкінці таблиця `Decision rules` і чекліст.
- **Хто викликає:** користувач; amy, коли тест падає з непередбаченої причини; wolowitz, коли verification хвилі червона (див. 3.5).
- **Під контролером:** коли leslie викликає контролер wolowitz, що диспатчить implementer-ів, вона зупиняється після Phase 3 і повертає першопричину, докази й фікс; Phase 4 виконується в implementer-і. Фази 1–3 при цьому лишаються read-only: тимчасова діагностика прибирається до повернення результату.
- Не має `disallowed-tools`: leslie передає роботу в amy в тому ж ході, тож потрапляє до `routers` у `skills/skills.test.sh`.

### 3.3 bernie — новий `skills/bernie/SKILL.md`

e2e у реальному браузері, **запускається лише вручну**.

- **frontmatter `description`:** `Use when the user asks to check a feature in the browser, run an end-to-end check, or write e2e tests. Drives the running app through Playwright and either reports evidence or adds a lasting e2e test`.
- **Вибір режиму** за запитом: «перевір», «глянь, чи працює» → разова перевірка; «напиши e2e», «додай тест» → сталий тест. Якщо запит неоднозначний, bernie питає один раз.
- **Спільна частина (з webapp-testing):**
  - знайти команду запуску з `package.json` або README;
  - якщо сервер не працює, підняти його у фоні (`run_in_background` у Bash), дочекатися порту через `curl`, після роботи погасити через `TaskStop` лише той сервер, який підняв сам;
  - спершу розвідка: відкрити сторінку, дочекатися networkidle, зробити знімок DOM або accessibility tree;
  - селектори будувати з того, що реально відрендерилось (role, label, text), а не вгадувати класи.
- **Разова перевірка:** пройти сценарій через Playwright MCP або Chrome MCP, зібрати скриншоти ключових станів і помилки консолі, звітувати за правилом `Verify before claiming`. Файлів у репо не лишає.
- **Сталий тест:** раннер e2e, який уже є в проєкті (Playwright Test). Якщо його немає, bernie зупиняється і пропонує рішення щодо залежності, нічого не встановлюючи сам. Цикл — через `amy`: тест падає → мінімальна зміна → тест проходить. Гайди з testdino playwright-skill стиснуті до правил: локатори за role/label, web-first assertions замість `waitForTimeout`, ізольований стан на тест, авторизація через збережений `storageState`.
- **Браузер:** оголошує `mcp__playwright` і Chrome MCP, як penny. Якщо жодного немає (наприклад, Codex без MCP), один раз повідомляє про це і зупиняється. Запасного варіанту лише через shell немає: обидва режими потребують відрендереної сторінки, щоб вибрати селектори.
- Не має `disallowed-tools`, потрапляє до `routers`, бо викликає amy.

### 3.4 stuart — новий `skills/stuart/SKILL.md`

Візуальна перевірка верстки, **запускається лише вручну**. Адаптований із visual-eyes.

- **frontmatter `description`:** `Use when the user says the layout is broken, asks to check responsiveness, or wants a visual check of a page. Screenshots the page at several breakpoints, reports defects with evidence, and fixes them only after approval`.
- **Брейкпоінти за замовчуванням:** 375, 768, 1280, 1920 px завширшки. Користувач може задати свої.
- **Що шукає:** горизонтальний скрол сторінки, текст чи елементи, що виходять за межі контейнера, перекриття, зсунуту або розірвану сітку, обрізані елементи, нечитабельний контраст, порожні стани, які мали бути заповнені.
- **Порядок:**
  1. Підняти сервер (як у bernie) і зняти скриншоти кожного брейкпоінта.
  2. Звіт: дефект → брейкпоінт → скриншот → імовірне CSS-джерело.
  3. **Зупинка й запит згоди** на виправлення.
  4. Після згоди виправити, перезняти ті самі брейкпоінти й показати пари «до/після».
- Порівняння «до/після» робить модель за скриншотами. Піксельного diff-рушія немає.
- Браузер такий самий, як у bernie. Не має `disallowed-tools`.

### 3.5 wolowitz — зміни в `skills/wolowitz/SKILL.md` і `implementer-prompt.md`

1. **Фолбек без субагентів.** Якщо інструмент Agent недоступний, контролер пише код сам. Тоді перед першою задачею він викликає `pasadena:amy` через Skill tool і виконує кожну задачу за її циклом, а в коментарі хвилі на PR зазначає, що хвиля йшла без субагентів.
2. **Червона verification.** Якщо прогін verification хвилі червоний, а причина не очевидна з одного рядка помилки, контролер викликає `leslie` замість фіксу навздогад. Фікс іде окремою задачею через імплементера або, у фолбеку, через amy.
3. **Security-review перед ready-PR.** Після whole-branch review і перед закриттям журналу (`raj` → `gh pr ready`) контролер викликає скіл `security-review` на diff гілки. Знахідки йдуть у fix-хвилю за тими самими правилами, що й знахідки рев'ю. Якщо скіл недоступний (наприклад, у Codex), wolowitz один раз про це каже і фіксує пропуск у коментарі до PR.
4. **`implementer-prompt.md`:** у звіті рядок `One line on what your verification command printed` замінюється вимогою показати хвіст виводу verification (до 10 рядків) з exit code, згідно з `Verify before claiming`.

### 3.6 Супровідні файли

- `skills/skills.test.sh`: `routers="pasadena journal leonard amy leslie bernie"`, плюс нові перевірки з 6.1.
- `README.md` і `README.uk.md`: рядки для `leslie`, `bernie`, `stuart` у таблиці скілів.
- `.claude-plugin/plugin.json`, `.claude-plugin/marketplace.json`, `.codex-plugin/plugin.json`:
  - версія `0.7.0`;
  - опис змінюється з «six skills» на «nine skills», з'являється фраза про leslie, bernie і stuart;
  - keywords: додаються `debugging`, `e2e`, `visual-testing`.
- `THIRD_PARTY_NOTICES.md`:
  - до розділу obra/superpowers додаються `skills/amy/SKILL.md` (розділ Verify before claiming, з `skills/verification-before-completion`) і `skills/leslie/SKILL.md` (з `skills/systematic-debugging`);
  - нові розділи для anthropics/skills `skills/webapp-testing` (Apache-2.0, з повідомленням про зміни) → `skills/bernie/SKILL.md`, testdino-hq/playwright-skill (MIT) → `skills/bernie/SKILL.md`, nikolasdehor/visual-eyes (MIT) → `skills/stuart/SKILL.md`.

### 3.7 Хук-нагадування `nudge`

Headless-прогін 0.7.0 (`claude -p --plugin-dir`) показав: на запит «Тести в price.test.sh падають. Полагодь.» агент не викликав ні `pasadena:leslie`, ні `pasadena:amy`, а одразу правив код. Тригер у `description` на коротке побутове прохання не спрацьовує. Хук додає нагадування в контекст ще до того, як модель вирішить, що задача дрібна.

- **Модуль:** `hooks/nudge.sh`, окремий від `journal.sh`, бо в нього інша задача. Вхід — JSON події `UserPromptSubmit` на stdin, поле `.prompt`. Вихід — або нічого, або `{"hookSpecificOutput":{"hookEventName":"UserPromptSubmit","additionalContext":"<текст>"}}`. Залежності: `jq` і `git`, як у `journal.sh`. Завжди `exit 0`, бо хук ніколи не блокує промпт.
- **Мовчить** (нічого не виводить), якщо:
  - `PASADENA_NUDGE=0`;
  - `git rev-parse --is-inside-work-tree` не дає `true` для cwd;
  - промпт після пробілів починається з `/`;
  - промпт уже містить `leslie`, `amy` або `pasadena:` (без урахування регістру).
- **Група «баг»** (regex без урахування регістру): `баг|помилк|падає|падають|впав|зламал|не працює|полагод|виправ|fix|bug|broken|failing|fails|error|crash|regression`. Текст:
  `This prompt looks like a bug or failing check. Before changing any code, invoke the leslie skill with the Skill tool, as pasadena:leslie, and follow it: root cause first, then the fix through amy.`
- **Група «фіча»** (regex без урахування регістру): `додай|реаліз|імплемент|зроби функц|нов(а|у|ий) фіч|implement|add (a |an )?(feature|function|endpoint|test)|build (a|the)`. Текст:
  `This prompt looks like new behaviour. Before writing production code, invoke the amy skill with the Skill tool, as pasadena:amy: failing test first.`
- Якщо збігаються обидві групи, виводиться лише текст «баг».
- **Реєстрація:**
  - `hooks/claude-hooks.json`: подія `UserPromptSubmit` з командою `bash "${CLAUDE_PLUGIN_ROOT}/hooks/nudge.sh"`, `"shell": "bash"`, `"timeout": 5`;
  - `hooks/hooks.json` (Codex): та сама подія з guard `[ -n "${CLAUDE_PLUGIN_ROOT:-}" ] || bash "${PLUGIN_ROOT}/hooks/nudge.sh"`, `"timeout": 5`, як у наявних хуках.
- `README.md` і `README.uk.md`:
  - речення перед таблицею хуків змінюється на «Codex uses four hooks; Claude Code adds `StopFailure`» (і відповідно в uk);
  - у таблицю додається рядок `` | `UserPromptSubmit` | Reminds the agent to invoke leslie for a bug or amy for new behaviour; silent outside a Git repo. | Same | `` (і переклад в uk);
  - речення «Hooks read Git state and append to the journal» доповнюється: «; `UserPromptSubmit` only adds context to the prompt»;
  - у `## Configuration` додається абзац: `PASADENA_NUDGE=0` вимикає хук-нагадування;
  - у `## Checks` додається рядок `bash hooks/nudge.test.sh`.

## 4. Out of scope

- Semgrep, CodeQL, variant-analysis, fp-check і будь-який текст із trailofbits/skills.
- Плагін `security-guidance` і security-хуки в реальному часі.
- Автоматичний запуск bernie чи stuart із пайплайну та поле `Verify: e2e/visual` у плані leonard.
- CI-модулі, Page Object Model і шардинг з testdino.
- Піксельний diff-рушій і збережені візуальні бейзлайни.
- Python, Playwright for Python і `with_server.py`.
- Окремий скіл для verification-before-completion.
- Класифікація промпту через LLM, налаштовуваний список ключових слів у nudge, нагадування nudge для bernie і stuart.

## 5. Trade-offs accepted

- **Безпека неглибока.** `security-review` дивиться лише на diff гілки, тож незачеплений код не аудитується. Це прийнятно: мета — не пропустити нові вразливості, а повний аудит робиться окремим інструментом за потреби.
- **Адаптовані копії старіють.** Покращення в superpowers чи visual-eyes самі до нас не приходять. Натомість pasadena працює після одного встановлення, а тексти відповідають її стилю.
- **Порівняння «до/після» в stuart суб'єктивне.** Модель порівнює скриншоти без піксельної точності, тож дрібні зсуви на 1–2 px може пропустити.
- **bernie і stuart самі не запускаються.** Без явного запиту e2e і візуальна перевірка не відбуваються, але й не витрачають час і токени на задачах без UI.
- **Без браузерного MCP bernie і stuart недоступні**, наприклад у Codex без Playwright MCP.
- **nudge помиляється на ключових словах.** Наприклад, «виправ опечатку в README» нагадає про leslie. Це лише нагадування, а не блокування, тож агент може його відкинути. Вимикач `PASADENA_NUDGE=0` прибирає його повністю.

## 6. Verification

### 6.1 Автоматично: `bash skills/skills.test.sh`

Нові перевірки пишуться за amy: кожна спершу падає на поточному репо.

- кожен каталог `skills/<name>/` має рядок `` | `<name>` | `` у таблиці скілів і в `README.md`, і в `README.uk.md`;
- для `leslie`, `bernie` і `stuart` шлях `skills/<name>/SKILL.md` згаданий у `THIRD_PARTY_NOTICES.md`;
- поле `version` однакове в `.claude-plugin/plugin.json`, `.claude-plugin/marketplace.json` і `.codex-plugin/plugin.json`;
- `leslie` і `bernie` не мають `disallowed-tools`, бо вони в `routers`.

Також проходять наявні `bash hooks/journal.test.sh` і `bash proto/server.test.sh`.

`bash hooks/nudge.test.sh` подає промпти на stdin і перевіряє вивід. Для «Тести падають. Полагодь.» і для «the build is failing» має бути текст «баг». Для «Додай функцію mul» — текст «фіча». Для «полагодь і додай тест» — лише «баг». Порожній вивід має бути для `/pasadena`, для «виклич pasadena:leslie», для «що таке монада?», з `PASADENA_NUDGE=0` і поза git-репо (тимчасовий каталог із `mktemp -d`). Вихід скрипту — валідний JSON із `hookEventName` = `UserPromptSubmit`.

### 6.2 Вручну: поведінка

1. **Фолбек wolowitz.** У тестовому репо з одним маленьким планом запустити wolowitz із забороненим Agent. Перший Skill-виклик контролера має бути `pasadena:amy`, перший записаний файл — тест.
2. **leslie.** На тестовій гілці навмисно зламати функцію так, щоб тест упав із неочевидної причини, і попросити «полагодь». Агент викликає `pasadena:leslie`, називає гіпотезу до першої зміни коду, а фікс іде через тест від amy.
3. **bernie, разова перевірка.** Запустити `proto/start.sh` і попросити «перевір у браузері, що прототип відкривається». У звіті мають бути скриншот і вивід консолі, а в репо — жодних нових файлів.
4. **stuart.** На HTML-прототипі penny з навмисним `width: 1400px` на контейнері попросити «перевір верстку». Звіт має показати горизонтальний скрол на 375 і 768 px, після чого stuart зупиняється і чекає згоди. Після згоди він показує пари «до/після».
5. **security-review.** Наприкінці будь-якої гілки wolowitz до `gh pr ready` викликає `security-review`. Це видно з виклику Skill у транскрипті й із коментаря на PR.

Сценарії 1 і 2 автоматизовані headless-скриптами (`claude -p --plugin-dir <worktree> --output-format stream-json`) на тимчасових репо. Результат 2026-10-21 до nudge: сценарій 1 пройшов, сценарій 2 провалився (жодного Skill-виклику). Після nudge сценарій 2 проганяється тричі, і в кожному прогоні `pasadena:leslie` має бути першим Skill-викликом до будь-якого Edit.
