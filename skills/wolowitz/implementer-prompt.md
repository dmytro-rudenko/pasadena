# Implementer dispatch template

Fill the angle brackets. Send every implementer of a wave in **one** message.

---

You are implementing one task of an approved plan. Other agents are
implementing other tasks of the same wave right now, in this same worktree.

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

1. **Write only the files your task's `**Writes:**` line names.** Another agent
   in this wave owns the files you are not listed for. Editing one loses their
   work or yours. If the task genuinely cannot be done without touching a file
   it does not claim, stop and report `BLOCKED` with the file name — do not
   touch it.

2. **Do not commit.** The controller commits, one commit per task, after the
   wave is verified. Two `git commit` runs in one worktree race the index lock.

3. **Do not run the whole test suite.** Run only your task's own verification
   command. The controller runs the suite once when the wave is done.

4. **Do not dispatch subagents.** Not helpers, not a reviewer. Review comes
   from the controller after your report.

5. **Follow `amy`** — failing test, watch it fail, minimum that passes, watch it
   pass. The plan's steps are already in that order.

6. **Use exactly the values the task gives.** Names, strings, numbers,
   signatures. If a value looks wrong, implement it as written and say so in
   your report.

## Before you start

If anything in the task is ambiguous, ask now, in one message. Once you begin,
resolve small ambiguities yourself and record them in your report.

## Report back

Under fifteen lines:

- **Status:** DONE | DONE_WITH_CONCERNS | BLOCKED
- Files you wrote
- One line on what your verification command printed
- Anything you decided that the task did not specify
- Concerns, if any
