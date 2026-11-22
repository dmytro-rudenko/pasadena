from pathlib import Path
from typing import override

from bench.pasadena_wrap import COMMAND, PLUGIN_DIRS, REMOTE_ROOT, install_command, prompt
from bench.tui_agent import TuiClaudeCode

REPO = Path(__file__).resolve().parent.parent


class PasadenaPluginMissingError(RuntimeError):
    pass


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
