# Privacy

Pasadena is a Claude Code plugin made of skills, hooks and shell scripts that run on your machine. It has no server of its own and collects no telemetry.

## What stays on your machine

- **Session journal.** Hooks read Git state and write `.pasadena/journal/<branch>.md` in your repository. The file lives on the task branch and is removed before merge.
- **Prototype server.** `penny` starts a local Node server bound to loopback while a prototype is under review. It requires a per-session key and keeps its runtime state in the ignored `.sdd/` folder.
- **Codex log.** When Codex delegation runs, `hooks/codex.sh` writes a compact log under `${XDG_STATE_HOME:-~/.local/state}/pasadena/`, readable only by you.

## What leaves your machine, and only through tools you already use

- **Claude Code.** Skills run inside your Claude Code session, under Anthropic's terms for your account.
- **Codex CLI (optional).** If the Codex CLI is installed and logged in, skills send code lookups, a branch review and marked tasks to `codex exec`, under OpenAI's terms for your ChatGPT plan. Set `PASADENA_CODEX=0` to turn delegation off.
- **GitHub CLI.** `sheldon`, `wolowitz` and `raj` create draft pull requests and post progress comments with `gh`, under your GitHub account.

Pasadena does not send data anywhere else.

## Contact

Questions or concerns: [open an issue](https://github.com/dmytro-rudenko/pasadena/issues/new/choose).
