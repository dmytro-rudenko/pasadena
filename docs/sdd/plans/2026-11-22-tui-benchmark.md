# TUI benchmark — implementation plan

**Goal:** both arms (`baseline`, `pasadena`) run the real interactive `claude` TUI inside tmux in the Terminal-Bench task container, driven by a scripted user (`bench/tui_policy.py`); `npm run bench:*` keeps working and `summary.md` compares the two TUI jobs.
**Spec:** docs/sdd/specs/2026-11-22-tui-benchmark.md (amends docs/sdd/specs/2026-11-22-real-benchmark.md)
**Verification:** `bash bench/acceptance.test.sh && npm run --silent bench:test` → last line `All checks passed.`; then paid Tasks 7–8.
Codex: `codex.sh available` exits 1 → every task is `claude`.

## Context

Headless `claude --print` (Harbor's `claude-code` agent) hides `EnterPlanMode`, `ExitPlanMode`, `AskUserQuestion`, so Pasadena ran a fallback workflow. The user stopped all runs. A spike in `alexgshaw/polyglot-rust-c:20251031` proved a scripted user can drive the real TUI (screens quoted in the spec §2). Harbor stays for containers, verifier, resume, metrics; only the agent changes. Facts confirmed in Harbor 0.27.0:
- `ClaudeCode.install` (`claude_code.py:617`) uses `self.ensure_system_dependencies(environment, (...))` (`agents/installed/base.py:789`) and the bootstrap script.
- `ClaudeCode.run` (`claude_code.py:2109`) builds env: `self._resolve_auth_env()`, `ANTHROPIC_MODEL` from `self._resolved_model_name()`, `CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC=1`, `IS_SANDBOX=1`, `self._resolved_env_vars`, `CLAUDE_CONFIG_DIR=<environment_logs_dir>/sessions`.
- `exec_as_agent(environment, command, env=None, cwd=None, timeout_sec=None)` returns `ExecResult(stdout, stderr, return_code)` and raises `RuntimeError` on non-zero exit (`base.py:1117`, `:1059`).
- `ClaudeCode.__init__(self, logs_dir: Path, memory_dir=None, *args, **kwargs)` (`claude_code.py:312`); `self.logs_dir` is the host path of `/logs/agent`.
- `populate_context_post_run` converts the session JSONL under `logs_dir/sessions/projects/` into `trajectory.json`, tokens and an estimated cost (`claude_code.py:1815`, `:1847`).

## Global constraints

- Python: stdlib only outside the Harbor venv; Harbor-dependent modules are imported only by `.bench/venv/bin/python`.
- Shell scripts: `#!/usr/bin/env bash`, `set -euo pipefail`; tests: `set -uo pipefail`, `ok/FAIL` lines, last line `FAILED: N` or `All checks passed.` (as in `bench/tests/artifacts.test.sh`).
- Zero code comments except non-obvious constraints.
- Claude Code version stays `2.1.330` (`bench/config.json`).
- Policy constants, verbatim: `MAX_NUDGES = 5`; `BACKGROUND_WAIT_S = 600`; `NUDGE = "No human is available to answer. Take that as approval: continue with the recommended option until the task is finished and verified."`; `ASK_PHRASES = ("let me know", "tell me", "your approval", "approve", "would you like", "shall i", "should i", "ready to proceed", "before we move on", "before i continue")`.
- New PREAMBLE, verbatim (spec §3.2):
```
Run the full workflow: pasadena:sheldon with the Architectural path, then pasadena:leonard, then pasadena:wolowitz.
Invoke each skill with the Skill tool and do not skip a phase, however
small the task looks.
Work in the current directory without creating a worktree. Keep every
workflow file (spec, plan, journal) under /tmp/pasadena, outside the task
directory; if git is unavailable there, skip commits and the journal.
Do not open pull requests or push.
```
- Paid runs: at most 3 smoke iterations per arm for tuning; after the third failure stop and ask the user. The full run needs no extra approval.
- Never print or copy the OAuth token; all runs use `DOCKER_CONTEXT=default BENCH_ENV_FILE=/home/pc/projects/pasadena/.env`.

## Review Focus

1. A dialog stays on screen for two polls → the driver must not press the same key twice for an unchanged screen.
2. Plugin install writes `enabledPlugins` into `settings.json`; the TUI config must be written **before** the plugin install, so the CLI merges into it rather than being overwritten.
3. A `Stop` event is consumed once; a `Wait` on background tasks keeps it pending until `BACKGROUND_WAIT_S`.
4. `TuiStartError`/`TuiApiError` count as infra but must not raise the "плагін pasadena не встановився" warning.
5. Old headless jobs (no `"agent"` in `bench-meta.json`) never pair with TUI jobs.

## Waves

| Wave | Tasks | Why together |
|---|---|---|
| 0 | 0 | alone — acceptance tests, red until the last code wave |
| 1 | 1, 5, 6 | disjoint: `tui_policy.py` / `compare.py`+fixtures / `artifacts.py` |
| 2 | 2 | `tui_agent.py` consumes `decide` (Task 1) |
| 3 | 3, 4 | disjoint: `pasadena_*` / `run.sh`; both need `tui_agent.py` to exist |
| 4 | 7 | smoke: needs everything |
| 5 | 8 | full run after smoke |

Serialized: Task 2 after 1 (interface), Tasks 3–4 after 2 (subclass / hashed file), 7–8 paid and sequential.

---

### Task 0: acceptance tests

**Writes:** `bench/acceptance.test.sh`
**Executor:** claude
**Covers:** spec §6.1 «`npm run bench:test` — `All checks passed.`; серед тестів — таблиця `decide` для кожного правила»; §3.2 run.sh «`baseline` → `-a bench.tui_agent:TuiClaudeCode`»; §3.3 «різні значення `agent` → exit 1»; §3.2 artifacts «читає також транскрипти сесії». §6.2–6.4 are paid and covered by Tasks 7–8.

- [ ] **Step 1: edit the acceptance tests** — in `bench/acceptance.test.sh`:
  - replace line 22 with
    `[[ "$b" == *"-a bench.tui_agent:TuiClaudeCode"* ]] && ok "baseline dry-run uses the TUI agent" || bad "baseline dry-run uses the TUI agent: $b"`
  - before the final `echo`, add:
```bash
(cd "$ROOT" && python3 -c 'from bench.tui_policy import decide, Keys
s = "❯ 1. a.txt (Recommended)\n  2. b.txt\nEnter to select · ↑/↓ to navigate · Esc to cancel"
assert decide(s, None, None, 0, 0.0) == Keys("1")' >/dev/null 2>&1) && ok "decide picks the recommended option" || bad "decide picks the recommended option"

(cd "$ROOT" && python3 bench/compare.py --jobs-dir bench/fixtures/jobs-agent-mismatch --out "$tmp/m.md" >/dev/null 2>"$tmp/m.err"); rc=$?
[ "$rc" = 1 ] && grep -q agent "$tmp/m.err" && ok "compare refuses arms with different agents" || bad "compare refuses arms with different agents (rc=$rc)"

mkdir -p "$tmp/aj/full-pasadena-x/t__1/agent/sessions/projects/-app"
echo '{"arm":"pasadena","kind":"full","createdAt":"2026-11-22T10:00:00Z"}' >"$tmp/aj/full-pasadena-x/bench-meta.json"
echo '{"type":"assistant","message":{"content":[{"type":"tool_use","name":"Write","input":{"file_path":"/tmp/pasadena/specs/s.md","content":"# S"}}]}}' >"$tmp/aj/full-pasadena-x/t__1/agent/sessions/projects/-app/a.jsonl"
(cd "$ROOT" && python3 bench/artifacts.py --jobs-dir "$tmp/aj" --out "$tmp/aout" >/dev/null 2>&1)
[ -f "$tmp/aout/t__1/specs/s.md" ] && ok "artifacts reads session transcripts" || bad "artifacts reads session transcripts"
```
- [ ] **Step 2: run them, watch them fail** — `bash bench/acceptance.test.sh`, expect last line `FAILED: 4` (TUI agent, decide, agent mismatch, artifacts; `bench:test exits 0` stays green).

---

### Task 1: `bench/tui_policy.py` — the scripted user

**Writes:** `bench/tui_policy.py`, `bench/tests/policy.test.sh`
**Depends on:** Task 0
**Executor:** claude
**Complexity:** routine
**Satisfies:** acceptance «decide picks the recommended option»
**Interfaces:**
- Produces: frozen dataclasses `Keys(keys: str)`, `Paste(text: str)`, `Wait()`, `Done()`, `Fail(reason: str)`; constants from Global constraints; `decide(screen: str, stop: dict | None, failure: dict | None, nudges: int, idle_s: float) -> Keys | Paste | Wait | Done | Fail`.

- [ ] **Step 1: write the failing test** — `bench/tests/policy.test.sh` runs one `python3 - <<'PY'` block (with `PYTHONPATH=$ROOT`) holding a table of `(name, args, expected)` and prints `ok/FAIL` per row, exiting with the failure count. Screens are verbatim from spec §2:
  - `ASK` = the `AskUserQuestion` capture (`❯ 1. a.txt (Recommended)` … `Enter to select · ↑/↓ to navigate · Esc to cancel`) → `Keys("1")`
  - `ASK2` = same but `  1. a.txt` and `❯ 2. b.txt (Recommended)` → `Keys("2")`
  - `PLAN` = the `Would you like to proceed?` capture → `Keys("1")`
  - `MENU` = `"❯ No, exit\n  Yes, I accept\nEnter to confirm · Esc to cancel"` → `Keys("Enter")`
  - `IDLE` = `"✻ Crunched for 5s · done 4:32 PM\n❯ cat a.txt\n  ⏵⏵ bypass permissions on (shift+tab to cycle)"`:
    - `stop=None` → `Wait()`
    - `stop={"last_assistant_message":"Done.","background_tasks":["x"]}`, `idle_s=10` → `Wait()`; same with `idle_s=600` → `Done()`
    - `stop={"last_assistant_message":"Spec written.\nShall I continue?","background_tasks":[]}`, `nudges=0` → `Paste(NUDGE)`; same with `nudges=5` → `Done()`
    - `last_assistant_message="Spec saved. Let me know when ready."` → `Paste(NUDGE)` (phrase, no `?`)
    - `last_assistant_message="Is it fast? Yes.\nAll tests pass."` → `Done()` (the `?` is not on the last non-empty line, no phrase)
    - `last_assistant_message="All tests pass."` → `Done()`
  - `failure={"error":"rate_limit"}` with any screen → `Fail("rate_limit")`; `failure={}` → `Fail("StopFailure")`
  - `ASK` with a pending `stop` → still `Keys("1")` (dialogs first)
- [ ] **Step 2: run it, watch it fail** — `bash bench/tests/policy.test.sh`, expect `ModuleNotFoundError` → `FAILED:`.
- [ ] **Step 3: implement** — `bench/tui_policy.py`:
```python
import re
from dataclasses import dataclass

MAX_NUDGES = 5
BACKGROUND_WAIT_S = 600
NUDGE = ("No human is available to answer. Take that as approval: continue with the "
         "recommended option until the task is finished and verified.")
ASK_PHRASES = ("let me know", "tell me", "your approval", "approve", "would you like",
               "shall i", "should i", "ready to proceed", "before we move on", "before i continue")
RECOMMENDED = re.compile(r"^\s*(?:❯\s*)?(\d+)\.\s.*\(Recommended\)", re.M)

@dataclass(frozen=True)
class Keys: keys: str
@dataclass(frozen=True)
class Paste: text: str
@dataclass(frozen=True)
class Wait: pass
@dataclass(frozen=True)
class Done: pass
@dataclass(frozen=True)
class Fail: reason: str

def asks(message):
    lines = [l for l in message.splitlines() if l.strip()]
    lowered = message.lower()
    return bool(lines and "?" in lines[-1]) or any(p in lowered for p in ASK_PHRASES)

def decide(screen, stop, failure, nudges, idle_s):
    if failure is not None:
        return Fail(str(failure.get("error") or "StopFailure"))
    match = RECOMMENDED.search(screen)
    if match:
        return Keys(match.group(1))
    if "Would you like to proceed?" in screen:
        return Keys("1")
    if "Enter to select" in screen or "Enter to confirm" in screen:
        return Keys("Enter")
    if stop is None:
        return Wait()
    if stop.get("background_tasks") and idle_s < BACKGROUND_WAIT_S:
        return Wait()
    if asks(stop.get("last_assistant_message") or "") and nudges < MAX_NUDGES:
        return Paste(NUDGE)
    return Done()
```
  (format the dataclasses one field per line.)
- [ ] **Step 4: run it, watch it pass** — `bash bench/tests/policy.test.sh`, expect `All checks passed.`

---

### Task 2: `bench/tui_agent.py` — Harbor agent driving the TUI

**Writes:** `bench/tui_agent.py`, `bench/tests/tui_agent.test.sh`
**Reads:** `.bench/venv/lib/python3.14/site-packages/harbor/agents/installed/claude_code.py` (lines 617–647, 2109–2160)
**Depends on:** Task 1
**Executor:** claude
**Complexity:** complex
**Interfaces:**
- Consumes: `decide`, `Keys`, `Paste`, `Wait`, `Done`, `Fail` (Task 1).
- Produces: `TuiClaudeCode(ClaudeCode)` with `name()` → `"tui-claude-code"`; overridable `command(self) -> str` (default `""`), `prompt(self, instruction) -> str` (default identity), `async prepare(self, environment, env) -> None` (default no-op, called after the config files are written and before tmux starts); exceptions `TuiStartError`, `TuiApiError`; module constants `POLL_S = 2`, `START_TIMEOUT_S = 60`; pure helpers `claude_json(cwd) -> str`, `settings_json(logs) -> str`; `async _sh(self, environment, command, env=None) -> str` (stdout of `exec_as_agent`, the only exec path, so tests can replace it).

- [ ] **Step 1: write the failing test** — `bench/tests/tui_agent.test.sh`; skips with `  skip — harbor venv absent` when `.bench/venv/bin/python` is missing; otherwise runs a `.bench/venv/bin/python - <<'PY'` block with `PYTHONPATH=$ROOT`:
  - `json.loads(claude_json("/app"))` has `hasCompletedOnboarding: True`, `theme: "dark"`, `projects["/app"]["hasTrustDialogAccepted"] is True`.
  - `json.loads(settings_json("/logs/agent"))` has `skipDangerousModePermissionPrompt: True`; its `Stop` hook command contains `/logs/agent/stops.jsonl`; its `StopFailure` hook command contains `/logs/agent/failures.jsonl`.
  - Fake run: `agent = TuiClaudeCode(logs_dir=Path(tmp), model_name="anthropic/claude-opus-5-5")`; `tui_agent.POLL_S = 0`; replace `agent._sh` with an async fake that records commands and answers by substring:
    - `pwd` → `/app`
    - `capture-pane` → successive screens from a list: `IDLE_START` (`"❯ \n  ⏵⏵ bypass permissions on (shift+tab to cycle)"`), then `ASK` (spec §2), then `ASK` again (unchanged), then `IDLE_START` forever
    - `stops.jsonl` read → `""` until the 4th capture, then one line `{"last_assistant_message":"Done.","background_tasks":[]}`
    - `failures.jsonl` read → `""`
    - anything else → `""`
  - `asyncio.run(agent.run("do X", FakeEnv(), AgentContext()))` (FakeEnv is unused because `_sh` is replaced; use `object()` if `run` doesn't touch it).
  - Assert, on the recorded commands: one contains `claude --dangerously-skip-permissions --model claude-opus-5-5`; one contains `paste-buffer -p`; exactly **one** `send-keys -t cc 1` (unchanged screen not pressed twice); the run returned (Done) and a `driver.log` exists in `tmp` with a line containing `Keys`.
  - Second fake run where `failures.jsonl` returns `{"error":"rate_limit"}` → `run` raises `TuiApiError`.
  - Third fake run where `capture-pane` never shows `bypass permissions on` and `tui_agent.START_TIMEOUT_S = 0` → raises `TuiStartError`.
- [ ] **Step 2: run it, watch it fail** — `bash bench/tests/tui_agent.test.sh`, expect `FAILED:` (`ModuleNotFoundError: bench.tui_agent`).
- [ ] **Step 3: implement** — `bench/tui_agent.py`:
  - imports: `asyncio, base64, json, os, shlex, time`, `from pathlib import Path`, `from typing import override`, `from harbor.agents.installed.claude_code import ClaudeCode`, `from bench.tui_policy import Done, Fail, Keys, Paste, Wait, decide`.
  - `claude_json(cwd)`: `json.dumps({"hasCompletedOnboarding": True, "theme": "dark", "projects": {cwd: {"hasTrustDialogAccepted": True, "hasCompletedProjectOnboarding": True}}})`.
  - `settings_json(logs)`: `json.dumps({"skipDangerousModePermissionPrompt": True, "hooks": {"Stop": [hook(f"{logs}/stops.jsonl")], "StopFailure": [hook(f"{logs}/failures.jsonl")]}})` with `hook(path) = {"hooks": [{"type": "command", "command": f"cat >> {path}; echo >> {path}"}]}`.
  - `install`: `await super().install(environment)` then `await self.ensure_system_dependencies(environment, ("tmux",))`.
  - `_env()`: as `ClaudeCode.run` builds it (`_resolve_auth_env()`, `CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC=1`, `IS_SANDBOX=1`, `self._resolved_env_vars`, `CLAUDE_CONFIG_DIR=(self.environment_logs_dir / "sessions").as_posix()`), without `ANTHROPIC_MODEL` (the model goes on the command line).
  - `_write(environment, path, text)`: `await self._sh(environment, f"mkdir -p {dir} && echo {b64} | base64 -d > {path}")` with `b64 = base64.b64encode(text.encode()).decode()`.
  - `run(instruction, environment, context)`:
    1. `env = self._env()`; `logs = self.environment_logs_dir.as_posix()`; `cfg = env["CLAUDE_CONFIG_DIR"]`; `cwd = (await self._sh(environment, "pwd")).strip()`.
    2. `_write` `cfg/.claude.json` ← `claude_json(cwd)` and `cfg/settings.json` ← `settings_json(logs)`; `: > {logs}/stops.jsonl; : > {logs}/failures.jsonl`.
    3. `await self.prepare(environment, env)`.
    4. `model = (self._resolved_model_name() or self.model_name).split("/")[-1]`; launch: `await self._sh(environment, f'tmux new-session -d -s cc -x 200 -y 50 -c {shlex.quote(cwd)} {shlex.quote(f"export PATH=$HOME/.local/bin:$PATH; claude --dangerously-skip-permissions --model {model}")}', env=env)` — the tmux server inherits `env`.
    5. Poll `capture-pane -p -t cc` every `POLL_S` until `"bypass permissions on"` appears; after `START_TIMEOUT_S` raise `TuiStartError("claude TUI did not start")`.
    6. If `self.command()`: `send-keys -t cc -l {shlex.quote(command)}`. Then `_write` `/tmp/tui-prompt.txt` ← `self.prompt(instruction)`; `tmux load-buffer -b p /tmp/tui-prompt.txt && tmux paste-buffer -p -d -b p -t cc`; sleep 1 s; `tmux send-keys -t cc Enter`.
    7. Loop: `screen = capture`; `stops = [json.loads(l) for l in (await self._sh(environment, f"cat {logs}/stops.jsonl")).splitlines() if l.strip()]`; new entries beyond `seen` set `pending = stops[-1]`, `pending_at = time.monotonic()`; `failures` likewise, `failure = failures[-1] if failures else None`; `action = decide(screen, pending, failure, nudges, time.monotonic() - pending_at if pending else 0.0)`.
       - `Keys`: if `screen == last_keys_screen`, treat as `Wait`; else `tmux send-keys -t cc {keys}`, `last_keys_screen = screen`, `pending = None`.
       - `Paste`: same paste sequence as step 6 with `action.text`; `nudges += 1`; `pending = None`.
       - `Done`: break. `Fail`: raise `TuiApiError(action.reason)`.
       - Every non-`Wait` action appends `f"{time.strftime('%H:%M:%S')} {action!r}\n{screen}\n---\n"` to `self.logs_dir / "driver.log"` (host path, plain `open(..., "a")`).
       - `await asyncio.sleep(POLL_S)`.
    8. `finally`: `await self._sh(environment, "tmux kill-server || true")`.
  - `_sh(environment, command, env=None)`: `return (await self.exec_as_agent(environment, command=command, env=env)).stdout or ""`.
- [ ] **Step 4: run it, watch it pass** — expect `All checks passed.`

---

### Task 3: Pasadena agent on top of the TUI agent

**Writes:** `bench/pasadena_agent.py`, `bench/pasadena_wrap.py`, `bench/tests/agent.test.sh`
**Depends on:** Task 2
**Executor:** claude
**Complexity:** routine
**Satisfies:** acceptance «pasadena dry-run uses the custom agent» (stays green)
**Interfaces:**
- Consumes: `TuiClaudeCode`, `prepare`, `command`, `prompt` (Task 2).
- Produces: `PasadenaClaudeCode(TuiClaudeCode)`; `pasadena_wrap.PREAMBLE` (new text), `pasadena_wrap.COMMAND = "/pasadena:pasadena "`, `pasadena_wrap.prompt(instruction) -> str` = `f"{instruction}\n\n{PREAMBLE}"`; `install_command` unchanged; `wrap` removed.

- [ ] **Step 1: update the test first** — `bench/tests/agent.test.sh`:
  - replace the `wrap` case with: `python3 -c 'from bench.pasadena_wrap import COMMAND, prompt; print(COMMAND + "|" + prompt("fix X"))'` matching `'/pasadena:pasadena |fix X*'`, `'*Run the full workflow: pasadena:sheldon with the Architectural path, then pasadena:leonard, then pasadena:wolowitz.*'`, `'*/tmp/pasadena*'`, `'*Do not open pull requests or push.*'`; plus a check that the output does **not** contain `No human is available during this run.`
  - replace the subclass check with `issubclass(PasadenaClaudeCode, TuiClaudeCode)` (`from bench.tui_agent import TuiClaudeCode`) and `PasadenaClaudeCode(logs_dir=Path("/tmp/x"), model_name="anthropic/claude-opus-5-5").command() == "/pasadena:pasadena "`.
- [ ] **Step 2: run it, watch it fail** — `bash bench/tests/agent.test.sh`, expect `FAILED: 2` or more.
- [ ] **Step 3: implement**
  - `bench/pasadena_wrap.py`: `PREAMBLE` = the verbatim text in Global constraints joined with `\n`; `COMMAND = "/pasadena:pasadena "`; `def prompt(instruction): return f"{instruction}\n\n{PREAMBLE}"`; delete `wrap`.
  - `bench/pasadena_agent.py`:
```python
class PasadenaClaudeCode(TuiClaudeCode):
    @staticmethod
    @override
    def name() -> str:
        return "pasadena-claude-code"

    @override
    def command(self) -> str:
        return COMMAND

    @override
    def prompt(self, instruction: str) -> str:
        return prompt(instruction)

    @override
    async def prepare(self, environment, env) -> None:
        await self._sh(environment, f"mkdir -p {REMOTE_ROOT}")
        for d in PLUGIN_DIRS:
            await environment.upload_dir(REPO / d, f"{REMOTE_ROOT}/{d}")
        try:
            await self._sh(environment, install_command(env["CLAUDE_CONFIG_DIR"]), env=env)
        except Exception as e:
            raise PasadenaPluginMissingError(f"pasadena plugin not installed: {e}") from e
```
  (no `run` override; `PasadenaPluginMissingError` stays.)
- [ ] **Step 4: run it, watch it pass** — expect `All checks passed.`

---

### Task 4: `run.sh` — TUI agent for baseline, agent files in the job hash

**Writes:** `bench/run.sh`, `bench/tests/run.test.sh`
**Depends on:** Task 2
**Executor:** claude
**Complexity:** routine
**Satisfies:** acceptance «baseline dry-run uses the TUI agent»
**Interfaces:**
- Produces: `bench-meta.json` gains `"agent": "tui"`.

- [ ] **Step 1: update the test first** — `bench/tests/run.test.sh`:
  - line 17 also copies `"$ROOT"/bench/tui_{agent,policy}.py` into `$BENCH_PLUGIN_ROOT/bench/`;
  - first case expects `'-a bench.tui_agent:TuiClaudeCode'` instead of `'-a claude-code'`;
  - new case: append `# x` to `$BENCH_PLUGIN_ROOT/bench/tui_policy.py` → both `--arm baseline --print-job-name` and `--arm pasadena --print-job-name` change;
  - `check_metadata` also asserts `metadata["agent"] == "tui"`.
- [ ] **Step 2: run it, watch it fail** — `bash bench/tests/run.test.sh`, expect `FAILED: 3`.
- [ ] **Step 3: implement** — in `bench/run.sh`:
  - `baseline) agent=bench.tui_agent:TuiClaudeCode ;;`
  - before the plugin hash: `agent_hash="$(cd "$BENCH_PLUGIN_ROOT" && sha256sum bench/tui_agent.py bench/tui_policy.py | sha256sum | cut -c1-64)"`
  - add `"$agent_hash"` to the `printf '\0%s'` list that feeds the job hash.
  - in the metadata Python block add `"agent": "tui",`.
- [ ] **Step 4: run it, watch it pass** — expect `All checks passed.`

---

### Task 5: `compare.py` — TUI infra errors and agent pairing

**Writes:** `bench/compare.py`, `bench/tests/compare.test.sh`, `bench/fixtures/jobs-agent-mismatch/**`
**Depends on:** Task 0
**Executor:** claude
**Complexity:** routine
**Satisfies:** acceptance «compare refuses arms with different agents»

- [ ] **Step 1: fixtures and failing test**
  - `bench/fixtures/jobs-agent-mismatch/`: copy `bench/fixtures/jobs/full-baseline-aaaa1111` and `full-pasadena-bbbb2222` with all trials; add `"agent": "tui"` to the pasadena `bench-meta.json` only.
  - `bench/tests/compare.test.sh` new cases:
    - `--jobs-dir bench/fixtures/jobs-agent-mismatch` → rc `1`, stderr contains `agent`;
    - a temp copy of `bench/fixtures/jobs` where one pasadena trial `result.json` gets `"exception_info": {"exception_type": "TuiApiError"}`, `reward_valid: true` → the summary's pasadena infra column counts it (pasadena `infra error` = `1`) and the summary has **no** `плагін pasadena не встановився`.
- [ ] **Step 2: run it, watch it fail** — `bash bench/tests/compare.test.sh`, expect `FAILED: 2`.
- [ ] **Step 3: implement**
  - `INFRA_TYPES = {"PasadenaPluginMissingError", "TuiStartError", "TuiApiError"}`
  - in `load_trials`: `infra = exception in INFRA_TYPES`; `valid = bool(result.get("reward_valid")) and not infra`; `"plugin_missing": exception == "PasadenaPluginMissingError"`.
  - in the pair checks: `if baseline.get("agent", "headless") != pasadena.get("agent", "headless"): sys.exit("bench: baseline and pasadena differ in agent")`.
- [ ] **Step 4: run it, watch it pass** — expect `All checks passed.`

---

### Task 6: `artifacts.py` reads session transcripts

**Writes:** `bench/artifacts.py`, `bench/tests/artifacts.test.sh`
**Depends on:** Task 0
**Executor:** claude
**Complexity:** routine
**Satisfies:** acceptance «artifacts reads session transcripts»

- [ ] **Step 1: failing test** — in `bench/tests/artifacts.test.sh` add a trial `task-b__Q` whose log is `agent/sessions/projects/-app/s1.jsonl` (no `claude-code.txt`) with one `Write` of `/tmp/pasadena/plans/q.md` content `# Q`; assert `$out/task-b__Q/plans/q.md` equals `# Q`.
- [ ] **Step 2: run it, watch it fail** — expect `FAILED: 1`.
- [ ] **Step 3: implement** — in `main()` iterate trials as `for trial_dir in sorted(p for p in job.iterdir() if p.is_dir())`; logs = `[trial_dir / "agent/claude-code.txt"]` (if it exists) plus `sorted((trial_dir / "agent/sessions/projects").glob("*/*.jsonl"))`; merge `written_files` of every log in that order (later wins); the existing containment check stays.
- [ ] **Step 4: run it, watch it pass** — expect `All checks passed.`

---

### Task 7: README + smoke both arms in the TUI (paid)

**Writes:** `bench/README.md`; `bench/tui_policy.py`, `bench/tests/policy.test.sh`, `bench/tui_agent.py`, `bench/tests/tui_agent.test.sh`, `bench/pasadena_wrap.py`, `bench/tests/agent.test.sh` only if smoke needs tuning (each fix test-first).
**Depends on:** Tasks 1–6
**Executor:** claude
**Complexity:** complex
**Satisfies:** spec §6.2, §6.3

- [ ] **Step 1: README** — replace the arm descriptions: both arms run interactive `claude` in tmux; the scripted user (rules of `bench/tui_policy.py` in one list); `driver.log` and the session transcript live in `agent/`; old headless jobs are not compared.
- [ ] **Step 2: green** — `bash bench/acceptance.test.sh && npm run --silent bench:test`, expect `All checks passed.` twice.
- [ ] **Step 3: smoke baseline** — `DOCKER_CONTEXT=default BENCH_ENV_FILE=/home/pc/projects/pasadena/.env npm run bench:baseline -- --task build-pmars -k 1`; pass = `reward_valid: true`, `agent/driver.log` has `Done`, `agent/trajectory.json` exists.
- [ ] **Step 4: smoke pasadena (≤3 iterations)** — `… npm run bench:pasadena -- --task build-pmars -k 1 --fresh`; pass = `reward_valid: true`, transcript under `agent/sessions/projects/` has `EnterPlanMode` and `ExitPlanMode` tool uses and `Skill` calls to `pasadena:sheldon`, `pasadena:leonard`, `pasadena:wolowitz`; `driver.log` has `Keys(keys='1')` on a `Would you like to proceed?` screen. On failure read `driver.log`, fix test-first, rerun; after 3 failures stop and ask the user.
- [ ] **Step 5** — `npm run --silent bench:test`, expect `All checks passed.`

---

### Task 8: full run and report (paid)

**Writes:** `bench/results/summary.md`, `bench/results/artifacts/**`
**Depends on:** Task 7
**Executor:** claude
**Complexity:** complex

- [ ] **Step 1: arms** — `… npm run bench:baseline`, then `… npm run bench:pasadena` (10 tasks × 3); start the image sweeper and a disk watcher for each job; an interrupted run resumes with the same command.
- [ ] **Step 2: compare** — `npm run bench:compare`; `bench/results/summary.md` has both arms, the Δ table and `**Вердикт:**`, without `УВАГА: плагін pasadena не встановився`.
- [ ] **Step 3: artifacts** — `npm run bench:artifacts`.
- [ ] **Step 4: commit** — `bench/results/summary.md` and `bench/results/artifacts/`; verdict in a PR comment.
