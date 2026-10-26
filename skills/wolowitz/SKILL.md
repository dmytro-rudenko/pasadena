---
name: wolowitz
description: Use when the user asks to implement an approved plan, run the plan, execute planned tasks, or continue a build. Runs independent tasks in parallel waves, verifies and commits each one, and comments progress on the PR
allowed-tools:
  - Read
  - Grep
  - Glob
  - Edit
  - Write
  - Agent
  - TodoWrite
  - Skill
  - Bash(git status *)
  - Bash(git log *)
  - Bash(git diff *)
  - Bash(git show *)
  - Bash(git rev-parse *)
  - Bash(git merge-base *)
  - Bash(git worktree *)
  - Bash(git add *)
  - Bash(git commit *)
  - Bash(git rm *)
  - Bash(gh pr view *)
  - Bash(gh pr comment *)
  - Bash(gh pr edit *)
  - Bash(gh pr ready *)
  - Bash(bash *)
  - Bash(sha256sum *)
  - Bash(cp *)
  - Bash(npm *)
  - Bash(pnpm *)
  - Bash(yarn *)
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
directory: the plan sends it anywhere in the tree. Edit code directly only for
a change small enough to state in one line — or for every task when the session
has no subagents, see **Without subagents**; anything larger goes to the wave's
implementers, whose contexts are discarded, which is what lets one session run
every wave.

`git push` is deliberately absent from the pre-approved list — a push to a
shared branch is one of the four stop gates below, so it asks. The plan's
verification command asks once when its runner is not in the list; approve it
and the rest of the build runs uninterrupted.

## Models

Every dispatch sets `model` **explicitly** — never leave it to a default, never
pick a cheaper one to save cost:

| Dispatch | `model` |
|---|---|
| Implementer, including a round-3 fresh implementer | The session's model, as your own system prompt names it: `opus` on Opus, `fable` on Fable |
| Wave reviewer and whole-branch review | `sonnet`, with `effort: "xhigh"` |
| Read-only lookup | `codex.sh explore <prompt-file>` when `codex.sh available` exits 0; otherwise `Explore` on `sonnet` |

Every review dispatch also sets `effort: "xhigh"` explicitly. `sonnet` never
writes code; `haiku` never writes code and never reviews.

## Without subagents

When the session has no Agent tool, you run the wave's tasks yourself, one at a
time, in task order. Before the first task, invoke the `amy` skill with the
Skill tool, as `pasadena:amy`, and take every task through her cycle. Naming amy in the text
does not load her.

The wave review in this mode is yours: read the `BASE..HEAD` diff against the
spec and the plan yourself, and say "no subagents" in the wave's PR comment.
The rest of the loop — verify, commit, comment, close — stays the same. At
**Finish**, you do the whole-branch review yourself over the branch diff, and
you apply its findings and the security-review findings yourself through amy.
`**Executor:** codex` tasks still run through **Codex tasks** when
`codex.sh available` exits 0; otherwise you implement them yourself through
amy.

## Codex tasks

`codex.sh` lives beside `journal.sh`; the session-start digest names that
directory. A task with `**Executor:** codex` runs as two Codex calls with your
own gates between them, because Codex cannot load amy and its report is not
evidence. Start every `codex.sh` call through Bash with `run_in_background`.

Start a wave's Codex tasks only after all of the wave's Claude implementers
have reported, and run Codex calls one at a time. No other writer is active
during a Codex call, so the `codex changed:` line that `red` and `green` print
on stderr attributes every change it lists to that call.

1. **Red.** Write a prompt file in the scratchpad: the full text of
   `skills/amy/SKILL.md`, then `implementer-prompt-codex.md` filled in for the
   task. Run `codex.sh red <prompt-file>`. Line 1 of its stdout is the thread
   id; keep it.
2. **Gate red.** Check it yourself:
   - the `codex changed:` paths are all test files from the task's
     `**Writes:**`;
   - the task's verification command is red, and each failure is the reason
     the plan predicts — a syntax or import error does not count;
   - record `sha256sum` of the task's test files and copy those files into
     the scratchpad.
   When the gate fails, run `codex.sh green <thread-id> <prompt-file>` with a
   prompt that names the problem and says to fix the tests only, then run Gate
   red again. At most two such retries; after that the task goes to a fresh
   Claude implementer.
3. **Green.** Run `codex.sh green <thread-id> <prompt-file>` with a prompt that
   says: write the minimum code that makes these tests pass; do not edit the
   tests.
4. **Gate green.**
   - `sha256sum` of the test files matches the recorded one;
   - the `codex changed:` paths are all in the task's `**Writes:**`, and no
     test file is among them;
   - the task's verification command is green.
5. The rest of the wave — suite, review, commit, PR comment — is unchanged.

When any gate after Gate red finds a checksum mismatch, first restore the test
files from the scratchpad copy, then tell the next implementer — the Codex
round or the fresh Claude implementer — that the tests were edited and
restored.

Fix loop: a Gate green failure right after step 3 counts as round 1, and its
findings are the gate's output. Rounds 1–2 go to
`codex.sh green <thread-id> <prompt-file>`, the prompt file holding the
findings verbatim; round 3 goes to a fresh Claude implementer on the session's
model. After each round sent to `codex.sh green`, run Gate green again before
the wave goes on. A Gate green failure of any kind — checksum, `**Writes:**`
set or verification — consumes that round; after round 2 the task goes to a
fresh Claude implementer. When `codex.sh` exits non-zero, the task goes to a
Claude implementer at once and the wave's PR comment names the exit code. Exit `75`
means the ChatGPT plan's usage limit: tell the user in one line that Codex is
off for the rest of the session and Claude usage is no longer being saved.
Exit `1` from `codex.sh review` with `codex: nothing to review` means an empty
diff; skip the Codex review for that wave. The wave's PR comment sums the
`codex usage:` lines its Codex calls printed on stderr.

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
5. **Resume from the record.** Checked boxes in the plan mean done, and their
   commits are present in `git log`. Start at the first unchecked task. After a
   compaction, the plan file and git log remain authoritative.

## The wave loop

For each wave in order:

### 1. Record the base

Run `git rev-parse HEAD` and keep the result as `BASE`. The wave's review always
diffs against `BASE`, capturing every commit in the wave.

### 2. Dispatch the whole wave at once

**Dispatch all of the wave's implementers in a single message.** Multiple
dispatches in one response run concurrently, which is the execution model the
wave table establishes.

Each dispatch carries what `implementer-prompt.md` lays out. Compose it so the
plan stays the single source of requirements:

- one line on where this task sits in the project;
- the plan's path and the task number, told to read **only** that task plus
  `## Global constraints`; the plan content stays at its source;
- interfaces and decisions from earlier waves that the task requires;
- your resolution of any ambiguity you spotted in the task;
- the instruction to invoke the `amy` skill (`pasadena:amy`) before writing
  code — a subagent starts with no skills loaded, and naming amy in passing
  does not load her;
- `model` set to the session's model, per **Models**.

A task whose block says `**Executor:** codex` is not dispatched through the
Agent tool: run it through **Codex tasks**, started only after all of the
wave's Claude implementers have reported, one Codex call at a time. When `codex.sh available` exits non-zero at build
time, dispatch it as a Claude task and say so in the wave's PR comment.

A dispatch describes one task and its required context. The plan and journal
remain the source for accumulated history from earlier waves.

### 3. Verify the wave yourself

When every implementer has reported, run the plan's verification command — the
whole suite, once. Implementers only ran their own task's check, on purpose: a
suite run by four agents at once is a flake generator.

**The acceptance tests are red on purpose until the last wave.** After Wave 0,
the run is red exactly in Task 0's acceptance tests, each failing for the
reason Task 0 predicted. After each later wave, the number of failing
acceptance tests never grows, the tests named in the wave's `**Satisfies:**`
lines pass, and everything outside the acceptance tests is green. After the
last wave, none is red. Any red outside that expectation is a failed
verification. When a commit hook or push gate rejects the red tests, mark them
with the runner's expected-failure marker (`it.fails` in Vitest, `xfail` in
pytest) and have each task remove the marker from the tests it satisfies.

Then `git status --porcelain`. Every changed file must be claimed by exactly
one task's `**Writes:**`. A changed file outside those claims is a defect in the
plan: record a ruling assigning its owner and explaining why, then carry on.
Overlapping write claims require a ruling and serialized execution for the
remaining work.

When the run is red and one line of the error does not show the cause, do not
patch by guesswork: invoke the `leslie` skill with the Skill tool, as
`pasadena:leslie`. Leslie diagnoses: she returns the root cause and the fix to make. The
implementer fixes: the fix goes to the task's implementer — through amy when
the session has no subagents — and the verification runs again.

### 4. Review the wave

One reviewer on `sonnet` at `effort: "xhigh"` examines the `BASE..HEAD` diff with
`reviewer-prompt.md`. A complete report contains both verdicts: spec compliance
and quality.

When `codex.sh available` exits 0, write a prompt file in the scratchpad:
`reviewer-prompt.md` from this skill's directory, filled in exactly as for the
`sonnet` reviewer — `BASE`, the plan's path, the task numbers, the spec's path.
In this Codex copy, replace the `**The diff:**` line with: the diff arrives on
stdin as a `<stdin>` block — review that diff; read local files only for
context. Keep "Do not re-run the tests". Run `codex.sh review <BASE> <prompt-file>` in the background in the same
message as the `sonnet` dispatch. The wave is still uncommitted at this point;
`codex.sh review <BASE>` sends the working tree against `BASE`, untracked
files included. Every `sonnet` finding goes to the
fix loop. A Codex finding goes there only after you confirm it yourself at its
`file:line`; drop the unconfirmed ones with a one-line note in the wave's PR
comment. The `sonnet` verdict stays the verdict.

The controller's verification result remains authoritative; the reviewer
focuses on the diff and skips duplicate test execution.

### 5. Fix loop, at most three rounds

- **Rounds 1–2:** send the open findings, verbatim, back to the implementer
  that wrote the code through `SendMessage` — it still
  has the context.
- **Round 3:** a fresh implementer — on the session's model, per **Models** —
  framed honestly: "two prior attempts failed on this task; you own it now,
  here is what was tried."

Findings still open after three rounds are parked. Write down what is unresolved,
note it in the PR comment, keep every fix with an implementer, and continue.

### 6. Commit — one commit per task, by you

Only the controller commits; implementers return their changes uncommitted.
Commit processes stay serialized because the worktree shares one
`.git/index.lock`.

For each task in the wave, in task order: stage exactly that task's
`**Writes:**` set, commit with the message the plan gives it. The history
stays one-commit-per-task, which is what makes it reviewable.

Keep the message description to **30–40 words** — what changed and why, and
nothing else. The diff carries the detail.

### 7. Comment on the PR

One comment per wave, **2–3 sentences** — no longer:

    gh pr comment <n> --body-file <file>

Say which tasks landed with their shas, whether verification passed, and any
ruling or parked item a reviewer could not infer from `git log`. That is all —
the diff and the commits carry the detail. When `gh` is unavailable, announce
that once and continue.

### 8. Close the wave

1. Tick the wave's checkboxes in the plan file and commit it.
2. Update `## Now`: which wave is next, what is verified, the concrete next
   step with a file and a command.
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
in the wave's PR comment.

Execution pauses only for these four gates:

- an irreversible or destructive operation;
- anything security-sensitive beyond a code fix in this branch — see
  **Finish**;
- a side effect outside this worktree — a merge, a push to a shared branch, a
  publish;
- a plan so broken that every path forward is a guess.

## Finish

When the last wave is closed:

1. **Whole-branch review** over `git merge-base <trunk> HEAD..HEAD`, on
   `sonnet` at `effort: "xhigh"` like every review. One combined fix dispatch receives all findings
   together; this is the single whole-branch fix wave. With
   `codex.sh available`, run
   `codex.sh review $(git merge-base <trunk> HEAD) <prompt-file>` beside it,
   the prompt file being `reviewer-prompt.md` filled in for the whole branch
   as in step 4, with the same `<stdin>` diff line in place of
   `**The diff:**`, and merge its findings by the rule in step 4.
2. **Security review.** Invoke the `security-review` skill with the Skill tool
   on the branch diff. Findings go to one fix dispatch under the same rules as
   review findings. A finding fixable inside the branch's own code goes to
   that fix dispatch; a finding that needs a decision beyond the code —
   credentials or secrets to rotate, permissions or access policy, data
   already exposed — is the security-sensitive stop gate: pause and put it to
   the user. When the skill is unavailable, say
   so once and note the skip in the PR comment.
3. Invoke `journal` with `finish` — status `done`, the timeline summarized into the PR body,
   `git rm` the journal, commit `chore(journal): close <task>`.
4. `gh pr ready` — the draft becomes a real PR.

## Decision rules

| Situation | Required rule |
|---|---|
| Two tasks are candidates for one wave | Their `Writes:` sets must be disjoint. |
| A wave contains multiple tasks | Dispatch all implementers in one message; disjoint write sets provide safe concurrency. |
| A task is ready to commit | The controller commits it, keeping access to the shared index serialized. |
| Review finds a small issue | Return it to the responsible implementer so the fix receives review. |
| A wave closes | Post its one PR comment, then start the next wave in the same session. |
| The context feels long | The code work stays in subagents and the main context holds compact reports; loop the waves and hand off only when a genuine ruling forces a stop. |
| A resumed task appears complete | Treat the plan's checkboxes and `git log` as the authoritative record. |
| The wave suite has already run | The reviewer uses that result and focuses on spec compliance and quality. |
| The Agent tool is unavailable | Run the wave yourself, invoking `pasadena:amy` before the first task. |
| Wave verification is red for an unclear reason | Invoke `pasadena:leslie` before any fix. |
