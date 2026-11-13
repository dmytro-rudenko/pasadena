# Make it right

Runs in **Finish**, after the last wave closes and before the whole-branch,
Codex and security reviews. `ub-tools.sh` sits beside `journal.sh`. It always
exits 0 and ends each run with a `<tool> exit: <code>` line.

**Files.** `git diff --name-only $(git merge-base origin/<trunk> HEAD)..HEAD`,
keeping files that still exist and are not tests. The plan's
**Verification** command is the test command. It goes after `--` as one
quoted argument: `ub-tools.sh crapper <files> -- "<test command>"`.

**Not installed.** When a run prints `unavailable (not installed`, ask the
user once through `AskUserQuestion` whether to run `ub-tools.sh install`: it
downloads unclebob's dryer, crapper and mutator at pinned commits and runs
them on this machine. On no, or on any other `unavailable`, skip that step and
put `<tool>: skipped (<reason>)` in the final PR comment.

1. **Structure.** Run `ub-tools.sh crapper <files> -- "<test command>"` and
   `ub-tools.sh dryer <files>`. Findings: every function with CRAP 10 or
   above, every pair at 0.8 or above. A `warning: … is not gitignored` line
   means that folder stays out of every commit. An `unchecked: N JS files`
   line goes in the final PR comment.
   The findings go to one fix wave per `references/two-dispatch.md`, through
   `pasadena:amy` as pin, change, prove: the test writer, who invokes amy,
   pins the current behaviour of every function the findings name; one
   implementer splits the high-CRAP functions and merges the duplicates under
   Gate green; the unchanged suite proves nothing else changed. Its
   `**Writes:**` is the files the tools named plus their test files. Commit
   `refactor(<scope>): crapper and dryer findings`. No findings, no wave.
2. **Tests.** Run `ub-tools.sh mutator --scan <files>` and leave out every
   file with more than 50 sites — mutator's `--mutation-warning` default —
   naming it in the final PR comment. Run
   `ub-tools.sh mutator <the rest> -- "<test command>"`. `mutator exit: 3` means
   survivors: one test writer kills them and covers the uncovered lines, then
   one implementer deletes the code no test can reach. Commit
   `test(<scope>): mutator survivors`. `mutator exit: 2` means the baseline
   tests failed: invoke `pasadena:leslie` before anything else.
3. In a session without subagents, run both fix waves yourself through
   `pasadena:amy`.
4. One round each, no loop. What remains goes in the final PR comment with its
   `file:line`. Then start the reviews.
