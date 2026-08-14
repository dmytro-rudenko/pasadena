> English · [Українська](README.uk.md)

# pasadena

`pasadena` is a Claude Code and Codex plugin for spec-driven development. It keeps a task journal in the branch, turns an agreed design into a plan, and builds independent plan tasks in parallel.

## The problem it solves

A spec says what you intend to build. Git history says what you merged. Neither says where work stopped, what you verified, or which file to open next.

Pasadena stores that working context in `.pasadena/journal/<branch>.md`. The journal travels with the task branch and is removed before merge, after its useful summary moves to the pull request. Existing `.claude/journal/` files remain readable as legacy journals.

## Workflow

Run `$pasadena` in Codex or `/pasadena` in Claude Code to continue from the branch's current stage. `/bazinga` remains a Claude Code alias.

| Skill | Job |
| --- | --- |
| `sheldon` | Scopes the request, asks focused questions, and writes an agreed spec. For architectural work, it creates the worktree, journal, and draft PR first. |
| `penny` | Builds two to four browser prototypes for a UI decision, tests the chosen version with you, and records the decision. |
| `leonard` | Uses Claude Code plan mode to split the spec into executable tasks and safe parallel waves. |
| `wolowitz` | Runs each wave, verifies it, reviews the diff, commits every task, and records progress on the PR. |
| `amy` | Requires a failing test before production code for features, fixes, and refactors. |
| `raj` | Starts, updates, resumes, hands off, and closes the session journal. |

The journal front matter and the plan's checkboxes are the pipeline state. Pasadena does not maintain a second status file.

## Install in Codex

From GitHub, add the repository marketplace and install Pasadena:

```bash
codex plugin marketplace add dmytro-rudenko/pasadena
codex plugin add pasadena@pasadena
```

Open a new task after installing. Review and trust the bundled hooks through
`/hooks`; until then Codex loads the skills but skips automatic journal context,
commit tracking, and session-end pause markers. Update with:

```bash
codex plugin marketplace upgrade pasadena
codex plugin add pasadena@pasadena
```

## Install in Claude Code

Run the plugin from a local checkout:

```bash
claude --plugin-dir /path/to/pasadena
```

Or install it through its GitHub marketplace:

```
/plugin marketplace add dmytro-rudenko/pasadena
/plugin install pasadena@pasadena
```

For local development, copy the plugin into Claude Code's skills directory and reload plugins after changes:

```bash
cp -r /path/to/pasadena ~/.claude/skills/pasadena
/reload-plugins
```

Requirements: `bash`, `git`, `jq`, and Node.js for browser prototypes.

Validate the plugin structure:

```bash
claude plugin validate .
```

## Session journal

Use `$journal start`, `$journal note`, `$journal pause`, or `$journal finish` in Codex; Claude Code keeps `/journal`.

```markdown
---
branch: port/0021-stuck-calls-recovery
spec: docs/specs/0021-stuck-calls-recovery.md
plan: docs/plans/2026-08-05-st-patches-port.md
status: in-progress
started: 2026-08-10
---

## Goal
Prevent QUEUE_FULL jobs from failing automatically. Done when the backend test passes and the PR is open.

## Now
Phase 2 of 3. `deferQueueJob` has a test. Next: `backend/src/queue/transcribe.ts:212`, then `pnpm --filter backend test`.

## Timeline
### 2026-08-10
- 14:20 ▶ start · port/0021 @ 12a9a4b
- 15:02 ● a1b2c3d feat: defer queue job on QUEUE_FULL
- 15:40 ✎ Phase 2/3: deferQueueJob covered by a test
```

Keep `## Goal`, `## Now`, and `## Timeline` in English. Hooks parse those headings. Write their contents in the user's language.

`## Now` is the only section that changes. It records the current phase, the blocker if there is one, and a concrete next step with a verification command. `## Timeline` only grows.

Codex uses three hooks; Claude Code adds `StopFailure`:

| Event | Codex | Claude Code |
| --- | --- | --- |
| `SessionStart` | Restores the journal context and offers to start one on a task branch. | Same |
| `PostToolUse` | Adds commits that appeared since the last journal entry. | Same |
| `SessionEnd` | Adds a pause marker with HEAD and dirty files. | Same |
| `StopFailure` | — | Adds the failure type. |

Hooks read Git state and append to the journal. They do not modify Git history or the index.

> The session journal (`.pasadena/journal/<branch>.md`) lives only on the task
> branch. Before the merge: the summary moves into the PR description and the file
> is deleted in a `chore(journal): close <task>` commit.

```bash
git rm .pasadena/journal/<branch>.md
git commit -m "chore(journal): close <task>"
```

## Configuration

`PASADENA_TRUNK` lists branches that never get a journal. Its default value is `main master dev develop trunk`.

Set it in your shell profile or in `.claude/settings.json`:

```json
{ "env": { "PASADENA_TRUNK": "main staging" } }
```

## Browser prototypes

`penny` starts a dependency-free local Node server only while a prototype is under review. It binds to loopback, requires a per-session key for the first request, and keeps runtime state in the ignored `.sdd/` directory. Prototype files and decisions stay in `docs/sdd/proto/` for review.

The server uses `fetch` for choice events and a one-second poll for updates. That keeps the prototype server small and avoids a WebSocket dependency.

## Checks

```bash
bash hooks/journal.test.sh
bash proto/server.test.sh
```

The journal checks create temporary Git repositories and cover branch detection, resume context, commits, pauses, and journal formatting. The server checks authentication, traversal protection, events, polling, and shutdown.

For the full design, read [docs/design.md](docs/design.md).

## License

Pasadena is MIT-licensed. Modified portions of `proto/server.cjs` and `proto/frame.css` derive from obra/superpowers; see [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md).
