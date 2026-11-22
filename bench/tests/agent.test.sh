#!/usr/bin/env bash
set -uo pipefail

cd "$(dirname "$0")/../.." || exit 1
export PYTHONPATH=.
export PYTHONDONTWRITEBYTECODE=1
fails=0

assert_output() {
  local name="$1" status="$2" output="$3" pattern
  shift 3
  if [ "$status" -ne 0 ]; then
    printf '  FAIL — %s (exit %s)\n        %s\n' "$name" "$status" "${output##*$'\n'}"
    fails=$((fails + 1))
    return
  fi
  for pattern; do
    if [[ "$output" != $pattern ]]; then
      printf '  FAIL — %s\n        expected pattern: %s\n        got: %s\n' "$name" "$pattern" "$output"
      fails=$((fails + 1))
      return
    fi
  done
  printf '  ok  — %s\n' "$name"
}

wrapped="$(python3 -c 'from bench.pasadena_wrap import COMMAND, prompt; print(COMMAND + "|" + prompt("fix X"))' 2>&1)"
assert_output 'prompt appends the benchmark instructions after the task' "$?" "$wrapped" \
  '/pasadena:pasadena |fix X*' \
  '*Run the full workflow: pasadena:sheldon with the Architectural path, then pasadena:leonard, then pasadena:wolowitz.*' \
  '*/tmp/pasadena*' \
  '*Do not open pull requests or push.*'

if [[ "$wrapped" != *'No human is available during this run.'* ]]; then
  echo '  ok  — prompt leaves the no-human nudge to the TUI policy'
else
  printf '  FAIL — prompt leaves the no-human nudge to the TUI policy\n'
  printf '        got: %s\n' "$wrapped"
  fails=$((fails + 1))
fi

install="$(python3 -c 'from bench.pasadena_wrap import install_command; print(install_command("/logs/agent/sessions"))' 2>&1)"
assert_output 'install_command configures the session and installs the plugin' "$?" "$install" \
  '*export CLAUDE_CONFIG_DIR=/logs/agent/sessions*' \
  '*claude plugin marketplace add /opt/pasadena*' \
  '*claude plugin install pasadena@pasadena*' \
  '*claude plugin list*'

if [[ "$install" != *'grep -q'* && "$install" == *'grep pasadena >/dev/null'* ]]; then
  echo '  ok  — install_command reads the full plugin list'
else
  printf '  FAIL — install_command reads the full plugin list\n'
  printf '        expected grep pasadena >/dev/null and no grep -q\n'
  printf '        got: %s\n' "$install"
  fails=$((fails + 1))
fi

harbor_python="${BENCH_HARBOR_PYTHON:-}"
if [ -e .bench/venv/bin/python ]; then
  harbor_python=.bench/venv/bin/python
fi
if [ -n "$harbor_python" ]; then
  imported="$("$harbor_python" -c 'from pathlib import Path; from bench.pasadena_agent import PasadenaClaudeCode; from bench.tui_agent import TuiClaudeCode; assert issubclass(PasadenaClaudeCode, TuiClaudeCode); assert PasadenaClaudeCode(logs_dir=Path("/tmp/x"), model_name="anthropic/claude-opus-5-5").command() == "/pasadena:pasadena "' 2>&1)"
  assert_output 'PasadenaClaudeCode is a TuiClaudeCode that opens with /pasadena:pasadena' "$?" "$imported"
else
  echo '  skip — harbor venv absent'
fi

echo
if [ "$fails" -gt 0 ]; then
  echo "FAILED: $fails"
  exit 1
fi
echo "All checks passed."
