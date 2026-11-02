# Швидше рев'ю у wolowitz — design

**Date:** 2026-11-02
**Status:** agreed

## 1. Problem

Рев'ю у `wolowitz` забирає 20–35 хв на гілку. Виміряно за транскриптами субагентів
29.10–02.11, 11 гілок, 102 рев'ю:

- рев'юер працює на `sonnet` з `effort: "xhigh"` (`skills/wolowitz/SKILL.md`, **Models**),
  генерує 50–170 тис. вихідних токенів за рев'ю зі стабільною швидкістю ~16 тис./хв,
  тож тривалість рев'ю ≈ обсяг thinking;
- wave review триває 1–7 хв, whole-branch review — 4,5–10 хв;
- кожна хвиля чекає свого рев'ю, перш ніж закомітитися; рев'ю хвиль ідуть послідовно.
  Приклад: гілка `effects` — 5 wave review (20 хв), whole-branch (6,5 хв), security (1 хв);
- у **Finish** `security-review` стартує лише після whole-branch review;
- Codex review (1–4 хв) іде паралельно з `sonnet` і завершується раніше — він не вузьке місце.

## 2. Constraint that shapes the solution

Якість рев'ю всієї гілки не знижується: whole-branch review лишається на `xhigh`, поруч
із ним — Codex і `security-review`. Економія береться з проміжних рев'ю, бо whole-branch
review однаково бачить увесь diff. Тому проміжні рев'ю стають рідшими й легшими, а не
зникають: Wave 0 фіксує acceptance-тести, на яких тримається решта роботи, тож її
рев'ю лишається одразу.

Очевидну альтернативу — Codex як wave reviewer — відкинуто: інший рев'юер з іншими
сліпими зонами, і `docs/sdd/specs/2026-10-23-codex-exec-delegation.md` уже виносить
«Codex як основний ревʼюер» за межі.

## 3. Solution

### 3.1. Графік рев'ю

Хвилі нумеруються, як у плані: Wave 0 — лише Task 0, далі хвилі 1…N, де N — номер
останньої хвилі.

- **Wave 0** рев'юється одразу після верифікації, як сьогодні: fix loop до коміту,
  виправлення входять у коміт Task 0. Diff — за 3.4.
- **Хвилі 1…N** групуються по три: 1–3, 4–6, 7–9… Хвиля k закриває групу, коли
  `k mod 3 = 0`.
- **Групове рев'ю** запускається після хвилі k, яка закриває групу, лише коли `k < N`.
  Воно охоплює `GROUP_BASE..HEAD`, де `GROUP_BASE` — `HEAD` на кроці 1 першої хвилі
  групи (хвилі 1, 4, 7…).
- `GROUP_BASE` переживає компакцію: контролер записує рядок `GROUP_BASE: <sha>` у
  `## Now` на кроці 8.2 кожної хвилі групи. Коли рядка немає, `GROUP_BASE` — батьківський
  коміт першого коміту задач першої хвилі групи за `git log`.
- Решта хвиль без окремого рев'ю. Їхній код перевіряє наступне групове рев'ю або
  whole-branch review.

Наслідок: при N ≤ 3 групових рев'ю немає. При N = 5 — одне, після хвилі 3; хвилі 4–5
перевіряє whole-branch review. При N = 6 — одне, після хвилі 3; хвиля 6 остання.

### 3.2. Порядок кроків хвилі

Хвиля без рев'ю: record base → dispatch → verify → commit → PR comment → close.
Кроки 4–5 (review, fix loop) пропускаються.

Хвиля, що закриває групу при `k < N`: record base → dispatch → verify → commit задач
хвилі → групове рев'ю → fix loop → fix-коміти → PR comment → close. Чекбокси хвилі k
ставляться лише після групового рев'ю, тож сесія, яка відновилася й бачить коміти
хвилі k без чекбоксів, запускає групове рев'ю.

Wave 0: порядок як сьогодні — verify → review → fix loop → commit.

### 3.3. Fix loop після групового рев'ю

- Розподіл знахідок не змінюється: щодо коду — implementer задачі, щодо тестів — її test
  writer, раунди 1–2 через `SendMessage`, раунд 3 — нова пара за
  `references/two-dispatch.md`. Codex-задачі — за `references/codex-tasks.md`. Адресат
  може бути з хвилі, що завершилася дві хвилі тому.
- **Недосяжний адресат** (компакція, втрачений id): тест-фікс іде до нового test writer за
  наявним правилом `two-dispatch.md`; фікс коду — до нового implementer, якому
  **Context** дозволяє писати лише `**Writes:**` цієї задачі; номер раунду не змінюється.
  Недосяжний Codex thread — задача переходить до нового Claude implementer за правилом
  раунду 3 з `codex-tasks.md`.
- Виправлення лишаються незакоміченими, поки триває fix loop. Після кожного раунду —
  повна верифікація, потім повторне рев'ю (3.4).
- Коли fix loop закрито, контролер комітить виправлення окремим комітом на кожну задачу, в
  порядку задач: стейджить лише `**Writes:**` задачі, повідомлення
  `fix(<scope>): review findings for task N`, опис 30–40 слів, як для коміту задачі.
- Знахідки, відкриті після трьох раундів, паркуються, як сьогодні.
- Результат рев'ю й рішення щодо `Declined to judge` — у PR-коментар хвилі k: які хвилі
  покрито, скільки знахідок, sha fix-комітів.

### 3.4. Рев'юер

`reviewer-prompt.md` стає шаблоном для Wave 0 і групового рев'ю: «Review waves `<a>`–`<b>`»
(для Wave 0 — `a = b = 0`).

**Diff.** Перед рев'ю контролер робить `git add -N` на нових файлах із `**Writes:**`
задач, що рев'юються, і дає рев'юеру `git diff <BASE>` — коміти плюс робоче дерево. Для
Wave 0 це незакомічений Task 0, для групи — `GROUP_BASE` і закомічені хвилі. Так
закривається і сьогоднішня прогалина: зараз крок 4 рев'ює `BASE..HEAD` до коміту на
кроці 6, і цей diff порожній.

**Повторне рев'ю** після раунду fix loop (Wave 0 і групи; fix wave у **Finish** — без
змін): `SendMessage` тому самому рев'юеру з `git diff HEAD` після `git add -N` на нових
файлах виправлень. Якщо рев'юер недосяжний — новий рев'юер на `sonnet`/`high` за тим самим
шаблоном над цим diff. Нові знахідки повторного рев'ю — наступний раунд; після раунду 3
вони паркуються.

Перевірки cross-task collisions
застосовуються в межах кожної хвилі; interface drift — у межах усієї групи, бо пізніші
хвилі споживають інтерфейси ранніх. Зберігаються рядки `Review for pasadena:wolowitz`,
`reasonable person`, `## Declined to judge`, «Do not re-run the tests».

### 3.5. Finish

1. `git fetch origin <trunk>`, як сьогодні.
2. В одному повідомленні у фоні: whole-branch review (`sonnet`, `xhigh`) над
   `git merge-base origin/<trunk> HEAD..HEAD` і `codex.sh review`, коли Codex доступний.
   Одразу після цього, поки вони працюють, контролер викликає скіл `security-review`
   через Skill tool. Усі три рев'ю йдуть одночасно.
3. Коли всі три повернулися: правила для знахідок Codex (`file:line`), `Declined to judge`
   і security stop gate — як сьогодні. Security-знахідка, що потребує рішення поза кодом,
   зупиняє роботу до fix wave.
4. Одна fix wave для всіх знахідок за `references/two-dispatch.md`, як сьогодні.
   Виправлення комітяться одним комітом
   `fix(<scope>): whole-branch and security review findings`.
5. Далі без змін: фінальний PR-коментар, `journal finish`, `gh pr ready`.

### 3.6. Models

Рядок `| Wave reviewer and whole-branch review | `sonnet` | `xhigh` |` замінюють два:

| Dispatch | `model` | `effort` |
|---|---|---|
| Wave 0 review and grouped wave review | `sonnet` | `high` |
| Whole-branch review | `sonnet` | `xhigh` |

Решта рядків і правило «Every dispatch sets `model` and `effort` explicitly» без змін.

### 3.7. Without subagents

Той самий графік: контролер сам рев'ює Wave 0, групи й гілку, а виправлення робить
через `amy`. Fix-коміти — за тими самими правилами.

### 3.8. Файли

- `skills/wolowitz/SKILL.md` — **Models**, **Without subagents**, **The wave loop**
  (кроки 1, 4–8), **Finish**, **Decision rules**. Графік (3.1) лишається тут і містить
  фразу `every third wave`. `SKILL.md` має обмеження в 20 000 байтів (`skills.test.sh`),
  а зараз займає 17 802, тож процедура групового рев'ю (3.2–3.4) переходить у новий
  файл.
- `skills/wolowitz/references/grouped-review.md` — новий файл. `SKILL.md` вимагає
  прочитати його перед першим груповим рев'ю і знову після компакції, як роблять
  `two-dispatch.md` і `codex-tasks.md`.
- `skills/wolowitz/reviewer-prompt.md` — шаблон за 3.4.
- `skills/wolowitz/references/two-dispatch.md`, `references/codex-tasks.md` — рядок
  «suite, review, commit, PR comment» узгоджується з тим, що рев'ю буває не в кожній хвилі.
- `README.md`, `README.uk.md` — опис `wolowitz` (рядок 22) і таблиця моделей (рядки
  146–148 / 144–146).
- `skills/skills.test.sh` — перевірки нових рядків **Models** і графіка, версія.
- `.claude-plugin/plugin.json`, `.claude-plugin/marketplace.json` — `0.15.0` → `0.16.0`.

## 4. Out of scope

- Codex як wave reviewer.
- Моделі й effort implementer, test writer, fix wave.
- Зміни в `hooks/codex.sh` і шаблоні плану `leonard`.
- Правка історичних spec: `2026-11-01-skill-model-routing.md`,
  `2026-11-02-skill-frontmatter-models.md`.
- Рев'ю хвиль за розміром diff чи складністю задач — графік фіксований, по три хвилі.

## 5. Trade-offs accepted

- Дефект у хвилі 1 знаходять після хвилі 3, коли на ньому вже збудовано дві хвилі; його
  виправлення дорожче. Повна верифікація після кожної хвилі лишається, тож ловить
  усе, що видно тестам.
- Історія більше не строго «один коміт на задачу»: з'являються `fix(...)`-коміти. Зате
  видно, що саме змінило рев'ю, і не потрібен force-push.
- Implementer зі старшої хвилі отримує знахідку, коли його контекст уже давній. Раунд 3
  з новою парою лишається запасним виходом.
- `high` замість `xhigh` для проміжних рев'ю може пропустити тонші проблеми; їх
  підстраховують whole-branch review на `xhigh`, Codex і `security-review`.

## 6. Verification

- `bash skills/skills.test.sh` зелений; він перевіряє обидва нові рядки **Models**, відсутність
  `| Wave reviewer and whole-branch review |`, фразу `every third wave` і посилання
  `references/grouped-review.md` у `SKILL.md`, наявність цього файлу, рядок `GROUP_BASE` у
  ньому, версію `0.16.0` в обох маніфестах і розмір `SKILL.md` до 20 000 байтів.
- `bash hooks/codex.test.sh`, `bash hooks/nudge.test.sh` зелені.
- Ручна перевірка на наступній гілці з планом, де N ≥ 4: у транскрипті субагентів —
  рев'ю Wave 0 і групове рев'ю на `sonnet/high`, whole-branch на `sonnet/xhigh`, жодного
  рев'ю після хвиль, що не закривають групу; `security-review` стартує до повернення
  whole-branch review. Оцінка для гілки на кшталт `effects` (хвилі 0–4): ~13 хв рев'ю
  замість 28.
