# Test writer and implementer

Bare file names here, apart from `codex.sh`, live in the skill directory above
this file, and other paths are relative to the plugin root. `SKILL.md` stays in
context.

Most tasks are a pair: a test writer with `test-writer-prompt.md`, then an
implementer with `implementer-prompt.md`, with your own gates between them.
Three shapes take one role, through the normal wave loop, with no Gate red:

- Task 0: a test writer alone, stopping on red; the wave's verification checks
  its red.
- A task with no test file in `**Writes:**` turns existing tests green: an
  implementer alone, on its `**Complexity:**` row, naming those tests. Record
  their checksums and the scratchpad copy before the dispatch, and run Gate
  green on its report like a paired implementer's.
- A task that only covers existing code has tests that pass on arrival: a test
  writer alone, under amy's rules for existing code. State under **Context** in
  the dispatch that, overriding Rule 1, its temporary mutation may touch the
  code under test outside `**Writes:**`, must be reverted before it reports,
  and that a file another task of this wave writes is `BLOCKED`. Dispatch this
  shape alone, after the wave's other Claude work and before its Codex tasks,
  so no other agent runs tests against the mutation.

When a test fix is needed and the tests' writer is not reachable — an earlier
wave wrote them, or Codex did — send it to a fresh test writer for those tests.
Its dispatch says under **Context** that, overriding Rule 1, it may write those
test files and no others; then follow the test-fix route below.

A wave runs in stages: every test writer, apart from the test writer of a task
that only covers existing code, and every implementer of a task without a test
writer go in a single message; when all have reported, run every Gate red, and
Gate green for the lone implementers; then send every paired implementer in one
message, and run every remaining Gate green and finish its fix rounds; a
round-3 implementer goes in a later message, once its fresh test writer passes
Gate red; then the tasks that only cover existing code; only then the wave's
Codex tasks, because a Codex call needs no other writer active.

1. **Red.** Dispatch the test writer.
2. **Gate red.** Check it yourself:
   - the test writer's reported files are all test files from the task's
     `**Writes:**`, and `git status --porcelain` shows none of the task's other
     `**Writes:**` files changed;
   - the task's verification command is red, and each failure is the reason
     the plan predicts, or the toolchain's error for something this task has
     yet to create, whatever that toolchain calls it. A mistake in the test
     file itself does not count;
   - record `sha256sum` of the task's test files and copy those files into
     the scratchpad.
   When the tests are green on arrival and the task writes no production code,
   it is a task that only covers existing code: rule it so and continue under
   that shape instead of retrying. When the gate fails, send the problem to
   the test writer through `SendMessage`, then run Gate red again. At most two
   such retries; after that the task goes to round 3: its fresh test writer
   goes out in the paired implementers' stage, and its implementer after that
   writer passes Gate red. Such a task enters the fix loop at round 3.
3. **Green.** Dispatch the implementer, naming the test files.
4. **Gate green.**
   - `sha256sum` of the test files matches the recorded one;
   - the reported files are all in the task's `**Writes:**`, and no test file
     is among them;
   - the task's verification command is green.
5. The rest of the wave — suite, review, commit, PR comment — is unchanged.

One counter per task covers every Gate green failure, `BLOCKED` report and
review round. On a checksum mismatch, first restore the test files from the
scratchpad copy and tell the next implementer they were edited and restored.

A fix to the tests, after `BLOCKED` or a review finding, goes to the test
writer in rounds 1–2. Then record the checksums anew, replace the scratchpad
copy, send the implementer the changed tests, and run Gate green. In a task
with no implementer — Task 0, or a task that only covers existing code — the
fix ends at the test writer: Task 0's tests must stay red for the reasons they
predict, and an existing-code task's tests must pass with every mutation proved
again. A missing test goes the same way as a wrong one. A `BLOCKED` for any
other reason, such as a file outside `**Writes:**`, takes a ruling and costs no
round. A fix from `leslie` follows the same split and counts as a round. Its
reproducing test must fail for the reason leslie predicted before the code half
goes out. Run Gate green after every fix round 1–2. After a test fix, the test
writer's reported files must also all be test files.

Round 3 is a fresh pair. A new test writer receives the current tests, the open
findings and what was tried; its dispatch says under **Context** whether
production code exists. When the task reached round 3 from Gate red, no
production code exists yet, so it stops on red and passes the full Gate red;
otherwise production code already exists, so its gate checks only that its
reported files are all test files. Either way, then record the checksums and the
scratchpad copy. When that Gate red fails in round 3, the task is at the
broken-plan stop gate, like a `BLOCKED` still open after round 3. A new
implementer follows under Gate green. A one-role task gets a fresh agent of its
role. After a Codex task, the fresh Claude implementer that
`references/codex-tasks.md` names is this fresh pair. A `BLOCKED` still open
after round 3 is the broken-plan stop gate: tests and code cannot agree, so
pause and put it to the user.

At **Finish**, findings that need a new or changed test go to one test writer;
record the checksums, then one implementer receives every finding under Gate
green. When no finding needs a test, one implementer receives them all. This fix
wave has no plan task: in both prompts, write "the whole-branch fix wave" in
place of the task and the plan's path, list the findings under **Context**, use
the plan's verification command, and treat as its `**Writes:**` the files the
findings name plus the test files the test writer reports. Its test writer's
dispatch says under **Context** that production code exists and that,
overriding Rule 1, it may create or edit test files only, plus a temporary
mutation of the code under test reverted before it reports; its reported files
must all be test files.
