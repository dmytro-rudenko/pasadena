---
name: journal
description: Use when the user asks to start, update, pause, inspect, or finish a Pasadena session journal.
---

# Pasadena journal actions

Use `raj` for the requested action.

- `start`: create the canonical `.pasadena/journal/<branch>.md` file.
- `note`: update `## Now` and append a `✎` line through the bundled journal script.
- `pause`: update `## Now` and append a pause note before stopping deliberately.
- `finish`: summarize the work in the PR, delete the active journal file, and
  commit `chore(journal): close <task>`.

When the action is omitted, inspect the active journal and report its goal,
current state, and next step. `.pasadena/journal` is always the location for a
new journal; `.claude/journal` is read only as a fallback for an existing task.
