---
name: leonard
description: Use when the user asks to plan the implementation, write an implementation plan, break an agreed spec into tasks, or identify parallel work. Runs native plan mode, declares file sets, and computes parallel waves
---

# Planning

Turn an agreed spec into tasks a subagent with no context can execute, and
declare which of them can run at the same time.

Two things make this different from writing a plan by hand: the approval gate
is **native plan mode**, not a sentence you invent; and every task declares the
files it writes, which is what lets the builder run independent tasks in
parallel instead of marching through them one by one.

## Before you start

There must be an agreed spec. If there is not, this is the wrong skill —
`sheldon` first. If the shaping classifier called the work *bounded* or a
*spike*, there is no plan document at all: bounded work goes straight to
implementation after its in-chat design was approved, and a spike's output is
an answer.

## 1. Use plan mode

Use Codex plan mode when it is available. It keeps exploration read-only and
puts the implementation plan in front of the user as the approval gate. If the
host exposes no plan-mode control, present the same plan in chat and wait for
explicit approval before making changes.

Explore before decomposing — this is where a plan's quality is won or lost.
Gather context deliberately, so every task carries what an implementer needs and
nothing it must guess:

- **Read the stack.** Framework and versions, the test runner, the naming and
  folder conventions, and the existing helpers and abstractions the tasks
  should reuse. Name them by path in the tasks — a plan that reinvents a utility
  three files over failed here.
- **Restate the goal of each task** in actionable terms: what exists or changes
  once that task is done.
- **Enumerate every file** each task creates, modifies, or reads. This is what
  becomes the task's `**Writes:**` and `**Reads:**` lines below, and what the
  wave computation keys on — so getting it exact here is what makes the parallel
  waves safe.

## 2. Write the plan into the native plan file

**The file's content is the decomposition itself — nothing else.** Plan mode
normally asks "what will you do once I approve?", and here the honest answer
would be step 5 below: save the file, set the journal, commit. Do not write
that. Those steps are bookkeeping, they are not the plan, and a plan file
describing them is a plan to write a plan. What the user approves is the task
list `wolowitz` will execute.

**Write for an implementer who knows the language but nothing about this
repo, and who will read only their own task.** That is longer than a plan
written for the user to skim, and deliberately so: every value the implementer
has to guess is a defect you shipped into the wave.

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

`**Writes:**` is load-bearing — it is what the wave computation and the
builder's staging both key on. A task that writes a file it did not declare
corrupts a wave.

`**Interfaces:**` exists because an implementer sees only their own task. It is
how they learn the names and signatures their neighbours produce.

Steps follow `amy`: failing test, watch it fail, minimum that passes, watch it
pass. One action per step, with the literal command and its expected output.

**No placeholders.** "TBD", "add appropriate error handling", "write tests for
the above", "similar to Task 2" — each of these is a decision you pushed onto
someone with less context than you. Repeat the code; tasks are read out of
order.

## 3. Compute the waves

Task B must come after task A when any of these hold:

1. B declares `**Depends on:** A`;
2. their `**Writes:**` sets intersect — two agents editing one file in one
   worktree is a lost edit, not a merge;
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

A wave of one is normal and is exactly the old sequential flow. Do not force
tasks together to make the table look impressive — a false parallel costs a
whole wave when it collides.

**Say what you had to serialize and why.** "Tasks 1–3 all write
`hooks/journal.sh`, so they are three waves" is information the builder and
the reader both want.

## 4. Present the plan for approval

Present the plan through the host's plan-mode approval control, or in chat when
that control is unavailable. If the user asks for changes, revise the plan and
present it again — do not argue the plan into acceptance.

**This is the only approval gate in planning, and it is the start of
building.** Approval means "execute this decomposition", not "go ahead and
write it down". There is no second plan and no second gate.

## 5. Persist it, then build

Approval unblocks writing, so do all of this in the turn right after it — it
is bookkeeping, not a checkpoint. Do not stop, do not summarise the plan back,
do not ask whether to proceed:

1. copy the approved plan to `docs/sdd/plans/YYYY-MM-DD-<slug>.md`;
2. set `plan:` in the journal frontmatter to that path — this is what tells
   the next session the stage is *building*, and it is what `wolowitz` reads
   in its setup;
3. commit both;
4. `✎` note: what the decomposition turned on, not that a plan now exists.

Then invoke `wolowitz` and start wave 1. `wolowitz` runs every wave through to
the finish in this session — its code work is in subagents, so it does not stop
at wave boundaries; the user's next say is the finished branch or a genuine
ruling that forces a halt.

## Red flags

| Thought | Reality |
|---|---|
| "The plan is what I'll do after approval — save the file, commit, hand over" | That is a plan to write a plan, and it costs a whole approval round. The file holds the decomposition; step 5 happens without being announced. |
| "Approved — now I'll write it up and check back before building" | Approval already was the go-ahead. Persist and start wave 1 in the same breath; `wolowitz` then runs the waves through to the finish. |
| "The plan is obvious, I'll skip plan mode" | The gate is the point, not the ceremony. Approving a plan in the UI is one keystroke. |
| "I'll list the files roughly, the implementer will figure it out" | `Writes:` is what the builder stages and what the waves are computed from. Rough means wrong. |
| "Everything is independent, one big wave" | Check the write sets. Two tasks touching one file are not independent no matter how unrelated they read. |
| "I'll keep the steps short, they're competent" | They are competent and they have never seen this repo. Exact values or nothing. |
| "This step is the same as Task 2's" | Write it out. Tasks are read out of order, by different agents. |
| "I'll gather context as I write each task" | Scan the stack and enumerate the files up front. A task built on a guessed convention is a defect shipped into the wave. |
