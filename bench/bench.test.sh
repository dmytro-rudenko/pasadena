#!/usr/bin/env bash
set -uo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
failed=0
for t in "$HERE"/tests/*.test.sh; do
  echo "== ${t##*/}"
  bash "$t" || failed=$((failed + 1))
done

echo
if [ "$failed" -gt 0 ]; then
  echo "FAILED: $failed"
  exit 1
fi
echo "All checks passed."
