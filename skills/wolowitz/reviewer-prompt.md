# Wave reviewer dispatch template

One reviewer for Wave 0 and one for each group of three waves, over their diff. Fill the angle brackets.

---

Review waves `<a>`–`<b>` of an approved plan (`<a>` = `<b>` = 0 for Wave 0).
`<K>` tasks were implemented, in parallel within each wave; you are reviewing
all of them together.

**Working directory:** `<absolute path to the worktree>`
**The diff:** `git diff <BASE>` — commits plus the working tree; review the diff, not the files.
**The plan:** `<path>`, tasks `<N, M, …>`, plus `## Global constraints` and,
when the plan has one, `## Review Focus`. Read those blocks only:
`grep -n '^##' <plan>` gives their line ranges.
**The spec:** `<path>`.

The implementers already ran their verification commands and the controller
ran the full suite on exactly this code. **Do not re-run the tests** — that
buys a slower review, not a safer one.

## Return two verdicts

Start the report with the line `Review for pasadena:wolowitz`; it keeps the
controller's prompt hook quiet.

**1. Spec compliance.** Does the code do what its task specified, with the
exact values the task named? Name any place it diverges, with the file and
line. Silence here is a verdict, so do not skip it when the answer is yes.

**2. Quality.** Correctness first: what input or state makes this wrong?
Then the things a fresh reader would trip on — a name that lies, a branch with
no test, duplication that will drift, an error path that swallows the cause.
Where the spec is silent, judge behaviour by what a reasonable person using this
software would expect, starting with the plan's `## Review Focus` when it has one.
A `## Review Focus` line whose code belongs to a task outside this review is not
a finding.

For each finding: file and line, what is wrong, and what happens if it ships.
Severity in your own words. Rank the list most severe first.

## Two things these waves specifically risk

- **Cross-task collisions.** Tasks of one wave ran in parallel because their
  declared file sets were disjoint. Check that the diff bears that out within
  each wave — a file touched by two tasks of one wave, or by a task that did not
  declare it, is a real finding. Changes under `.pasadena/` and checkbox ticks
  in the plan file are the controller's, not findings.
- **Interface drift.** A function one task produces and another consumes must
  match in name and signature. Check it across every wave under review: later
  waves consume what earlier ones produce. `clearLayers()` in one and
  `clearFullLayers()` in the other is a bug, not a style note.

## Declined to judge

List anything you could not judge from the diff, the plan and the spec, with the
reason. The controller decides each item. Write `none` when nothing was declined.

## Do not

Do not judge decisions the plan or the spec made — if the plan chose an
approach, that is settled; flag it only if it cannot work. Do not propose
refactors outside the diff. Do not soften a real finding because the waves are
otherwise clean.

Do not read whole files the diff already covers. When a finding needs context
the hunk does not show, find it with `grep -n` and read that range. When the
diff is large, start from `git diff --stat <BASE>` and take it file by file.

Report findings and declined items only, no fixes, in this shape and nothing
before or after it:

```
Review for pasadena:wolowitz
Spec: compliant | <file>:<line> — <how it diverges>, one per line
Findings: none | numbered, most severe first:
1. <file>:<line> — <what is wrong>; <what happens if it ships>. <severity>
Declined: none | <item> — <why>, one per line
```

A compliant verdict needs no evidence. Do not describe what you checked or
restate the plan.
