import asyncio
import base64
import json
import os
import shlex
import time
from pathlib import Path
from typing import override

from harbor.agents.installed.base import with_prompt_template
from harbor.agents.installed.claude_code import ClaudeCode

from bench.tui_policy import Done, Fail, Keys, Paste, Wait, decide

POLL_S = 2
START_TIMEOUT_S = 60
PASTE_SETTLE_S = 1
SESSION = "cc"
PROMPT_FILE = "/tmp/tui-prompt.txt"


class TuiStartError(RuntimeError):
    pass


class TuiApiError(RuntimeError):
    pass


def claude_json(cwd):
    return json.dumps({
        "hasCompletedOnboarding": True,
        "theme": "dark",
        "projects": {cwd: {"hasTrustDialogAccepted": True, "hasCompletedProjectOnboarding": True}},
    })


def _hook(path):
    return {"hooks": [{"type": "command", "command": f"cat >> {path}; echo >> {path}"}]}


def settings_json(logs):
    return json.dumps({
        "skipDangerousModePermissionPrompt": True,
        "hooks": {
            "Stop": [_hook(f"{logs}/stops.jsonl")],
            "StopFailure": [_hook(f"{logs}/failures.jsonl")],
        },
    })


class TuiClaudeCode(ClaudeCode):
    @staticmethod
    @override
    def name() -> str:
        return "tui-claude-code"

    def command(self) -> str:
        return ""

    def prompt(self, instruction) -> str:
        return instruction

    async def prepare(self, environment, env) -> None:
        pass

    @override
    async def install(self, environment) -> None:
        await super().install(environment)
        await self.ensure_system_dependencies(environment, ("tmux",))

    async def _sh(self, environment, command, env=None) -> str:
        return (await self.exec_as_agent(environment, command=command, env=env)).stdout or ""

    def _env(self):
        env = self._resolve_auth_env()
        env["CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC"] = "1"
        env["IS_SANDBOX"] = "1"
        env.update(self._resolved_env_vars)
        env["CLAUDE_CONFIG_DIR"] = (self.environment_logs_dir / "sessions").as_posix()
        return env

    async def _write(self, environment, path, text):
        b64 = base64.b64encode(text.encode()).decode()
        await self._sh(environment, f"mkdir -p {os.path.dirname(path)} && echo {b64} | base64 -d > {path}")

    async def _paste(self, environment, text):
        await self._write(environment, PROMPT_FILE, text)
        await self._sh(
            environment,
            f"tmux load-buffer -b p {PROMPT_FILE} && tmux paste-buffer -p -d -b p -t {SESSION}",
        )
        await asyncio.sleep(PASTE_SETTLE_S)
        await self._sh(environment, f"tmux send-keys -t {SESSION} Enter")

    async def _capture(self, environment):
        return await self._sh(environment, f"tmux capture-pane -p -t {SESSION}")

    async def _events(self, environment, path):
        text = await self._sh(environment, f"cat {path}")
        return [json.loads(line) for line in text.splitlines() if line.strip()]

    def _log(self, action, screen):
        with open(self.logs_dir / "driver.log", "a") as f:
            f.write(f"{time.strftime('%H:%M:%S')} {action!r}\n{screen}\n---\n")

    async def _start(self, environment):
        deadline = time.monotonic() + START_TIMEOUT_S
        while "bypass permissions on" not in await self._capture(environment):
            if time.monotonic() >= deadline:
                raise TuiStartError("claude TUI did not start")
            await asyncio.sleep(POLL_S)

    @override
    @with_prompt_template
    async def run(self, instruction, environment, context) -> None:
        env = self._env()
        logs = self.environment_logs_dir.as_posix()
        cfg = env["CLAUDE_CONFIG_DIR"]
        cwd = (await self._sh(environment, "pwd")).strip()
        await self._write(environment, f"{cfg}/.claude.json", claude_json(cwd))
        await self._write(environment, f"{cfg}/settings.json", settings_json(logs))
        await self._sh(environment, f": > {logs}/stops.jsonl; : > {logs}/failures.jsonl")
        await self.prepare(environment, env)
        model = (self._resolved_model_name() or self.model_name).split("/")[-1]
        launch = f"export PATH=$HOME/.local/bin:$PATH; claude --dangerously-skip-permissions --model {model}"
        try:
            await self._sh(
                environment,
                f"tmux new-session -d -s {SESSION} -x 200 -y 50 -c {shlex.quote(cwd)} {shlex.quote(launch)}",
                env=env,
            )
            await self._start(environment)
            if self.command():
                await self._sh(environment, f"tmux send-keys -t {SESSION} -l {shlex.quote(self.command())}")
            await self._paste(environment, self.prompt(instruction))
            await self._drive(environment, logs)
        finally:
            await self._sh(environment, "tmux kill-server || true")

    async def _drive(self, environment, logs):
        seen = 0
        pending = None
        pending_at = 0.0
        nudges = 0
        last_keys_screen = None
        while True:
            screen = await self._capture(environment)
            stops = await self._events(environment, f"{logs}/stops.jsonl")
            if len(stops) > seen:
                seen = len(stops)
                pending = stops[-1]
                pending_at = time.monotonic()
            failures = await self._events(environment, f"{logs}/failures.jsonl")
            failure = failures[-1] if failures else None
            idle_s = time.monotonic() - pending_at if pending else 0.0
            action = decide(screen, pending, failure, nudges, idle_s)
            if isinstance(action, Keys) and screen == last_keys_screen:
                action = Wait()
            if not isinstance(action, Wait):
                self._log(action, screen)
            if isinstance(action, Keys):
                await self._sh(environment, f"tmux send-keys -t {SESSION} {shlex.quote(action.keys)}")
                last_keys_screen = screen
                pending = None
            elif isinstance(action, Paste):
                await self._paste(environment, action.text)
                nudges += 1
                pending = None
            elif isinstance(action, Done):
                return
            elif isinstance(action, Fail):
                raise TuiApiError(action.reason)
            await asyncio.sleep(POLL_S)
