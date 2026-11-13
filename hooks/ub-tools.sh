#!/usr/bin/env bash
set -uo pipefail

DRYER_SHA=66ff6d21a42c04afcad89c78a80066176d1294b0
CRAPPER_SHA=c757ec79a6c15dc815238bbd9c2f4601eb54d3cc
MUTATOR_SHA=830ec7e9c39664d753f8699015bc796df67727b9
UB_HOME="${XDG_DATA_HOME:-${HOME:-}/.local/share}/pasadena/ub-tools"

TOOL_ARGS=()
PATHS=()
CMD=""
RUN=()

python_ok() {
  command -v python3 >/dev/null 2>&1 &&
    python3 -c 'import sys; sys.exit(sys.version_info < (3, 11))' 2>/dev/null
}

resolve() {
  local tool="$1" var exe
  var="PASADENA_$(tr '[:lower:]' '[:upper:]' <<<"$tool")"
  exe="${!var:-}"
  if [ -n "$exe" ]; then
    [ -x "$exe" ] || { echo "$tool: unavailable ($var is not executable)"; return 1; }
    RUN=("$exe")
    return 0
  fi
  if exe="$(command -v "$tool" 2>/dev/null)"; then
    RUN=("$exe")
    return 0
  fi
  if [ -d "$UB_HOME/lib/$tool" ]; then
    python_ok || { echo "$tool: unavailable (python3 >= 3.11 not found)"; return 1; }
    RUN=(env "PYTHONPATH=$UB_HOME/lib${PYTHONPATH:+:$PYTHONPATH}" python3 -m "$tool")
    return 0
  fi
  echo "$tool: unavailable (not installed; run ub-tools.sh install)"
  return 1
}

split_args() {
  local seen=0 arg rest=()
  for arg in "$@"; do
    if [ "$seen" = 1 ]; then
      rest+=("$arg")
    elif [ "$arg" = "--" ]; then
      seen=1
    elif [ -e "$arg" ]; then
      case "$arg" in
        /*) ;;
        *) arg="$PWD/$arg" ;;
      esac
      TOOL_ARGS+=("$arg")
      PATHS+=("$arg")
    else
      TOOL_ARGS+=("$arg")
    fi
  done
  if [ "${#rest[@]}" -eq 1 ]; then
    CMD="${rest[0]}"
  elif [ "${#rest[@]}" -gt 1 ]; then
    CMD="$(printf '%q ' "${rest[@]}")"
    CMD="${CMD% }"
  fi
}

project_root() {
  git rev-parse --show-toplevel 2>/dev/null || echo "$PWD"
}

warn_ignored() {
  local root="$1" dir
  git -C "$root" rev-parse --is-inside-work-tree >/dev/null 2>&1 || return 0
  for dir in .metrics target coverage; do
    git -C "$root" check-ignore -q "$dir/.probe" ||
      echo "warning: $dir is not gitignored; do not commit it"
  done
}

js_count() {
  local p js=(-type f \( -name '*.js' -o -name '*.jsx' -o -name '*.mjs' -o -name '*.cjs' \)
    ! -name '*.test.*' ! -name '*.spec.*' -print)
  for p in ${PATHS[@]+"${PATHS[@]}"}; do
    find "$p" -maxdepth 0 "${js[@]}"
    find "$p" -mindepth 1 \
      \( -type d \( -name node_modules -o -name dist -o -name build -o -name out \
      -o -name coverage -o -name target -o -name .git -o -name test -o -name tests \
      -o -name spec -o -name specs -o -name __tests__ \) -prune \) -o "${js[@]}"
  done 2>/dev/null | wc -l | tr -d ' '
}

cmd_dryer() {
  resolve dryer || return 0
  if [ "${#PATHS[@]}" -eq 0 ]; then
    PATHS=("$PWD")
    TOOL_ARGS+=("$PWD")
  fi
  local scratch rc count
  scratch="$(mktemp -d)"
  "${RUN[@]}" --root "$scratch" --threshold 0.8 "${TOOL_ARGS[@]}"
  rc=$?
  rm -rf "$scratch"
  echo "dryer exit: $rc"
  count="$(js_count)"
  [ "$count" -gt 0 ] && echo "unchecked: $count JS files (dryer supports TypeScript only)"
  return 0
}

cmd_crapper() {
  resolve crapper || return 0
  local root
  root="$(project_root)"
  warn_ignored "$root"
  "${RUN[@]}" --root "$root" --threshold 10 ${TOOL_ARGS[@]+"${TOOL_ARGS[@]}"}
  echo "crapper exit: $?"
}

cmd_mutator() {
  resolve mutator || return 0
  local root extra=()
  root="$(project_root)"
  warn_ignored "$root"
  [ -n "$CMD" ] && extra=(--test-command "$CMD")
  case " ${TOOL_ARGS[*]-} " in
    *" --scan "*) ;;
    *) extra+=(--max-workers 3) ;;
  esac
  "${RUN[@]}" --root "$root" ${extra[@]+"${extra[@]}"} ${TOOL_ARGS[@]+"${TOOL_ARGS[@]}"}
  echo "mutator exit: $?"
}

cmd_install() {
  command -v git >/dev/null 2>&1 || { echo "install: unavailable (git not found)"; return 0; }
  python_ok || { echo "install: unavailable (python3 >= 3.11 not found)"; return 0; }
  local tool sha src
  for tool in dryer crapper mutator; do
    case "$tool" in
      dryer) sha="$DRYER_SHA" ;;
      crapper) sha="$CRAPPER_SHA" ;;
      mutator) sha="$MUTATOR_SHA" ;;
    esac
    src="$UB_HOME/src/$tool"
    { rm -rf "$src" && mkdir -p "$src" &&
      git -C "$src" init -q &&
      git -C "$src" fetch -q --depth 1 "https://github.com/unclebob/$tool.git" "$sha" &&
      git -C "$src" checkout -q FETCH_HEAD; } ||
      { echo "install: failed to fetch $tool@$sha"; return 0; }
  done
  python3 -m pip install --quiet --upgrade --target "$UB_HOME/lib" \
    "$UB_HOME/src/dryer" "$UB_HOME/src/crapper" "$UB_HOME/src/mutator" ||
    { echo "install: pip failed"; return 0; }
  echo "installed: dryer crapper mutator in $UB_HOME"
}

sub="${1:-}"
[ "$#" -gt 0 ] && shift
split_args "$@"
case "$sub" in
  install) cmd_install ;;
  dryer) cmd_dryer ;;
  crapper) cmd_crapper ;;
  mutator) cmd_mutator ;;
  *) echo "usage: ub-tools.sh install | dryer|crapper [path...] | mutator [path...] [-- <test command>]" ;;
esac
exit 0
