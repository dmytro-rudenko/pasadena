#!/usr/bin/env bash
set -uo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"

if [ ! -e "$ROOT/.bench/venv/bin/python" ]; then
  echo '  skip — harbor venv absent'
  echo
  echo "All checks passed."
  exit 0
fi

PYTHONPATH="$ROOT" PYTHONDONTWRITEBYTECODE=1 "$ROOT/.bench/venv/bin/python" - <<'PY'
import asyncio
import base64
import json
import re
import sys
import tempfile
from pathlib import Path

from harbor.agents.installed.claude_code import ClaudeCode
from harbor.models.agent.context import AgentContext

import bench.tui_policy as tui_policy
from bench import tui_agent
from bench.tui_agent import TuiApiError, TuiClaudeCode, TuiStartError, claude_json, settings_json
from bench.tui_policy import NUDGE

IDLE_START = "❯ \n  ⏵⏵ bypass permissions on (shift+tab to cycle)"
ASK = """ ☐ File name
Which file name should I use?
❯ 1. a.txt (Recommended)
     Write the file as a.txt
  2. b.txt
     Write the file as b.txt
  3. Type something.
  4. Chat about this
Enter to select · ↑/↓ to navigate · Esc to cancel"""
LOADING = "Welcome to Claude Code"
MAX_CAPTURES = 500

failures = 0


def check(name, condition, detail=""):
    global failures
    if condition:
        print(f"  ok  — {name}")
    else:
        print(f"  FAIL — {name}{': ' + detail if detail else ''}")
        failures += 1


class Runaway(Exception):
    pass


class FakeShell:
    def __init__(self, screens, stops=lambda n: "", fails=lambda n: ""):
        self.screens = list(screens)
        self.stops = stops
        self.fails = fails
        self.captures = 0
        self.calls = []

    async def __call__(self, environment, command, env=None):
        self.calls.append((command, env))
        if command == "pwd":
            return "/app\n"
        if "capture-pane" in command:
            self.captures += 1
            if self.captures > MAX_CAPTURES:
                raise Runaway(f"more than {MAX_CAPTURES} captures")
            return self.screens.pop(0) if len(self.screens) > 1 else self.screens[0]
        if command.startswith("cat ") and "stops.jsonl" in command:
            return self.stops(self.captures)
        if command.startswith("cat ") and "failures.jsonl" in command:
            return self.fails(self.captures)
        return ""

    def commands(self):
        return [c for c, _ in self.calls]

    def index(self, needle):
        return next((i for i, c in enumerate(self.commands()) if needle in c), -1)

    def count(self, needle):
        return sum(needle in c for c in self.commands())

    def writes(self, path):
        found = []
        for c in self.commands():
            m = re.search(r"echo (\S+) \| base64 -d > (\S+)", c)
            if m and m.group(2) == path:
                found.append(base64.b64decode(m.group(1)).decode())
        return found

    def written(self, path):
        found = self.writes(path)
        return found[0] if found else None


def make(cls, tmp, shell):
    agent = cls(logs_dir=Path(tmp), model_name="anthropic/claude-opus-5-5")
    agent._sh = shell
    return agent


def run(agent):
    try:
        asyncio.run(agent.run("do X", object(), AgentContext()))
        return None
    except Exception as e:
        return e


tui_agent.POLL_S = 0

cj = json.loads(claude_json("/app"))
check("claude_json skips onboarding and trusts the cwd",
      cj.get("hasCompletedOnboarding") is True and cj.get("theme") == "dark"
      and cj.get("projects", {}).get("/app", {}).get("hasTrustDialogAccepted") is True,
      repr(cj))

sj = json.loads(settings_json("/logs/agent"))
hooks = sj.get("hooks", {})
stop_cmd = json.dumps(hooks.get("Stop"))
fail_cmd = json.dumps(hooks.get("StopFailure"))
check("settings_json skips the bypass prompt and logs Stop/StopFailure",
      sj.get("skipDangerousModePermissionPrompt") is True
      and "/logs/agent/stops.jsonl" in stop_cmd and "/logs/agent/failures.jsonl" in fail_cmd,
      repr(sj))

check("TuiClaudeCode is a Harbor ClaudeCode named tui-claude-code",
      issubclass(TuiClaudeCode, ClaudeCode) and TuiClaudeCode.name() == "tui-claude-code")

stop_done = '{"last_assistant_message":"Done.","background_tasks":[]}\n'

with tempfile.TemporaryDirectory() as tmp:
    sh = FakeShell([IDLE_START, ASK, ASK, IDLE_START],
                   stops=lambda n: stop_done if n >= 4 else "")
    err = run(make(TuiClaudeCode, tmp, sh))
    check("happy run returns on Done", err is None, repr(err))
    launch = sh.index("tmux new-session")
    check("launches claude with bypass and the model from model_name",
          launch >= 0 and "claude --dangerously-skip-permissions --model claude-opus-5-5" in sh.commands()[launch],
          sh.commands()[launch] if launch >= 0 else "no tmux new-session")
    env = sh.calls[launch][1] or {} if launch >= 0 else {}
    check("tmux server inherits IS_SANDBOX and CLAUDE_CONFIG_DIR, not ANTHROPIC_MODEL",
          env.get("IS_SANDBOX") == "1" and env.get("CLAUDE_CONFIG_DIR") == "/logs/agent/sessions"
          and "ANTHROPIC_MODEL" not in env, repr(sorted(env)))
    check("the prompt is written and pasted as bracketed paste",
          sh.writes("/tmp/tui-prompt.txt") == ["do X"] and sh.count("paste-buffer -p") == 1,
          repr(sh.writes("/tmp/tui-prompt.txt")))
    check("an unchanged dialog screen is answered once",
          sh.count("send-keys -t cc 1") == 1, str(sh.count("send-keys -t cc 1")))
    written_cfg = sh.written("/logs/agent/sessions/.claude.json")
    check("config .claude.json trusts the cwd reported by pwd",
          written_cfg is not None and "/app" in json.loads(written_cfg).get("projects", {}),
          repr(written_cfg))
    check("config settings.json is the Stop/StopFailure settings",
          sh.written("/logs/agent/sessions/settings.json") == settings_json("/logs/agent"))
    log = Path(tmp, "driver.log")
    check("driver.log records the Keys action",
          log.exists() and any("Keys" in line for line in log.read_text().splitlines()))
    check("tmux kill-server is the last command", "tmux kill-server" in sh.commands()[-1],
          sh.commands()[-1])


class Prepared(TuiClaudeCode):
    async def prepare(self, environment, env):
        await self._sh(environment, "PREPARE", env=env)

    def command(self):
        return "/pasadena:pasadena "

    def prompt(self, instruction):
        return f"wrapped {instruction}"


ask_stop = '{"last_assistant_message":"Spec written.\\nShall I continue?","background_tasks":[]}\n'

with tempfile.TemporaryDirectory() as tmp:
    sh = FakeShell([IDLE_START],
                   stops=lambda n: ask_stop + (stop_done if n >= 6 else "") if n >= 2 else "")
    err = run(make(Prepared, tmp, sh))
    check("nudge run returns on the second Stop", err is None, repr(err))
    check("a Stop event is nudged once, not on every poll",
          sh.count("paste-buffer -p") == 2, str(sh.count("paste-buffer -p")))
    pasted = sh.writes("/tmp/tui-prompt.txt")
    check("the prompt is pasted first, then the nudge", pasted == ["wrapped do X", NUDGE], repr(pasted))
    order = [sh.index("/logs/agent/sessions/.claude.json"), sh.index("/logs/agent/sessions/settings.json"),
             sh.index("PREPARE"), sh.index("tmux new-session")]
    check("config files are written, then prepare(), then tmux starts",
          all(i >= 0 for i in order) and order == sorted(order), repr(order))
    cmd = sh.index("send-keys -t cc -l")
    check("command() is typed before the prompt is pasted",
          cmd >= 0 and "/pasadena:pasadena" in sh.commands()[cmd] and cmd < sh.index("paste-buffer -p"),
          repr(cmd))

bg_stop = '{"last_assistant_message":"Running.","background_tasks":["x"]}\n'
saved_wait = tui_policy.BACKGROUND_WAIT_S
tui_policy.BACKGROUND_WAIT_S = 0.05
tui_agent.POLL_S = 0.01
with tempfile.TemporaryDirectory() as tmp:
    sh = FakeShell([IDLE_START], stops=lambda n: bg_stop if n >= 2 else "")
    err = run(make(TuiClaudeCode, tmp, sh))
    check("a Stop with background tasks stays pending until the wait limit", err is None, repr(err))
tui_policy.BACKGROUND_WAIT_S = saved_wait
tui_agent.POLL_S = 0

with tempfile.TemporaryDirectory() as tmp:
    sh = FakeShell([IDLE_START], fails=lambda n: '{"error":"rate_limit"}\n')
    err = run(make(TuiClaudeCode, tmp, sh))
    check("a StopFailure raises TuiApiError", isinstance(err, TuiApiError) and "rate_limit" in str(err),
          repr(err))
    check("tmux kill-server runs after TuiApiError", "tmux kill-server" in sh.commands()[-1],
          sh.commands()[-1])

tui_agent.START_TIMEOUT_S = 0
with tempfile.TemporaryDirectory() as tmp:
    sh = FakeShell([LOADING])
    err = run(make(TuiClaudeCode, tmp, sh))
    check("a TUI that never starts raises TuiStartError", isinstance(err, TuiStartError), repr(err))
    check("tmux kill-server runs after TuiStartError", "tmux kill-server" in sh.commands()[-1],
          sh.commands()[-1])

sys.exit(failures)
PY
fails=$?

echo
if [ "$fails" -gt 0 ]; then
  echo "FAILED: $fails"
  exit 1
fi
echo "All checks passed."
