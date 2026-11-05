echo "== lib =="
(
  fails=0
  BENCH_ROOT="$ROOT/bench"
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

  put_oracle_tests "$ORACLE" t/one.test.sh,t/two.test.sh "$tmp/tr" >/dev/null 2>&1
  mkdir -p "$tmp/o"
  rc=0
  run_oracle t/one.test.sh,t/two.test.sh "$tmp/tr" "$tmp/o" >/dev/null 2>&1 || rc=$?
  assert_eq "$rc" 0 "run_oracle returns 0"
  assert_eq "$(wc -l <"$tmp/o/oracle.exit" 2>/dev/null | tr -d ' ')" 2 "oracle.exit has two lines"
  assert_eq "$(awk -F'\t' 'NF == 2 && $2 != 0' "$tmp/o/oracle.exit" 2>/dev/null | wc -l | tr -d ' ')" 2 "both oracle tests fail on the base tree"
  assert_eq "$([ -f "$tmp/o/oracle-1.log" ] && [ -f "$tmp/o/oracle-2.log" ] && echo yes)" yes "run_oracle writes oracle-1.log and oracle-2.log"

  exit "$fails"
)
fails=$((fails + $?))
