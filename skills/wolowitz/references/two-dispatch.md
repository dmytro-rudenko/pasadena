# Task agent

Bare file names here, apart from `codex.sh` and `ub-tools.sh`, live in the
skill directory above this file, and other paths are relative to the plugin
root. `ub-tools.sh` sits beside `journal.sh`. `SKILL.md` stays in context.

Most tasks are built by one task agent in two halves, with your gates between
them: dispatched with `test-writer-prompt.md`, it writes the tests and stops on
red; then the same agent receives `implementer-prompt.md` through `SendMessage`
and writes the code. It keeps the reasons behind its tests, and the checkpoint
keeps the tests frozen while it writes the code. Three shapes take one role,
through the normal wave loop, with no Gate red:

- Task 0: a test writer alone, stopping on red; the wave's verification checks
  its red.
- A task with no test file in `**Writes:**` turns existing tests green: an
  implementer alone, on its `**Complexity:**` row, naming those tests. Record
  their checksums and the scratchpad copy before the dispatch, and run Gate
  green on its report like a task agent's.
- A task that only covers existing code has tests that pass on arrival: a test
  writer alone, under amy's rules for existing code. State under **Context** in
  the dispatch that, overriding Rule 1, its temporary mutation may touch the
  code under test outside `**Writes:**`, must be reverted before it reports,
  and that a file another task of this wave writes is `BLOCKED`. Dispatch this
  shape alone, after the wave's other Claude work and before its Codex tasks,
  so no other agent runs tests against the mutation.

When a test fix is needed and the task's agent is not reachable — an earlier
wave wrote the tests, or Codex did — send it to a fresh task agent for those
tests. Its dispatch says under **Context** that, overriding Rule 1, it may
write those test files and no others, and that it stops when the test fix is
done; then follow **The checkpoint.**

A wave runs in stages: every task agent, every test writer alone apart from the
one of a task that only covers existing code, and every implementer alone go in
a single message; when all have reported, run every Gate red, and Gate green
for the lone implementers; then send every task agent that passed Gate red its
green, in one message, and run every remaining Gate green and finish its fix
rounds; a round-3 task agent's green goes in a later message, once it passes
Gate red; then the tasks that only cover existing code; only then the wave's
Codex tasks, because a Codex call needs no other writer active.

1. **Red.** Dispatch the task agent with `test-writer-prompt.md`.
2. **Gate red.** Check it yourself:
   - the agent's reported files are all test files from the task's
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
   the task agent through `SendMessage`, then run Gate red again. At most two
   such retries; after that the task goes to round 3: its fresh task agent
   goes out in the green stage, and its green after it passes Gate red. Such a
   task enters the fix loop at round 3.
3. **Green.** Send the same agent, through `SendMessage`,
   `implementer-prompt.md` filled in for the task, naming the test files.
4. **Gate green.**
   - `sha256sum` of the test files matches the recorded one;
   - the reported files are all in the task's `**Writes:**`, and no test file
     is among them;
   - the task's verification command is green;
   - **the mutation check.** Run `ub-tools.sh mutator --scan <the task's
     production files from **Writes:**>` and leave out every file with more
     than 50 sites, naming it in the wave's `✎` note. Run `ub-tools.sh mutator
     <the rest> -- "<the task's verification command>"`. Run mutation checks
     one at a time, while no agent of the wave is working: a mutant in the
     shared worktree breaks every other agent's tests. `mutator exit: 0`
     passes. `mutator exit: 3` means survivors: a test fix to the task agent
     through **The checkpoint.**, naming each survivor; it counts as a round.
     `mutator exit: 2` means the baseline failed: invoke `pasadena:leslie`. On
     `unavailable`, skip the check and put `mutator: skipped (<reason>)` in the
     wave's `✎` note; the install question belongs to
     `references/make-it-right.md`.
5. The rest of the wave — suite, review when the schedule has one, commit, PR comment — is unchanged.

One counter per task covers every Gate green failure, `BLOCKED` report,
survivor round and review round. On a checksum mismatch, first restore the test
files from the scratchpad copy and tell the agent they were edited and
restored.

**The checkpoint.** A test fix — after `BLOCKED`, a review finding or survivors
— goes to the task agent through `SendMessage` in rounds 1–2, saying it changes
test files only and stops when they are done. Check that its reported files are
all test files, record the checksums anew, replace the scratchpad copy, then
send it the green — make these tests pass, do not edit them — and run Gate
green. A code fix goes to the same agent, then Gate green. In a task with no
green half — Task 0, or a task that only covers existing code — the fix ends at
the test writer: Task 0's tests must stay red for the reasons they predict, and
an existing-code task's tests must pass with every mutation proved again. A
missing test goes the same way as a wrong one. A `BLOCKED` for any other
reason, such as a file outside `**Writes:**`, takes a ruling and costs no
round. A fix from `leslie` follows the same split and counts as a round. Its
reproducing test must fail for the reason leslie predicted before the code half
goes out.

Round 3 is a fresh task agent. It receives the current tests, the open findings
and what was tried; its dispatch says under **Context** whether production code
exists. When the task reached round 3 from Gate red, no production code exists
yet, so it stops on red and passes the full Gate red; otherwise production code
already exists, so it stops after its test changes, and its gate checks only
that its reported files are all test files. Either way, then record the
checksums and the scratchpad copy and send its green. When that Gate red fails
in round 3, the task is at the broken-plan stop gate, like a `BLOCKED` still
open after round 3. A one-role task gets a fresh agent of its role. After a
Codex task, the fresh Claude implementer that `references/codex-tasks.md` names
is this fresh task agent. A `BLOCKED` still open after round 3 is the
broken-plan stop gate: tests and code cannot agree, so pause and put it to the
user.

At **Finish**, findings go to one task agent: when any needs a new or changed
test, its test half first, then **The checkpoint.**, then its green with every
finding under Gate green; when none needs a test, one implementer alone
receives them all. This fix wave has no plan task: in both prompts, write "the
whole-branch fix wave" in place of the task and the plan's path, list the
findings under **Context**, use the plan's verification command, and treat as
its `**Writes:**` the files the findings name plus the test files the test
writer reports. Its test half's dispatch says under **Context** that production
code exists and that, overriding Rule 1, it may create or edit test files only,
plus a temporary mutation of the code under test reverted before it reports;
its reported files must all be test files.

## A wave of one task

A wave whose only task is not `**Executor:** codex` gets no subagent: run
that task yourself as in **Without subagents** in `SKILL.md`, invoking
`pasadena:amy` first, and apply this file's gates to your own work — Gate
red with its checksums and scratchpad copy after your red, Gate green with
the mutation check after your green. Rounds 1–2 are yours; round 3 goes to
a fresh task agent. Reviews keep their schedule and their subagents. Write
`inline` in the wave's `✎` note.
