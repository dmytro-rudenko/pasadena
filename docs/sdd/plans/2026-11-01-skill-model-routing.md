# Маршрутизація моделей та effort у skills — implementation plan

**Goal:** `wolowitz` задає `model` і `effort` явно для кожного dispatch за матрицею зі специфікації, `leonard` розмічає задачі `**Complexity:**`, складні задачі йдуть двома dispatch, а README описують моделі й advisor. Версія плагіна — `0.14.0`.
**Spec:** docs/sdd/specs/2026-11-01-skill-model-routing.md
**Verification:** `bash skills/skills.test.sh && bash hooks/journal.test.sh && bash hooks/codex.test.sh`, останній рядок `All checks passed.`

## Global constraints

- Skills і `implementer-prompt.md` написані англійською, `README.uk.md` — українською. Текст задач вставляти дослівно.
- Жодних коментарів у коді.
- Не додавати `model:` чи `effort:` у frontmatter жодного skill.
- `hooks/codex.sh` і `skills/wolowitz/implementer-prompt-codex.md` не змінювати.
- Ручний прогін із пункту 3 Verification специфікації можливий лише після встановлення `0.14.0`, бо ця збірка виконується кешованою `0.13.0`. Він лишається за користувачем.

## Waves

| Wave | Tasks | Why together |
|---|---|---|
| 0 | 0 | alone — acceptance tests, red until the last wave |
| 1 | 1, 2, 3, 4 | disjoint: `skills/leonard/`, `skills/wolowitz/`, README, `.claude-plugin/` |

Серіалізувати нічого не довелось: усі чотири задачі пишуть різні файли.

### Task 0: acceptance tests

**Writes:** `skills/skills.test.sh`
**Executor:** claude
**Covers:** усі пункти 1 Verification специфікації: матриця в `wolowitz`, поле `**Complexity:**` у `leonard`, блоки `Red dispatch` і `Green dispatch`, відсутність `model:`/`effort:` у frontmatter, таблиця моделей в обох README, версія `0.14.0`.

- [ ] **Step 1: write the acceptance tests** — вставити перед рядком `echo "Manifest versions"`:

```bash
echo "Model routing"
before=$fails
require leonard '**Complexity:** routine | complex'
require leonard '- the task is `**Complexity:** routine`;'
require leonard 'When in doubt, write `complex`.'
require wolowitz '| Task 0 | `opus` | `high` |'
require wolowitz '| `routine` task, the whole `amy` cycle | `sonnet` | `xhigh` |'
require wolowitz '| `complex` task, red | `opus` | `high` |'
require wolowitz '| `complex` task, green | `opus` | `medium` |'
require wolowitz '| Round-3 fresh implementer, including after Codex | `opus` | `medium` |'
require wolowitz '| Fix dispatch after the whole-branch and security reviews | `opus` | `medium` |'
require wolowitz '| Wave reviewer and whole-branch review | `sonnet` | `xhigh` |'
require wolowitz '| `Explore`, when `codex.sh available` exits non-zero | `sonnet` | `xhigh` |'
require wolowitz '## Complex tasks'
require wolowitz 'A task with no `**Complexity:**` line is `complex`.'
! grep -qF 'on Fable' "$SKILLS/wolowitz/SKILL.md" || fail "wolowitz: implementers still follow a Fable session"
! grep -qF "session's model" "$SKILLS/wolowitz/SKILL.md" || fail "wolowitz: a dispatch still follows the session's model"
for block in "Red dispatch" "Green dispatch"; do
  grep -qF "## $block" "$SKILLS/wolowitz/implementer-prompt.md" || fail "implementer-prompt.md: missing \"$block\""
done
for file in "$SKILLS"/*/SKILL.md; do
  if sed -n '2,/^---$/p' "$file" | grep -qE '^(model|effort):'; then
    fail "$file: model or effort in frontmatter lasts one turn only"
  fi
done
grep -qF '| `complex` task, green | `opus` | `medium` |' "$ROOT/README.md" || fail "README.md: no model table"
grep -qF '| `complex`-задача, green | `opus` | `medium` |' "$ROOT/README.uk.md" || fail "README.uk.md: no model table"
for readme in README.md README.uk.md; do
  grep -qF -- '--advisor' "$ROOT/$readme" || fail "$readme: no advisor note"
done
for manifest in .claude-plugin/plugin.json .claude-plugin/marketplace.json; do
  grep -qF '"version": "0.14.0"' "$ROOT/$manifest" || fail "$manifest: not on 0.14.0"
done
[ "$fails" -eq "$before" ] && ok "model routing checked"

```

- [ ] **Step 2: run them, watch them fail** — `bash skills/skills.test.sh | tail -1`, expect `FAILED: 23`: поведінки ще немає. Склад: `leonard` 3, `wolowitz` 12, `implementer-prompt.md` 2, README 4, маніфести 2. Перевірка frontmatter уже зелена, а всі рядки `FAIL` стосуються блоку `Model routing`.

### Task 1: `leonard` розмічає Complexity

**Writes:** `skills/leonard/SKILL.md`
**Depends on:** Task 0
**Executor:** claude
**Satisfies:** три рядки `require leonard` блоку `Model routing`.

- [ ] **Step 1: перевірити red** — `bash skills/skills.test.sh | grep -c 'leonard: missing'`, expect `3`.
- [ ] **Step 2: implement.**
  1. У шаблоні задачі після `**Executor:** codex` додати рядок `**Complexity:** routine`.
  2. У список умов `Executor: codex`, перед рядком про `codex.sh available`, додати `- the task is `**Complexity:** routine`;`.
  3. Після абзацу, що закінчується `The user sees the split when approving the plan.`, вставити:

```markdown
`**Complexity:** routine | complex` decides which models build the task. Write
`complex` when at least one of these holds:

- the task touches concurrency, persisted state or migrations, or security;
- it produces a contract named in another task's `**Depends on:**`, and the task
  text does not give that contract's full shape;
- the repository has no example to model its test on.

Otherwise write `routine`. When in doubt, write `complex`. Task 0 carries no
`**Complexity:**` line: it always runs on Opus at high effort.
```

  4. У блоці `### Task 0: acceptance tests` нічого не змінювати.
- [ ] **Step 3: перевірити green** — та сама команда, expect `0`.

### Task 2: `wolowitz` виконує матрицю

**Writes:** `skills/wolowitz/SKILL.md`, `skills/wolowitz/implementer-prompt.md`
**Depends on:** Task 0
**Executor:** claude
**Satisfies:** рядки `require wolowitz`, дві заборони й перевірка блоків implementer-prompt у `Model routing`.

- [ ] **Step 1: перевірити red** — `bash skills/skills.test.sh | grep -cE 'FAIL — (wolowitz: |implementer-prompt.md: missing)'`, expect `14`.
- [ ] **Step 2: замінити зміст `## Models`** (рядки від `Every dispatch sets` до `never reviews.`) на:

```markdown
Every dispatch sets `model` and `effort` **explicitly**, whatever model the
session runs on — never leave either to a default, never pick a cheaper one to
save cost:

| Dispatch | `model` | `effort` |
|---|---|---|
| Task 0 | `opus` | `high` |
| `routine` task, the whole `amy` cycle | `sonnet` | `xhigh` |
| `complex` task, red | `opus` | `high` |
| `complex` task, green | `opus` | `medium` |
| Round-3 fresh implementer, including after Codex | `opus` | `medium` |
| Fix dispatch after the whole-branch and security reviews | `opus` | `medium` |
| Wave reviewer and whole-branch review | `sonnet` | `xhigh` |
| `Explore`, when `codex.sh available` exits non-zero | `sonnet` | `xhigh` |

Read-only lookups go to `codex.sh explore <prompt-file>` when
`codex.sh available` exits 0. `haiku` is never used.
```

- [ ] **Step 3: три точкові заміни.**
  1. `fresh Claude implementer on the session's\nmodel.` у **Codex tasks** → `fresh Claude implementer per **Models**.`
  2. `- `model` set to the session's model, per **Models**.` → `- `model` and `effort` set per **Models**.`
  3. `a fresh implementer — on the session's model, per **Models** —` → `a fresh implementer, per **Models** —`
- [ ] **Step 4: у `### 5. Fix loop` після пункту Round 3** вставити:

```markdown
On a `complex` task, findings on code go to its green implementer and findings
on tests go to its red implementer.
```

- [ ] **Step 5: перед `## Setup`** вставити:

```markdown
## Complex tasks

`**Complexity:**` decides how a Claude task runs. `routine` is one implementer
through the whole `amy` cycle. `complex` is two dispatches with your own gates
between them. A task with no `**Complexity:**` line is `complex`. A task with
`**Executor:** codex` runs through **Codex tasks**.

A wave with `complex` tasks runs in stages: every red dispatch goes in the
single message with the wave's `routine` implementers; when all have reported,
run every Gate red; then send every green dispatch in one message; run every
Gate green; only then start the wave's Codex tasks.

1. **Red.** Dispatch `implementer-prompt.md` with its **Red dispatch** block.
2. **Gate red.** Check it yourself:
   - the implementer's reported files and `git status --porcelain` show only
     test files from the task's `**Writes:**`;
   - the task's verification command is red, and each failure is the reason
     the plan predicts — a syntax or import error does not count;
   - record `sha256sum` of the task's test files and copy those files into
     the scratchpad.
   When the gate fails, send the problem to the red implementer through
   `SendMessage`, then run Gate red again. At most two such retries; after that
   the task goes to a Round-3 fresh implementer.
3. **Green.** Dispatch `implementer-prompt.md` with its **Green dispatch** block
   to a new implementer, naming the test files.
4. **Gate green.**
   - `sha256sum` of the test files matches the recorded one;
   - the reported files are all in the task's `**Writes:**`, and no test file
     is among them;
   - the task's verification command is green.
5. The rest of the wave — suite, review, commit, PR comment — is unchanged.

A failed Gate green counts as a round of the fix loop. On a checksum mismatch,
first restore the test files from the scratchpad copy and tell the next
implementer they were edited and restored.

When the green implementer reports `BLOCKED` on a wrong test, send its reason to
the red implementer; this counts as a round. After the fix, run Gate red again,
record the checksums anew, and send the green implementer the changed tests.

```

- [ ] **Step 6: в `implementer-prompt.md` перед `## Before you start`** вставити:

```markdown
## Red dispatch

Include this block only for the red half of a `complex` task; delete it
otherwise.

You write the tests, and only the tests. Write every test the task names, run
the task's verification command, and stop on red with its output in your report.
Leave the implementation steps to the next implementer. Production code is not
yours to touch, even to make a test compile. Findings on these tests may come
back to you through `SendMessage`.

## Green dispatch

Include this block only for the green half of a `complex` task; delete it
otherwise.

The tests at `<test file paths>` were written by another implementer and their
checksums are recorded. Do not edit them. Write the minimum that makes them
pass. When a test itself is wrong, stop and report `BLOCKED` with the test and
your reason.

```

- [ ] **Step 7: перевірити green** — команда зі Step 1, expect `0`.

### Task 3: README описують моделі й advisor

**Writes:** `README.md`, `README.uk.md`
**Depends on:** Task 0
**Executor:** claude
**Satisfies:** перевірки таблиці та `--advisor` у `Model routing`.

- [ ] **Step 1: перевірити red** — `bash skills/skills.test.sh | grep -cE 'README(\.uk)?\.md: no (model table|advisor note)'`, expect `4`.
- [ ] **Step 2: у `README.md` перед `## Codex delegation`** вставити:

```markdown
## Models

`wolowitz` sets `model` and `effort` on every dispatch. The main session stays on your own settings; `leonard` marks each task `routine` or `complex` in the plan.

| Dispatch | Model | Effort |
|---|---|---|
| Task 0 (acceptance tests) | `opus` | `high` |
| `routine` task | `sonnet` | `xhigh` |
| `complex` task, red | `opus` | `high` |
| `complex` task, green | `opus` | `medium` |
| Round-3 fresh implementer, final fix dispatch | `opus` | `medium` |
| Reviews, `Explore` fallback | `sonnet` | `xhigh` |

The advisor (`--advisor opus`) is optional and Pasadena does not depend on it: plan approval, `leslie` and the whole-branch review already cover its usual moments. Subagents inherit it, so an Opus subagent with an Opus advisor pays twice for the same check.

```

- [ ] **Step 3: у `README.uk.md` перед `## Делегування в Codex`** вставити:

```markdown
## Моделі

`wolowitz` задає `model` і `effort` у кожному dispatch. Головна сесія лишається на ваших налаштуваннях; `leonard` позначає кожну задачу в плані як `routine` або `complex`.

| Dispatch | Модель | Effort |
|---|---|---|
| Task 0 (acceptance-тести) | `opus` | `high` |
| `routine`-задача | `sonnet` | `xhigh` |
| `complex`-задача, red | `opus` | `high` |
| `complex`-задача, green | `opus` | `medium` |
| Fresh implementer у раунді 3, фінальний fix dispatch | `opus` | `medium` |
| Ревʼю, fallback `Explore` | `sonnet` | `xhigh` |

Advisor (`--advisor opus`) необовʼязковий, і Pasadena від нього не залежить: його типові моменти вже закривають затвердження плану, `leslie` і ревʼю всієї гілки. Субагенти його успадковують, тому Opus-субагент з Opus-advisor двічі платить за ту саму перевірку.

```

- [ ] **Step 4: перевірити green** — команда зі Step 1, expect `0`.

### Task 4: версія 0.14.0

**Writes:** `.claude-plugin/plugin.json`, `.claude-plugin/marketplace.json`
**Depends on:** Task 0
**Executor:** claude
**Satisfies:** перевірка `0.14.0` у `Model routing`.

- [ ] **Step 1: перевірити red** — `bash skills/skills.test.sh | grep -c 'not on 0.14.0'`, expect `2`.
- [ ] **Step 2: implement** — у обох файлах замінити `"version": "0.13.0"` на `"version": "0.14.0"`.
- [ ] **Step 3: перевірити green** — та сама команда, expect `0`; окремо `bash skills/skills.test.sh | grep -c 'manifest versions differ'`, expect `0`.
