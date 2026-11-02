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

8. **Start at the first implement step.** Your task's steps that write the
   failing tests and watch them fail are done. Do not invoke other skills: an
   unexpected failure goes in your report as `BLOCKED` or `DONE_WITH_CONCERNS`
   with its output.

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
