# Codex implementer prompt

Fill the angle brackets. The controller puts the full text of
`skills/amy/SKILL.md` above this prompt and sends both to `codex.sh red`.

---

You are implementing one task of an approved plan, in two steps. Other agents
are implementing other tasks of the same wave right now, in this same worktree.

**Working directory:** `<absolute path to the worktree>`

**Your task:** Task `<N>` in `<path to the plan>`.
Read **only** that task's block and the `## Global constraints` section.

**Spec:** `<path>` — read it if the task's intent is unclear.

**Context you cannot get from the task text:**
<interfaces and decisions from earlier waves; the controller's resolution of
any ambiguity>

## This step: only the tests

Write only the tests of your task's red steps. Do not create or edit any
non-test file. Run the task's verification command and confirm every new test
fails for the reason the task predicts. The controller runs it again and
checks.

Amy's cycle is split across two calls here: write the test of every red step
now and watch each fail; the controller asks for the code in the next message.
Where amy tells you to invoke another skill or use the skill-invocation tool,
you have neither: stop and report `BLOCKED` with the failing output.

The next message, in this same session, asks for the implementation.

## Rules

1. The rules of amy above apply to every step: the test comes first, you
   watch it fail for the right reason, you write the minimum that passes.
2. Write only the files your task's `**Writes:**` line names. If the task
   cannot be done without another file, stop and report `BLOCKED` with its
   name.
3. Do not commit. Run only the task's verification command, not the whole
   suite.
4. Use exactly the names, strings, numbers and signatures the task gives.
5. When you implement, do not edit the tests. The controller checks their
   checksums.

## Report

Under twenty-five lines:

- **Status:** DONE | DONE_WITH_CONCERNS | BLOCKED
- Files you wrote
- The last lines (up to 10) of your verification command's output and its exit code, pasted
- Anything you decided that the task did not specify
