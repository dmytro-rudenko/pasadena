import shlex

PLUGIN_DIRS = (".claude-plugin", "skills", "hooks", ".claude/commands", "proto")
REMOTE_ROOT = "/opt/pasadena"
PREAMBLE = (
    "Run the full workflow: pasadena:sheldon with the Architectural path, then pasadena:leonard, then pasadena:wolowitz.\n"
    "Invoke each skill with the Skill tool and do not skip a phase, however\n"
    "small the task looks.\n"
    "Work in the current directory without creating a worktree. Keep every\n"
    "workflow file (spec, plan, journal) under /tmp/pasadena, outside the task\n"
    "directory; if git is unavailable there, skip commits and the journal.\n"
    "Do not open pull requests or push."
)
COMMAND = "/pasadena:pasadena "


def prompt(instruction: str) -> str:
    return f"{instruction}\n\n{PREAMBLE}"


def install_command(config_dir: str) -> str:
    q = shlex.quote(config_dir)
    return (
        'export PATH="$HOME/.local/bin:$PATH"; '
        f"export CLAUDE_CONFIG_DIR={q}; mkdir -p \"$CLAUDE_CONFIG_DIR\" && "
        f"claude plugin marketplace add {REMOTE_ROOT} && "
        "claude plugin install pasadena@pasadena && "
        "claude plugin list | grep pasadena >/dev/null"
    )
