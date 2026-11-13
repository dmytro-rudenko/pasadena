BENCH_ROOT="${BENCH_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)}"
BENCH_REPO="${BENCH_REPO:-$(git -C "$BENCH_ROOT" rev-parse --show-toplevel)}"
BENCH_PLUGIN="${BENCH_PLUGIN:-$BENCH_REPO}"
BENCH_DIR="${BENCH_DIR:-${XDG_STATE_HOME:-$HOME/.local/state}/pasadena/bench}"
BENCH_TASKS="${BENCH_TASKS:-$BENCH_ROOT/tasks.tsv}"
BENCH_CONFIGS="${BENCH_CONFIGS:-$BENCH_ROOT/configs.tsv}"
BENCH_CHECKS="${BENCH_CHECKS:-$BENCH_ROOT/checks.tsv}"
BENCH_BUDGET="${BENCH_BUDGET:-15}"
BENCH_TIMEOUT="${BENCH_TIMEOUT:-5400}"
BENCH_ORACLE_TIMEOUT="${BENCH_ORACLE_TIMEOUT:-600}"
BENCH_RUN="${BENCH_RUN:-$BENCH_ROOT/run.sh}"

_tsv_field() {
  local file="$1" kind="$2" key="$3" field="$4" out rc=0
  out="$(awk -F'\t' -v key="$key" -v field="$field" '
    NR == 1 { for (i = 1; i <= NF; i++) if ($i == field) col = i; next }
    $1 == key { found = 1; if (col) print $col; exit }
    END { if (!found) exit 1; if (!col) exit 3 }
  ' "$file")" || rc=$?
  case "$rc" in
    0) printf '%s\n' "$out" ;;
    3) echo "unknown field: $field" >&2; return 2 ;;
    *) echo "unknown $kind: $key" >&2; return 2 ;;
  esac
}

task_field() { _tsv_field "$BENCH_TASKS" task "$1" "$2"; }

config_field() { _tsv_field "$BENCH_CONFIGS" config "$1" "$2"; }

task_ids() {
  awk -F'\t' -v want="$1" '
    NR == 1 { for (i = 1; i <= NF; i++) if ($i == "holdout") col = i; next }
    col && $col == want { print $1 }
  ' "$BENCH_TASKS"
}

config_names() {
  awk -F'\t' 'NR > 1 && $1 != "" { print $1 }' "$BENCH_CONFIGS"
}

bench_rev() {
  cat "$BENCH_TASKS" "$BENCH_CHECKS" 2>/dev/null | sha256sum | cut -c1-12
}

plugin_rev() {
  local rev
  rev="$(git -C "$BENCH_PLUGIN" rev-parse --short HEAD)" || return
  if [ -n "$(git -C "$BENCH_PLUGIN" status --porcelain)" ]; then
    rev="$rev-dirty"
  fi
  printf '%s\n' "$rev"
}

make_tree() {
  local commit="$1" dest="$2"
  mkdir -p "$dest" || return
  git -C "$BENCH_REPO" archive "$commit" | tar -x -C "$dest" || return
  if [ -n "${3:-}" ]; then git -C "$BENCH_REPO" show "$3:$4" >"$dest/$4" || return; fi
  git -C "$dest" init -q || return
  git -C "$dest" add -A || return
  git -C "$dest" -c user.name=bench -c user.email=bench@localhost -c commit.gpgsign=false commit -qm "bench: base"
}

put_oracle_tests() {
  local oracle="$1" csv="$2" tree="$3" paths p
  IFS=, read -ra paths <<<"$csv"
  for p in "${paths[@]}"; do
    mkdir -p "$tree/$(dirname "$p")" || return
    git -C "$BENCH_REPO" show "$oracle:$p" >"$tree/$p" || return
  done
}

run_oracle() {
  local csv="$1" tree="$2" outdir="$3" paths p n=0 code
  mkdir -p "$outdir" || return
  IFS=, read -ra paths <<<"$csv"
  for p in "${paths[@]}"; do
    n=$((n + 1))
    code=0
    (cd "$tree" && timeout "$BENCH_ORACLE_TIMEOUT" bash "$p") >"$outdir/oracle-$n.log" 2>&1 || code=$?
    printf '%s\t%s\n' "$p" "$code" >>"$outdir/oracle.exit"
  done
  return 0
}
