# Codex tasks

Bare file names here, apart from `codex.sh`, live in the skill directory above
this file, and other paths are relative to the plugin root. `SKILL.md` stays in
context.

A task with `**Executor:** codex` runs as two Codex calls with your own gates
between them, because Codex cannot load amy and its report is not evidence.

Run Codex calls one at a time, and start a wave's Codex tasks only after all of
the wave's Claude implementers have reported, and after every Gate green and its
fix rounds. No other writer is active during a Codex call, so the
`codex changed:` line that `red` and `green` print on stderr attributes every
change it lists to that call.

1. **Red.** Write a prompt file in the scratchpad: the full text of
   `skills/amy/SKILL.md`, then `implementer-prompt-codex.md` filled in for the
   task. Run `codex.sh red <prompt-file>`. Line 1 of its stdout is the thread
   id; keep it.
2. **Gate red.** Check it yourself:
   - the `codex changed:` paths are all test files from the task's
     `**Writes:**`;
   - the task's verification command is red, and each failure is the reason
     the plan predicts, or the toolchain's error for something this task has
     yet to create, whatever that toolchain calls it. A mistake in the test
     file itself does not count;
   - record `sha256sum` of the task's test files and copy those files into
     the scratchpad.
   When the gate fails, run `codex.sh green <thread-id> <prompt-file> <complexity>` with a
   prompt that names the problem and says to fix the tests only, then run Gate
   red again. At most two such retries; after that the task goes to a fresh
   Claude implementer.
   `<complexity>` is the task's `routine` or `complex` from the plan; it sets
   Codex's model and effort.
3. **Green.** Run `codex.sh green <thread-id> <prompt-file> <complexity>` with a prompt that
   says: write the minimum code that makes these tests pass; do not edit the
   tests.
4. **Gate green.**
   - `sha256sum` of the test files matches the recorded one;
   - the `codex changed:` paths are all in the task's `**Writes:**`, and no
     test file is among them;
   - the task's verification command is green.
5. The rest of the wave — suite, review when the schedule has one, commit, PR comment — is unchanged.

When any gate after Gate red finds a checksum mismatch, first restore the test
files from the scratchpad copy, then tell the next implementer — the Codex
round or the fresh Claude implementer — that the tests were edited and
restored.

Fix loop: a Gate green failure right after step 3 counts as round 1, and its
findings are the gate's output. Rounds 1–2 go to
`codex.sh green <thread-id> <prompt-file> <complexity>`, the prompt file holding the
findings verbatim; round 3 goes to a fresh Claude implementer per **Models**.
After each round sent to `codex.sh green`, run Gate green again before
the wave goes on. A Gate green failure of any kind — checksum, `**Writes:**`
set or verification — consumes that round; after round 2 the task goes to a
fresh Claude implementer. When `codex.sh` exits non-zero, the task goes to a
Claude implementer at once and the wave's PR comment names the exit code. The
wave's PR comment sums the `codex usage:` lines its Codex calls printed on
stderr.

## Codex mode full

The effective mode is the branch journal's `codex-mode:` line when present,
else `codex.sh mode get`; read it before Wave 1, since the digest's
`Codex mode:` line is only the value at session start. When it is `full`:

- **Executor.** A plan with a `Codex budget:` line already carries the split:
  follow each task's `**Executor:**`. A plan without one was written in
  `explore`; before Wave 1, split it yourself. Every task except Task 0 is a
  candidate. Run `codex.sh budget` and
  `codex.sh cost estimate routine|complex`. Give candidates `codex` in order —
  `routine` first, then `complex`, each by task number — while the sum of
  their estimates fits in `weekly_left` − 10. The rest stay with Claude.
  When `codex.sh budget` exits 1, all of them go to `codex`. Name the split in
  the Wave 1 PR comment.
- **Budget guard.** Before each Codex task's `codex.sh red`, run
  `codex.sh budget` and `codex.sh cost estimate <the task's complexity>`; a
  task with no `**Complexity:**` line is `complex`. The task goes to Codex when
  `weekly_left` − 10 ≥ estimate and `five_hour_left` ≥ estimate, or when
  `codex.sh budget` exits 1. Otherwise that task and every remaining Codex
  task of the plan go to Claude per **Test writer and implementer**, and the
  wave's PR comment carries
  `codex budget: exhausted (<weekly|five_hour> <left>% < <need>%)`.
- **Cost.** After each Codex task's Gate green, run
  `codex.sh cost add <the task's complexity> <delta>`. `<delta>` is
  `weekly_used` from a fresh `codex.sh budget` minus `weekly_used` from the
  guard's run. Skip it when the delta is negative (the week reset) or when
  either `codex.sh budget` run exited 1.
- **Finish.** No Codex review; the final PR comment carries
  `codex review: skipped (codex-mode full)`.

In `explore`, none of this applies.
