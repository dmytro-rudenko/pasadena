#!/usr/bin/env bash
# Self-check for the ub-tools wrapper. Run: bash hooks/ub-tools.test.sh
set -uo pipefail
unset PASADENA_DRYER PASADENA_CRAPPER PASADENA_MUTATOR XDG_DATA_HOME

DIR="$(cd "$(dirname "$0")" && pwd)"
TOOL="$DIR/ub-tools.sh"
fails=0

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

assert_not_contains() {
  if [[ "$1" != *"$2"* ]]; then
    echo "  ok  — $3"
  else
    echo "  FAIL — $3"
    echo "        unexpected substring: $2"
    fails=$((fails + 1))
  fi
}

assert_exit0() {
  if [ "$1" -eq 0 ]; then
    echo "  ok  — $2"
  else
    echo "  FAIL — $2"
    echo "        expected exit 0, got: $1"
    fails=$((fails + 1))
  fi
}

assert_exit() {
  if [ "$1" -eq "$2" ]; then
    echo "  ok  — $3"
  else
    echo "  FAIL — $3"
    echo "        expected exit $2, got: $1"
    fails=$((fails + 1))
  fi
}

work="$(cd "$(mktemp -d)" && pwd -P)"
fakebin="$work/bin"
mkdir -p "$fakebin"
for name in dryer crapper mutator; do
  cat >"$fakebin/fake-$name" <<EOF
#!/usr/bin/env bash
printf '%s\n' "\$@" >"$work/$name.args"
prev=""; for a in "\$@"; do [ "\$prev" = "--root" ] && { [ -d "\$a" ] && echo yes || echo no; } >"$work/$name.rootdir"; prev="\$a"; done
echo "FAKE $name ran"
exit \${FAKE_EXIT:-0}
EOF
  chmod +x "$fakebin/fake-$name"
done

proj="$work/proj"
mkdir -p "$proj/src" "$proj/src/node_modules/pkg" "$proj/src/dist" "$proj/src/test"
git -C "$proj" init -q
for f in a.js b.mjs c.cjs d.jsx e.ts f.d.ts g.test.js; do echo x >"$proj/src/$f"; done
echo x >"$proj/src/node_modules/pkg/i.js"
echo x >"$proj/src/dist/j.js"
echo x >"$proj/src/test/k.js"

echo "== dryer =="
out="$(cd "$proj" && PASADENA_DRYER="$fakebin/fake-dryer" bash "$TOOL" dryer src)"
assert_exit0 $? "dryer exits 0"
args="$(cat "$work/dryer.args")"$'\n'
assert_contains "$out" "FAKE dryer ran" "dryer output passes through"
assert_contains "$args" $'--threshold\n0.8\n' "dryer threshold is 0.8"
assert_contains "$args" "$proj/src" "relative path made absolute"
scratch="$(sed -n '/^--root$/{n;p;}' "$work/dryer.args")"
assert_not_contains "$scratch" "$proj" "dryer root is not the project"
[ -n "$scratch" ] && [ ! -e "$scratch" ] && echo "  ok  — dryer scratch root removed" ||
  { echo "  FAIL — dryer scratch root removed"; fails=$((fails + 1)); }
assert_contains "$(cat "$work/dryer.rootdir" 2>/dev/null)" "yes" "dryer scratch root existed during the run"
assert_contains "$out" "dryer exit: 0" "dryer exit code reported"
assert_contains "$out" "unchecked: 4 JS files (dryer supports TypeScript only)" "JS counted; tests, node_modules, dist, .d.ts skipped"
[ "$(tail -n 1 <<<"$out")" = "unchecked: 4 JS files (dryer supports TypeScript only)" ] &&
  echo "  ok  — unchecked is the last line" ||
  { echo "  FAIL — unchecked is the last line"; fails=$((fails + 1)); }

mkdir -p "$work/tsonly"
echo x >"$work/tsonly/a.ts"
out="$(cd "$work/tsonly" && PASADENA_DRYER="$fakebin/fake-dryer" bash "$TOOL" dryer)"
assert_not_contains "$out" "unchecked:" "no JS, no unchecked line"
assert_contains "$(cat "$work/dryer.args")" "$work/tsonly" "no path defaults to the current directory"

mkdir -p "$work/out/src"
echo x >"$work/out/src/a.js"
out="$(cd "$work/out" && PASADENA_DRYER="$fakebin/fake-dryer" bash "$TOOL" dryer)"
assert_contains "$out" "unchecked: 1 JS files (dryer supports TypeScript only)" "start dir named like an excluded dir is still counted"
mkdir -p "$work/build"
echo x >"$work/build/b.js"
out="$(cd "$proj" && PASADENA_DRYER="$fakebin/fake-dryer" bash "$TOOL" dryer "$work/build/b.js")"
assert_contains "$out" "unchecked: 1 JS files" "explicit file under an excluded dir name is counted"

echo "== crapper =="
out="$(cd "$proj/src" && FAKE_EXIT=2 PASADENA_CRAPPER="$fakebin/fake-crapper" bash "$TOOL" crapper e.ts -- npm test)"
assert_exit0 $? "crapper exits 0 when the tool exits 2"
args="$(cat "$work/crapper.args")"$'\n'
assert_contains "$args" $'--root\n'"$proj"$'\n' "crapper root is the git toplevel"
assert_contains "$args" $'--threshold\n10\n' "crapper threshold is 10"
assert_not_contains "$args" "--coverage-command" "crapper ignores the test command and measures coverage itself"
assert_contains "$args" "$proj/src/e.ts" "crapper path made absolute"
assert_contains "$out" "crapper exit: 2" "crapper exit code reported"
assert_contains "$out" "warning: .metrics is not gitignored; do not commit it" "unignored .metrics warned"

printf '.metrics/\ntarget/\ncoverage/\n' >"$proj/.gitignore"
out="$(cd "$proj" && PASADENA_CRAPPER="$fakebin/fake-crapper" bash "$TOOL" crapper src)"
assert_not_contains "$out" "warning:" "ignored folders, no warning"
assert_not_contains "$(cat "$work/crapper.args")" "--coverage-command" "no tail, no coverage command"

out="$(cd "$proj" && PASADENA_MUTATOR="$fakebin/fake-mutator" bash "$TOOL" mutator src -- npm test)"
assert_contains "$(cat "$work/mutator.args")"$'\n' $'--test-command\nnpm test\n' "plain words join into the exact command"
out="$(cd "$proj" && PASADENA_MUTATOR="$fakebin/fake-mutator" bash "$TOOL" mutator src -- npm test -- --grep 'two words')"
assert_contains "$(cat "$work/mutator.args")" 'two\ words' "quoted test argument keeps its boundary"
out="$(cd "$proj" && PASADENA_MUTATOR="$fakebin/fake-mutator" bash "$TOOL" mutator src -- 'bash a.sh && bash b.sh')"
assert_contains "$(cat "$work/mutator.args")"$'\n' $'--test-command\nbash a.sh && bash b.sh\n' "single-argument command passes through unchanged"

echo "== mutator =="
out="$(cd "$proj/src" && FAKE_EXIT=3 PASADENA_MUTATOR="$fakebin/fake-mutator" bash "$TOOL" mutator e.ts --lines 3,4 -- npm test)"
assert_exit0 $? "mutator exits 0 when the tool exits 3"
args="$(cat "$work/mutator.args")"$'\n'
assert_contains "$args" $'--root\n'"$proj"$'\n' "mutator root is the git toplevel"
assert_contains "$args" $'--max-workers\n3\n' "mutator max workers 3"
assert_contains "$args" $'--test-command\nnpm test' "tail after -- is the test command"
assert_contains "$args" $'--lines\n3,4' "flag value passes through unchanged"
assert_contains "$out" "mutator exit: 3" "mutator exit code reported"
out="$(cd "$proj" && PASADENA_MUTATOR="$fakebin/fake-mutator" bash "$TOOL" mutator --scan src/e.ts)"
assert_contains "$(cat "$work/mutator.args")" "--scan" "flags pass through"
assert_not_contains "$(cat "$work/mutator.args")" "--max-workers" "scan runs without max workers, which mutator rejects"

echo "== unavailable =="
out="$(cd "$proj" && PATH=/usr/bin:/bin XDG_DATA_HOME="$work/empty" bash "$TOOL" dryer src)"
assert_exit0 $? "missing tool exits 0"
assert_contains "$out" "dryer: unavailable (not installed; run ub-tools.sh install)" "missing tool says unavailable"
out="$(cd "$proj" && PASADENA_DRYER="$work/nope" bash "$TOOL" dryer src)"
assert_contains "$out" "dryer: unavailable (PASADENA_DRYER is not executable)" "bad override says unavailable"

lib="$work/data/pasadena/ub-tools/lib/dryer"
mkdir -p "$lib"
printf 'import sys\nprint("LIB dryer", *sys.argv[1:])\n' >"$lib/__main__.py"
touch "$lib/__init__.py"
out="$(cd "$proj" && PATH=/usr/bin:/bin XDG_DATA_HOME="$work/data" bash "$TOOL" dryer src)"
assert_contains "$out" "LIB dryer" "installed copy runs through python3 -m"

mkdir -p "$work/oldpy"
printf '#!/usr/bin/env bash\nexit 1\n' >"$work/oldpy/python3"
chmod +x "$work/oldpy/python3"
out="$(cd "$proj" && PATH="$work/oldpy:/usr/bin:/bin" XDG_DATA_HOME="$work/data" bash "$TOOL" dryer src)"
assert_contains "$out" "dryer: unavailable (python3 >= 3.11 not found)" "old python says unavailable"

echo "== install =="
inst="$work/instbin"
mkdir -p "$inst"
printf '#!/usr/bin/env bash\necho "$*" >>"%s/git.log"\n' "$work" >"$inst/git"
printf '#!/usr/bin/env bash\necho "$*" >>"%s/py.log"\n' "$work" >"$inst/python3"
chmod +x "$inst/git" "$inst/python3"
out="$(PATH="$inst:/usr/bin:/bin" XDG_DATA_HOME="$work/inst" bash "$TOOL" install)"
assert_exit0 $? "install exits 0"
gitlog="$(cat "$work/git.log")"
assert_contains "$gitlog" "https://github.com/unclebob/dryer.git 66ff6d21a42c04afcad89c78a80066176d1294b0" "dryer fetched at its pinned SHA"
assert_contains "$gitlog" "https://github.com/unclebob/crapper.git c757ec79a6c15dc815238bbd9c2f4601eb54d3cc" "crapper fetched at its pinned SHA"
assert_contains "$gitlog" "https://github.com/unclebob/mutator.git 830ec7e9c39664d753f8699015bc796df67727b9" "mutator fetched at its pinned SHA"
assert_contains "$gitlog" "checkout -q FETCH_HEAD" "pinned commit checked out"
assert_contains "$(cat "$work/py.log")" "-m pip install --quiet --upgrade --target $work/inst/pasadena/ub-tools/lib" "pip installs into lib without a venv"
assert_contains "$out" "installed: dryer crapper mutator" "install reports success"

badgit="$work/badgit"
mkdir -p "$badgit"
printf '#!/usr/bin/env bash\nfor a in "$@"; do [ "$a" = fetch ] && exit 1; done\necho "$*" >>"%s/badgit.log"\n' "$work" >"$badgit/git"
cp "$inst/python3" "$badgit/python3"
chmod +x "$badgit/git" "$badgit/python3"
out="$(PATH="$badgit:/usr/bin:/bin" XDG_DATA_HOME="$work/inst-fetch" bash "$TOOL" install)"
assert_exit0 $? "install exits 0 when fetch fails"
assert_contains "$out" "install: failed to fetch dryer@66ff6d21a42c04afcad89c78a80066176d1294b0" "fetch failure reported"

badpip="$work/badpip"
mkdir -p "$badpip"
cp "$inst/git" "$badpip/git"
printf '#!/usr/bin/env bash\n[ "$1" = -m ] && exit 1\nexit 0\n' >"$badpip/python3"
chmod +x "$badpip/git" "$badpip/python3"
out="$(PATH="$badpip:/usr/bin:/bin" XDG_DATA_HOME="$work/inst-pip" bash "$TOOL" install)"
assert_exit0 $? "install exits 0 when pip fails"
assert_contains "$out" "install: pip failed" "pip failure reported"

echo "== usage =="
out="$(bash "$TOOL" bogus)"
assert_exit0 $? "unknown subcommand exits 0"
assert_contains "$out" "usage: ub-tools.sh" "unknown subcommand prints usage"

echo "== available =="
out="$(PASADENA_DRYER="$fakebin/fake-dryer" bash "$TOOL" available dryer)"
assert_exit $? 0 "available dryer exits 0 with an executable override"
assert_contains "$out" "dryer: $fakebin/fake-dryer" "available dryer prints the command"
out="$(PASADENA_CRAPPER=/nonexistent bash "$TOOL" available crapper)"
assert_exit $? 1 "available crapper exits 1 with a bad override"
assert_contains "$out" "crapper: unavailable (PASADENA_CRAPPER is not executable)" "available crapper says why"
mkdir -p "$work/empty-data"
out="$(PATH=/usr/bin:/bin XDG_DATA_HOME="$work/empty-data" bash "$TOOL" available mutator)"
assert_exit $? 1 "available mutator exits 1 when not installed"
assert_contains "$out" "mutator: unavailable (not installed; run ub-tools.sh install)" "available mutator says not installed"
out="$(bash "$TOOL" available foo)"
assert_exit $? 2 "available with an unknown tool exits 2"
assert_contains "$out" "usage: ub-tools.sh" "available with an unknown tool prints usage"

rm -rf "$work"

echo
if [ "$fails" -gt 0 ]; then
  echo "FAILED: $fails"
  exit 1
fi
echo "All checks passed."
