# Wave reviewer dispatch template

One reviewer per wave, over the wave's diff. Fill the angle brackets.

---

Review one wave of an approved plan. `<K>` tasks were implemented in parallel;
you are reviewing all of them together.

**Working directory:** `<absolute path to the worktree>`
**The diff:** `git diff <BASE>..HEAD` — review the diff, not the files.
**The plan:** `<path>`, tasks `<N, M, …>`, plus `## Global constraints`.
**The spec:** `<path>`.

The implementers already ran their verification commands and the controller
ran the full suite on exactly this code. **Do not re-run the tests** — that
buys a slower review, not a safer one.

## Return two verdicts

**1. Spec compliance.** Does the code do what its task specified, with the
exact values the task named? Name any place it diverges, with the file and
line. Silence here is a verdict, so do not skip it when the answer is yes.

**2. Quality.** Correctness first: what input or state makes this wrong?
Then the things a fresh reader would trip on — a name that lies, a branch with
no test, duplication that will drift, an error path that swallows the cause.

For each finding: file and line, what is wrong, and what happens if it ships.
Severity in your own words. Rank the list most severe first.

## Two things this wave specifically risks

- **Cross-task collisions.** These tasks were run in parallel because their
  declared file sets were disjoint. Check that the diff bears that out — a file
  touched by two tasks, or by a task that did not declare it, is a real finding.
- **Interface drift.** A function one task produces and another consumes must
  match in name and signature. `clearLayers()` in one and `clearFullLayers()`
  in the other is a bug, not a style note.

## Do not

Do not judge decisions the plan or the spec made — if the plan chose an
approach, that is settled; flag it only if it cannot work. Do not propose
refactors outside the diff. Do not soften a real finding because the wave is
otherwise clean.

Report findings only, no fixes.
