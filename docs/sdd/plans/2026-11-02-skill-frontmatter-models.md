# Model і effort у frontmatter, окремий test writer — implementation plan

**Goal:** кожен `skills/*/SKILL.md` задає `model` і `effort` у рядках 4–5 frontmatter; `wolowitz` будує кожну Claude-задачу парою test writer (викликає `amy`, лише тести) → implementer (без `amy`, лише код) з Gate red і Gate green; README описують обидві таблиці моделей; версія плагіна `0.15.0`.
**Spec:** docs/sdd/specs/2026-11-02-skill-frontmatter-models.md
**Verification:** `bash skills/skills.test.sh && bash hooks/journal.test.sh && bash hooks/codex.test.sh && bash hooks/nudge.test.sh`, останній рядок `All checks passed.`

## Global constraints

- Skills, промпти й references пишуться англійською, `README.uk.md` — українською. Текст із задач вставляти дослівно.
- Жодних коментарів у коді.
- Рядок 4 кожного `SKILL.md` — `model: <value>`, рядок 5 — `effort: <value>`, одразу після рядка 3 `description:`. Решта frontmatter не змінюється.
- Не змінювати: `hooks/codex.sh`, `skills/wolowitz/implementer-prompt-codex.md`, `skills/wolowitz/references/codex-tasks.md`, `skills/wolowitz/reviewer-prompt.md`, розділ `## Without subagents` у `skills/wolowitz/SKILL.md`, тіло `skills/leonard/SKILL.md`.
- `skills/wolowitz/SKILL.md` має лишитися меншим за 20 000 байт.
- Збірка виконується кешованою `0.14.0`. Ручний прогін із пункту 2 Verification специфікації можливий лише після встановлення `0.15.0` і лишається за користувачем.

## Review Focus

- Dispatch або промпт implementer-а, що все ще каже завантажити `amy` (крок 2 wave loop, fix loop, Finish): `amy` має з'являтися лише в dispatch test writer-а.
- `references/codex-tasks.md` каже «round 3 goes to a fresh Claude implementer per **Models**»: `SKILL.md` має однозначно читати це як свіжу пару з `references/two-dispatch.md`.
- Finish, де частина знахідок потребує тесту, а частина ні: один test writer отримує лише ті, що потребують тесту, потім один implementer отримує всі.
- Test writer mutation-форми, якому промпт каже «stop on red»: його тести проходять одразу, тож він має звітувати green.
- Задача без тестового файлу у `**Writes:**`: implementer іде в першому етапі хвилі, без Gate red.

## Waves

| Wave | Tasks | Why together |
|---|---|---|
| 0 | 0 | alone — acceptance tests, red until the last wave |
| 1 | 1, 2, 3, 4 | disjoint: десять `SKILL.md` поза `wolowitz` / `skills/wolowitz/` / README / маніфести й стара специфікація |

Серіалізувати нічого не довелося. Frontmatter `wolowitz/SKILL.md` віддано Task 2, бо цей файл уже пише вона.

### Task 0: acceptance tests

**Writes:** `skills/skills.test.sh`
**Executor:** claude
**Covers:** spec §6 п.1 через перевірки §3.8: frontmatter у кожному `SKILL.md` і точні значення з §3.1; matrix §3.7 у `wolowitz`; `test-writer-prompt.md` з `pasadena:amy`; `implementer-prompt.md` без `amy`, `## Red dispatch`, `## Green dispatch`; `references/two-dispatch.md` замість `references/complex-tasks.md`; дві таблиці моделей в обох README; `0.15.0`; посилання зі старої специфікації.

- [x] **Step 1: write the acceptance tests.**
  1. Замінити весь блок від рядка `echo "Model routing"` до рядка `[ "$fails" -eq "$before" ] && ok "model routing checked"` включно (зараз рядки 141–174) на:

```bash
echo "Frontmatter models"
before=$fails
for file in "$SKILLS"/*/SKILL.md; do
  name="$(basename "$(dirname "$file")")"
  fm="$(awk 'NR > 1 && /^---$/ { exit } NR > 1' "$file")"
  if ! grep -qxE 'model: (opus|sonnet)' <<<"$fm" || ! grep -qxE 'effort: (low|medium|high|xhigh|max)' <<<"$fm"; then
    fail "$name: frontmatter needs model: opus|sonnet and effort: low|medium|high|xhigh|max"
  fi
done
while read -r name model effort; do
  [ "$(sed -n '4,5p' "$SKILLS/$name/SKILL.md")" = "$(printf 'model: %s\neffort: %s' "$model" "$effort")" ] ||
    fail "$name: lines 4-5 are not model: $model, effort: $effort"
done <<'EOF'
amy opus high
sheldon opus high
leonard opus high
leslie opus high
wolowitz opus medium
penny opus medium
bernie sonnet xhigh
stuart sonnet xhigh
pasadena sonnet medium
raj sonnet medium
journal sonnet medium
EOF
[ "$fails" -eq "$before" ] && ok "frontmatter models checked"

echo "Model routing"
before=$fails
require leonard '**Complexity:** routine | complex'
require leonard '- the task is `**Complexity:** routine`;'
require leonard 'When in doubt, write `complex`.'
require wolowitz '| Test writer: Task 0, red of every task, test fixes, round 3, Finish | `opus` | `high` |'
require wolowitz '| Implementer, `routine` | `sonnet` | `xhigh` |'
require wolowitz '| Implementer: `complex`, round 3, Finish | `opus` | `medium` |'
require wolowitz '| Wave reviewer and whole-branch review | `sonnet` | `xhigh` |'
require wolowitz '| `Explore`, when `codex.sh available` exits non-zero | `sonnet` | `xhigh` |'
require wolowitz '## Test writer and implementer'
require wolowitz 'A task with no `**Complexity:**` line is `complex`.'
require wolowitz 'test-writer-prompt.md'
require wolowitz 'references/two-dispatch.md'
wolowitz_flat="$(tr '\n' ' ' <"$SKILLS/wolowitz/SKILL.md")"
! grep -qF 'whole `amy` cycle' <<<"$wolowitz_flat" || fail "wolowitz: a routine task still runs the whole amy cycle"
! grep -qF '## Complex tasks' "$SKILLS/wolowitz/SKILL.md" || fail "wolowitz: still has ## Complex tasks"
! grep -qF 'on Fable' "$SKILLS/wolowitz/SKILL.md" || fail "wolowitz: implementers still follow a Fable session"
! grep -qF "session's model" <<<"$wolowitz_flat" || fail "wolowitz: a dispatch still follows the session's model"
! grep -rqF --exclude=skills.test.sh 'complex-tasks.md' "$SKILLS" || fail "wolowitz: complex-tasks.md still referenced"
! grep -rqE '(Red|Green) dispatch' "$SKILLS/wolowitz" || fail "wolowitz: a Red or Green dispatch is still named"
test_writer="$SKILLS/wolowitz/test-writer-prompt.md"
if [ -f "$test_writer" ]; then
  grep -qF 'pasadena:amy' "$test_writer" || fail "test-writer-prompt.md: does not invoke pasadena:amy"
  grep -qF 'only the tests' "$test_writer" || fail "test-writer-prompt.md: missing \"only the tests\""
else
  fail "test-writer-prompt.md: missing"
fi
implementer="$SKILLS/wolowitz/implementer-prompt.md"
! grep -qiw 'amy' "$implementer" || fail "implementer-prompt.md: still mentions amy"
for block in "Red dispatch" "Green dispatch"; do
  ! grep -qF "## $block" "$implementer" || fail "implementer-prompt.md: still has \"$block\""
done
grep -qF 'checksums are recorded' "$implementer" || fail "implementer-prompt.md: does not protect the tests"
require_ref two-dispatch.md 'Gate red'
require_ref two-dispatch.md 'Gate green'
require_ref two-dispatch.md 'test-writer-prompt.md'
[ ! -e "$SKILLS/wolowitz/references/complex-tasks.md" ] || fail "references/complex-tasks.md: still present"
for readme in README.md README.uk.md; do
  grep -qF '| `wolowitz`, `penny` | `opus` | `medium` |' "$ROOT/$readme" || fail "$readme: no skill model table"
  grep -qF -- '--advisor' "$ROOT/$readme" || fail "$readme: no advisor note"
done
grep -qF '| Implementer, `complex` task, round 3, final fix | `opus` | `medium` |' "$ROOT/README.md" || fail "README.md: no dispatch model table"
grep -qF '| Implementer, `complex`-задача, раунд 3, фінальний fix | `opus` | `medium` |' "$ROOT/README.uk.md" || fail "README.uk.md: no dispatch model table"
! grep -qF 'stays on your own settings' "$ROOT/README.md" || fail "README.md: the main session still stays on the user's settings"
! grep -qF 'лишається на ваших налаштуваннях' "$ROOT/README.uk.md" || fail "README.uk.md: the main session still stays on the user's settings"
for manifest in .claude-plugin/plugin.json .claude-plugin/marketplace.json; do
  grep -qF '"version": "0.15.0"' "$ROOT/$manifest" || fail "$manifest: not on 0.15.0"
done
grep -qF '2026-11-02-skill-frontmatter-models.md' "$ROOT/docs/sdd/specs/2026-11-01-skill-model-routing.md" ||
  fail "docs/sdd/specs/2026-11-01-skill-model-routing.md: no link to the spec that supersedes it"
[ "$fails" -eq "$before" ] && ok "model routing checked"
```

  2. У блоці `echo "Upstream adoption"` видалити п'ять рядків: `require wolowitz 'references/complex-tasks.md'` і чотири `require_ref complex-tasks.md …` (`'Gate red'`, `'Gate green'`, `'**Red dispatch**'`, `'**Green dispatch**'`). Решту блоку не чіпати.
- [x] **Step 2: run them, watch them fail** — `bash skills/skills.test.sh | tail -1`, expect `FAILED: 50` (ruling у Wave 0: +1 перевірка `require wolowitz '- for a test writer only, the instruction to invoke the `amy` skill'`, а перевірка Complexity читає `wolowitz_flat`): поведінки ще немає. Склад: десять skills поза `wolowitz` дають 20 (`grep -cE 'FAIL — (amy|bernie|journal|leonard|leslie|pasadena|penny|raj|sheldon|stuart): (frontmatter needs|lines 4-5)'`); `wolowitz` дає 21 (`grep -cE 'FAIL — (wolowitz|test-writer-prompt\.md|implementer-prompt\.md|references/)'`); README дають 6 (`grep -cE 'FAIL — README(\.uk)?\.md:'`); маніфести й стара специфікація дають 3 (`grep -cE 'FAIL — (\.claude-plugin/|docs/sdd/specs/)'`).

### Task 1: frontmatter у десяти skills

**Writes:** `skills/amy/SKILL.md`, `skills/bernie/SKILL.md`, `skills/journal/SKILL.md`, `skills/leonard/SKILL.md`, `skills/leslie/SKILL.md`, `skills/pasadena/SKILL.md`, `skills/penny/SKILL.md`, `skills/raj/SKILL.md`, `skills/sheldon/SKILL.md`, `skills/stuart/SKILL.md`
**Reads:** `skills/skills.test.sh`
**Depends on:** Task 0
**Executor:** claude
**Complexity:** routine
**Satisfies:** рядки `Frontmatter models` для `amy`, `bernie`, `journal`, `leonard`, `leslie`, `pasadena`, `penny`, `raj`, `sheldon`, `stuart`.

- [ ] **Step 1: перевірити red** — `bash skills/skills.test.sh | grep -cE 'FAIL — (amy|bernie|journal|leonard|leslie|pasadena|penny|raj|sheldon|stuart): (frontmatter needs|lines 4-5)'`, expect `20`.
- [ ] **Step 2: implement.**
  1. У кожному файлі вставити два рядки одразу після рядка 3 (`description: …`), щоб вони стали рядками 4 і 5:

| Файл | рядок 4 | рядок 5 |
|---|---|---|
| `skills/amy/SKILL.md` | `model: opus` | `effort: high` |
| `skills/sheldon/SKILL.md` | `model: opus` | `effort: high` |
| `skills/leonard/SKILL.md` | `model: opus` | `effort: high` |
| `skills/leslie/SKILL.md` | `model: opus` | `effort: high` |
| `skills/penny/SKILL.md` | `model: opus` | `effort: medium` |
| `skills/bernie/SKILL.md` | `model: sonnet` | `effort: xhigh` |
| `skills/stuart/SKILL.md` | `model: sonnet` | `effort: xhigh` |
| `skills/pasadena/SKILL.md` | `model: sonnet` | `effort: medium` |
| `skills/raj/SKILL.md` | `model: sonnet` | `effort: medium` |
| `skills/journal/SKILL.md` | `model: sonnet` | `effort: medium` |

  2. У тілі `skills/amy/SKILL.md` два речення описують її як частину implementer-а, а тепер її викликає test writer:
     - речення `It is a technique applied inside whichever skill or implementer is already running, and its writes are that caller's writes; a scope declared here would narrow theirs for the rest of the turn.` замінити на `It is a technique applied inside whichever skill or test writer is already running, and its writes are that caller's writes; a scope declared here would narrow theirs for the rest of the turn.`
     - абзац `Under \`wolowitz\`, \`leonard\` plans the outer loop as Task 0 in Wave 0 and each implementer runs the inner loops of its task. Working alone, you run both.` замінити на `Under \`wolowitz\`, \`leonard\` plans the outer loop as Task 0 in Wave 0. For every later task a test writer runs your red steps and stops on red, and an implementer who does not load you writes the code. Working alone, you run both.`
  3. У жодному з десяти файлів більше нічого не змінювати.
- [ ] **Step 3: перевірити green** — та сама команда, expect `0`.

### Task 2: `wolowitz` — test writer та implementer

**Writes:** `skills/wolowitz/SKILL.md`, `skills/wolowitz/test-writer-prompt.md`, `skills/wolowitz/implementer-prompt.md`, `skills/wolowitz/references/two-dispatch.md`, `skills/wolowitz/references/complex-tasks.md` (видалити)
**Reads:** `skills/skills.test.sh`, `skills/wolowitz/references/codex-tasks.md`
**Depends on:** Task 0
**Executor:** claude
**Complexity:** complex
**Satisfies:** рядки `Frontmatter models` для `wolowitz` і всі перевірки `Model routing`, що починаються з `wolowitz:`, `test-writer-prompt.md:`, `implementer-prompt.md:` і `references/`.

- [ ] **Step 1: перевірити red** — `bash skills/skills.test.sh | grep -cE 'FAIL — (wolowitz|test-writer-prompt\.md|implementer-prompt\.md|references/)'`, expect `21`.
- [ ] **Step 2: frontmatter.** У `skills/wolowitz/SKILL.md` вставити після рядка 3 рядки `model: opus` і `effort: medium`.
- [ ] **Step 3: `## Models`.** Замінити все від `Every dispatch sets` до `` `haiku` is never used.`` включно на:

```markdown
Every dispatch sets `model` and `effort` **explicitly**, whatever model the
session runs on — never leave either to a default, never pick another level to
save cost:

| Dispatch | `model` | `effort` |
|---|---|---|
| Test writer: Task 0, red of every task, test fixes, round 3, Finish | `opus` | `high` |
| Implementer, `routine` | `sonnet` | `xhigh` |
| Implementer: `complex`, round 3, Finish | `opus` | `medium` |
| Wave reviewer and whole-branch review | `sonnet` | `xhigh` |
| `Explore`, when `codex.sh available` exits non-zero | `sonnet` | `xhigh` |

The test writer's row equals `amy`'s frontmatter, so it holds whichever of the
two wins inside the subagent. Read-only lookups go to
`codex.sh explore <prompt-file>` when `codex.sh available` exits 0. `haiku` is
never used.
```

- [ ] **Step 4: розділ `## Complex tasks`.** Замінити весь розділ (від заголовка до рядка перед `## Setup`) на:

```markdown
## Test writer and implementer

Every Claude task is built by two subagents. A test writer, dispatched with
`test-writer-prompt.md`, invokes `amy` and writes only the tests. An
implementer, dispatched with `implementer-prompt.md`, writes only the code and
never loads `amy`; its dispatch does not mention her. `**Complexity:**` decides
only the implementer's row in **Models**. A task with no `**Complexity:**` line
is `complex`. Task 0 is a test writer alone, stopping on red, with no gates.
Some shapes take one role only; the reference names them. A task with
`**Executor:** codex` runs through **Codex tasks**; one handed to Claude because
`codex.sh available` exits non-zero is an ordinary pair on the `routine` row.
Round 3, including after Codex, is a fresh pair. A session with no subagents
skips this section.

Before a wave's first task, read `references/two-dispatch.md` in this skill's
directory, and read it again after a compaction.
```

- [ ] **Step 5: крок `### 2. Dispatch the whole wave at once`.** Замінити текст від `**Dispatch all of the wave's implementers in a single message.**` до рядка `` - `model` and `effort` set per **Models**.`` включно на:

```markdown
**Dispatch the wave's first stage in a single message**: every test writer,
and every implementer of a task that has no test writer. Multiple dispatches in
one response run concurrently, which is the execution model the wave table
establishes. Implementers of paired tasks go after Gate red, per
`references/two-dispatch.md`.

Each dispatch carries what its prompt file lays out. Compose it so the plan
stays the single source of requirements:

- one line on where this task sits in the project;
- the plan's path and the task number, told to read **only** that task plus
  `## Global constraints`; the plan content stays at its source;
- interfaces and decisions from earlier waves that the task requires;
- your resolution of any ambiguity you spotted in the task;
- for a test writer only, the instruction to invoke the `amy` skill
  (`pasadena:amy`) before writing a test — a subagent starts with no skills
  loaded, and naming amy in passing does not load her;
- `model` and `effort` set per **Models**.
```

  Наступний абзац (`A task whose block says **Executor:** codex …`) не змінювати.
- [ ] **Step 6: `leslie` у кроці 3.** Речення `The implementer fixes: the fix goes to the task's implementer — through amy when the session has no subagents — and the verification runs again.` замінити на `The fix goes to the task's subagents — a fix to a test to its test writer, a fix to code to its implementer, or through amy when the session has no subagents — and the verification runs again.`
- [ ] **Step 7: крок `### 5. Fix loop, at most three rounds`.** Замінити два пункти списку й абзац `On a task with red and green implementers, …` (до рядка перед `Findings still open after three rounds are parked.`) на:

```markdown
- **Rounds 1–2:** send the open findings, verbatim, through `SendMessage`:
  findings on code to the task's implementer, findings on tests — a wrong or
  missing test — to its test writer. Both still have the context. After a test
  fix, follow `references/two-dispatch.md`.
- **Round 3:** a fresh pair, per **Models** and `references/two-dispatch.md` —
  framed honestly: "two prior attempts failed on this task; you own it now,
  here is what was tried."
```

- [ ] **Step 8: Finish.**
  1. У пункті 1 речення `One combined fix dispatch receives all findings together; this is the single whole-branch fix wave.` замінити на `All findings go to one fix wave, per references/two-dispatch.md: findings that need a new or changed test go first to one test writer, then one implementer receives every finding under Gate green; when none needs a test, one implementer receives them all. This is the single whole-branch fix wave.` (`references/two-dispatch.md` у backticks.)
  2. У пункті 1 `Every \`sonnet\` finding goes to the fix dispatch.` → `Every \`sonnet\` finding goes to the fix wave.`
  3. У пункті 2 `Findings go to one fix dispatch under the same rules as review findings.` → `Findings go to that fix wave under the same rules as review findings.`; `goes to that fix dispatch;` → `goes to that fix wave;`.
- [ ] **Step 9: Decision rules.** Рядок `| A wave contains multiple tasks | … |` замінити на `| A wave contains multiple tasks | Dispatch the wave's test writers, and implementers of tasks without one, in one message; disjoint write sets provide safe concurrency. Implementers of paired tasks go after Gate red, per \`references/two-dispatch.md\`. |`.
- [ ] **Step 10: `skills/wolowitz/test-writer-prompt.md`** (новий файл):

```markdown
# Test writer dispatch template

Fill the angle brackets. Send every test writer of a wave in **one** message.

---

You are writing the tests for one task of an approved plan. Other agents are
working on other tasks of the same wave right now, in this same worktree. A
separate implementer writes the code after you report.

**Working directory:** `<absolute path to the worktree>`

**Your task:** Task `<N>` in `<path to the plan>`.
Read **only** that task's block and the `## Global constraints` section. Do not
read the rest of the plan — the other tasks are not yours and their detail will
mislead you.

**Spec:** `<path>` — read it if the task's intent is unclear.

**Context you cannot get from the task text:**
<interfaces and decisions produced by earlier waves; your resolution of any
ambiguity you spotted in the task; nothing else>

## Rules

1. **Write only the test files your task's `**Writes:**` line names.**
   Production code is not yours to touch, even to make a test compile. Another
   agent in this wave owns the files you are not listed for. If the task
   genuinely cannot be done without touching another file, stop and report
   `BLOCKED` with the file name — do not touch it.

2. **Do not commit.** The controller commits, one commit per task, after the
   wave is verified. Two `git commit` runs in one worktree race the index lock.

3. **Do not run the whole test suite.** Run only your task's verification
   command. The controller runs the suite once when the wave is done.

4. **Do not dispatch subagents.** Not helpers, not a reviewer.

5. **Invoke the `amy` skill before writing any test** — with the Skill tool,
   as `pasadena:amy` — and follow her for how to write the tests and watch them
   fail. Her green steps and done checklist belong to the implementer. Say in
   your report that you invoked it.

6. **Use exactly the values the task gives.** Names, strings, numbers,
   signatures. If a value looks wrong, write it as given and say so in your
   report.

## Your job

You write the tests, and only the tests. Write every test the task names, run
the task's verification command, and stop on red with its output in your
report. A test that uses something this task creates may fail on it however the
toolchain reports that: leave it and name it in your report.

When the task only covers existing code, its tests pass on arrival: prove each
one with a temporary mutation under amy's rules for existing code, revert the
mutation before you report, and report the verification command green.

Findings on these tests may come back to you through `SendMessage`. In a
test-fix round production code already exists, so a corrected test may pass.
Fix the test, run the verification command, and report its result as it
stands; do not chase red.

## Before you start

If anything in the task is ambiguous, ask now, in one message. Once you begin,
resolve small ambiguities yourself and record them in your report.

## Report back

Under twenty-five lines:

- **Status:** DONE | DONE_WITH_CONCERNS | BLOCKED
- Files you wrote
- The last lines (up to 10) of your verification command's output and its exit code, pasted, not summarised
- Anything you decided that the task did not specify
- Concerns, if any
```

- [ ] **Step 11: `skills/wolowitz/implementer-prompt.md`** — замінити весь файл на:

```markdown
# Implementer dispatch template

Fill the angle brackets. Implementers of tasks with a test writer go after Gate
red, per `references/two-dispatch.md`; the rest go with the wave's first stage.

---

You are implementing one task of an approved plan. Other agents are
implementing other tasks of the same wave right now, in this same worktree.

**Working directory:** `<absolute path to the worktree>`

**Your task:** Task `<N>` in `<path to the plan>`.
Read **only** that task's block and the `## Global constraints` section. Do not
read the rest of the plan — the other tasks are not yours and their detail will
mislead you.

**Spec:** `<path>` — read it if the task's intent is unclear.

**Tests:** `<test file paths>`

**Context you cannot get from the task text:**
<interfaces and decisions produced by earlier waves; your resolution of any
ambiguity you spotted in the task; nothing else>

## Rules

1. **Write only the files your task's `**Writes:**` line names, apart from its
   tests.** Another agent in this wave owns the files you are not listed for.
   Editing one loses their work or yours. If the task genuinely cannot be done
   without touching a file it does not claim, stop and report `BLOCKED` with
   the file name — do not touch it.

2. **Do not commit.** The controller commits, one commit per task, after the
   wave is verified. Two `git commit` runs in one worktree race the index lock.

3. **Do not run the whole test suite.** Run only your task's own verification
   command and the acceptance tests in its `**Satisfies:**` line, which must
   end green. The controller runs the suite once when the wave is done.

4. **Do not dispatch subagents.** Not helpers, not a reviewer. Review comes
   from the controller after your report.

5. **The tests are not yours.** The tests at the paths above were written
   before you started and their checksums are recorded. Do not edit them.
   Write the minimum that makes them pass. When a test itself is wrong, or a
   behaviour you must write has no test, stop and report `BLOCKED` with the
   test and your reason.

6. **Use exactly the values the task gives.** Names, strings, numbers,
   signatures. If a value looks wrong, implement it as written and say so in
   your report.

7. **Evidence before done.** Before you report `DONE`, run the verification
   command fresh and paste its output. An earlier run is not evidence.

## Before you start

If anything in the task is ambiguous, ask now, in one message. Once you begin,
resolve small ambiguities yourself and record them in your report.

## Report back

Under twenty-five lines:

- **Status:** DONE | DONE_WITH_CONCERNS | BLOCKED
- Files you wrote
- The last lines (up to 10) of your verification command's output and its exit code, pasted, not summarised
- Anything you decided that the task did not specify
- Concerns, if any
```

- [ ] **Step 12: `skills/wolowitz/references/two-dispatch.md`** (новий файл) і видалити `skills/wolowitz/references/complex-tasks.md` (`git rm` не робити — лише видалити файл; індекс веде controller):

```markdown
# Test writer and implementer

Bare file names here, apart from `codex.sh`, live in the skill directory above
this file, and other paths are relative to the plugin root. `SKILL.md` stays in
context.

Most tasks are a pair: a test writer with `test-writer-prompt.md`, then an
implementer with `implementer-prompt.md`, with your own gates between them.
Three shapes take one role, through the normal wave loop, with no gates:

- Task 0: a test writer alone, stopping on red; the wave's verification checks
  its red.
- A task with no test file in `**Writes:**` turns existing tests green: an
  implementer alone, on its `**Complexity:**` row, naming those tests.
- A task that only covers existing code has tests that pass on arrival: a test
  writer alone, under amy's rules for existing code. State under **Context** in
  the dispatch that, overriding Rule 1, its temporary mutation may touch the
  code under test outside `**Writes:**`, must be reverted before it reports,
  and that a file another task of this wave writes is `BLOCKED`. Dispatch this
  shape alone, after the wave's other Claude work and before its Codex tasks,
  so no other agent runs tests against the mutation.

A wave runs in stages: every test writer and every implementer without a test
writer go in a single message; when all have reported, run every Gate red; then
send every paired implementer in one message; run every Gate green and finish
its fix rounds; then the one-role tasks that only cover existing code; only
then the wave's Codex tasks, because a Codex call needs no other writer active.

1. **Red.** Dispatch the test writer.
2. **Gate red.** Check it yourself:
   - the test writer's reported files are all test files from the task's
     `**Writes:**`, and `git status --porcelain` shows none of the task's other
     `**Writes:**` files changed;
   - the task's verification command is red, and each failure is the reason
     the plan predicts, or the toolchain's error for something this task has
     yet to create, whatever that toolchain calls it. A mistake in the test
     file itself does not count;
   - record `sha256sum` of the task's test files and copy those files into
     the scratchpad.
   When the gate fails, send the problem to the test writer through
   `SendMessage`, then run Gate red again. At most two such retries; after that
   the task goes to round 3, whose fresh pair goes out in place of the task's
   implementer, in the same stage. Such a task enters the fix loop at round 3.
3. **Green.** Dispatch the implementer, naming the test files.
4. **Gate green.**
   - `sha256sum` of the test files matches the recorded one;
   - the reported files are all in the task's `**Writes:**`, and no test file
     is among them;
   - the task's verification command is green.
5. The rest of the wave — suite, review, commit, PR comment — is unchanged.

One counter per task covers every Gate green failure, `BLOCKED` report and
review round. On a checksum mismatch, first restore the test files from the
scratchpad copy and tell the next implementer they were edited and restored.

A fix to the tests, after `BLOCKED` or a review finding, goes to the test
writer in rounds 1–2. Then record the checksums anew, replace the scratchpad
copy, send the implementer the changed tests, and run Gate green. A missing
test goes the same way as a wrong one. A `BLOCKED` for any other reason, such
as a file outside `**Writes:**`, takes a ruling and costs no round. A fix from
`leslie` follows the same split and counts as a round. Run Gate green after
every fix round 1–2. After a test fix, the test writer's reported files must
also all be test files.

Round 3 is a fresh pair. A new test writer receives the current tests, the open
findings and what was tried; production code already exists, so its gate
checks only that its reported files are all test files, then records the
checksums and the scratchpad copy. A new implementer follows under Gate green.
A one-role task gets a fresh agent of its role. After a Codex task, the fresh
Claude implementer that `references/codex-tasks.md` names is this fresh pair. A
`BLOCKED` still open after round 3 is the broken-plan stop gate: tests and code
cannot agree, so pause and put it to the user.

At **Finish**, findings that need a new or changed test go to one test writer;
record the checksums, then one implementer receives every finding under Gate
green. When no finding needs a test, one implementer receives them all.
```

- [ ] **Step 13: перевірити green** — команда з Step 1, expect `0`; `wc -c <skills/wolowitz/SKILL.md` — менше `20000`.

### Task 3: README — дві таблиці моделей

**Writes:** `README.md`, `README.uk.md`
**Reads:** `skills/skills.test.sh`
**Depends on:** Task 0
**Executor:** claude
**Complexity:** routine
**Satisfies:** шість перевірок `Model routing` з префіксами `README.md:` і `README.uk.md:`.

- [ ] **Step 1: перевірити red** — `bash skills/skills.test.sh | grep -cE 'FAIL — README(\.uk)?\.md:'`, expect `6`.
- [ ] **Step 2: `README.md`.** Під `## Models` замінити абзац `` `wolowitz` sets `model` and `effort` on every dispatch. … `` і таблицю під ним (до порожнього рядка перед `The advisor (`--advisor opus`)`) на:

```markdown
Every skill sets `model` and `effort` in its frontmatter. The override lasts until your next message, then the session returns to your own model; when one turn invokes several skills, the last one wins.

| Skill | Model | Effort |
|---|---|---|
| `amy`, `sheldon`, `leonard`, `leslie` | `opus` | `high` |
| `wolowitz`, `penny` | `opus` | `medium` |
| `bernie`, `stuart` | `sonnet` | `xhigh` |
| `pasadena`, `raj`, `journal` | `sonnet` | `medium` |

`wolowitz` also sets `model` and `effort` on every dispatch. Each Claude task goes to a test writer, who invokes `amy` and writes only the tests, then to an implementer, who writes only the code; `leonard` marks each task `routine` or `complex` in the plan.

| Dispatch | Model | Effort |
|---|---|---|
| Test writer | `opus` | `high` |
| Implementer, `routine` task | `sonnet` | `xhigh` |
| Implementer, `complex` task, round 3, final fix | `opus` | `medium` |
| Reviews, `Explore` fallback | `sonnet` | `xhigh` |
```

  Абзац про advisor не змінювати.
- [ ] **Step 3: `README.uk.md`.** Під `## Моделі` замінити абзац `` `wolowitz` задає `model` і `effort` у кожному dispatch. … `` і таблицю під ним (до порожнього рядка перед `Advisor (`--advisor opus`)`) на:

```markdown
Кожен skill задає `model` і `effort` у своєму frontmatter. Override діє до вашого наступного повідомлення, після чого сесія повертається на вашу модель; коли за один хід викликано кілька skills, діє останній.

| Skill | Модель | Effort |
|---|---|---|
| `amy`, `sheldon`, `leonard`, `leslie` | `opus` | `high` |
| `wolowitz`, `penny` | `opus` | `medium` |
| `bernie`, `stuart` | `sonnet` | `xhigh` |
| `pasadena`, `raj`, `journal` | `sonnet` | `medium` |

`wolowitz` також задає `model` і `effort` у кожному dispatch. Кожна Claude-задача йде спершу до test writer-а, який викликає `amy` і пише лише тести, а потім до implementer-а, який пише лише код; `leonard` позначає кожну задачу в плані як `routine` або `complex`.

| Dispatch | Модель | Effort |
|---|---|---|
| Test writer | `opus` | `high` |
| Implementer, `routine`-задача | `sonnet` | `xhigh` |
| Implementer, `complex`-задача, раунд 3, фінальний fix | `opus` | `medium` |
| Ревʼю, fallback `Explore` | `sonnet` | `xhigh` |
```

  Абзац про advisor не змінювати.
- [ ] **Step 4: перевірити green** — команда з Step 1, expect `0`.

### Task 4: версія `0.15.0` і посилання зі старої специфікації

**Writes:** `.claude-plugin/plugin.json`, `.claude-plugin/marketplace.json`, `docs/sdd/specs/2026-11-01-skill-model-routing.md`
**Reads:** `skills/skills.test.sh`
**Depends on:** Task 0
**Executor:** claude
**Complexity:** routine
**Satisfies:** три перевірки `Model routing` з префіксами `.claude-plugin/` і `docs/sdd/specs/`.

- [ ] **Step 1: перевірити red** — `bash skills/skills.test.sh | grep -cE 'FAIL — (\.claude-plugin/|docs/sdd/specs/)'`, expect `3`.
- [ ] **Step 2: implement.**
  1. `.claude-plugin/plugin.json` рядок 4 і `.claude-plugin/marketplace.json` рядок 12: `"version": "0.14.0"` → `"version": "0.15.0"`.
  2. `docs/sdd/specs/2026-11-01-skill-model-routing.md` рядок 4: `**Status:** agreed` → ``**Status:** agreed; розділ 2 і рядок «`routine`-задача, весь цикл `amy`» замінено специфікацією `docs/sdd/specs/2026-11-02-skill-frontmatter-models.md` ``.
- [ ] **Step 3: перевірити green** — команда з Step 1, expect `0`; `bash skills/skills.test.sh | grep -c 'manifest versions differ'`, expect `0`.
