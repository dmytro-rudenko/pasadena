# ub-mode і quality gates — implementation plan

**Goal:** `hooks/ub-tools.sh` запускає dryer, crapper, mutator; `leonard` робить dryer №1, `wolowitz` Finish запускає Make it Right gate перед reviews; принципи ub-mode живуть у `sheldon`, `leonard`, `amy`, `wolowitz`, `leslie`; версія 0.24.0.
**Spec:** docs/sdd/specs/2026-11-13-ub-mode-quality-gates.md
**Verification:** `bash hooks/ub-tools.test.sh && bash skills/skills.test.sh`, обидва закінчуються рядком `All checks passed.`

dryer №1 для цього плану: репозиторій містить лише bash і markdown, dryer їх не підтримує, а інструменти ще не встановлені — пропущено.

## Global constraints
- Жодних коментарів у коді, крім обмежень, яких код не показує (`~/.claude/CLAUDE.md`).
- Пороги: dryer `--threshold 0.8`, crapper `--threshold 10`, mutator `--max-workers 3`, межа сайтів mutator 50.
- SHA: dryer `66ff6d21a42c04afcad89c78a80066176d1294b0`, crapper `c757ec79a6c15dc815238bbd9c2f4601eb54d3cc`, mutator `830ec7e9c39664d753f8699015bc796df67727b9`.
- Каталог встановлення: `${XDG_DATA_HOME:-$HOME/.local/share}/pasadena/ub-tools` (`src/<tool>`, `lib/`).
- `ub-tools.sh` завжди `exit 0`; кожен запуск інструмента закінчується рядком `<tool> exit: <code>`; для dryer після нього може йти `unchecked: N JS files (dryer supports TypeScript only)`.
- Скіли посилаються на скрипт як «`ub-tools.sh` beside `journal.sh`».
- Кожен `skills/*/SKILL.md` менший за 20 000 байт.
- Текст скілів англійською, як решта скілів.

## Review Focus
- Відносний шлях передано, коли `--root` dryer — тимчасова тека: dryer резолвить відносні шляхи від `--root`, тож шлях має стати абсолютним, інакше dryer мовчки нічого не знайде.
- Аргумент-прапорець зі значенням (`--lines 3,4`): значення не існує як файл і передається як є, не перетворюючись на шлях.
- `set -u` і порожній масив на bash 3.2 (macOS): `${arr[@]+"${arr[@]}"}`.
- `target/` у `.gitignore` з кінцевою косою рискою, а тека ще не існує: перевірка ігнорування не має давати хибне попередження.
- crapper/mutator, запущені з підтеки: `--root` — корінь git, а не `$PWD`.

## Waves
| Wave | Tasks | Why together |
|---|---|---|
| 0 | 0 | alone — acceptance tests, red until the last wave |
| 1 | 1, 2, 3, 4, 5, 6, 7, 8 | disjoint: `hooks/ub-tools.sh`, `skills/wolowitz/{SKILL.md,references/*}`, `skills/leonard`, `skills/amy`, `skills/sheldon`, `skills/leslie`, `skills/wolowitz/implementer-prompt*.md`, docs+manifests |

Нічого не довелося серіалізувати: кожна задача пише свій набір файлів, а інтерфейс `ub-tools.sh` дано повністю в тексті кожної задачі.

---

### Task 0: acceptance tests

**Writes:** `hooks/ub-tools.test.sh`, `skills/skills.test.sh`
**Executor:** claude
**Covers:**
- «TS: два дублікати в `.ts` дають `DUPLICATE score=…` ≥ 0.8» — через фальшивий dryer: перевіряється, що dryer отримує `--threshold 0.8`, абсолютні шляхи і тимчасовий `--root`.
- «JS: `.js/.mjs/.cjs/.jsx` дають `unchecked: 4 JS files (dryer supports TypeScript only)`»
- «Пропуски: `.d.ts`, тести, `node_modules` не рахуються»
- «Деградація: без інструмента вивід `<tool>: unavailable (…)`, exit 0»
- «Gitignore: без `.metrics` в `.gitignore` є `warning:`»
- «Test-command: хвіст після `--` потрапляє в `--test-command`»
- «`bash skills/skills.test.sh` зелений, зокрема 20 000-байтний ліміт»
- «`git grep -n "Remove duplication" skills/amy/SKILL.md` порожній»
- «`.claude-plugin/plugin.json` має `"version": "0.24.0"`»

- [ ] **Step 1: write the acceptance tests**

`hooks/ub-tools.test.sh` (новий, `chmod +x` не потрібен, запускається через `bash`):

```bash
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

work="$(cd "$(mktemp -d)" && pwd -P)"
fakebin="$work/bin"
mkdir -p "$fakebin"
for name in dryer crapper mutator; do
  cat >"$fakebin/fake-$name" <<EOF
#!/usr/bin/env bash
printf '%s\n' "\$@" >"$work/$name.args"
echo "FAKE $name ran"
exit \${FAKE_EXIT:-0}
EOF
  chmod +x "$fakebin/fake-$name"
done

proj="$work/proj"
mkdir -p "$proj/src" "$proj/node_modules/pkg" "$proj/dist" "$proj/test"
git -C "$proj" init -q
for f in a.js b.mjs c.cjs d.jsx e.ts f.d.ts g.test.js; do echo x >"$proj/src/$f"; done
echo x >"$proj/node_modules/pkg/i.js"
echo x >"$proj/dist/j.js"
echo x >"$proj/test/k.js"

echo "== dryer =="
out="$(cd "$proj" && PASADENA_DRYER="$fakebin/fake-dryer" bash "$TOOL" dryer src)"
assert_exit0 $? "dryer exits 0"
args="$(cat "$work/dryer.args")"
assert_contains "$out" "FAKE dryer ran" "dryer output passes through"
assert_contains "$args" $'--threshold\n0.8' "dryer threshold is 0.8"
assert_contains "$args" "$proj/src" "relative path made absolute"
scratch="$(sed -n '/^--root$/{n;p;}' "$work/dryer.args")"
assert_not_contains "$scratch" "$proj" "dryer root is not the project"
[ -n "$scratch" ] && [ ! -e "$scratch" ] && echo "  ok  — dryer scratch root removed" ||
  { echo "  FAIL — dryer scratch root removed"; fails=$((fails + 1)); }
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

echo "== crapper =="
out="$(cd "$proj/src" && FAKE_EXIT=2 PASADENA_CRAPPER="$fakebin/fake-crapper" bash "$TOOL" crapper e.ts -- npm test)"
assert_exit0 $? "crapper exits 0 when the tool exits 2"
args="$(cat "$work/crapper.args")"
assert_contains "$args" $'--root\n'"$proj" "crapper root is the git toplevel"
assert_contains "$args" $'--threshold\n10' "crapper threshold is 10"
assert_contains "$args" $'--coverage-command\nnpm test' "tail after -- is the coverage command"
assert_contains "$args" "$proj/src/e.ts" "crapper path made absolute"
assert_contains "$out" "crapper exit: 2" "crapper exit code reported"
assert_contains "$out" "warning: .metrics is not gitignored; do not commit it" "unignored .metrics warned"

printf '.metrics/\ntarget/\ncoverage/\n' >"$proj/.gitignore"
out="$(cd "$proj" && PASADENA_CRAPPER="$fakebin/fake-crapper" bash "$TOOL" crapper src)"
assert_not_contains "$out" "warning:" "ignored folders, no warning"
assert_not_contains "$(cat "$work/crapper.args")" "--coverage-command" "no tail, no coverage command"

echo "== mutator =="
out="$(cd "$proj" && FAKE_EXIT=3 PASADENA_MUTATOR="$fakebin/fake-mutator" bash "$TOOL" mutator src/e.ts --lines 3,4 -- npm test)"
assert_exit0 $? "mutator exits 0 when the tool exits 3"
args="$(cat "$work/mutator.args")"
assert_contains "$args" $'--max-workers\n3' "mutator max workers 3"
assert_contains "$args" $'--test-command\nnpm test' "tail after -- is the test command"
assert_contains "$args" $'--lines\n3,4' "flag value passes through unchanged"
assert_contains "$out" "mutator exit: 3" "mutator exit code reported"
out="$(cd "$proj" && PASADENA_MUTATOR="$fakebin/fake-mutator" bash "$TOOL" mutator --scan src/e.ts)"
assert_contains "$(cat "$work/mutator.args")" "--scan" "flags pass through"

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

echo "== usage =="
out="$(bash "$TOOL" bogus)"
assert_exit0 $? "unknown subcommand exits 0"
assert_contains "$out" "usage: ub-tools.sh" "unknown subcommand prints usage"

rm -rf "$work"

echo
if [ "$fails" -gt 0 ]; then
  echo "FAILED: $fails"
  exit 1
fi
echo "All checks passed."
```

`skills/skills.test.sh`: вставити цей блок безпосередньо перед рядком `echo "Manifest versions"`:

```bash
echo "ub-mode quality gates"
before=$fails
require leonard 'ub-tools.sh dryer'
require leonard '**Foundational thinking.**'
require leonard '**Verifiable units.**'
require leonard '**Build the lever.**'
require wolowitz 'references/make-it-right.md'
require wolowitz 'references/finish.md'
require wolowitz 'how it was proved'
require_ref make-it-right.md 'ub-tools.sh crapper'
require_ref make-it-right.md 'ub-tools.sh dryer'
require_ref make-it-right.md 'ub-tools.sh mutator'
require_ref make-it-right.md 'refactor(<scope>): crapper and dryer findings'
require_ref make-it-right.md 'test(<scope>): mutator survivors'
require_ref make-it-right.md 'ub-tools.sh install'
require_ref make-it-right.md '--mutation-warning'
require_ref finish.md 'reviewer-prompt.md'
require amy 'ub-tools.sh dryer'
require amy 'pin, change, prove'
require amy '**Behaviour, not implementation.**'
require amy '**An honest test or none.**'
! grep -qF 'Remove duplication' "$SKILLS/amy/SKILL.md" || fail "amy: still says Remove duplication"
require sheldon '**Attack the premise.**'
require sheldon '**Model the domain.**'
require sheldon '**Subtract before you add.**'
require leslie '**Attack the premise.**'
require leslie 'A guard that only hides'
for prompt in implementer-prompt.md implementer-prompt-codex.md; do
  grep -qF 'Subtract before you add' "$SKILLS/wolowitz/$prompt" || fail "$prompt: missing Subtract before you add"
done
grep -qF 'unclebob/ub-mode' "$ROOT/THIRD_PARTY_NOTICES.md" || fail "ub-mode: not credited"
grep -qF 'unclebob/dryer' "$ROOT/THIRD_PARTY_NOTICES.md" || fail "dryer: not credited"
for readme in README.md README.uk.md; do
  grep -qF 'ub-tools.sh install' "$ROOT/$readme" || fail "$readme: no ub-tools.sh install"
  grep -qF 'PASADENA_DRYER' "$ROOT/$readme" || fail "$readme: no PASADENA_DRYER"
  grep -qF 'bash hooks/ub-tools.test.sh' "$ROOT/$readme" || fail "$readme: no ub-tools check"
done
grep -qF '"version": "0.24.0"' "$ROOT/.claude-plugin/plugin.json" || fail "plugin.json: not 0.24.0"
[ "$fails" -eq "$before" ] && ok "ub-mode quality gates checked"
```

- [ ] **Step 2: run them, watch them fail** — `bash hooks/ub-tools.test.sh; bash skills/skills.test.sh`, expect `FAILED:` у обох: скрипта і правил ще немає.

---

### Task 1: `hooks/ub-tools.sh`

**Writes:** `hooks/ub-tools.sh`
**Reads:** `hooks/reuse.sh` (стиль)
**Depends on:** Task 0
**Executor:** claude
**Complexity:** complex
**Satisfies:** усі перевірки `hooks/ub-tools.test.sh`
**Interfaces:**
- Produces: `ub-tools.sh install | dryer|crapper|mutator [args...] [-- <test command>]`. Аргумент, що існує як файл чи тека, стає абсолютним шляхом; інші йдуть як є. Вивід інструмента без змін, потім `<tool> exit: <code>`; для dryer ще `unchecked: N JS files (dryer supports TypeScript only)`, коли N > 0. Недоступність: `<tool>: unavailable (<reason>)`. Завжди `exit 0`.

- [ ] **Step 1: implement** — створити `hooks/ub-tools.sh`:

```bash
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
  local seen=0 arg
  for arg in "$@"; do
    if [ "$seen" = 1 ]; then
      CMD="${CMD:+$CMD }$arg"
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
  find "${PATHS[@]}" \
    \( -type d \( -name node_modules -o -name dist -o -name build -o -name out \
    -o -name coverage -o -name target -o -name .git -o -name test -o -name tests \
    -o -name spec -o -name specs -o -name __tests__ \) -prune \) -o \
    -type f \( -name '*.js' -o -name '*.jsx' -o -name '*.mjs' -o -name '*.cjs' \) \
    ! -name '*.test.*' ! -name '*.spec.*' -print 2>/dev/null | wc -l | tr -d ' '
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
  local root extra=()
  root="$(project_root)"
  warn_ignored "$root"
  [ -n "$CMD" ] && extra=(--coverage-command "$CMD")
  "${RUN[@]}" --root "$root" --threshold 10 ${extra[@]+"${extra[@]}"} ${TOOL_ARGS[@]+"${TOOL_ARGS[@]}"}
  echo "crapper exit: $?"
}

cmd_mutator() {
  resolve mutator || return 0
  local root extra=()
  root="$(project_root)"
  warn_ignored "$root"
  [ -n "$CMD" ] && extra=(--test-command "$CMD")
  "${RUN[@]}" --root "$root" --max-workers 3 ${extra[@]+"${extra[@]}"} ${TOOL_ARGS[@]+"${TOOL_ARGS[@]}"}
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
  *) echo "usage: ub-tools.sh install | dryer|crapper|mutator [path...] [-- <test command>]" ;;
esac
exit 0
```

Примітка для `js_count`: `PATHS` у dryer завжди непорожній (дефолт `$PWD`).

- [ ] **Step 2: run it, watch it pass** — `bash hooks/ub-tools.test.sh`, expect `All checks passed.`

---

### Task 2: Make it Right gate у `wolowitz` Finish

**Writes:** `skills/wolowitz/SKILL.md`, `skills/wolowitz/references/make-it-right.md`, `skills/wolowitz/references/finish.md`
**Depends on:** Task 0
**Executor:** claude
**Complexity:** routine
**Satisfies:** `skills.test.sh` рядки `require wolowitz 'references/make-it-right.md'`, `'references/finish.md'`, `'how it was proved'`, усі `require_ref make-it-right.md …`, `require_ref finish.md 'reviewer-prompt.md'`, ліміт 20 000 байт.
**Interfaces:**
- Consumes: `ub-tools.sh` (Task 1) — інтерфейс у Global constraints і Task 1 Interfaces.

- [ ] **Step 1: implement**

1. Створити `skills/wolowitz/references/finish.md`: заголовок `# Whole-branch review dispatch`, порожній рядок, потім **дослівно** абзац, що зараз у `skills/wolowitz/SKILL.md` починається з `   Fill \`reviewer-prompt.md\` for the whole branch — the merge-base as` і закінчується `step 4 of the wave loop, in the final PR comment.` (рядки 352–366), без початкового відступу в три пробіли.
2. У `skills/wolowitz/SKILL.md` замінити цей абзац на:
   ```
      Fill both reviews as `references/finish.md` describes.
   ```
3. У `skills/wolowitz/SKILL.md`, у кроці 1 Finish, рядок `   **Reviews at once.** In one message, dispatch the **whole-branch` замінити на два:
   ```
      **Make it right** first, per `references/make-it-right.md`.
      **Reviews at once.** In one message, dispatch the **whole-branch
   ```
4. У кроці 6 рядок `Keep the message description to **30–40 words** — what changed and why, and
nothing else. The diff carries the detail.` замінити на
   ```
   Keep the message description to **30–40 words** — why, what changed, and
   how it was proved. The diff carries the detail.
   ```
5. Створити `skills/wolowitz/references/make-it-right.md`:

```markdown
# Make it right

Runs in **Finish**, after the last wave closes and before the whole-branch,
Codex and security reviews. `ub-tools.sh` sits beside `journal.sh`. It always
exits 0 and ends each run with a `<tool> exit: <code>` line.

**Files.** `git diff --name-only $(git merge-base origin/<trunk> HEAD)..HEAD`,
keeping files that still exist and are not tests. The plan's
**Verification** command is the test command.

**Not installed.** When a run prints `unavailable (not installed`, ask the
user once through `AskUserQuestion` whether to run `ub-tools.sh install`: it
downloads unclebob's dryer, crapper and mutator at pinned commits and runs
them on this machine. On no, or on any other `unavailable`, skip that step and
put `<tool>: skipped (<reason>)` in the final PR comment.

1. **Structure.** Run `ub-tools.sh crapper <files> -- <test command>` and
   `ub-tools.sh dryer <files>`. Findings: every function with CRAP 10 or
   above, every pair at 0.8 or above. A `warning: … is not gitignored` line
   means that folder stays out of every commit. An `unchecked: N JS files`
   line goes in the final PR comment.
   The findings go to one fix wave per `references/two-dispatch.md`: one test
   writer first pins the current behaviour of every function the findings
   name; then one implementer splits the high-CRAP functions and merges the
   duplicates under Gate green. Its `**Writes:**` is the files the tools
   named plus their test files. Commit
   `refactor(<scope>): crapper and dryer findings`. No findings, no wave.
2. **Tests.** Run `ub-tools.sh mutator --scan <files>` and leave out every
   file with more than 50 sites — mutator's `--mutation-warning` default —
   naming it in the final PR comment. Run
   `ub-tools.sh mutator <the rest> -- <test command>`. `mutator exit: 3` means
   survivors: one test writer kills them and covers the uncovered lines, then
   one implementer deletes the code no test can reach. Commit
   `test(<scope>): mutator survivors`. `mutator exit: 2` means the baseline
   tests failed: invoke `pasadena:leslie` before anything else.
3. One round each, no loop. What remains goes in the final PR comment with its
   `file:line`. Then start the reviews.
```

- [ ] **Step 2: run it, watch it pass** — `bash skills/skills.test.sh`, у виводі `ok  — upstream adoption checked` (ліміт) і жодного `FAIL` з `wolowitz` чи `make-it-right.md`/`finish.md`; `wc -c skills/wolowitz/SKILL.md` < 20000.

---

### Task 3: `leonard` — dryer №1 і порядок задач

**Writes:** `skills/leonard/SKILL.md`
**Depends on:** Task 0
**Executor:** claude
**Complexity:** routine
**Satisfies:** `require leonard 'ub-tools.sh dryer'`, `'**Foundational thinking.**'`, `'**Verifiable units.**'`, `'**Build the lever.**'`

- [ ] **Step 1: implement** — у `## 1. Use plan mode`, після пункту `- **Enumerate every file** …` (закінчується `waves safe.`), додати:

```markdown
- **Reuse what is already duplicated.** Run `ub-tools.sh dryer <paths>` —
  the script sits beside `journal.sh` — on every file and folder the spec
  says the work touches. Each pair it reports at 0.8 or above becomes an
  instruction in the task that touches it: reuse or merge `<file:lines>` and
  `<file:lines>`, do not copy them a third time. When it prints
  `unavailable (not installed`, ask the user once through `AskUserQuestion`
  whether to run `ub-tools.sh install` (it downloads and runs unclebob's
  tools). Any other `unavailable`, or `unchecked: N JS files`, goes in the
  plan header as one line, and planning goes on.
- **Foundational thinking.** Get the data shape right first: the task that
  fixes a type, schema or data structure comes before the logic that uses it,
  and whatever helps every later task goes in the earliest wave.
- **Verifiable units.** Each task ends in a state one command can check; a
  task that cannot be checked on its own is split or merged.
- **Build the lever.** When one change repeats across many places and is not
  obvious at a glance, plan one task that does a single unit by hand and one
  that builds the tool doing the rest, matched against that unit.
```

- [ ] **Step 2: run it, watch it pass** — `bash skills/skills.test.sh | grep -E 'FAIL.*leonard'`, expect порожньо.

---

### Task 4: `amy` — REFACTOR і цінність тесту

**Writes:** `skills/amy/SKILL.md`
**Depends on:** Task 0
**Executor:** claude
**Complexity:** routine
**Satisfies:** `require amy 'ub-tools.sh dryer'`, `'pin, change, prove'`, `'**Behaviour, not implementation.**'`, `'**An honest test or none.**'`, відсутність `Remove duplication`

- [ ] **Step 1: implement**

1. Тіло `### REFACTOR` (зараз `Only once green. Remove duplication, improve names, extract helpers. Keep the
tests green and keep behaviour unchanged. Then the next failing test.`) замінити на:

```markdown
Only once green. Improve names, extract helpers, and keep each decision in one
place. Duplication is measured, not eyeballed: `ub-tools.sh dryer <files you
touched>` (beside `journal.sh`) lists the pairs at 0.8 or above; merge them.
Refactor as pin, change, prove: a test pins what the code does, the structure
changes, the same tests prove nothing else did. Then the next failing test.
```

2. Безпосередньо перед `## Decision rules` додати:

```markdown
## What a test is worth

- **Behaviour, not implementation.** A test calls the code the way its user
  does and checks what that user would see. A test that would still pass if
  every function returned nothing is thrown out.
- **An honest test or none.** When an honest test is impractical, say so out
  loud, like the exceptions in `## When it applies`, and write none rather
  than one that checks nothing.
- **The smallest edit.** Ship the smallest change that solves the problem.
```

- [ ] **Step 2: run it, watch it pass** — `bash skills/skills.test.sh | grep -E 'FAIL.*amy'`, expect порожньо.

---

### Task 5: `sheldon` — принципи дизайну

**Writes:** `skills/sheldon/SKILL.md`
**Depends on:** Task 0
**Executor:** claude
**Complexity:** routine
**Satisfies:** `require sheldon '**Attack the premise.**'`, `'**Model the domain.**'`, `'**Subtract before you add.**'`; ліміт 20 000 байт

- [ ] **Step 1: implement**

1. У `## Present the design`, після абзацу, що закінчується `and what it depends on.`, додати:

```markdown
Check the design against these before presenting it:

- **Attack the premise.** When two approaches that share one premise fail the
  same constraint, write that premise in one sentence and drop it before
  proposing a third.
- **Redesign from first principles.** A new requirement is not bolted onto the
  old design: ask what would have been built had it been there from the
  start, and deliver that in pieces.
- **Subtract before you add.** Name what the design removes before what it adds.
- **Model the domain.** The data structure makes illegal states impossible to
  write; the spec keeps a glossary when the work introduces domain terms.
  Clear, local code stays as it is.
- **Boundaries.** Outside data is checked and parsed once, where it enters;
  inside, the code trusts it, and business logic is a pure function.
- **Idempotent, unshared.** An operation run twice, or after a crash halfway,
  ends in the same state. Writers that do not need the same mutable thing each
  get their own; those that do get one writer, enforced by the structure.
```

2. У шаблоні специфікації рядок `How anyone can verify that it works.` (під `## 6. Verification`) замінити на `The end state, written so that a command or a person can check it.`

- [ ] **Step 2: run it, watch it pass** — `bash skills/skills.test.sh | grep -E 'FAIL.*sheldon'`, expect порожньо; `wc -c skills/sheldon/SKILL.md` < 20000.

---

### Task 6: `leslie` — корінь і передумова

**Writes:** `skills/leslie/SKILL.md`
**Depends on:** Task 0
**Executor:** claude
**Complexity:** routine
**Satisfies:** `require leslie '**Attack the premise.**'`, `'A guard that only hides'`

- [ ] **Step 1: implement**

1. У `## Phase 4 — Fix`, пункт 3: після `"while I am here" improvements.` дописати ` A guard that only hides the crash is not a fix.`
2. У `## The rule of three`, після наявного абзацу, додати:

```markdown
**Attack the premise.** When two fixes that share one premise fail the same
check, stop before a third: write that premise in one sentence, find which
parts of the code hold it, and remove it. Only then try another fix.
```

- [ ] **Step 2: run it, watch it pass** — `bash skills/skills.test.sh | grep -E 'FAIL.*leslie'`, expect порожньо.

---

### Task 7: implementer prompts

**Writes:** `skills/wolowitz/implementer-prompt.md`, `skills/wolowitz/implementer-prompt-codex.md`
**Depends on:** Task 0
**Executor:** claude
**Complexity:** routine
**Satisfies:** цикл `for prompt in implementer-prompt.md implementer-prompt-codex.md` у `skills.test.sh`

- [ ] **Step 1: implement**

1. `skills/wolowitz/implementer-prompt.md`, у `## Rules` після правила 9 додати:

```markdown
10. **Subtract before you add.** Take complexity out before adding any, keep
    each decision in one place, and ship the smallest edit that passes.
    Outside data is checked once, where it enters; inside, trust it.
```

2. `skills/wolowitz/implementer-prompt-codex.md`, у `## Rules` останнім пунктом, у тій самій нумерації чи маркуванні, що й попередні пункти цього розділу, додати той самий текст: `**Subtract before you add.** Take complexity out before adding any, keep each decision in one place, and ship the smallest edit that passes. Outside data is checked once, where it enters; inside, trust it.`

- [ ] **Step 2: run it, watch it pass** — `bash skills/skills.test.sh | grep -E 'FAIL.*implementer-prompt'`, expect порожньо.

---

### Task 8: документація, notices, версія

**Writes:** `README.md`, `README.uk.md`, `THIRD_PARTY_NOTICES.md`, `.claude-plugin/plugin.json`, `.claude-plugin/marketplace.json`
**Depends on:** Task 0
**Executor:** claude
**Complexity:** routine
**Satisfies:** `unclebob/ub-mode`, `unclebob/dryer` у notices; `ub-tools.sh install`, `PASADENA_DRYER`, `bash hooks/ub-tools.test.sh` в обох README; `"version": "0.24.0"`; наявна перевірка однакових версій маніфестів.

- [ ] **Step 1: implement**

1. `.claude-plugin/plugin.json` і `.claude-plugin/marketplace.json`: `"version": "0.23.1"` → `"version": "0.24.0"`.
2. `THIRD_PARTY_NOTICES.md`, у кінець:

```markdown
## unclebob/ub-mode

The principles in `skills/sheldon/SKILL.md` ("Check the design against these"),
`skills/leonard/SKILL.md` (Foundational thinking, Verifiable units, Build the
lever), `skills/amy/SKILL.md` (REFACTOR, "What a test is worth"),
`skills/leslie/SKILL.md` (Attack the premise), `skills/wolowitz/implementer-prompt.md`
and `skills/wolowitz/references/make-it-right.md` are rewritten from
`SKILL.md`.

Source: <https://github.com/unclebob/ub-mode>

Copyright (c) 2026 Robert C. Martin

MIT License

## unclebob/dryer, unclebob/crapper, unclebob/mutator

`hooks/ub-tools.sh install` downloads and runs these tools at pinned commits;
pasadena does not redistribute them.

Sources: <https://github.com/unclebob/dryer>, <https://github.com/unclebob/crapper>,
<https://github.com/unclebob/mutator>

Copyright (C) 2026 by Robert C. Martin

BSD Zero Clause License
```

3. `README.md`, у `## Configuration`, після абзацу про `PASADENA_REUSE`, додати:

```markdown
Quality gates come from unclebob's [dryer](https://github.com/unclebob/dryer), [crapper](https://github.com/unclebob/crapper) and [mutator](https://github.com/unclebob/mutator). `leonard` runs dryer on the files a spec touches, so the plan reuses code that is already duplicated; `wolowitz` runs crapper (CRAP under 10), dryer (similarity under 0.8) and mutator on the branch before the whole-branch review. `bash hooks/ub-tools.sh install` fetches them at pinned commits into `~/.local/share/pasadena/ub-tools` with `pip install --target` (Python 3.11+, no venv); the skills ask before running it. `PASADENA_DRYER`, `PASADENA_CRAPPER` and `PASADENA_MUTATOR` point at your own copies. dryer reads TypeScript but not plain JavaScript, so `.js`, `.jsx`, `.mjs` and `.cjs` files are counted and reported as unchecked; crapper and mutator handle both. Without the tools the steps are skipped and the PR comment says so.
```

   У `## Checks` у блок команд після `bash hooks/codex.test.sh` додати рядок `bash hooks/ub-tools.test.sh`; в кінець абзацу після блоку додати речення: `The ub-tools checks run hooks/ub-tools.sh against fake tools and cover the thresholds, absolute paths, the scratch root, the JS count, the gitignore warning, the test command, the unavailable cases and the pinned install.` (з `hooks/ub-tools.sh` в бектиках).

4. `README.uk.md`: той самий абзац українською в розділі, що відповідає `## Configuration` (знайти за `PASADENA_REUSE`), з тими самими ідентифікаторами `bash hooks/ub-tools.sh install`, `PASADENA_DRYER`, `PASADENA_CRAPPER`, `PASADENA_MUTATOR`; рядок `bash hooks/ub-tools.test.sh` у блок перевірок і речення українською про ub-tools checks.

- [ ] **Step 2: run it, watch it pass** — `bash skills/skills.test.sh`, expect `All checks passed.` після завершення хвилі 1 (разом з Tasks 2–7).
