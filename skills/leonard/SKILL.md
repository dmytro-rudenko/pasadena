---
name: leonard
description: Use when the user asks to plan the implementation, write an implementation plan, break an agreed spec into tasks, or identify parallel work. Runs native plan mode, declares file sets, and computes parallel waves
allowed-tools:
  - Read
  - Grep
  - Glob
  - WebFetch
  - WebSearch
  - AskUserQuestion
  - TodoWrite
  - Skill
  - Edit(docs/sdd/plans/**)
  - Bash(git status *)
  - Bash(git log *)
  - Bash(git diff *)
  - Bash(git show *)
  - Bash(git add *)
  - Bash(git commit *)
  - Bash(ls *)
  - Bash(rg *)
  - Bash(wc *)
---

# Planning

Turn an agreed spec into self-contained tasks a subagent can execute, and
declare which of them can run at the same time.

## Tools

Read anything. **The only file this skill writes is the plan**,
`docs/sdd/plans/YYYY-MM-DD-<slug>.md`. Step 5's journal update goes through
`raj`, which owns that file. No production code changes here — the plan
describes them and `wolowitz` makes them.

This skill deliberately carries no `disallowed-tools`: step 5 invokes
`wolowitz` inside the same turn, and a restriction declared here would still
be in force when the builder's first wave starts.

Two things make this different from writing a plan by hand: the approval gate
always uses **native plan mode** when it is available, and every task declares
the files it writes. Those declarations let the builder run independent tasks
in parallel.

## Before you start

Begin with an agreed spec. Work that still needs an agreed spec returns to
`sheldon` first. The shaping classifier routes *bounded* work directly from an
approved in-chat design to implementation, while a *spike* produces an answer;
both paths remain outside the plan-document flow.

## 1. Use plan mode

Use Codex plan mode when it is available. It keeps exploration read-only and
puts the implementation plan in front of the user as the approval gate. If the
host provides chat as the approval surface, present the same plan there and
wait for explicit approval before making changes.

Explore before decomposing — this is where a plan's quality is won or lost.
Gather context deliberately, so every task carries what an implementer needs:

- **Read the stack.** Framework and versions, the test runner, the naming and
  folder conventions, and the existing helpers and abstractions the tasks
  should reuse. Name them by path in the tasks — every task reuses the relevant
  utilities already present in the repository.
- **Restate the goal of each task** in actionable terms: what exists or changes
  once that task is done.
- **Enumerate every file** each task creates, modifies, or reads. This is what
  becomes the task's `**Writes:**` and `**Reads:**` lines below, and what the
  wave computation keys on — so getting it exact here is what makes the parallel
  waves safe.

## 2. Write the plan into the native plan file

**The file contains only the decomposition.** Plan mode normally asks "what
will you do once I approve?" The user approves the task list `wolowitz` will
execute. Step 5 handles persistence, journal updates, and the commit as
bookkeeping after approval.

**Write for an implementer whose repository context comes entirely from their
own task.** The plan provides every value needed for implementation, even when
that makes it longer than a plan written for the user to skim.

Header:

```markdown
# <Feature> — implementation plan

**Goal:** what exists when this is done.
**Spec:** docs/sdd/specs/YYYY-MM-DD-<slug>.md
**Prototype:** docs/sdd/proto/<slug>/decision.md   (when there was one)
**Verification:** the exact command that must pass, and its expected last line.

## Global constraints
Project-wide rules, with exact values copied verbatim from the spec. Every
task's requirements implicitly include this section.
```

Then one block per task:

```markdown
### Task 3: `↳` fallback at end of session

**Writes:** `hooks/journal.sh`, `hooks/journal.test.sh`
**Reads:** `docs/design.md`
**Depends on:** Task 1
**Interfaces:**
- Consumes: the `✎` marker written by `cmd_note` (Task 1).
- Produces: `append_now_fallback` — appends `  ↳ <one line, ≤200 chars>`;
  silent when a `✎` already follows the newest `▶ start`.

- [ ] **Step 1: write the failing test** — <the actual test code>
- [ ] **Step 2: run it, watch it fail** — `bash hooks/journal.test.sh`,
      expect `FAILED: 2`
- [ ] **Step 3: implement** — <the actual code>
- [ ] **Step 4: run it, watch it pass** — expect `All checks passed.`
```

`**Writes:**` is load-bearing: the wave computation and the builder's staging
both key on it. Each task writes only the files it declares.

`**Interfaces:**` exists because an implementer sees only their own task. It is
how they learn the names and signatures their neighbours produce.

Steps follow `amy`: failing test, watch it fail, minimum that passes, watch it
pass. One action per step, with the literal command and its expected output.

**Every field has a final value.** Replace "TBD", "add appropriate error
handling", "write tests for the above", and "similar to Task 2" with the exact
decision or code. Repeat the code because agents read tasks out of order.

## 3. Compute the waves

Task B must come after task A when any of these hold:

1. B declares `**Depends on:** A`;
2. their `**Writes:**` sets intersect, so one agent at a time owns that file in
   the shared worktree;
3. B's `Consumes:` names something A's `Produces:` defines.

Everything else can run together. Group by topological level and put the table
at the top of the plan:

```markdown
## Waves
| Wave | Tasks | Why together |
|---|---|---|
| 1 | 1 | alone — everything reads its output |
| 2 | 2, 7 | disjoint: proto/ vs skills/amy/ |
| 3 | 3, 5, 9 | disjoint: three separate files |
```

A wave of one is normal and is exactly the old sequential flow. Group tasks
only when the dependency rules above prove that they can run together.

**Say what you had to serialize and why.** "Tasks 1–3 all write
`hooks/journal.sh`, so they are three waves" is information the builder and
the reader both want.

## 4. Present the plan for approval

Present the plan through the host's plan-mode approval control when provided;
use chat as the fallback approval surface. If the user asks for changes, revise
the plan and present it again. User feedback directly produces the next
revision.

**This is the only approval gate in planning, and it is the start of
building.** Approval authorizes execution of the decomposition, including its
immediate persistence and the start of wave 1. One plan and one gate cover this
transition.

## 5. Persist it, then build

Approval unblocks writing, so do all of this in the turn right after it — it
is bookkeeping rather than a checkpoint. Continue directly through all four
steps:

1. copy the approved plan to `docs/sdd/plans/YYYY-MM-DD-<slug>.md`;
2. have `raj` set `plan:` in the journal frontmatter to that path — this is
   what tells the next session the stage is *building*, and it is what
   `wolowitz` reads in its setup;
3. commit both;
4. `✎` note: the execution state enabled by the decomposition.

Then invoke `wolowitz` and start wave 1. `wolowitz` runs every wave through to
the finish in this session — its code work is in subagents, so it does not stop
at wave boundaries; the user's next say is the finished branch or a genuine
ruling that forces a halt.

## Decision and acceptance rules

| Situation | Rule |
|---|---|
| Plan content | The approved file contains the executable decomposition; step 5 persists it after approval. |
| Approval transition | Approval immediately persists the plan and starts wave 1. `wolowitz` then runs every wave through to the finish. |
| Plan-mode gate | Every plan uses native plan mode when available, with one-keystroke UI approval as the gate. |
| File ownership | Every `Writes:` set names the exact files the builder stages and the wave computation uses. |
| Wave independence | Tasks share a wave only when their write sets and interfaces satisfy the dependency rules above. |
| Task context | Each task supplies exact values and complete steps for an implementer seeing that task in isolation. |
| Repeated work | Each task repeats the full instruction because agents read tasks out of order. |
| Context gathering | The stack scan and file enumeration happen up front, so every task rests on a verified convention. |
