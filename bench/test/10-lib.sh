echo "== lib =="
(
  fails=0
  BENCH_ROOT="$ROOT/bench"
  BENCH_CHECKS="$tmp/lib-checks.tsv"
  printf 'task\ttest\tcheck\tstatus\treason\n' >"$BENCH_CHECKS"
  source "$ROOT/bench/lib.sh"

  assert_eq "$(task_field t1 oracle)" "$ORACLE" "task_field t1 oracle is the oracle commit"
  rc=0
  task_field nope base >/dev/null 2>&1 || rc=$?
  assert_eq "$rc" 2 "task_field on an unknown id returns 2"
  assert_eq "$(task_ids 0)" t1 "task_ids 0 lists t1"
  assert_eq "$(task_ids 1)" t2 "task_ids 1 lists t2"
  assert_eq "$(config_names | wc -l | tr -d ' ')" 5 "config_names lists 5 configs"
  assert_eq "$(config_field plugin-noreuse env)" "PASADENA_CODEX=0 PASADENA_REUSE=0" "config_field plugin-noreuse env"

  rev="$(plugin_rev)"
  clean=no
  [[ "$rev" =~ ^[0-9a-f]{7,}$ ]] && clean=yes
  assert_eq "$clean" yes "plugin_rev on a clean plugin is a short hash without -dirty (got $rev)"
  touch "$tmp/plugin/x"
  rev="$(plugin_rev)"
  dirty=no
  [[ "$rev" == *-dirty ]] && dirty=yes
  assert_eq "$dirty" yes "plugin_rev on a dirty plugin ends with -dirty (got $rev)"
  rm -f "$tmp/plugin/x"

  make_tree "$BASE" "$tmp/tr" >/dev/null 2>&1
  assert_eq "$(git -C "$tmp/tr" rev-list --count HEAD 2>/dev/null)" 1 "make_tree makes one commit"
  assert_eq "$(git -C "$tmp/tr" log -1 --format='%an <%ae>' 2>/dev/null)" "bench <bench@localhost>" "make_tree commits as bench"
  assert_eq "$([ -f "$tmp/tr/src/a.sh" ] && echo yes)" yes "make_tree tree has src/a.sh"
  assert_eq "$([ -e "$tmp/tr/t/one.test.sh" ] && echo yes || echo no)" no "make_tree tree has no t/one.test.sh"
  assert_eq "$(cat "$tmp/tr/spec.md" 2>/dev/null)" "$(git -C "$repo" show "$BASE:spec.md")" "make_tree without an oracle keeps the base spec.md"

  make_tree "$BASE" "$tmp/mt" "$ORACLE" spec.md >/dev/null 2>&1
  assert_eq "$(cat "$tmp/mt/spec.md" 2>/dev/null)" "$(git -C "$repo" show "$ORACLE:spec.md")" "make_tree with an oracle takes spec.md from the oracle"
  assert_eq "$(git -C "$tmp/mt" rev-list --count HEAD 2>/dev/null)" 1 "make_tree with an oracle makes one commit"
  assert_eq "$(git -C "$tmp/mt" status --porcelain 2>/dev/null)" "" "make_tree with an oracle commits the oracle spec.md"

  put_oracle_tests "$ORACLE" t/one.test.sh,t/two.test.sh "$tmp/tr" >/dev/null 2>&1
  mkdir -p "$tmp/o"
  rc=0
  run_oracle t/one.test.sh,t/two.test.sh "$tmp/tr" "$tmp/o" >/dev/null 2>&1 || rc=$?
  assert_eq "$rc" 0 "run_oracle returns 0"
  assert_eq "$(wc -l <"$tmp/o/oracle.exit" 2>/dev/null | tr -d ' ')" 2 "oracle.exit has two lines"
  assert_eq "$(awk -F'\t' 'NF == 2 && $2 != 0' "$tmp/o/oracle.exit" 2>/dev/null | wc -l | tr -d ' ')" 2 "both oracle tests fail on the base tree"
  assert_eq "$([ -f "$tmp/o/oracle-1.log" ] && [ -f "$tmp/o/oracle-2.log" ] && echo yes)" yes "run_oracle writes oracle-1.log and oracle-2.log"

  mkdir -p "$tmp/stdin-tree/t" "$tmp/stdin-out"
  echo 'cat >/dev/null' >"$tmp/stdin-tree/t/reads.test.sh"
  sleep 7 | BENCH_ORACLE_TIMEOUT=5 run_oracle t/reads.test.sh "$tmp/stdin-tree" "$tmp/stdin-out" >/dev/null 2>&1
  assert_eq "$(cut -f2 "$tmp/stdin-out/oracle.exit")" 0 "run_oracle gives tests a closed stdin"

  r1="$(bench_rev 2>/dev/null)"
  hex=no
  [[ "$r1" =~ ^[0-9a-f]{12}$ ]] && hex=yes
  assert_eq "$hex" yes "bench_rev prints 12 hex characters (got $r1)"
  printf 't1\tt/one.test.sh\tok — x\ttarget\t\n' >>"$BENCH_CHECKS"
  r2="$(bench_rev 2>/dev/null)"
  changed=no
  [ -n "$r1" ] && [ "$r1" != "$r2" ] && changed=yes
  assert_eq "$changed" yes "bench_rev changes after a line is added to checks.tsv ($r1 -> $r2)"

  assert_eq "$(awk -F'\t' '$1 == "model-routing" { print $4 }' "$ROOT/bench/tasks.tsv")" fbdd4ae "tasks.tsv model-routing oracle is fbdd4ae"
  assert_eq "$(awk -F'\t' '$1 == "reuse-first" { print $4 }' "$ROOT/bench/tasks.tsv")" 8c0f8f8 "tasks.tsv reuse-first oracle is 8c0f8f8"

  exit "$fails"
)
fails=$((fails + $?))
