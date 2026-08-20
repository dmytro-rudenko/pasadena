---
name: raj
description: Use when the user asks to start, resume, pause, hand off, or finish a task that spans sessions, or when unfinished work needs its context preserved for the next session. Keeps the session journal
allowed-tools:
  - Read
  - Grep
  - Glob
  - TodoWrite
  - Edit(.pasadena/journal/**)
  - Edit(.claude/journal/**)
  - Bash(bash ${CLAUDE_PLUGIN_ROOT}/hooks/journal.sh *)
  - Bash(mkdir -p .pasadena/journal)
  - Bash(git status *)
  - Bash(git log *)
  - Bash(git branch *)
  - Bash(git rev-parse *)
  - Bash(git add *)
  - Bash(git commit *)
  - Bash(git rm *)
  - Bash(gh pr view *)
  - Bash(gh pr edit *)
  - Bash(gh pr ready *)
disallowed-tools:
  - Agent
  - NotebookEdit
---

# Session journal

File: `.pasadena/journal/<branch with / replaced by ->.md`. It lives on the
task branch, is pushed with it, and is **deleted before the merge**. Read an
existing `.claude/journal/<...>.md` only when the canonical file is absent;
always leave the legacy file in place and migrate it only after an explicit
user request.

The mechanics — start, commits, pause, hard stop — are written by the
`pasadena` plugin hooks. Your job is three things: create the file, keep
`## Now` current, close the journal when the task is done.

## Tools

**This skill writes exactly one file: the journal for the current branch.** It
is also the only skill that writes it — `sheldon`, `leonard`, and `wolowitz`
come here to start one, to set `spec:` and `plan:`, and to close it. Timeline
lines go through the plugin's `journal.sh` rather than by hand, because the
script owns the `### YYYY-MM-DD` heading and coordinates with the commit hook.
Everything else is reading: `git log`, the journal, the session-start digest.
No subagents — a journal entry never justifies a second context.

**Language.** Write the journal content in the language the user speaks. Keep
the section headings (`## Goal`, `## Now`, `## Timeline`) verbatim in English —
the hooks grep for them, a translated heading yields a silently empty digest.

## When to start one

Start one when the task spans multiple sessions: it has a written plan, it has a
spec or notes file, or the work is split into phases. A small one-session fix
stays journal-free, keeping the ceremony proportional to the work.

SDD work starts one earlier than that rule would suggest: `sheldon` creates
it before the first question, at the start of the design. A socratic dialogue is
the phase most likely to run out of context halfway, and the journal is what
makes it resumable.

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
    Written once and kept unchanged.

    ## Now
    (filled in on the first update)

    ## Timeline

`spec:` and `plan:` point at whatever files the project already keeps — a design
doc, a ticket, an implementation plan. When an artifact is unavailable, write
`-`.

Keep the phases in the referenced plan — `plan:` already points at them. This
keeps the plan as the single source of truth.

## The two fields are the SDD stage

`spec:` and `plan:` are pointers and, together with the plan's `- [ ]`
checkboxes, the whole state of the pipeline. This compact state model uses the
frontmatter and checkboxes as its ledger and stage marker:

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
**always** before a deliberate pause. Keep it to three concise items:

1. where we stand — phase/step and what is already verified;
2. what we stopped on — the concrete problem;
3. the next step — a file with a line number and a verification command.

Plus, when it applies, "preserve unchanged: …" — boundaries that are easy to
cross blind.

Complete example: "Phase 2/3. deferQueueJob is covered by a test. Stopped on a
circular-structure error in the catch block: trim AxiosError down to {status, code}
BEFORE JSON.stringify. Next: backend/src/queue/transcribe.ts:212, then
`pnpm --filter backend test`. Preserve unchanged: the bulkhead config — that is
SKIP #4 from the notes."

Existing timeline lines stay unchanged because the timeline is append-only.
Add new entries as described below.

## Record what happened (`✎`)

Alongside every `## Now` update, append one line to the timeline:

    bash "<path from the session-start digest>" note "Phase 2/3: deferQueueJob is covered by a test"

The session-start digest hands you the absolute path to the script. Always append
the line through that script: it coordinates with the asynchronous commit hook
and owns the `### YYYY-MM-DD` heading.

**When.** At a phase or stage boundary — the same moment you rewrite `## Now` —
and before a deliberate pause.

**What.** One line describing what happened: a decision made, a thing proved, or
a thing ruled out. `## Now` owns the next action, while the timeline captures
what the work established.

Complete example: "Phase 2/3: deferQueueJob covered by a test; AxiosError has to
be trimmed to {status, code} before stringify so the root cause remains visible."

If a session ends before you write one, the `SessionEnd` hook drops a `↳` copy of
`## Now` under the pause line as a fallback. A deliberate `✎` note remains the
preferred record because it captures what you learned.

## Resume

The `SessionStart` hook has already handed you `## Now` and any commits made since
the last journal entry. Use that digest as the initial context and read the whole
journal **only** when it leaves required context unresolved. Continue from the
documented next step.

If the commit history contains work newer than the timeline coverage, reconcile
those commits with `## Now` before continuing.

## Close

When the task is done:

1. `status: done` in the frontmatter;
2. summarize the timeline (what was done, key decisions, what was deliberately
   skipped) into the PR description: `gh pr edit --body-file -`, or the body of a
   new PR;
3. `git rm <active journal file>`;
4. `git commit -m "chore(journal): close <task>"`;
5. `gh pr ready` — the draft PR `sheldon` opened becomes a real one.

Step 3 is required. Removing the active journal before merge keeps the trunk
branch free of completed session records.
