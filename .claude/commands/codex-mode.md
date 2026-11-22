---
description: Show or set how much work Pasadena hands to Codex — explore, full or auto
argument-hint: "[explore|full|auto] [--branch]"
allowed-tools: Bash(bash ${CLAUDE_PLUGIN_ROOT}/hooks/codex.sh *), Bash(bash ${CLAUDE_PLUGIN_ROOT}/hooks/journal.sh *), Bash(git rev-parse *), Read
---

Arguments: `$ARGUMENTS`

Pasadena has three Codex modes:

- `explore` — Codex reads code and reviews the branch once at the finish; it
  implements only the narrow tasks `leonard` marks `**Executor:** codex`.
- `full` — Codex implements every task except Task 0, within the remaining
  Codex usage; Claude plans, runs the gates and does the final review alone.
- `auto` — `sheldon` picks `explore` or `full` per task from its
  classification and the task's risks.

The global mode applies to every branch. A branch's journal may hold its own
`codex-mode: explore|full` line, which wins on that branch.

Do exactly one of these, by the arguments:

1. **No arguments.** Run `bash ${CLAUDE_PLUGIN_ROOT}/hooks/codex.sh mode get`
   and `bash ${CLAUDE_PLUGIN_ROOT}/hooks/codex.sh available` (exit 0 means
   available). Read the `codex-mode:` line from
   `.pasadena/journal/<branch with / replaced by ->.md` at the repository root
   (`git rev-parse --show-toplevel`, `git rev-parse --abbrev-ref HEAD`), or,
   when that file is absent, from the legacy `.claude/journal/<same name>.md`;
   the value is `-` when the journal or the line is missing. Reply with three
   lines: `global: <mode>`, `branch: <mode or ->`, `codex: available | off`.
2. **`explore`, `full` or `auto`.** Run
   `bash ${CLAUDE_PLUGIN_ROOT}/hooks/codex.sh mode set <mode>` and report the
   new global mode. When the branch journal has a `codex-mode:` line, add that
   it still wins on this branch.
3. **`explore --branch` or `full --branch`.** Run
   `bash ${CLAUDE_PLUGIN_ROOT}/hooks/journal.sh codex-mode <mode>`. Exit 0:
   report the branch mode. Exit 1: say this branch has no journal and that
   `/pasadena` starts one; run nothing else.

After a set in 2 or 3, add that skills read the journal line and
`codex.sh mode get` directly, so the change applies in this session, and that
the session-start digest's `Codex mode:` line updates next session.
4. **`auto --branch`.** Say a branch holds only `explore` or `full`, because
   `auto` is resolved by `sheldon` into one of them; run nothing.
5. **Anything else.** List the valid forms above; run nothing.
