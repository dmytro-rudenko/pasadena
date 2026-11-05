#!/usr/bin/env bash
set -uo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
FIXTURES="$ROOT/bench/fixtures"
fails=0

assert_eq() {
  if [ "$1" = "$2" ]; then
    echo "  ok  — $3"
  else
    echo "  FAIL — $3"
    echo "        expected: $2"
    echo "        got: $1"
    fails=$((fails + 1))
  fi
}

assert_contains() {
  if [[ "$1" == *"$2"* ]]; then
    echo "  ok  — $3"
  else
    echo "  FAIL — $3"
    echo "        expected substring: $2"
    echo "        got: $1"
    fails=$((fails + 1))
  fi
}

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
bin="$tmp/bin"
mkdir -p "$bin"
export PATH="$bin:$PATH"

gitc() { git -c user.email=t@t -c user.name=t -c commit.gpgsign=false "$@"; }

repo="$tmp/repo"
git init -q "$repo"
mkdir -p "$repo/src" "$repo/t"
echo "# spec" >"$repo/spec.md"
echo 'helper() { :; }' >"$repo/src/a.sh"
git -C "$repo" add -A
gitc -C "$repo" commit -qm base
BASE="$(git -C "$repo" rev-parse HEAD)"
echo 'grep -qx done feature.txt' >"$repo/t/one.test.sh"
echo 'grep -qx done feature2.txt' >"$repo/t/two.test.sh"
echo done >"$repo/feature.txt"
echo done >"$repo/feature2.txt"
git -C "$repo" add -A
gitc -C "$repo" commit -qm oracle
ORACLE="$(git -C "$repo" rev-parse HEAD)"

printf 'id\tbase\tspec\toracle\ttests\tholdout\n' >"$tmp/tasks.tsv"
printf 't1\t%s\tspec.md\t%s\tt/one.test.sh,t/two.test.sh\t0\n' "$BASE" "$ORACLE" >>"$tmp/tasks.tsv"
printf 't2\t%s\tspec.md\t%s\tt/one.test.sh\t1\n' "$BASE" "$ORACLE" >>"$tmp/tasks.tsv"

plugin="$tmp/plugin"
git init -q "$plugin"
mkdir -p "$plugin/hooks"
cat >"$plugin/hooks/codex.sh" <<'CODEX'
#!/usr/bin/env bash
case "${1:-}" in
  available) exit "${FAKE_CODEX_AVAILABLE:-0}" ;;
  budget)
    used="${FAKE_CODEX_USED:-10}"
    echo "weekly_left=$((100 - used)) weekly_used=$used five_hour_left=90 five_hour_reset=0"
    ;;
esac
CODEX
chmod +x "$plugin/hooks/codex.sh"
git -C "$plugin" add -A
gitc -C "$plugin" commit -qm plugin

export BENCH_REPO="$repo"
export BENCH_TASKS="$tmp/tasks.tsv"
export BENCH_CONFIGS="$ROOT/bench/configs.tsv"
export BENCH_PLUGIN="$plugin"
export BENCH_DIR="$tmp/bench"
export FAKE_LOG="$tmp/claude.args"

{
  printf '#!/usr/bin/env bash\nfixtures=%q\n' "$FIXTURES"
  cat <<'FAKE'
printf '%s\n' "$@" >"$FAKE_LOG"
{
  echo "pwd=$(pwd)"
  echo "XDG_STATE_HOME=${XDG_STATE_HOME-}"
  echo "PASADENA_CODEX=${PASADENA_CODEX-}"
  echo "PASADENA_REUSE=${PASADENA_REUSE-}"
  echo "codex-mode=$(cat "${XDG_STATE_HOME-}/pasadena/codex-mode" 2>/dev/null)"
} >"$FAKE_LOG.env"
git rev-list --count HEAD >"$FAKE_LOG.count" 2>/dev/null

plugin_dir=""
prev=""
for arg in "$@"; do
  [ "$prev" = "--plugin-dir" ] && plugin_dir="$arg"
  prev="$arg"
done

mode="${FAKE_CLAUDE:-}"
case "$mode" in
  hang) exec sleep 30 ;;
  empty) exit 1 ;;
  wrongplugin) plugin_dir="/elsewhere" ;;
esac

if [ -n "${FAKE_WRITES:-}" ]; then
  for pair in $FAKE_WRITES; do
    file="${pair%%=*}"
    mkdir -p "$(dirname "$file")"
    printf '%s\n' "${pair#*=}" >"$file"
  done
  git add -A
  git -c user.name=fake -c user.email=fake@localhost -c commit.gpgsign=false commit -qm fake
fi

if [ -n "$plugin_dir" ]; then
  jq -c --arg p "$plugin_dir" '.plugins = [{"name":"pasadena","path":$p,"source":"pasadena@inline","version":"0.23.0"}]' "$fixtures/init.json"
else
  jq -c '.plugins = []' "$fixtures/init.json"
fi
for _ in $(seq 1 "${FAKE_AGENTS:-1}"); do
  cat "$fixtures/assistant.json"
done
if [ "$mode" = "budget" ]; then
  cat "$fixtures/result-budget.json"
  exit 1
fi
cat "$fixtures/result-success.json"
FAKE
} >"$bin/claude"
chmod +x "$bin/claude"

fresh_bench() {
  rm -rf "$BENCH_DIR"
  : >"$FAKE_LOG"
  rm -f "$FAKE_LOG.env" "$FAKE_LOG.count"
}

last_run() {
  tail -1 "$BENCH_DIR/runs.jsonl" 2>/dev/null | jq -r "$1" 2>/dev/null
}

for part in "$ROOT"/bench/test/*.sh; do
  [ -e "$part" ] && source "$part"
done

echo
if [ "$fails" -gt 0 ]; then
  echo "FAILED: $fails"
  exit 1
fi
echo "All checks passed."
