# Fold chained subagents — implementation plan

**Goal:** a paired task is built by one task agent (tests → checkpoint → code through `SendMessage`, plus a mutation check on Gate green); a wave of one task runs in the controller; sheldon drafts the design inline; plugin version 0.25.0.
**Spec:** docs/sdd/specs/2026-11-17-fold-subagents.md
**Verification:** `bash skills/skills.test.sh` — last line `All checks passed.`

## Waves
| Wave | Tasks | Why together |
|---|---|---|
| 0 | 0 | alone — acceptance assertions in `skills/skills.test.sh`, red until wave 1 closes |
| 1 | 1, 2, 3, 4, 5 | disjoint write sets: sheldon / wolowitz references+prompts / wolowitz SKILL.md+grouped-review+make-it-right / amy+leslie / READMEs+manifests |

Nothing had to be serialized beyond Task 0: every later task writes its own files, and the only shared contract is the vocabulary in Global constraints.

## Global constraints
- Skill prose stays English; wrap at about 80 columns like the surrounding text. No new comments in shell code.
- **Task agent** is the term for the merged subagent: dispatched with `test-writer-prompt.md`, it invokes `amy`, writes the tests and stops on red; after Gate red the controller sends the same agent the filled `implementer-prompt.md` through `SendMessage`. "Test writer alone" and "implementer alone" are the one-role shapes (Task 0, covering existing code, a task with no test file, an unreachable addressee's code fix).
- **The checkpoint**: after any test change by a task agent, the controller checks its reported files are all test files, records `sha256sum` anew and replaces the scratchpad copy, then sends the green.
- **Mutation check** (part of Gate green): `ub-tools.sh mutator --scan <task's production files>`, drop files with more than 50 sites, then `ub-tools.sh mutator <rest> -- "<task's verification command>"`; one at a time, while no agent of the wave is working. `exit: 0` pass, `exit: 3` survivors → test fix (a round), `exit: 2` → `pasadena:leslie`, `unavailable` → skip with `mutator: skipped (<reason>)` in the wave's `✎` note.
- Model rows, exact:
  `| Task agent, \`routine\` | \`sonnet\` | \`xhigh\` |`,
  `| Task agent: \`complex\`, round 3, Finish | \`opus\` | \`high\` |`,
  `| Test writer alone: Task 0, covering existing code | \`opus\` | \`high\` |`,
  `| Implementer alone, \`routine\` | \`sonnet\` | \`xhigh\` |`,
  `| Implementer alone, \`complex\` | \`opus\` | \`medium\` |`.
- `skills/wolowitz/SKILL.md` must stay under 20000 bytes (existing assertion); the detailed rules live in `references/two-dispatch.md`.

## Review Focus
- A mutation check run while another agent of the wave is still writing: the mutant breaks their tests — two-dispatch must say one at a time, with no agent working (asserted: `Run mutation checks one at a time`).
- A wave whose single task is `**Executor:** codex` must stay on the Codex path, not inline (asserted: `A wave whose only task is not`).
- A review finding on tests reaching a task agent after its green: it must stop after the test change for the checkpoint, not edit code in the same turn (asserted: `**The checkpoint.**`).
- A grouped-review addressee from an earlier wave that is no longer reachable: the test fix goes to a fresh task agent that stops after the test change (asserted: `to its task agent` in grouped-review).

### Task 0: acceptance tests

**Writes:** `skills/skills.test.sh`
**Executor:** claude
**Covers:** "`bash skills/skills.test.sh` — зелений"; "`grep -n 'one subagent per section' skills/sheldon/SKILL.md` — нічого"; "SendMessage … mutator у two-dispatch.md"; "`\"version\": \"0.25.0\"` — два рядки".

- [ ] **Step 1: write the acceptance tests** — edits to `skills/skills.test.sh`:
  1. In `echo "Model routing"`, replace the three lines
     `require wolowitz '| Test writer: Task 0, red of every task, test fixes, round 3, Finish | \`opus\` | \`high\` |'`,
     `require wolowitz '| Implementer, \`routine\` | \`sonnet\` | \`xhigh\` |'`,
     `require wolowitz '| Implementer: \`complex\`, round 3, Finish | \`opus\` | \`medium\` |'`
     with five `require wolowitz '<row>'` lines, one per model row in Global constraints, in that order.
  2. `require wolowitz '## Test writer and implementer'` → `require wolowitz '## Task agent'`.
  3. `require wolowitz '- for a test writer only, the instruction to invoke the \`amy\` skill'` → `require wolowitz '- for a task agent or a test writer, the instruction to invoke the \`amy\` skill'`.
  4. README dispatch rows:
     `grep -qF '| Task agent, \`complex\` task, round 3, final fix | \`opus\` | \`high\` |' "$ROOT/README.md" || fail "README.md: no task agent row"` and
     `grep -qF '| Task agent, \`complex\`-задача, раунд 3, фінальний fix | \`opus\` | \`high\` |' "$ROOT/README.uk.md" || fail "README.uk.md: no task agent row"` replace the two `Implementer, complex` lines.
  5. Every `0.24.1` in the file (the manifest loop in Model routing, its fail message, and the `plugin.json` line in ub-mode) → `0.25.0`.
  6. Replace the whole `echo "Parallel design"` block (from `echo "Parallel design"` through `ok "parallel design checked"`) with:
     ```bash
     echo "Inline design"
     before=$fails
     ! grep -qF 'one subagent per section' "$SKILLS/sheldon/SKILL.md" || fail "sheldon: still fans the design out to subagents"
     ! grep -qF 'section outline' "$SKILLS/sheldon/SKILL.md" || fail "sheldon: still writes a section outline"
     ! grep -qF 'without the fan-out' "$SKILLS/sheldon/SKILL.md" || fail "sheldon: still mentions the fan-out"
     require sheldon 'Write every section yourself'
     require sheldon 'open questions'
     require sheldon 'one message through the `AskUserQuestion` tool'
     require sheldon 'one approval'
     ! grep -qF 'After each section, ask whether everything looks right' "$SKILLS/sheldon/SKILL.md" || fail "sheldon: still asks after each section"
     grep -qF 'one approval' "$ROOT/README.md" || fail "README.md: sheldon row lacks one approval"
     grep -qF 'drafted inline' "$ROOT/README.md" || fail "README.md: sheldon row does not say drafted inline"
     ! grep -qF 'drafted in parallel' "$ROOT/README.md" || fail "README.md: sheldon row still says drafted in parallel"
     grep -qF 'одне погодження' "$ROOT/README.uk.md" || fail "README.uk.md: sheldon row lacks одне погодження"
     ! grep -qF 'пишуться паралельно' "$ROOT/README.uk.md" || fail "README.uk.md: sheldon row still says пишуться паралельно"
     [ "$fails" -eq "$before" ] && ok "inline design checked"
     ```
  7. Insert before `echo "Manifest versions"`:
     ```bash
     echo "Folded subagents"
     before=$fails
     require_ref_flat two-dispatch.md 'Send the same agent, through `SendMessage`,'
     require_ref_flat two-dispatch.md 'ub-tools.sh mutator'
     require_ref_flat two-dispatch.md 'mutator exit: 3'
     require_ref_flat two-dispatch.md 'Run mutation checks one at a time'
     require_ref_flat two-dispatch.md 'A wave whose only task is not'
     require_ref_flat two-dispatch.md '**The checkpoint.**'
     ! grep -qF 'send every paired implementer' "$SKILLS/wolowitz/references/two-dispatch.md" || fail "references/two-dispatch.md: still sends paired implementers"
     require_flat wolowitz 'A wave of one task runs without a subagent'
     ! grep -qF 'a fresh pair' "$SKILLS/wolowitz/SKILL.md" || fail "wolowitz: round 3 is still a fresh pair"
     grep -qF 'implementation half' "$SKILLS/wolowitz/test-writer-prompt.md" || fail "test-writer-prompt.md: no implementation half"
     ! grep -qF 'separate implementer writes the code' "$SKILLS/wolowitz/test-writer-prompt.md" || fail "test-writer-prompt.md: still names a separate implementer"
     grep -qF 'even when you wrote them yourself' "$SKILLS/wolowitz/implementer-prompt.md" || fail "implementer-prompt.md: tests not frozen for a task agent"
     require amy 'a task agent runs your red steps'
     ! grep -qF 'implementer who does not load you' "$SKILLS/amy/SKILL.md" || fail "amy: still names an implementer who does not load her"
     require leslie 'both halves run in the task agent'
     require_ref_flat grouped-review.md 'to its task agent'
     require_ref_flat make-it-right.md 'one task agent'
     require_ref codex-tasks.md '**Task agent**'
     [ "$fails" -eq "$before" ] && ok "folded subagents checked"
     ```
- [ ] **Step 2: run them, watch them fail** — `bash skills/skills.test.sh`, expect `FAILED: 37`: 5 model rows, `## Task agent`, the amy instruction line, 2 README task-agent rows, 3 version checks, 7 inline-design checks, 18 folded-subagent checks — each because the behaviour is missing.

### Task 1: sheldon drafts the design inline

**Writes:** `skills/sheldon/SKILL.md`
**Depends on:** Task 0
**Executor:** claude
**Complexity:** routine
**Satisfies:** `one subagent per section`, `section outline`, `without the fan-out`, `Write every section yourself`

- [ ] **Step 1: replace the fan-out** — in `## Present the design`, replace from `Do not stop for approval after each section. Draft them together and ask once:` through `When the design is one or two sections, write it inline without the fan-out.` with:
  ```markdown
  Do not stop for approval after each section. Write every section yourself, in
  this context: the user's answers and the repository facts are already here,
  and sections drafted apart would need their interfaces reconciled.

  1. Draft the sections in order, keeping one set of names and interfaces
     across them.
  2. Collect the open questions: only those whose answer changes what gets
     built. Ask them in one message through the `AskUserQuestion` tool, most
     important first. This is an exception to one question per message.
     Rewrite only the sections the answers touch.
  3. Present the whole design once and ask for one approval.
  ```
- [ ] **Step 2: run** `bash skills/skills.test.sh` — the four sheldon checks no longer appear among the FAIL lines.

### Task 2: task agent in the two-dispatch reference and prompts

**Writes:** `skills/wolowitz/references/two-dispatch.md`, `skills/wolowitz/test-writer-prompt.md`, `skills/wolowitz/implementer-prompt.md`, `skills/wolowitz/references/codex-tasks.md`
**Depends on:** Task 0
**Executor:** claude
**Complexity:** complex
**Satisfies:** the six `require_ref_flat two-dispatch.md` checks, `send every paired implementer`, `implementation half`, `separate implementer writes the code`, `even when you wrote them yourself`, `**Task agent**` in codex-tasks
**Interfaces:**
- Produces: the section names `**The checkpoint.**`, `## A wave of one task` and the mutation check, which `wolowitz/SKILL.md` (Task 3) points to as "per `references/two-dispatch.md`".

- [ ] **Step 1: rewrite `references/two-dispatch.md`** — keep its Gate red bullets, the three one-role shapes' wording for Task 0 and existing-code tasks, the "Finish" paragraph's prompt-filling rules, and the phrase `review when the schedule has one`. Make these changes:
  - Title `# Task agent`. First paragraph: add `and \`ub-tools.sh\`` to the exceptions, and the sentence "`ub-tools.sh` sits beside `journal.sh`."
  - Replace "Most tasks are a pair: … with your own gates between them." with: "Most tasks are built by one task agent in two halves, with your gates between them: dispatched with `test-writer-prompt.md`, it writes the tests and stops on red; then the same agent receives `implementer-prompt.md` through `SendMessage` and writes the code. It keeps the reasons behind its tests, and the checkpoint keeps the tests frozen while it writes the code."
  - Lone implementer shape: "run Gate green on its report like a task agent's."
  - Unreachable writer: "When a test fix is needed and the task's agent is not reachable — an earlier wave wrote the tests, or Codex did — send it to a fresh task agent for those tests. Its dispatch says under **Context** that, overriding Rule 1, it may write those test files and no others, and that it stops when the test fix is done; then follow **The checkpoint.**"
  - Stages paragraph: "A wave runs in stages: every task agent, every test writer alone apart from the one of a task that only covers existing code, and every implementer alone go in a single message; when all have reported, run every Gate red, and Gate green for the lone implementers; then send every task agent that passed Gate red its green, in one message, and run every remaining Gate green and finish its fix rounds; a round-3 task agent's green goes in a later message, once it passes Gate red; then the tasks that only cover existing code; only then the wave's Codex tasks, because a Codex call needs no other writer active."
  - Step 1: "**Red.** Dispatch the task agent with `test-writer-prompt.md`." Step 2's retry text: "send the problem to the task agent through `SendMessage` … after that the task goes to round 3: its fresh task agent goes out in the green stage, and its green after it passes Gate red."
  - Step 3: "**Green.** Send the same agent, through `SendMessage`, `implementer-prompt.md` filled in for the task, naming the test files."
  - Step 4 adds a fourth bullet: "**the mutation check.** Run `ub-tools.sh mutator --scan <the task's production files from **Writes:**>` and leave out every file with more than 50 sites, naming it in the wave's `✎` note. Run `ub-tools.sh mutator <the rest> -- \"<the task's verification command>\"`. Run mutation checks one at a time, while no agent of the wave is working: a mutant in the shared worktree breaks every other agent's tests. `mutator exit: 0` passes. `mutator exit: 3` means survivors: a test fix to the task agent through **The checkpoint.**, naming each survivor; it counts as a round. `mutator exit: 2` means the baseline failed: invoke `pasadena:leslie`. On `unavailable`, skip the check and put `mutator: skipped (<reason>)` in the wave's `✎` note; the install question belongs to `references/make-it-right.md`."
  - Counter: "One counter per task covers every Gate green failure, `BLOCKED` report, survivor round and review round. On a checksum mismatch, first restore the test files from the scratchpad copy and tell the agent they were edited and restored."
  - Replace the paragraph "A fix to the tests, after `BLOCKED` or a review finding, goes to the test writer in rounds 1–2. Then record … Run Gate green after every fix round 1–2. After a test fix, the test writer's reported files must also all be test files." with: "**The checkpoint.** A test fix — after `BLOCKED`, a review finding or survivors — goes to the task agent through `SendMessage` in rounds 1–2, saying it changes test files only and stops when they are done. Check that its reported files are all test files, record the checksums anew, replace the scratchpad copy, then send it the green — make these tests pass, do not edit them — and run Gate green. A code fix goes to the same agent, then Gate green." followed by the existing sentences from "In a task with no implementer —" (reworded "with no green half") through "before the code half goes out."
  - Round 3: "Round 3 is a fresh task agent." Its existing sentences stay, with "otherwise production code already exists, so it stops after its test changes, and its gate checks only that its reported files are all test files. Either way, then record the checksums and the scratchpad copy and send its green." and "the fresh Claude implementer that `references/codex-tasks.md` names is this fresh task agent."
  - Finish: "At **Finish**, findings go to one task agent: when any needs a new or changed test, its test half first, then **The checkpoint.**, then its green with every finding under Gate green; when none needs a test, one implementer alone receives them all." Rest of that paragraph unchanged, with "Its test half's dispatch says …" in place of "Its test writer's dispatch says …".
  - Append:
    ```markdown
    ## A wave of one task

    A wave whose only task is not `**Executor:** codex` gets no subagent: run
    that task yourself as in **Without subagents** in `SKILL.md`, invoking
    `pasadena:amy` first, and apply this file's gates to your own work — Gate
    red with its checksums and scratchpad copy after your red, Gate green with
    the mutation check after your green. Rounds 1–2 are yours; round 3 goes to
    a fresh task agent. Reviews keep their schedule and their subagents. Write
    `inline` in the wave's `✎` note.
    ```
- [ ] **Step 2: `test-writer-prompt.md`** — line 3: "Send every task agent and test writer of a wave in **one** message,"; replace "A\nseparate implementer writes the code after you report." with "You stop on red. After the controller checks your tests, the implementation half may reach you through `SendMessage`; until it arrives, the code is not yours."
- [ ] **Step 3: `implementer-prompt.md`** — lines 3–4: "Fill the angle brackets. A task agent receives this through `SendMessage` after Gate red, per `references/two-dispatch.md`; an implementer alone goes with the wave's first stage." Rule 5 sentence: "The tests at the paths above are frozen: their checksums are recorded, even when you wrote them yourself. Do not edit them." Keep "Subtract before you add" and no mention of amy.
- [ ] **Step 4: `references/codex-tasks.md`** line 82: `per **Test writer and implementer**` → `per **Task agent**`.
- [ ] **Step 5: run** `bash skills/skills.test.sh` — none of this task's Satisfies checks among the FAIL lines.

### Task 3: wolowitz controller, grouped review, make-it-right

**Writes:** `skills/wolowitz/SKILL.md`, `skills/wolowitz/references/grouped-review.md`, `skills/wolowitz/references/make-it-right.md`
**Depends on:** Task 0
**Executor:** claude
**Complexity:** complex
**Satisfies:** the five model rows, `## Task agent`, `- for a task agent or a test writer, …`, `A wave of one task runs without a subagent`, `a fresh pair`, `to its task agent`, `one task agent`
**Interfaces:**
- Consumes: `**The checkpoint.**`, the mutation check and `## A wave of one task` in `references/two-dispatch.md` (Task 2), referenced by name only.

- [ ] **Step 1: `wolowitz/SKILL.md`** —
  - Line 47: "— unless the session has none or the wave has one task; see **Without subagents** —".
  - Tools paragraph: "or for every task when the session has no subagents or the wave has one task, see **Without subagents**;".
  - Models: replace the three Test writer / Implementer rows with the five rows from Global constraints, in that order; replace "The test writer's row equals `amy`'s frontmatter, so it holds whichever of the two wins inside the subagent." with "The `opus`/`high` rows equal `amy`'s frontmatter, so they hold whichever of the two wins inside the subagent; a `routine` task agent may run its red on `amy`'s."
  - Section `## Test writer and implementer` → `## Task agent`, body: "Every Claude task with tests and code to write is built by one task agent: dispatched with `test-writer-prompt.md`, it invokes `amy`, writes the tests and stops on red; after Gate red, the same agent receives `implementer-prompt.md` through `SendMessage` and writes the code. `**Complexity:**` decides its row in **Models**. A task with no `**Complexity:**` line is `complex`. Task 0 is a test writer alone, stopping on red, with no gates. Some shapes take one role only; the reference names them. A task with `**Executor:** codex` runs through **Codex tasks**; one handed to Claude because `codex.sh available`, `codex.sh red`, or a `codex.sh green` before Gate red passes exits non-zero is an ordinary task agent on the `routine` row; one whose `codex.sh green` exits non-zero after Gate red goes to an implementer alone on the `routine` row, naming its tests. Round 3, including after Codex, is a fresh task agent. A wave of one task runs without a subagent, per `references/two-dispatch.md`. A session with no subagents skips this section."
  - Step 2: "every task agent, every test writer alone except the one of a task that only covers existing code, and every implementer alone." / "A task agent's green goes after Gate red, through `SendMessage`, per `references/two-dispatch.md`." / bullet "- for a task agent or a test writer, the instruction to invoke the `amy` skill" (continuation line unchanged).
  - Step 3 leslie sentence: "The fix goes to the task's agent — a test fix through the checkpoint of `references/two-dispatch.md` — or through amy when you ran the task yourself — and the verification runs again."
  - Step 5: "- **Rounds 1–2:** send the open findings, verbatim, through `SendMessage` to the task agent, which still has the context; findings on tests — a wrong or missing test — go through the checkpoint of `references/two-dispatch.md`." / "- **Round 3:** a fresh task agent, per **Models** and `references/two-dispatch.md` —" / "keep every fix with the task's agent".
  - Finish step 2: "All findings go to one fix wave, per `references/two-dispatch.md`: one task agent, its test half first when any finding needs a new or changed test; when none needs a test, one implementer alone receives them all."
  - Check `wc -c skills/wolowitz/SKILL.md` < 20000.
- [ ] **Step 2: `references/grouped-review.md`** — Fix loop: "Step 5 applies: findings go to its task agent through `SendMessage` in rounds 1–2, test findings through the checkpoint; round 3 is a fresh task agent per `two-dispatch.md`; …". Unreachable: "a test fix goes to a fresh task agent per `two-dispatch.md`, and a code fix goes to a fresh implementer alone whose dispatch …".
- [ ] **Step 3: `references/make-it-right.md`** — step 1: "The findings go to one fix wave per `references/two-dispatch.md`, through `pasadena:amy` as pin, change, prove: one task agent, who invokes amy, pins the current behaviour of every function the findings name in its test half; after the checkpoint, its green splits the high-CRAP functions and merges the duplicates under Gate green; …". Step 2: "one task agent kills them and covers the uncovered lines in its test half, then, after the checkpoint, deletes the code no test can reach."
- [ ] **Step 4: run** `bash skills/skills.test.sh` — none of this task's Satisfies checks among the FAIL lines, and no `20000 bytes` failure.

### Task 4: amy and leslie describe the task agent

**Writes:** `skills/amy/SKILL.md`, `skills/leslie/SKILL.md`
**Depends on:** Task 0
**Executor:** claude
**Complexity:** routine
**Satisfies:** `a task agent runs your red steps`, `implementer who does not load you`, `both halves run in the task agent`

- [ ] **Step 1: amy** — lines 112–114 become: "Under `wolowitz`, `leonard` plans the outer loop as Task 0 in Wave 0. For every later task a task agent runs your red steps and stops on red; after the controller's checkpoint, the same agent writes the code under the implementer's rules. Working alone, you run both." Lines 52–53: "A task agent, test writer or implementer dispatched by `wolowitz` skips it: there the builder runs Codex."
- [ ] **Step 2: leslie** — lines 105–107: "Phase 4 then splits, and both halves run in the task agent: the test half, with amy loaded, ends at the controller's checkpoint; the code half then makes the reproducing test pass without editing it, so the fix goes through review."
- [ ] **Step 3: run** `bash skills/skills.test.sh` — none of this task's Satisfies checks among the FAIL lines.

### Task 5: READMEs and version 0.25.0

**Writes:** `README.md`, `README.uk.md`, `.claude-plugin/plugin.json`, `.claude-plugin/marketplace.json`
**Depends on:** Task 0
**Executor:** claude
**Complexity:** routine
**Satisfies:** the two README task-agent rows, the three `0.25.0` checks, `drafted inline`, `drafted in parallel`, `пишуться паралельно`

- [ ] **Step 1: README.md** — sheldon row: "Design sections are drafted inline and presented for one approval." Paragraph above the dispatch table: "`wolowitz` also sets `model` and `effort` on every dispatch. A Claude task goes to one task agent: it invokes `amy`, writes the tests and stops on red, then, once the controller has checked and frozen them, writes the code in the same context and passes a mutation check. A task that writes only tests or only code takes a test writer or an implementer alone, and a wave of one task runs in the main session. `leonard` marks each task `routine` or `complex` in the plan." Rows `Test writer` / `Implementer, routine` / `Implementer, complex …` become:
  `| Task agent, \`routine\` task | \`sonnet\` | \`xhigh\` |`
  `| Task agent, \`complex\` task, round 3, final fix | \`opus\` | \`high\` |`
  `| Test writer alone (acceptance tests, covering existing code) | \`opus\` | \`high\` |`
  `| Implementer alone, \`routine\` / \`complex\` task | \`sonnet\` / \`opus\` | \`xhigh\` / \`medium\` |`
- [ ] **Step 2: README.uk.md** — sheldon row: "Секції дизайну пишуться в основному контексті й подаються на одне погодження." Paragraph: "`wolowitz` також задає `model` і `effort` у кожному dispatch. Claude-задача йде до одного task agent-а: він викликає `amy`, пише тести й зупиняється на red, а після того як контролер перевірив і заморозив їх, пише код у тому самому контексті й проходить mutation-перевірку. Задача, що пише тільки тести або тільки код, іде до test writer-а чи implementer-а окремо, а хвиля з однієї задачі виконується в основній сесії. `leonard` позначає кожну задачу в плані як `routine` або `complex`." Rows:
  `| Task agent, \`routine\`-задача | \`sonnet\` | \`xhigh\` |`
  `| Task agent, \`complex\`-задача, раунд 3, фінальний fix | \`opus\` | \`high\` |`
  `| Test writer окремо (acceptance-тести, покриття наявного коду) | \`opus\` | \`high\` |`
  `| Implementer окремо, \`routine\` / \`complex\`-задача | \`sonnet\` / \`opus\` | \`xhigh\` / \`medium\` |`
- [ ] **Step 3: manifests** — `"version": "0.24.1"` → `"version": "0.25.0"` in `.claude-plugin/plugin.json` and `.claude-plugin/marketplace.json`.
- [ ] **Step 4: run** `bash skills/skills.test.sh` — none of this task's Satisfies checks among the FAIL lines.

## Verification (end to end)
After wave 1: `bash skills/skills.test.sh` → `All checks passed.`; `grep -n 'one subagent per section' skills/sheldon/SKILL.md` → nothing; `grep -c '"version": "0.25.0"' .claude-plugin/*.json` → 1 each.
