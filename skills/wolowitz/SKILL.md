---
name: wolowitz
description: Use when the user asks to implement an approved plan, run the plan, execute planned tasks, or continue a build. Runs independent tasks in parallel waves, verifies and commits each one, and comments progress on the PR
---

# Building

Execute an approved plan wave by wave. Independent tasks run at the same time,
you verify and commit them, and every wave leaves a comment on the PR and an
offer to continue in a fresh session.

You are the controller. **You never edit code yourself** — your context stays
clean for coordination, and a fix you make yourself skips review.

## Setup

1. **Isolation.** You must be in a worktree, not on trunk. `sheldon`
   created one; if you arrived here without one, create it with the available
   Codex worktree control or `git worktree add`, and say so.
2. **Journal.** It should exist with `spec:` and `plan:` set. If `plan:` is
   empty, planning is not finished — go back.
3. **The plan.** Read it. Read the `## Waves` table and the `## Global
   constraints` section; you will hand both down. If the plan has no waves
   table, compute one now with the rules in `leonard` and say what you
   computed.
4. **Baseline.** Run the plan's verification command before touching anything.
   A suite that was already red is not something you want to discover after a
   wave of parallel edits.
5. **Resume, don't restart.** Checked boxes in the plan mean done — the commits
   they refer to are in `git log` whether or not you remember making them.
   Start at the first unchecked task. After a compaction, trust the plan file
   and the git log over your own recollection.

## The wave loop

For each wave in order:

### 1. Record the base

`git rev-parse HEAD`. This is what the wave's review diffs against — never
`HEAD~1`, which silently drops all but the last commit.

### 2. Dispatch the whole wave at once

**All of the wave's implementers in a single message.** Multiple dispatches in
one response run concurrently; one per response is the sequential execution
this framework exists to stop doing.

Each dispatch carries what `implementer-prompt.md` lays out. Compose it so the
plan stays the single source of requirements:

- one line on where this task sits in the project;
- the plan's path and the task number, told to read **only** that task plus
  `## Global constraints` — never paste the plan into the prompt, and never
  make a subagent read the whole file;
- interfaces and decisions from earlier waves that the task text cannot know;
- your resolution of any ambiguity you spotted in the task;
- **name the model explicitly.** An omitted model inherits yours, which is
  usually the most expensive one available. Transcription-grade edits go cheap;
  anything needing judgement goes standard.

A dispatch describes one task, not the session's history. Do not paste
accumulated summaries of earlier waves into later prompts.

### 3. Verify the wave yourself

When every implementer has reported, run the plan's verification command — the
whole suite, once. Implementers only ran their own task's check, on purpose: a
suite run by four agents at once is a flake generator.

Then `git status --porcelain`. Every changed file must be claimed by exactly
one task's `**Writes:**`. A file nobody claimed is a defect in the plan —
record a ruling saying which task owns it and why, and carry on. Two tasks
claiming one file should never have shared a wave; if it happened, note it and
serialize the rest.

### 4. Review the wave

One reviewer over `BASE..HEAD` — the diff, not the files. Use
`reviewer-prompt.md`. It returns two verdicts, spec compliance and quality;
never accept a report missing either.

Do not ask the reviewer to re-run tests you already ran on the same code.

### 5. Fix loop, at most three rounds

- **Rounds 1–2:** send the open findings, verbatim, back to the implementer
  that wrote the code through the host's follow-up messaging tool — it still
  has the context.
- **Round 3:** a fresh implementer on a more capable model, framed honestly:
  "two prior attempts failed on this task; you own it now, here is what was
  tried."

Still open after three? Park it. Write down what is unresolved, note it in the
PR comment, and keep moving. Do not fix it yourself.

### 6. Commit — one commit per task, by you

Implementers do not commit. Two `git commit` processes in one worktree race
`.git/index.lock`, and a shared index is not something to be clever about.

For each task in the wave, in task order: stage exactly that task's
`**Writes:**` set, commit with the message the plan gives it. The history
stays one-commit-per-task, which is what makes it reviewable.

### 7. Comment on the PR

One comment per wave:

    gh pr comment <n> --body-file <file>

What belongs in it: which tasks landed and their shas, what was actually
decided or discovered, what the verification showed, any rulings you made, and
anything parked. The wave's review is most of this already — reuse it rather
than composing twice.

Write what a reviewer needs to follow the reasoning, not a changelog they can
read from `git log`. No `gh`? Skip it, once, out loud.

### 8. Close the wave

1. Tick the wave's checkboxes in the plan file and commit it.
2. Update `## Now`: which wave is next, what is verified, the concrete next
   step with a file and a command.
3. `✎` note — what this wave decided or proved, not that it finished.

### 9. Offer a fresh session, and stop

> Хвиля 2/5 закрита: задачі 2 і 7, `ca37a58` `2fd166f`, тести зелені,
> коментар у PR. `## Now` вказує на хвилю 3.
> Рекомендую нову сесію — digest поверне тебе сюди. Продовжуємо в цій сесії?

Then stop and wait. This is the boundary the framework is built around: a long
plan executed in one session degrades as the context fills, and the journal
exists precisely so it does not have to be.

## Rulings, not stalls

A running plan does not wait on a human for things you can decide. An
ambiguity in a task, a conflict between two tasks, a plan defect, a cap you
would have asked to raise — decide it, write it down as
`Ruling: <what> — <why> — <what it costs if wrong>`, and keep going. Rulings
go in the wave's PR comment.

Four things stop you instead:

- an irreversible or destructive operation;
- anything security-sensitive;
- a side effect outside this worktree — a merge, a push to a shared branch, a
  publish;
- a plan so broken that every path forward is a guess.

## Finish

When the last wave is closed:

1. **Whole-branch review** on your most capable model, over
   `git merge-base <trunk> HEAD..HEAD`. One fix dispatch for its findings —
   all of them together, not one agent per finding. There is no second wave.
2. Invoke `journal` with `finish` — status `done`, the timeline summarized into the PR body,
   `git rm` the journal, commit `chore(journal): close <task>`.
3. `gh pr ready` — the draft becomes a real PR.

## Red flags

| Thought | Reality |
|---|---|
| "These two tasks are basically independent, one wave" | Check the `Writes:` sets. Basically is not disjoint. |
| "I'll dispatch them one at a time, it's safer" | It is not safer, it is slower. Disjoint write sets are what makes it safe; the wave table already proved that. |
| "The implementer can commit its own work" | Two commits in one worktree race the index lock. You commit. |
| "This finding is small, I'll just fix it" | A controller fix skips review and burns your context. Send it back. |
| "I'll run all five waves and report at the end" | Every wave boundary is an offer to start fresh. That is the whole session-hygiene story. |
| "I don't remember doing Task 4, I'll redo it" | The plan's checkboxes and `git log` are the record. Trust them over your memory. |
| "The reviewer should re-run the tests to be sure" | You ran them. Asking twice buys a slower review, not a safer one. |
