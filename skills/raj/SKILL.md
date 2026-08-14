---
name: raj
description: Use when the user asks to start, resume, pause, hand off, or finish a task that spans sessions, or when unfinished work needs its context preserved for the next session. Keeps the session journal
---

# Session journal

File: `.pasadena/journal/<branch with / replaced by ->.md`. It lives on the
task branch, is pushed with it, and is **deleted before the merge**. Read an
existing `.claude/journal/<...>.md` only when the canonical file is absent;
never migrate it automatically.

The mechanics — start, commits, pause, hard stop — are written by the
`pasadena` plugin hooks. Your job is three things: create the file, keep
`## Now` current, close the journal when the task is done.

**Language.** Write the journal content in the language the user speaks. Keep
the section headings (`## Goal`, `## Now`, `## Timeline`) verbatim in English —
the hooks grep for them, a translated heading yields a silently empty digest.

## When to start one

Start one when the task does not fit in a single session: it has a written plan,
it has a spec or notes file, or the work is split into phases. A small one-session
fix does not need a journal — that is pure ceremony.

SDD work starts one earlier than that rule would suggest: `sheldon` creates
it before the first question, not after the design. A socratic dialogue is the
phase most likely to run out of context halfway, and the journal is what makes
it resumable.

## Create

    mkdir -p .pasadena/journal

Four parts. `## Timeline` is **always last** — the hooks append to the end of the
file.

    ---
    branch: <full branch name>
    spec: <path to the spec or notes file, or ->
    plan: <path to the plan, or ->
    status: in-progress
    started: <YYYY-MM-DD>
    ---

    ## Goal
    2–4 lines: what we are doing and what makes it done.
    Written once, never revised.

    ## Now
    (filled in on the first update)

    ## Timeline

`spec:` and `plan:` point at whatever files the project already keeps — a design
doc, a ticket, an implementation plan. If the project keeps none, write `-`.

Do **not** copy the phases in — `plan:` already points at them. Duplication
creates a second source of truth that drifts from the first.

## The two fields are the SDD stage

`spec:` and `plan:` are not only pointers — together with the plan's `- [ ]`
checkboxes they are the whole state of the pipeline, which is why there is no
ledger file and no stage field:

| frontmatter | stage | skill |
|---|---|---|
| `spec: -` | shaping | `sheldon` |
| `spec:` set, `plan: -` | spec agreed | `leonard` |
| both set | building | `wolowitz` |

The session-start hook injects both as `## Artifacts`, so a resuming session
knows where it stands before reading anything. Keep them accurate: an unset
`plan:` after the plan is written sends the next session back a phase.

## Keep `## Now` current

This is the only section that gets overwritten. Update it at phase boundaries and
**always** before a deliberate pause. Three things, no filler:

1. where we stand — phase/step and what is already verified;
2. what we stopped on — the concrete problem, not "working on X";
3. the next step — a file with a line number and a verification command.

Plus, when it applies, "do not touch: …" — boundaries that are easy to cross blind.

Bad: "Continuing work on the queue refactor."
Good: "Phase 2/3. deferQueueJob is covered by a test. Stopped on a
circular-structure error in the catch block: trim AxiosError down to {status, code}
BEFORE JSON.stringify. Next: backend/src/queue/transcribe.ts:212, then
`pnpm --filter backend test`. Do not touch: the bulkhead config — that is SKIP #4
from the notes."

Do not edit existing timeline lines — the timeline is append-only. You do add to
it, though: see below.

## Record what happened (`✎`)

Alongside every `## Now` update, append one line to the timeline:

    bash "<path from the session-start digest>" note "Phase 2/3: deferQueueJob is covered by a test"

The session-start digest hands you the absolute path to the script. Never write
the line with an editor — the commit hook appends asynchronously and would race
you, and the script owns the `### YYYY-MM-DD` heading.

**When.** At a phase or stage boundary — the same moment you rewrite `## Now` —
and before a deliberate pause.

**What.** One line. What happened, not where to go next: "where to go next" is
`## Now`, and repeating it here is noise. A decision made, a thing proved, a
thing ruled out.

Bad: "Worked on the queue refactor."
Bad: "Phase 2/3. Next: backend/src/queue/transcribe.ts:212, then `pnpm --filter backend test`."
Good: "Phase 2/3: deferQueueJob covered by a test; AxiosError has to be trimmed to
{status, code} before stringify, otherwise the root cause is hidden."

If a session ends before you write one, the `SessionEnd` hook drops a `↳` copy of
`## Now` under the pause line instead. That is the fallback, not the target — it
repeats what you already wrote instead of saying what you learned.

## Resume

The `SessionStart` hook has already handed you `## Now` and any commits made since
the last journal entry. Read the whole journal **only** if that digest is not
enough. Start from the next step, not from asking "so what are we doing?".

If there are commits between the last entry and HEAD that the timeline does not
list, work happened outside a session; reconcile them with `## Now` before
continuing.

## Close

When the task is done:

1. `status: done` in the frontmatter;
2. summarize the timeline (what was done, key decisions, what was deliberately
   skipped) into the PR description: `gh pr edit --body-file -`, or the body of a
   new PR;
3. `git rm <active journal file>`;
4. `git commit -m "chore(journal): close <task>"`;
5. `gh pr ready` — the draft PR `sheldon` opened becomes a real one.

Step 3 is not optional. A journal that survives the merge piles up on the trunk
branch and turns into a backlog nobody reads.
