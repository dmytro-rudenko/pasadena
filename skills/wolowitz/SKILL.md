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

You are the controller. **All code edits live in the wave's subagents** — your
context stays clean across every wave, and every fix receives review.

## Tools

This is the only skill in the workflow whose writes are not scoped to a
directory: the plan sends it anywhere in the tree. Edit code directly only for
a change small enough to state in one line; anything larger goes to the wave's
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
| Wave reviewer and whole-branch review | `fable` |
| Read-only `Explore` lookup | `sonnet` is allowed |

`sonnet` and `haiku` never write code and never review. On a host without these
names, use its closest equivalent.

## Setup

1. **Isolation.** Implementation always takes place in a worktree while trunk
   stays unchanged. `sheldon` created one; if it is absent, create it with the
   available Codex worktree control or `git worktree add`, and say so.
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
- `model` set to the session's model, per **Models**.

A dispatch describes one task and its required context. The plan and journal
remain the source for accumulated history from earlier waves.

### 3. Verify the wave yourself

When every implementer has reported, run the plan's verification command — the
whole suite, once. Implementers only ran their own task's check, on purpose: a
suite run by four agents at once is a flake generator.

Then `git status --porcelain`. Every changed file must be claimed by exactly
one task's `**Writes:**`. A changed file outside those claims is a defect in the
plan: record a ruling assigning its owner and explaining why, then carry on.
Overlapping write claims require a ruling and serialized execution for the
remaining work.

### 4. Review the wave

One reviewer on `fable` examines the `BASE..HEAD` diff with
`reviewer-prompt.md`. A complete report contains both verdicts: spec compliance
and quality.

The controller's verification result remains authoritative; the reviewer
focuses on the diff and skips duplicate test execution.

### 5. Fix loop, at most three rounds

- **Rounds 1–2:** send the open findings, verbatim, back to the implementer
  that wrote the code through the host's follow-up messaging tool — it still
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
- anything security-sensitive;
- a side effect outside this worktree — a merge, a push to a shared branch, a
  publish;
- a plan so broken that every path forward is a guess.

## Finish

When the last wave is closed:

1. **Whole-branch review** over `git merge-base <trunk> HEAD..HEAD`, on
   `fable` like every review. One combined fix dispatch receives all findings
   together; this is the single whole-branch fix wave.
2. Invoke `journal` with `finish` — status `done`, the timeline summarized into the PR body,
   `git rm` the journal, commit `chore(journal): close <task>`.
3. `gh pr ready` — the draft becomes a real PR.

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
