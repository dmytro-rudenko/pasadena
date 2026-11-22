#!/usr/bin/env bash
set -uo pipefail

HERE="$(cd "$(dirname "$0")/.." && pwd)"
fails=0

assert_eq() {
  if [ "$1" = "$2" ]; then
    echo "  ok  — $3"
  else
    echo "  FAIL — $3 (expected '$2', got '$1')"
    fails=$((fails + 1))
  fi
}

. "$HERE/common.sh"
assert_eq "$(cfg harborVersion)" "0.27.0" "cfg reads harborVersion"
assert_eq "$(cfg attempts)" "3" "cfg reads attempts"

out="$(BENCH_DIR="$(mktemp -d)" bash -c ". '$HERE/common.sh'; require_venv" 2>&1)"
rc=$?
assert_eq "$rc" "1" "require_venv fails without venv"
if [[ "$out" == *"npm run bench:setup"* ]]; then
  echo "  ok  — require_venv names bench:setup"
else
  echo "  FAIL — require_venv hint"
  fails=$((fails + 1))
fi

echo
if [ "$fails" -gt 0 ]; then
  echo "FAILED: $fails"
  exit 1
fi
echo "All checks passed."
