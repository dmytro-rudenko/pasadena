# Grouped review

A grouped review covers waves k−2…k. It runs after wave k ≥ 1 when
`k mod 3 = 0` and wave k is not the plan's last wave.

## GROUP_BASE

`GROUP_BASE` is `BASE` from step 1 of the group's first wave — wave 1, 4, 7….
Write the line `GROUP_BASE: <sha>` into `## Now` at step 8 of every wave in
the group, replacing any earlier one, and drop it at step 8 of the wave that
closes the group. After a compaction, read it from `## Now`; when the line is
missing, take the parent of the first commit of the group's first-wave tasks
from `git log`. After a resume inside the group's first wave, take
`GROUP_BASE` from that `git log` fallback, not from that wave's step 1 `BASE`.

## Order for wave k

Verify (step 3), commit wave k's tasks (step 6), grouped review, fix loop,
fix commits, PR comment (step 7), close (step 8). Wave k's checkboxes are
ticked only after the fix commits, so a resumed session that finds wave k's
commits with unticked boxes runs the grouped review first.

## The review

Run `git add -N` on the new files in the group's `**Writes:**` sets, then
dispatch one reviewer on `sonnet` at `effort: "high"` with
`reviewer-prompt.md`, filled in for waves k−2…k and all their tasks, over
`git diff <GROUP_BASE>`.

## Fix loop

Step 5 applies: findings on code go to the task's implementer, findings on
tests to its test writer, through `SendMessage` in rounds 1–2; round 3 is a
fresh pair per `two-dispatch.md`; Codex tasks follow `codex-tasks.md`. Per
task, the counter carries on from the task's own wave, per `two-dispatch.md`,
so a task that already used rounds there reaches round 3 sooner. The
addressee may come from a wave two waves back.

Tasks of different waves in one group can share files. Fixes for tasks whose
`**Writes:**` sets intersect go one at a time, in task order, and a finding on
a shared file belongs to the latest task in the group that wrote it.

Before every code fix in the group loop, record that task's test checksums and
the scratchpad copy anew, per `two-dispatch.md`: a later wave may have changed
its tests.

When the addressee is not reachable, a test fix goes to a fresh test writer
per `two-dispatch.md`, and a code fix goes to a fresh implementer whose
dispatch says under **Context** that it may write only that task's
`**Writes:**` set; the round number stays the same. When a Codex thread is
not reachable, the task goes to a fresh Claude implementer per the round-3
rule in `codex-tasks.md`.

Fixes stay uncommitted while the loop runs. After each round run the
verification, then send the reviewer the fix diff through `SendMessage` —
`git diff HEAD` after `git add -N` on the fix's new files. When the reviewer
is not reachable, a fresh one on `sonnet` at `effort: "high"` reviews that
diff with `reviewer-prompt.md`. Its new findings are the next round; after
round 3 they are parked.

Without subagents, you make the group's fixes yourself through amy
(`pasadena:amy`) and review them yourself; the fix commits follow the same
rules.

## Fix commits

When the loop closes, for each task with fixes, in task order: stage the
files of that task's `**Writes:**` set that its fixes changed and commit
`fix(<scope>): review findings for task N`, with a 30–40 word description.
`<scope>` is the scope of that task's own commit. A file fixed for two tasks
goes in the earlier task's commit, whose description names both tasks. Skip a
task with nothing left to stage.

## PR comment

Wave k's comment adds one line: the waves covered, the number of findings,
the fix commits' shas, and the rulings and parked items from the review.
