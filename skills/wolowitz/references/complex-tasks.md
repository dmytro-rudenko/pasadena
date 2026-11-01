# Complex tasks

Bare file names here, apart from `codex.sh`, live in the skill directory above
this file, and other paths are relative to the plugin root. `SKILL.md` stays in
context.

Two shapes stay one implementer, dispatched with the wave's first message, with
neither block and no gates, through the normal wave loop. A `complex` task with
no test file in `**Writes:**` turns existing tests green: it runs on the
`complex` green row. A `complex` task that only covers existing code has tests
that pass on arrival: it runs on the `complex` red row, under amy's rules for
existing code. State under **Context** in the dispatch that, overriding Rule 1,
its temporary mutation may touch the code under test outside `**Writes:**`, must
be reverted before it reports, and that a file another task of this wave writes
is `BLOCKED`.

A wave with `complex` tasks runs in stages: every red dispatch goes in the
single message with the wave's `routine` implementers; when all have reported,
run every Gate red; then send every green dispatch in one message; run every
Gate green and finish its fix rounds; only then start the wave's Codex tasks,
because a Codex call needs no other writer active.

1. **Red.** Dispatch `implementer-prompt.md` with its **Red dispatch** block.
2. **Gate red.** Check it yourself:
   - the red implementer's reported files are all test files from the task's
     `**Writes:**`, and `git status --porcelain` shows none of the task's other
     `**Writes:**` files changed;
   - the task's verification command is red, and each failure is the reason
     the plan predicts, or the toolchain's error for something this task has
     yet to create, whatever that toolchain calls it. A mistake in the test
     file itself does not count;
   - record `sha256sum` of the task's test files and copy those files into
     the scratchpad.
   When the gate fails, send the problem to the red implementer through
   `SendMessage`, then run Gate red again. At most two such retries; after that
   the task goes to a Round-3 fresh implementer. That implementer goes out in
   place of the task's green dispatch, in the same stage. Such a task enters the
   fix loop at round 3.
3. **Green.** Dispatch `implementer-prompt.md` with its **Green dispatch** block
   to a new implementer, naming the test files.
4. **Gate green.**
   - `sha256sum` of the test files matches the recorded one;
   - the reported files are all in the task's `**Writes:**`, and no test file
     is among them;
   - the task's verification command is green.
5. The rest of the wave — suite, review, commit, PR comment — is unchanged.

One counter per task covers every Gate green failure, `BLOCKED` report and
review round. On a checksum mismatch, first restore the test files from the
scratchpad copy and tell the next implementer they were edited and restored.

A fix to the tests, after `BLOCKED` or a review finding, goes to the red
implementer in rounds 1–2. Then record the checksums anew, replace the
scratchpad copy, send the green implementer the changed tests, and run Gate
green. A missing test goes the same way as a wrong one. A `BLOCKED` for any
other reason, such as a file outside `**Writes:**`, takes a ruling and costs no
round. In a two-dispatch task, a fix from `leslie` follows the same split and
counts as a round. Run Gate green after every fix round 1–2. After a test fix,
the red implementer's reported files must also all be test files.

Round 3 is a fresh implementer who owns the tests and the code: dispatch with
neither block, no gates, and the verification command must end green. A
`BLOCKED` still open after round 3 is the broken-plan stop gate: tests and code
cannot agree, so pause and put it to the user.
