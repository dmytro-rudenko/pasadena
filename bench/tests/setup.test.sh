#!/usr/bin/env bash
set -uo pipefail

SETUP="$(cd "$(dirname "$0")/.." && pwd)/setup.sh"
tmp="$(mktemp -d)" || exit 1
trap 'rm -rf "$tmp"' EXIT
fails=0

python3_path="$(command -v python3)" || exit 1
mkdir "$tmp/bin" || exit 1
cat >"$tmp/bin/docker" <<'EOF' || exit 1
#!/usr/bin/env bash
exit "$SETUP_TEST_DOCKER_STATUS"
EOF
cat >"$tmp/bin/python3" <<'EOF' || exit 1
#!/usr/bin/env bash
if [[ "${1:-}" == -m && "${2:-}" == venv ]]; then
  echo "setup.test.sh: unexpected venv creation" >&2
  exit 1
fi
exec "$SETUP_TEST_PYTHON3" "$@"
EOF
chmod +x "$tmp/bin/"* || exit 1

prepare_case() {
  docker_status="$1"
  case_dir="$(mktemp -d "$tmp/case.XXXXXX")" || exit 1
  env_file="$case_dir/none.env"
  if [ "$docker_status" -eq 0 ]; then
    mkdir -p "$case_dir/venv/bin" || exit 1
    cat >"$case_dir/venv/bin/harbor" <<'EOF' || exit 1
#!/usr/bin/env bash
echo 0.27.0
EOF
    chmod +x "$case_dir/venv/bin/harbor" || exit 1
  fi
}

run_setup() {
  env -u ANTHROPIC_API_KEY -u CLAUDE_CODE_OAUTH_TOKEN -u BENCH_CONFIG \
    PATH="$tmp/bin:$PATH" BENCH_DIR="$case_dir" BENCH_ENV_FILE="$env_file" \
    SETUP_TEST_DOCKER_STATUS="$docker_status" SETUP_TEST_PYTHON3="$python3_path" \
    "$@" bash "$SETUP" >"$case_dir/stdout" 2>"$case_dir/stderr"
  rc=$?
  stdout="$(<"$case_dir/stdout")"
  stderr="$(<"$case_dir/stderr")"
}

assert_setup() {
  local name="$1" expected_rc="$2" stdout_pattern="$3" expected_stderr failed=0
  shift 3
  if [[ "$rc" != "$expected_rc" || "$stdout" != $stdout_pattern ]]; then
    failed=1
  fi
  for expected_stderr; do
    if [[ "$stderr" != *"$expected_stderr"* ]]; then
      failed=1
    fi
  done
  if [ "$failed" -eq 0 ]; then
    echo "  ok  — $name"
  else
    printf '  FAIL — %s (expected exit %s, got %s)\n' "$name" "$expected_rc" "$rc"
    printf '        stdout: %q, stderr: %q\n' "$stdout" "$stderr"
    fails=$((fails + 1))
  fi
}

prepare_case 1
run_setup
assert_setup "setup reports unavailable Docker" 1 '*' Docker

prepare_case 0
run_setup
assert_setup "setup explains the token when none is set" 1 '*' CLAUDE_CODE_OAUTH_TOKEN 'claude setup-token'

prepare_case 0
run_setup CLAUDE_CODE_OAUTH_TOKEN=x
assert_setup "setup reports readiness with an OAuth token" 0 'bench: ready (harbor 0.27.0)'

prepare_case 0
printf 'CLAUDE_CODE_OAUTH_TOKEN=x\n' >"$env_file" || exit 1
run_setup
assert_setup "setup accepts a token from the env file" 0 '*'

echo
if [ "$fails" -gt 0 ]; then
  echo "FAILED: $fails"
  exit 1
fi
echo "All checks passed."
