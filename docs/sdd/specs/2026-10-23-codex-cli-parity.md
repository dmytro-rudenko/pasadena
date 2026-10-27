# Pasadena для Codex CLI — design

**Date:** 2026-10-23
**Status:** agreed

## 1. Problem

Pasadena на `main` (`70ca24f`, версія `0.9.0`) постачається для Claude Code.
Коміт `bde598c` видалив Codex manifest, marketplace і hooks та прибрав
відповідні гілки зі скілів. Повернення тільки manifest не відновлює workflow:

- Скіли вимагають `Skill`, `EnterPlanMode`, `ExitPlanMode`, `Agent`,
  `SendMessage`, `TaskStop` і `run_in_background`, яких Codex не надає під
  цими іменами.
- `wolowitz` задає Claude-моделі `opus`, `fable`, `sonnet` і `haiku`.
- `hooks/nudge.sh` скеровує до Claude-виклику `pasadena:amy` або
  `pasadena:leslie`, а hooks використовують Claude-конфігурацію.
- Старий `hooks/hooks.json` до `bde598c` пропускав виконання, коли задано
  `CLAUDE_PLUGIN_ROOT`. Codex теж задає цю змінну як compatibility alias,
  тому така перевірка може вимкнути його hooks.
- `skills/skills.test.sh` зараз явно забороняє Codex artifacts і згадки Codex.

Мета — встановлюваний плагін для **Codex CLI** з тим самим порядком SDD,
дисципліною TDD, журналом, паралельними хвилями й перевірками. Підтримка
Claude Code зберігається. Це одна адаптація наявного workflow, а не його форк.

## 2. Constraint that shapes the solution

Користувач погодив **спільні скіли й окремі адаптери Claude/Codex**.
Правила процесу мають одне джерело; адаптери визначають тільки спосіб їх
виконання в конкретному host. Окрему Codex-копію всіх скілів відхилено через
ризик розходження правил. Просте повернення старих manifest і hooks
відхилено через незакриті залежності від Claude та дефект визначення host.

«Ідентична робота» тут означає однакові етапи, переходи, межі запису,
погодження, артефакти й критерії завершення. Синтаксис виклику, інструменти,
модель і UI погодження відповідають host. Це не обіцянка однакового тексту
відповідей двох моделей або однакового інтерфейсу двох CLI.

Погоджений виняток: **Codex не записує автоматично точний тип аварії через
`StopFailure`**. За доступним контрактом немає події з таким `error_type`.
`Stop` не підміняє аварію, а нестабільний transcript не стає API.
Журнал залишається основою відновлення, але точна класифікація аварії та
запис у момент аварійного завершення не гарантуються.

### Перевірені підстави дизайну

Під час shaping локально перевірено `codex-cli 0.164.0`, його `--help`,
`plugin add --help`, `plugin marketplace add --help` і `features list`.
`hooks`, `plugins` і `multi_agent` у цій інсталяції — stable та enabled.
Це базова версія для приймання; старі версії цим дизайном не сертифіковано.

Пакування й довіра hooks звірені з
[official OpenAI documentation](https://developers.openai.com/plugins/build/plugins).
Контракти подій, JSON і відмінність `Stop`, `Interrupt` та `SessionEnd` —
з [Hooks](https://learn.chatgpt.com/docs/hooks).
Успадкування моделі й робота субагентів —
з [Subagents](https://learn.chatgpt.com/docs/agent-configuration/subagents).
Керування `/plan` —
з [Developer commands](https://learn.chatgpt.com/docs/developer-commands).

Це технічна інтеграція в наявний CLI без нового візуального інтерфейсу.
Еквівалент prototype gate — дослідження репозиторію, CLI help і контрактів
runtime. Браузерний прототип не потрібний. Реальне встановлення адаптованого
пакета й наскрізний запуск **ще не виконано**; вони є критеріями реалізації
нижче, а не результатами shaping.

## 3. Solution

### 3.1 Компоненти та їхні межі

| Компонент | Відповідальність і використання | Залежності |
|---|---|---|
| `skills/*/SKILL.md` | Визначають процес, переходи, межі запису й докази завершення; читаються при вході у скіл | Адаптер активного host, артефакти задачі |
| `skills/pasadena/references/claude.md` | Зіставляє операції workflow з Claude Code; завантажується до першої платформної операції | Інструменти Claude Code |
| `skills/pasadena/references/codex.md` | Зіставляє ті самі операції з Codex CLI; завантажується також при прямому вході в будь-який скіл | Доступні інструменти поточної Codex-сесії |
| Manifest і marketplace кожного host | Оголошують один пакет `pasadena`, спільні скіли й відповідний hooks config | Пакетний менеджер host |
| `hooks/claude-hooks.json`, `hooks/codex-hooks.json` | Реєструють підтримувані події й явно задають host для shell-виклику | Runtime hooks і довіра користувача |
| `hooks/journal.sh`, `hooks/nudge.sh` | Спільна механіка журналу та нагадувань; обробляють stdin JSON | `bash`, `git`, `jq`, відповідний hooks config |
| `proto/*` | Наявний сервер прототипів; використовується через адаптер процесів | Node.js, браузерний MCP для роботи з браузером |

Окремий генератор скілів, MCP-сервер або другий файл стану не вводяться.
Кожний скіл явно вимагає завантажити адаптер, навіть якщо користувач
увійшов напряму через `$amy` чи `$raj`, оминувши `$pasadena`.
Шляхи до адаптерів і scripts визначаються від каталогу завантаженого пакета,
а не від поточного проєкту чи припущення про глобальний plugin cache.

Host визначається середовищем поточної сесії. Наявність
`CLAUDE_PLUGIN_ROOT` не є способом відрізнити Codex від Claude.
Shell-виклики hooks явно отримують `PASADENA_HOST=claude` або
`PASADENA_HOST=codex`; відсутнє значення при прямому запуску зберігає
поточний Claude-сумісний режим. Це аргумент виконання, не файл стану.

### 3.2 Пакування та встановлення

Для Claude залишаються `.claude-plugin/plugin.json`,
`.claude-plugin/marketplace.json` і явний шлях `./hooks/claude-hooks.json`.
Для Codex додаються:

- `.codex-plugin/plugin.json`: `name: pasadena`, `skills: ./skills/`,
  явний `hooks: ./hooks/codex-hooks.json`;
- `.agents/plugins/marketplace.json`: marketplace `pasadena`, один плагін
  `pasadena` з локальним source `./`, щоб перевіряти поточний checkout;
- `hooks/codex-hooks.json`: тільки підтримувані Codex-події, без `StopFailure`.

Відносні шляхи manifest починаються з `./` і залишаються всередині пакета.
У релізі адаптації версія плагіна — `0.10.0`; усі manifest-поля версії,
які присутні в обох форматах, узгоджені. Спека й журнал самі версій не змінюють.

Документований GitHub install після потрапляння реалізації на `main`:

```bash
codex plugin marketplace add dmytro-rudenko/pasadena
codex plugin add pasadena@pasadena
codex
```

Для перевірки до merge перша команда приймає абсолютний шлях до checkout
реалізації замість GitHub source. Чисте середовище перевірки має окремий
`CODEX_HOME`, штатний login і не використовує встановлену глобальну копію.

Користувач переглядає та довіряє hooks через штатний `/hooks`.
Плагін не обходить hook trust, не послаблює sandbox і не змінює глобальний
`config.toml` для прихованого ввімкнення можливостей. README обома мовами
описують установлення, довіру, залежності й погоджене обмеження аварій.

### 3.3 Вхід, routing і завантаження скілів

Наявні дев'ять робочих скілів і два routing-скіли залишаються спільними:
`sheldon`, `penny`, `leonard`, `wolowitz`, `amy`, `leslie`, `bernie`,
`stuart`, `raj`, а також `pasadena` і `journal`.

Для Codex додається `skills/bazinga/SKILL.md`: тонкий alias до `pasadena`,
який передає запит і не має власної логіки стану. Claude-команда
`commands/bazinga.md` зберігається. Входи Codex: `$pasadena`, `$journal`,
`$bazinga` та прямі виклики робочих скілів. За неоднозначних імен
завантажується скіл саме з пакета Pasadena.

У Claude адаптер використовує `Skill` та наявні namespaced імена.
У Codex агент знаходить і повністю читає відповідний `SKILL.md` доступним
інструментом читання. Згадка `$amy` у тексті не вважається завантаженням.
Так само діє субагент перед першою зміною коду.

Routing зберігається:

| Стан | Наступна дія |
|---|---|
| Журнал відсутній або `spec: -` | `sheldon` |
| `spec:` задано, `plan: -` | `leonard` |
| Обидва задано, є незавершені задачі | `wolowitz` |
| Усі задачі завершені | `journal finish` через `raj` |

Classifier `spike` / `bounded` / `architectural`, gates погодження та
обмеження файлів кожного скіла не змінюються. У Codex вони записані явно
в інструкціях; Claude-specific frontmatter не подається як механізм
примусового обмеження Codex. Правила й дозволи runtime мають вищий пріоритет.

### 3.4 Планування та субагенти

У Claude зберігаються `EnterPlanMode` / `ExitPlanMode` і поточна політика
моделей. Codex-адаптер не намагається викликати ці інструменти чи
вдавати перемикання режиму. Якщо користувач уже увімкнув `/plan`,
`leonard` працює в ньому. Інакше подає той самий план у чаті й чекає
явного погодження. Ручне `/plan` доступне користувачеві; воно не є ще
одним обов'язковим погодженням. Запис плану й перехід до build відбуваються
після погодження, як у поточному workflow.

У Codex implementer і reviewer успадковують модель та reasoning поточної
сесії; Claude-ідентифікатори моделей не передаються. Налаштування,
явно задані користувачем або runtime, зберігають пріоритет.
Рев'ю виконує окремий контекст. Доступні native-операції створення,
передачі задач, очікування й повідомлень зіставляються за можливістю,
без припущення, що інструмент має ім'я `Agent`.

Зберігаються Task 0 / Wave 0 з acceptance tests, disjoint `Writes:`,
залежності, одночасний запуск незалежних implementer, тестування хвилі
контролером, review/fix loop і один commit на задачу. Коміти робить
тільки контролер, послідовно. Ліміт активних агентів не обходиться:
задачі хвилі за потреби запускаються групами в межах ліміту.

Коли субагенти недоступні, діє наявний послідовний режим через `amy`;
звіт прямо зазначає відсутність незалежного reviewer. У такому середовищі
не можна заявити, що приймальний сценарій паралельної хвилі перевірено.

### 3.5 Hooks, нагадування й журнал

Codex-команди hooks використовують `${PLUGIN_ROOT}`; Claude-команди —
`${CLAUDE_PLUGIN_ROOT}`. Кожний manifest завантажує тільки власний config:
дублювання реєстрації й runtime-перевірки за compatibility alias не потрібні.

| Codex-подія | Дія Pasadena | Умова й результат |
|---|---|---|
| `SessionStart` | `journal.sh session-start` | `startup|resume|clear|compact|fork`; контекст потрапляє в сесію |
| `UserPromptSubmit` | `nudge.sh` | Той самий пріоритет bug → `leslie`, feature → `amy`, але Codex-спосіб завантаження |
| `PostToolUse` | `journal.sh commit` | Завершені Bash/exec і Git MCP; коміти визначаються за HEAD |
| `SessionEnd` | `journal.sh session-end other` | Без Claude-only matcher; один запис паузи |

Таймаути: `SessionStart` — 10 s, `UserPromptSubmit` — 5 s,
`PostToolUse` — 10 s, `SessionEnd` — 5 s.
Для Codex `PostToolUse` виконується синхронно, щоб закриття сесії не
скасувало ще не записані коміти. Перевірка й запис журналу захищені
спільною критичною секцією для одного journal path: паралельні callbacks
не створюють двох однакових commit lines або day headings.

Заголовки журналу — `## Goal`, `## Now`, `## Timeline`; шлях —
`.pasadena/journal/<branch-with-slashes-replaced-by-dashes>.md`.
Frontmatter, маркери й зміст digest зберігаються. Canonical journal має
пріоритет; `.claude/journal/` читається тільки як legacy fallback без
автоматичної міграції. Стан SDD — `spec:`, `plan:` та checkboxes плану.

`startup`, `resume`, `clear` додають start line; `compact` і `fork`
відновлюють контекст без зайвої start line. Append операції не переписують
попередні записи. Повторний callback для вже записаного HEAD або повторний
`SessionEnd` не дублює відповідну подію. На trunk, detached HEAD або поза
Git діють поточні правила. `PASADENA_TRUNK` і `PASADENA_NUDGE=0` зберігаються.

Nudge не створює журналу й не пише файлів. Прямі виклики скілів і alias
не отримують зайвого нагадування. Діагностика не змішується з JSON stdout.
Відсутній optional dependency або недовірений hook позначається явно;
це не успішне виконання відповідного сценарію.

Claude зберігає чинний `StopFailure`. Codex не реєструє `Stop` як його
заміну і не позначає звичайне завершення відповіді аварією або паузою.
Після збою відновлення починається з останнього `## Now`, plan checkboxes
та фактичного `git log`; незаписана через збій подія не вигадується.

### 3.6 Браузер, процеси та optional-можливості

Для Codex браузерний шлях — Playwright MCP. `penny` використовує чинні
`proto/start.sh` і `proto/stop.sh`; сервер, key і runtime data залишаються
локальними. Результати прототипування й `decision.md` мають ті самі шляхи.

Для серверів `bernie` та `stuart` Codex-адаптер використовує доступний
exec/session API замість `run_in_background` / `TaskStop`, запам'ятовує
створений session/process і завершує тільки його. Сервер користувача
зберігається. Відсутній браузер або сервер, що не запустився, дає явний
неперевірений результат, а не висновок за CSS чи unit tests.

`bernie` і `stuart` залишаються скілами за запитом. Якщо `security-review`
недоступний, діє поточне правило: явно зазначити пропуск; не оголошувати
інший інструмент еквівалентним security-review. Якщо `gh` недоступний,
локальний workflow продовжується з явною позначкою відсутності PR.

## 4. Out of scope

- Codex desktop, IDE, web, remote execution й сертифікація старіших CLI.
- Переписування SDD/TDD, нові правила рев'ю або зміна моделі стану.
- Окрема Codex-копія workflow, генератор пакетів і новий MCP-сервер.
- Обгортка над Codex, патч runtime або парсер transcript для імітації
  `StopFailure`.
- Автоматичне встановлення браузерного MCP, тестового runner або
  `security-review`; залежності не встановлюються приховано.
- Міграція старих журналів, зміни сторонніх проєктів, publish, merge
  або глобальне ввімкнення адаптації під час shaping.

## 5. Trade-offs accepted

- Адаптери додають платформні інструкції, зате правила workflow не
  розходяться між двома копіями.
- Codex погоджує план у чаті, якщо native plan mode не був увімкнений;
  однаковим залишається gate перед реалізацією, не його UI.
- Codex використовує поточну модель для обох ролей замість Claude-моделей;
  незалежність reviewer забезпечується окремим контекстом.
- Синхронний commit hook додає невелику затримку заради завершеного запису.
- Довіра hooks потребує штатної дії користувача після встановлення.
- Погоджене обмеження `StopFailure` залишається видимим у документації
  та звітах про сумісність; повна тотожність аварійних подій не заявляється.

## 6. Verification

Нижче — обов'язкові критерії **майбутньої реалізації**. На етапі цієї
специфікації код, конфігурацію і тести не змінено; їхній успіх тут не заявлено.

### 6.1 Автоматизоване приймання

Новий `tests/codex-cli-acceptance.test.sh` перевіряє публічні межі пакета:
завантажує hook registration, запускає зареєстровані команди зі stdin JSON
у тимчасових Git repositories і перевіряє JSON context та фактичний журнал.
Текстові перевірки manifest і посилань доповнюють ці сценарії, але не
замінюють виконання. Runtime-сценарії з п. 6.2 не підміняються fixtures.

| ID | Критерій | Доказ |
|---|---|---|
| AC-01 | Обидва пакети посилаються на одні спільні скіли й власний hooks config | Manifest parsing, наявність target paths, узгоджені версії |
| AC-02 | Входи `pasadena`, `journal`, `bazinga` і прямі скіли знаходять потрібні інструкції | Структурна перевірка всіх посилань плюс реальні виклики в п. 6.2 |
| AC-03 | Routing відновлює всі чотири стани SDD | Fixture кожного стану плюс runtime resume |
| AC-04 | `startup/resume/clear/compact/fork` передають актуальні Now, artifacts і commits у межах чинного digest | Виконані зареєстровані hooks; правильні start lines без повторів |
| AC-05 | Bash/exec і Git MCP commit потрапляють у журнал рівно один раз | Зміна HEAD у fixture; повторні й конкурентні callbacks; runtime Bash commit |
| AC-06 | `SessionEnd` додає одну паузу з HEAD і dirty files; normal turn не стає аварією | Виконання callbacks і перевірка timeline; відсутність Codex `StopFailure`/імітації через `Stop` |
| AC-07 | Nudge правильно обирає скіл і мовчить у тих самих silent cases | Українські й англійські prompts, explicit skill/alias, non-Git, `PASADENA_NUDGE=0`; обидва host |
| AC-08 | Canonical journal перемагає legacy; trunk/detached/non-Git не створюють зайвих файлів | Реальні temporary repositories і before/after file state |
| AC-09 | Погодження, TDD, waves і review працюють через Codex-інструменти | Наскрізний сценарій п. 6.2, не grep-only assertion |
| AC-10 | Claude-сумісність і prototype runtime збережені | Усі чинні suites плюс Claude smoke; Codex browser smoke за наявності MCP |

Команди автоматизованої перевірки після реалізації:

```bash
bash skills/skills.test.sh
bash hooks/journal.test.sh
bash hooks/nudge.test.sh
bash proto/server.test.sh
bash tests/codex-cli-acceptance.test.sh
git diff --check
```

Кожний shell-suite завершується `All checks passed.` і exit code 0;
`git diff --check` — exit code 0 без виводу. Нові acceptance tests пишуться
першими за `amy` й спочатку падають через відсутню поведінку. Перевірку
`Claude Code only` у skills-suite замінює перевірка обох пакетів.

### 6.2 Реальний CLI-сценарій

1. У чистому середовищі з `codex-cli 0.164.0` встановити пакет із checkout
   реалізації. Перевірити список скілів, спочатку недовірені hooks, потім
   штатне trust через `/hooks` і фактичну доставку context у нову сесію.
2. У тимчасовому проєкті викликати `$pasadena`, `$bazinga`, `$journal`
   та кожний робочий скіл. Перевірити alias і завантаження адаптера при
   прямому вході, без спроб викликати відсутні Claude-інструменти.
3. Провести невелику architectural задачу без нового UI: погоджена spec,
   план і явне погодження до коду, Task 0 з очікуваним RED, далі хвиля
   з двох незалежних задач із різними `Writes:`. Implementer проходять
   `amy`; контролер перевіряє хвилю; окремий reviewer повертає висновок.
   Коміти робить контролер, по одному на задачу.
4. Перервати роботу на зафіксованій межі, виконати resume і compact,
   перевірити правильний етап і наступну задачу без дублювання start lines
   та commits. У fork перевірити відновлення context без нового start line.
5. Завершити задачу через `journal finish`: підсумок у тестовому draft PR,
   видалення активного журналу, commit закриття. Зміни лише в тестовому
   проєкті; жодного merge чи publish. Окремо перевірити послідовний режим
   без субагентів із явною позначкою режиму.
6. З Playwright MCP перевірити старт/стоп прототипу й одного сервера
   браузерного скіла; сервер користувача після перевірки працює.
   Для `stuart` зберігаються ті самі breakpoints і gate перед CSS-змінами.
7. У Claude Code виконати `claude plugin validate .`, завантажити плагін
   із checkout і перевірити alias, nudge, journal restore та commit hook.
   Claude-прогони не підміняються запуском shell callbacks із Codex.

Для кожного пункту зберігаються версія host, команди/дії, exit codes,
фрагменти журналу або відповіді агента, а для браузера — screenshots,
console/network evidence. Чутливі auth і prototype keys у звіт не потрапляють.
Відсутній host, MCP або доступ означає **неперевірено**, а не pass;
AC-09 потребує фактично виконаної паралельної хвилі.

Підсумкове приймання можливе після всіх обов'язкових перевірок.
Погоджене обмеження аварійних записів зазначається окремо й не видається
за реалізований `StopFailure`.
