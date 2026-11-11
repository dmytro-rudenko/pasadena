---
name: wolowitz
description: Use when the user asks to implement an approved plan, run the plan, execute planned tasks, or continue a build. Runs independent tasks in parallel waves, verifies and commits each one, and comments progress on the PR
model: opus
effort: medium
allowed-tools:
  - Read
  - Grep
  - Glob
  - Agent
  - TodoWrite
  - Skill(pasadena:amy)
  - Skill(pasadena:leslie)
  - Skill(pasadena:raj)
  - Bash(git status *)
  - Bash(git log *)
  - Bash(git diff *)
  - Bash(git show *)
  - Bash(git rev-parse *)
  - Bash(git merge-base *)
  - Bash(git fetch *)
  - Bash(git worktree *)
  - Bash(git add *)
  - Bash(git commit *)
  - Bash(git rm *)
  - Bash(gh pr view *)
  - Bash(gh pr comment *)
  - Bash(gh pr edit *)
  - Bash(gh pr ready *)
  - Bash(sha256sum *)
  - Bash(cp *)
  - Bash(make *)
  - Bash(pytest *)
  - Bash(go test *)
  - Bash(cargo test *)
---

# Building

Execute an approved plan wave by wave, in one session. Independent tasks run at
the same time as subagents, you verify and commit them, and every wave leaves a
short comment on the PR before the next wave begins.

You are the controller. **All code edits live in the wave's subagents** — unless
the session has none; see **Without subagents** — your context stays clean
across every wave, and every fix receives review.

## Tools

This is the only skill in the workflow whose writes are not scoped to a
directory: the plan sends it anywhere in the tree. Edit code directly only for a
change small enough to state in one line — or for every task when the session
has no subagents, see **Without subagents**; anything larger goes to the wave's
subagents, whose contexts are discarded, which is what lets one session run
every wave.

`git push` is deliberately absent from the pre-approved list — a push to a
shared branch is one of the four stop gates below, so it asks. The plan's
verification command asks once when its runner is not in the list; approve it
and the rest of the build runs uninterrupted.

## Models

Every dispatch sets `model` and `effort` **explicitly**, whatever model the
session runs on — never leave either to a default, never pick another level to
save cost:

| Dispatch | `model` | `effort` |
|---|---|---|
| Test writer: Task 0, red of every task, test fixes, round 3, Finish | `opus` | `high` |
| Implementer, `routine` | `sonnet` | `xhigh` |
| Implementer: `complex`, round 3, Finish | `opus` | `medium` |
| Wave 0 review and grouped wave review | `sonnet` | `high` |
| Whole-branch review | `sonnet` | `xhigh` |
| `Explore`, when `codex.sh available` exits non-zero | `sonnet` | `xhigh` |

The test writer's row equals `amy`'s frontmatter, so it holds whichever of the
two wins inside the subagent. Read-only lookups go to
`codex.sh explore <prompt-file>` when `codex.sh available` exits 0. `haiku` is
never used.

## Without subagents

When the session has no Agent tool, you run the wave's tasks yourself, one at a
time, in task order. Before the first task, invoke the `amy` skill with the
Skill tool, as `pasadena:amy`, and take every task through her cycle. Naming amy in the text
does not load her.

The reviews in this mode are yours, on the schedule in step 4 of the wave
loop: read the diff against the spec and the plan yourself, and say "no
subagents" in the wave's PR comment.
The rest of the loop — verify, commit, comment, close — stays the same. At
**Finish**, you do the whole-branch review yourself over the branch diff, and
you apply its findings and the security-review findings yourself through amy.
`**Executor:** codex` tasks still run through **Codex tasks** when
`codex.sh available` exits 0; otherwise you implement them yourself through
amy.

## Codex tasks

`codex.sh` lives beside `journal.sh`; the session-start digest names that
directory. On any `codex.sh` call, exit `75` means the ChatGPT plan's usage
limit: tell the user in one line that Codex is off for this session.
Exit `1` from `codex.sh review` with `codex: nothing to review` means an empty
diff; skip the Codex review. Start every `codex.sh` call through Bash with
`run_in_background`.

An `**Executor:** codex` task is two Codex calls with your gates between.
Full mode: the effective mode, the journal's `codex-mode:` line or else
`codex.sh mode get`, is `full` (`Codex mode: full`). Before a wave's first such
task, or Wave 1 in full mode (`codex budget: exhausted`, `codex.sh cost add`),
read `references/codex-tasks.md`; reread it after compaction.

## Test writer and implementer

Every Claude task is built by two subagents. A test writer, dispatched with
`test-writer-prompt.md`, invokes `amy` and writes only the tests. An
implementer, dispatched with `implementer-prompt.md`, writes only the code and
never loads `amy`; its dispatch does not mention her. `**Complexity:**` decides
only the implementer's row in **Models**. A task with no `**Complexity:**` line
is `complex`. Task 0 is a test writer alone, stopping on red, with no gates.
Some shapes take one role only; the reference names them. A task with
`**Executor:** codex` runs through **Codex tasks**; one handed to Claude because
`codex.sh available`, `codex.sh red`, or a `codex.sh green` before Gate red
passes exits non-zero is an ordinary pair on the `routine` row; one whose
`codex.sh green` exits non-zero after Gate red goes to an implementer on the
`routine` row, naming its tests. Round 3, including after Codex, is a fresh
pair. A session with no subagents skips this section.

Before a wave's first task, read `references/two-dispatch.md` in this skill's
directory, and read it again after a compaction.

## Setup

1. **Isolation.** Implementation always takes place in a worktree while trunk
   stays unchanged. `sheldon` created one; if it is absent, create it with the
   `EnterWorktree` tool or `git worktree add`, and say so.
2. **Journal.** It exists with `spec:` and `plan:` set. Building begins after
   `plan:` is set; an empty value routes the task back to planning.
3. **The plan.** Read it. Read the `## Waves` table and the `## Global
   constraints` section; you will hand both down. When the waves table is
   absent, compute one now with the rules in `leonard` and say what you
   computed.
4. **Baseline.** Run the plan's verification command before touching anything.
   This records any existing red tests before the wave's parallel edits.
5. **Resume from the record.** Checked boxes mean done; their commits are in
   `git log`. Start at the first unchecked task. A wave closing a group before
   the last wave, committed but unticked, awaits its grouped review: read
   `references/grouped-review.md` and run it. After a compaction, the plan
   file and git log remain authoritative.

## The wave loop

For each wave in order:

### 1. Record the base

Run `git rev-parse HEAD` and keep the result as `BASE`. In waves 1, 4, 7… it
is also the group's `GROUP_BASE`; see `references/grouped-review.md`.

### 2. Dispatch the whole wave at once

**Dispatch the wave's first stage in a single message**: every test writer
except the test writer of a task that only covers existing code, and every
implementer of a task that has no test writer. Multiple dispatches in one
response run concurrently, which is the execution model the wave table
establishes.
Implementers of paired tasks go after Gate red, per
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

A task whose block says `**Executor:** codex` is not dispatched through the
Agent tool: run it through **Codex tasks**, one Codex call at a time, started
only after all of the wave's Claude subagents have reported, and after every
Gate green and its fix rounds. When `codex.sh available` exits non-zero at build
time, dispatch it as a Claude task and say so in the wave's PR comment.

A dispatch describes one task and its required context. The plan and journal
remain the source for accumulated history from earlier waves.

### 3. Verify the wave yourself

When every subagent of the wave has reported, run the plan's verification
command — the whole suite, once. Subagents only ran their own task's check, on
purpose: a suite run by four agents at once is a flake generator.

**The acceptance tests are red on purpose until the last wave.** After Wave 0,
the run is red exactly in Task 0's acceptance tests, each failing for the
reason Task 0 predicted. After each later wave, the number of failing
acceptance tests never grows, the tests named in the wave's `**Satisfies:**`
lines pass, and everything outside the acceptance tests is green. After the
last wave, none is red. Any red outside that expectation is a failed
verification. When a commit hook or push gate rejects the red tests, mark them
with the runner's expected-failure marker (`it.fails` in Vitest, `xfail` in
pytest) and remove the marker yourself, a one-line edit, from the tests a task
satisfies once its Gate green passes, then record those tests' checksums anew.

Then `git status --porcelain`. Every changed file must be claimed by exactly
one task's `**Writes:**`. A changed file outside those claims is a defect in the
plan: record a ruling assigning its owner and explaining why, then carry on.
Overlapping write claims require a ruling and serialized execution for the
remaining work.

When the run is red and one line of the error does not show the cause, do not
patch by guesswork: invoke the `leslie` skill with the Skill tool, as
`pasadena:leslie`. Leslie diagnoses: she returns the root cause and the fix to
make. The fix goes to the task's subagents — a fix to a test to its test writer,
a fix to code to its implementer, or through amy when the session has no
subagents — and the verification runs again. It counts as a round of the fix
loop for each task it touches, and that loop's routing applies.

### 4. Review schedule

Wave 0 is reviewed now, before its commit. Waves 1…N are reviewed in groups
of three, one review for every third wave: after wave k when `k mod 3 = 0`
and k is not the plan's last wave, over waves k−2…k, once step 6 has
committed wave k. Every other wave skips steps 4–5 and goes from step 3 to
step 6. The last group, of one to three waves, is covered by the
whole-branch review in **Finish**, so with three waves or fewer after
Wave 0 there is no grouped review.

Before the first grouped review, read `references/grouped-review.md` in this
skill's directory, and read it again after a compaction.

One reviewer on `sonnet` at `effort: "high"` examines the diff with
`reviewer-prompt.md`. Before it goes out, run `git add -N` on the new files
in the reviewed tasks' `**Writes:**` sets and hand it `git diff <base>` —
`BASE` for Wave 0, `GROUP_BASE` for a group — so uncommitted work is in the
diff. A complete report contains both verdicts: spec compliance and quality.

Codex does not review waves; it reviews the whole branch once, in **Finish**.

The controller's verification result remains authoritative; the reviewer
focuses on the diff and skips duplicate test execution.

Decide every `Declined to judge` item yourself: it becomes a finding or a
one-line ruling in the wave's PR comment.

### 5. Fix loop, at most three rounds

- **Rounds 1–2:** send the open findings, verbatim, through `SendMessage`:
  findings on code to the task's implementer, findings on tests — a wrong or
  missing test — to its test writer. Both still have the context. After a test
  fix, follow `references/two-dispatch.md`.
- **Round 3:** a fresh pair, per **Models** and `references/two-dispatch.md` —
  framed honestly: "two prior attempts failed on this task; you own it now,
  here is what was tried."

After each round, run the verification, then send the reviewer the fix diff
through `SendMessage` — `git diff HEAD` after `git add -N` on the fix's new
files; when it is not reachable, a fresh one on `sonnet` at `effort: "high"`
reviews that diff. Its new findings are the next round. A grouped review's fix
loop follows `references/grouped-review.md`.

Findings still open after three rounds are parked. Write down what is unresolved,
note it in the PR comment, keep every fix with a subagent, and continue.

### 6. Commit — one commit per task, by you

Only the controller commits; subagents return their changes uncommitted.
Commit processes stay serialized because the worktree shares one
`.git/index.lock`.

For each task in the wave, in task order: stage exactly that task's
`**Writes:**` set, commit with the message the plan gives it. The history
stays one-commit-per-task, which is what makes it reviewable. Fixes from a
grouped review land later as their own commits, per
`references/grouped-review.md`.

Keep the message description to **30–40 words** — what changed and why, and
nothing else. The diff carries the detail.

### 7. Comment on the PR

One comment per wave, **1–2 sentences, 25 words at most**: what the wave did and whether
verification passed.

    gh pr comment <n> --body-file <file>

Whatever else this skill or its references send to the wave's PR comment —
rulings, parked items, usage lines — goes in the wave's `✎` note instead. When `gh` is unavailable, announce
that once and continue.

### 8. Close the wave

1. Tick the wave's checkboxes in the plan file and commit it.
2. Update `## Now`: which wave is next, what is verified, the concrete next
   step with a file and a command. Inside a group, write its
   `GROUP_BASE: <sha>` line, per `references/grouped-review.md`.
3. `✎` note — the decision or proof produced by this wave.

### 9. Start the next wave

The wave's code work happened in subagents whose contexts are discarded, so
yours is still clean — go straight back to step 1 for the next wave. Report the
boundary in one line and keep moving:

> Хвиля 2/5 закрита: задачі 2 і 7, `ca37a58` `2fd166f`, тести зелені,
> коментар у PR. Починаю хвилю 3.

The `## Now` you just updated is the crash-recovery net: a session that resumes
after an interruption reads it and picks up the exact continuation point. Run
every wave through to the finish in this session, stopping only for the four
things under **Rulings and stop gates**.

## Rulings and stop gates

A running plan resolves every decision within the controller's authority. For
an ambiguity in a task, a conflict between two tasks, a plan defect, or a cap
that requires adjustment, record
`Ruling: <what> — <why> — <what it costs if wrong>` and keep going. Rulings go
in the wave's `✎` note.

Execution pauses only for these four gates:

- an irreversible or destructive operation;
- anything security-sensitive beyond a code fix in this branch — see
  **Finish**;
- a side effect outside this worktree — a merge, a push to a shared branch, a
  publish;
- a plan so broken that every path forward is a guess.

## Finish

When the last wave is closed:

1. First run `git fetch origin <trunk>`. When the fetch fails or
   `origin/<trunk>` does not exist, use the local trunk as the base instead and
   say so in the final PR comment.
   **Reviews at once.** In one message, dispatch the **whole-branch
   review** with `reviewer-prompt.md`, filled as below, over
   `git merge-base origin/<trunk> HEAD..HEAD` on `sonnet` at
   `effort: "xhigh"` in the background, and start the Codex review below; in
   full mode skip it, and the final PR comment carries
   `codex review: skipped (codex-mode full)`.
   Then, while the reviews run, invoke the `security-review` skill with the
   Skill tool on the branch diff; when the skill is unavailable, say so once
   and note the skip in the PR comment.

   Fill `reviewer-prompt.md` for the whole branch — the merge-base as
   `BASE`, the plan's path, every task number, waves `0`–`<last>` as
   `<a>`–`<b>`, the spec's path. When `codex.sh available` exits 0 outside
   full mode, write a
   Codex copy to a prompt file in the scratchpad, replacing the `**The diff:**` line with: the
   diff arrives on stdin as a `<stdin>` block — review that diff; read local
   files only for context. Keep "Do not re-run the tests". Run
   `codex.sh review $(git merge-base origin/<trunk> HEAD) <prompt-file>` in the
   background in the same message as the `sonnet` dispatch. Every `sonnet`
   finding goes to the fix wave. A Codex finding goes there only after you
   confirm it at its `file:line`; drop the unconfirmed ones with a
   one-line note in the final PR comment. The `sonnet` verdict stays the
   verdict. The final PR comment carries the review's `codex usage:` line.
   Decide every `Declined to judge` item from either review yourself, as in
   step 4 of the wave loop, in the final PR comment.
2. **Findings.** When every review started has returned: a security
   finding fixable inside the branch's own code goes to the fix wave like a
   review finding;
   a finding that needs a decision beyond the code — credentials or secrets
   to rotate, permissions or access policy, data already exposed — is the
   security-sensitive stop gate: pause and put it to the user before the fix
   wave. All findings go to one fix wave, per `references/two-dispatch.md`:
   findings that need a new or changed test go first to one test writer,
   then one implementer receives every finding under Gate green; when none
   needs a test, one implementer receives them all. This is the single
   whole-branch fix wave. Commit its changes in one commit,
   `fix(<scope>): whole-branch and security review findings`.
3. Post the final PR comment: every note the steps above assign to it, and the
   `codex usage:` line. Invoke `journal` with `finish` — status `done`, the timeline summarized into the PR body,
   `git rm` the journal, commit `chore(journal): close <task>`.
4. `gh pr ready` — the draft becomes a real PR.

## Decision rules

| Situation | Required rule |
|---|---|
| Two tasks are candidates for one wave | Their `Writes:` sets must be disjoint. |
| A wave contains multiple tasks | Dispatch the wave's test writers, apart from the test writer of a task that only covers existing code, and implementers of tasks without one, in one message; disjoint write sets provide safe concurrency. Implementers of paired tasks go after Gate red, per `references/two-dispatch.md`. |
| A task is ready to commit | The controller commits it, keeping access to the shared index serialized. |
| Review finds a small issue | Return it to the subagent that wrote the code or the test, so the fix receives review. |
| A wave closes | Post its one PR comment, then start the next wave in the same session. |
| A wave after Wave 0 closes no group, or closes the last one | Skip steps 4–5; the next grouped review or the whole-branch review covers it. |
| The context feels long | The code work stays in subagents and the main context holds compact reports; loop the waves and hand off only when a genuine ruling forces a stop. |
| A resumed task appears complete | Treat the plan's checkboxes and `git log` as the authoritative record. |
| The wave suite has already run | The reviewer uses that result and focuses on spec compliance and quality. |
| The Agent tool is unavailable | Run the wave yourself, invoking `pasadena:amy` before the first task. |
| Wave verification is red for an unclear reason | Invoke `pasadena:leslie` before any fix. |
