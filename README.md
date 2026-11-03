> English · [Українська](README.uk.md)

# pasadena

`pasadena` is a Claude Code plugin for spec-driven development. It keeps a task journal in the branch, turns an agreed design into a plan, and builds independent plan tasks in parallel.

## The problem it solves

A spec says what you intend to build. Git history says what you merged. Neither says where work stopped, what you verified, or which file to open next.

Pasadena stores that working context in `.pasadena/journal/<branch>.md`. The journal travels with the task branch and is removed before merge, after its useful summary moves to the pull request. Existing `.claude/journal/` files remain readable as legacy journals.

## Coming from obra/superpowers

Pasadena grew out of daily work with [obra/superpowers](https://github.com/obra/superpowers). It keeps the same idea of skills that steer the agent, and changes what I kept missing:

- **Plan mode for the plan.** After the spec is agreed, `leonard` writes the plan inside Claude Code's native plan mode.
- **Codex as a helper.** When the Codex CLI is installed, skills hand it read-only lookups, a second branch review and marked tasks. Claude checks every result.
- **Spec-driven plus test-driven.** `sheldon` agrees the spec first, then `amy` writes failing tests before any production code.
- **Parallel subagents.** `leonard` declares file sets per task and groups independent tasks into waves; `wolowitz` runs each wave in parallel.

Feedback is welcome: open an [issue](https://github.com/dmytro-rudenko/pasadena/issues/new/choose).

## Workflow

Run `/pasadena` to continue from the branch's current stage. `/bazinga` remains an alias.

| Skill | Job |
| --- | --- |
| `sheldon` | Scopes the request, asks focused questions, and writes an agreed spec. Design sections are drafted in parallel and presented for one approval. For architectural work, it creates the worktree, journal, and draft PR first. |
| `penny` | Builds two to four browser prototypes for a UI decision, tests the chosen version with you, and records the decision. |
| `leonard` | Uses Claude Code plan mode to split the spec into executable tasks and safe parallel waves. |
| `wolowitz` | Runs each wave, verifies it, commits every task, reviews every third wave and the whole branch, and records progress on the PR. |
| `amy` | Writes the task's acceptance tests first, then a failing test before production code for every step of a feature, fix, refactor, or test-only task, and demands proof from a fresh run before anything is called done. |
| `leslie` | Finds the root cause of a bug or unexpected failure in four phases before any fix, then fixes it through amy. |
| `bernie` | Checks a feature end-to-end in the browser with evidence, or adds a lasting Playwright e2e test. |
| `stuart` | Screenshots a page at several breakpoints, reports layout defects, and fixes them after your approval. |
| `raj` | Starts, updates, resumes, hands off, and closes the session journal. |

The journal front matter and the plan's checkboxes are the pipeline state. Pasadena does not maintain a second status file.

## Install

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

Use `/journal start`, `/journal note`, `/journal pause`, or `/journal finish`.

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

Pasadena uses six hooks:

| Event | What it does |
| --- | --- |
| `SessionStart` | Restores the journal context and offers to start one on a task branch; adds the reuse-first rule. |
| `UserPromptSubmit` | Reminds the agent to invoke leslie for a bug or amy for new behaviour; silent outside a Git repo. |
| `SubagentStart` | Gives every subagent that writes code the reuse-first rule and the cached tokeneconomizer repository map, when there is one. |
| `PostToolUse` | Adds commits that appeared since the last journal entry. |
| `SessionEnd` | Adds a pause marker with HEAD and dirty files. |
| `StopFailure` | Adds the failure type. |

Hooks read Git state and append to the journal; `UserPromptSubmit` only adds context to the prompt. They do not modify Git history or the index.

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

`PASADENA_NUDGE=0` turns off the `UserPromptSubmit` reminder.

`PASADENA_REUSE=0` turns off the reuse-first rule and the subagent map. `PASADENA_REUSE_HINT=0` hides only the hint to enable tokeneconomizer's repomap. `PASADENA_REUSE_SKIP` is a regex of subagent types that get neither (default `Explore|Plan|claude-code-guide|statusline-setup|web-fetch`; empty turns the filter off).

## Browser prototypes

`penny` starts a dependency-free local Node server only while a prototype is under review. It binds to loopback, requires a per-session key for the first request, and keeps runtime state in the ignored `.sdd/` directory. Prototype files and decisions stay in `docs/sdd/proto/` for review.

The server uses `fetch` for choice events and a one-second poll for updates. That keeps the prototype server small and avoids a WebSocket dependency.

## Models

Every skill sets `model` and `effort` in its frontmatter. The override lasts until your next message, then the session returns to your own model; when one turn invokes several skills, the last one wins.

| Skill | Model | Effort |
|---|---|---|
| `amy`, `sheldon`, `leonard`, `leslie` | `opus` | `high` |
| `wolowitz`, `penny` | `opus` | `medium` |
| `bernie`, `stuart` | `sonnet` | `xhigh` |
| `pasadena`, `raj`, `journal` | `sonnet` | `medium` |

`wolowitz` also sets `model` and `effort` on every dispatch. A Claude task goes to a test writer, who invokes `amy` and writes only the tests, then to an implementer, who writes only the code; a task that writes only tests or only code takes one of them. `leonard` marks each task `routine` or `complex` in the plan.

| Dispatch | Model | Effort |
|---|---|---|
| Test writer | `opus` | `high` |
| Implementer, `routine` task | `sonnet` | `xhigh` |
| Implementer, `complex` task, round 3, final fix | `opus` | `medium` |
| Wave 0 and grouped wave reviews | `sonnet` | `high` |
| Whole-branch review, `Explore` fallback | `sonnet` | `xhigh` |

The advisor (`--advisor opus`) is optional and Pasadena does not depend on it: plan approval, `leslie` and the whole-branch review already cover its usual moments. Subagents inherit it, so an Opus subagent with an Opus advisor pays twice for the same check.

## Codex delegation

When the Codex CLI is installed and logged in, the skills hand part of the work to `codex exec` to save Claude usage. Claude stays the orchestrator and checks every result itself. Codex runs here as a worker, not as a plugin host.

- **explore** — `leonard`, `leslie`, `sheldon` and `wolowitz` send bulk read-only lookups to Codex and get back facts with `file:line`.
- **review** — `wolowitz` runs one Codex review of the whole branch at the finish, beside the `sonnet` reviewer; only findings Claude confirms count.
- **implement** — plan tasks marked `**Executor:** codex` are written by Codex in two calls, tests first and then code, with Claude running the tests between them.

### Modes

`/codex-mode` shows the current mode; `/codex-mode explore|full|auto` sets the global one, kept in `pasadena/codex-mode` under `${XDG_STATE_HOME:-~/.local/state}`; `/codex-mode explore|full --branch` sets it for the current branch in the journal's `codex-mode:` line, which wins on that branch. The session-start digest names the effective mode.

| Mode | Reading | Implementation | Final review |
|---|---|---|---|
| `explore` (default) | Codex | Codex only for tasks marked `**Executor:** codex` | Claude `sonnet` + Codex |
| `full` | Codex | Codex for every task except Task 0, and for bounded fixes, within the usage budget | Claude only |
| `auto` | — | `sheldon` picks: spike → `explore`, bounded → `full`, architectural with concurrency, persisted state, security or a shared interface → `explore`, other architectural → asks | — |

In `full`, `bash hooks/codex.sh budget` reads the remaining 5-hour and weekly limits from Codex's own session files under `${CODEX_HOME:-~/.codex}/sessions`. `leonard` hands Codex only as many tasks as fit in the weekly limit minus a 10% reserve and names the split in the plan's `Codex budget:` line; `wolowitz` checks again before each Codex task and gives the rest to Claude when the limit runs short. A task's cost is learned from how far the weekly limit moved: `pasadena/codex-cost.tsv` under the state directory keeps the history, and the estimate is the median of the last ten tasks (3% routine, 6% complex until there is history).

While Codex works, `hooks/codex.sh` appends a compact session log to `pasadena/codex.log` under `${XDG_STATE_HOME:-~/.local/state}`: a `== ` header per call, then one `codex › ` line per command, failed exit code, file change, reasoning summary, message or error, cut to 200 characters. Follow it with `tail -f`. The log stays out of the script's output so Claude reads only the final answer on stdout and the `codex usage:`, `codex changed:` and error lines on stderr. Past 1 MB the log moves to `codex.log.1`. It holds the commands Codex ran and its messages, so it is created readable by you only.

| Variable | Default | Effect |
|---|---|---|
| `PASADENA_CODEX` | `1` | `0` turns delegation off |
| `PASADENA_CODEX_IDLE` | `120` | seconds without a Codex event before the call is stopped |
| `PASADENA_CODEX_CMD_IDLE` | `600` | the same limit while Codex runs a command |
| `PASADENA_CODEX_MODEL` | — | passed to Codex as `-m` |
| `PASADENA_CODEX_LOG` | `pasadena/codex.log` under the state directory | where the session log goes |

Codex spends your ChatGPT plan's usage. When it runs out, `hooks/codex.sh` exits `75`, the skills tell you once, and delegation stays off for six hours or until you delete `pasadena/codex-exhausted` under `${XDG_STATE_HOME:-~/.local/state}`.

## Checks

```bash
bash skills/skills.test.sh
bash hooks/journal.test.sh
bash proto/server.test.sh
bash hooks/nudge.test.sh
bash hooks/reuse.test.sh
bash hooks/codex.test.sh
```

The skills check covers skill frontmatter, README rows, third-party notices, and manifest versions. The journal checks create temporary Git repositories and cover branch detection, resume context, commits, pauses, and journal formatting. The server checks authentication, traversal protection, events, polling, and shutdown. The nudge checks cover bug and feature prompts, the silent cases, and hook registration. The reuse checks run `hooks/reuse.sh` against a fake `te` and cover the rule, the hint, the subagent map and filter, the timeout, the silent cases, and hook registration. The Codex checks run `hooks/codex.sh` against a fake `codex` and cover availability, each subcommand's flags, the session log, the idle stop and the usage-limit marker.

Specs and plans for each change live in [docs/sdd/specs](docs/sdd/specs) and [docs/sdd/plans](docs/sdd/plans).

## License

Pasadena is MIT-licensed. Modified portions of `proto/server.cjs` and `proto/frame.css` derive from obra/superpowers; see [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md).
