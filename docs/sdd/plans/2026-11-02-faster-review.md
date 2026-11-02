# Швидше рев'ю у wolowitz — implementation plan

**Goal:** `wolowitz` рев'ює Wave 0 одразу, а хвилі 1…N — групами по три (рев'ю після хвилі k, коли `k mod 3 = 0` і k не остання) на `sonnet`/`high`. Whole-branch review лишається на `xhigh`, а `security-review` іде паралельно з ним і з Codex. Виправлення після групового рев'ю — окремі `fix(...)`-коміти на задачу. Процедура описана в новому `references/grouped-review.md`; README описують новий графік; версія `0.16.0`.
**Spec:** docs/sdd/specs/2026-11-02-faster-review.md
**Verification:** `bash skills/skills.test.sh && bash hooks/journal.test.sh && bash hooks/codex.test.sh && bash hooks/nudge.test.sh`, останній рядок `All checks passed.`

## Context

Рев'ю займає 20–35 хв на гілку. Рев'юер на `sonnet`/`xhigh` генерує 50–170 тис. токенів (~16 тис./хв), кожна хвиля чекає на своє рев'ю, а `security-review` стоїть у черзі за whole-branch review. Spec і draft PR #24 уже є.

## Global constraints

- Skills, промпти й references пишуться англійською, `README.uk.md` — українською. Текст із задач вставляти дослівно.
- Жодних коментарів.
- Цитати «старого» тексту в задачах можуть бути перенесені у файлі інакше (переноси рядків на ~80 символів) — шукати за змістом, нові абзаци переносити так само на ~80 символів.
- `skills/wolowitz/SKILL.md` має лишитися меншим за 20 000 байтів (зараз 17 802).
- Не змінювати: `hooks/`, `skills/leonard/`, `skills/wolowitz/implementer-prompt*.md`, `skills/wolowitz/test-writer-prompt.md`, історичні spec у `docs/sdd/specs/` (крім цього).
- Збірка йде кешованою `0.15.0`. Ручна перевірка з §6 spec (наступна гілка з N ≥ 4) — за користувачем після встановлення `0.16.0`.

## Review Focus

- План із N = 3, N = 4 і N = 6 (хвилі після Wave 0): групове рев'ю має бути відповідно 0, 1 (після 3) і 1 (після 3, бо 6 остання). Текст кроку 4 має давати саме це.
- Wave 0: Task 0 ще не закомічений і пише нові файли. Без `git add -N` diff рев'юера порожній.
- Відновлення посеред групи після компакції: `GROUP_BASE` береться з `## Now`, а коли його там немає — з `git log`.
- Security-знахідка поза кодом, яка прийшла паралельно з whole-branch review: зупинка має статися до fix wave.
- Розмір `SKILL.md` після правок: < 20 000 байтів (перевіряє `skills.test.sh`).

## Waves

| Wave | Tasks | Why together |
|---|---|---|
| 0 | 0 | alone — acceptance tests, red until the last wave |
| 1 | 1, 2, 3 | disjoint: `skills/wolowitz/SKILL.md` / references + `reviewer-prompt.md` / README + маніфести |

Серіалізувати нічого не довелося. Task 1 посилається на `references/grouped-review.md`, який пише Task 2, лише за назвою, а назву зафіксовано тут.

### Task 0: acceptance tests

**Writes:** `skills/skills.test.sh`
**Executor:** claude
**Covers:** spec §6 п.1: обидва нові рядки **Models**; відсутність `| Wave reviewer and whole-branch review |`; `every third wave` і `references/grouped-review.md` у `SKILL.md`; файл `grouped-review.md` з `GROUP_BASE`; `0.16.0` в обох маніфестах; розмір `SKILL.md` < 20 000 (уже перевіряється в блоці `Upstream adoption`).

- [ ] **Step 1: write the acceptance tests.**
  1. У блоці `echo "Model routing"` видалити рядок
     ``require wolowitz '| Wave reviewer and whole-branch review | `sonnet` | `xhigh` |'``.
  2. У тому самому блоці замінити `'"version": "0.15.0"'` на `'"version": "0.16.0"'` і `"$manifest: not on 0.15.0"` на `"$manifest: not on 0.16.0"`.
  3. Безпосередньо перед рядком `echo "Upstream adoption"` вставити:

```bash
echo "Grouped review"
before=$fails
require wolowitz '| Wave 0 review and grouped wave review | `sonnet` | `high` |'
require wolowitz '| Whole-branch review | `sonnet` | `xhigh` |'
! grep -qF '| Wave reviewer and whole-branch review |' "$SKILLS/wolowitz/SKILL.md" || fail "wolowitz: one review row still covers waves and the whole branch"
require wolowitz 'one review for every third wave'
require wolowitz 'references/grouped-review.md'
require wolowitz 'while the reviews run'
require wolowitz 'fix(<scope>): whole-branch and security review findings'
require_ref grouped-review.md 'GROUP_BASE: <sha>'
require_ref grouped-review.md 'git add -N'
require_ref grouped-review.md 'fix(<scope>): review findings for task N'
for ref in two-dispatch.md codex-tasks.md; do
  require_ref "$ref" 'review when the schedule has one'
done
reviewer="$SKILLS/wolowitz/reviewer-prompt.md"
grep -qF 'Review waves `<a>`–`<b>`' "$reviewer" || fail "reviewer-prompt.md: does not review a range of waves"
grep -qF '**The diff:** `git diff <BASE>` —' "$reviewer" || fail "reviewer-prompt.md: the diff misses the working tree"
grep -qF 'reviews every third wave' "$ROOT/README.md" || fail "README.md: wolowitz row does not name the review schedule"
grep -qF 'кожну третю хвилю' "$ROOT/README.uk.md" || fail "README.uk.md: wolowitz row does not name the review schedule"
grep -qF '| Wave 0 and grouped wave reviews | `sonnet` | `high` |' "$ROOT/README.md" || fail "README.md: no grouped review row"
grep -qF '| Whole-branch review, `Explore` fallback | `sonnet` | `xhigh` |' "$ROOT/README.md" || fail "README.md: no whole-branch review row"
grep -qF '| Ревʼю Wave 0 і груп хвиль | `sonnet` | `high` |' "$ROOT/README.uk.md" || fail "README.uk.md: no grouped review row"
grep -qF '| Ревʼю всієї гілки, fallback `Explore` | `sonnet` | `xhigh` |' "$ROOT/README.uk.md" || fail "README.uk.md: no whole-branch review row"
[ "$fails" -eq "$before" ] && ok "grouped review checked"

```

- [ ] **Step 2: run them, watch them fail** — `bash skills/skills.test.sh`, expect `FAILED: 22`: 20 перевірок блоку `Grouped review` і 2 `not on 0.16.0`. Усі інші блоки `ok`.

### Task 1: графік рев'ю, fix loop і Finish у `SKILL.md`

**Writes:** `skills/wolowitz/SKILL.md`
**Reads:** `docs/sdd/specs/2026-11-02-faster-review.md`, `skills/skills.test.sh`
**Depends on:** Task 0
**Executor:** claude
**Complexity:** complex
**Satisfies:** `Grouped review`: два рядки Models, відсутність старого рядка, `one review for every third wave`, `references/grouped-review.md`, `while the reviews run`, `fix(<scope>): whole-branch and security review findings`; `Upstream adoption`: розмір < 20 000.
**Interfaces:**
- Consumes: `references/grouped-review.md` (Task 2) — лише назва файлу.
- Produces: назву розділу кроку 4 `### 4. Review schedule`, на яку посилається **Without subagents**.

- [ ] **Step 1: run the tests, watch the task's checks fail** — `bash skills/skills.test.sh`; серед FAIL є `wolowitz: missing "one review for every third wave"`.
- [ ] **Step 2: implement** — сім правок у `skills/wolowitz/SKILL.md`:
  1. **Models:** рядок ``| Wave reviewer and whole-branch review | `sonnet` | `xhigh` |`` замінити двома:
     ```
     | Wave 0 review and grouped wave review | `sonnet` | `high` |
     | Whole-branch review | `sonnet` | `xhigh` |
     ```
  2. **Without subagents:** речення ``The wave review in this mode is yours: read the `BASE..HEAD` diff against the
spec and the plan yourself, and say "no subagents" in the wave's PR comment.`` замінити на:
     ```
     The reviews in this mode are yours, on the schedule in step 4 of the wave
     loop: read the diff against the spec and the plan yourself, and say "no
     subagents" in the wave's PR comment.
     ```
  3. **Step 1, Record the base:** абзац ``Run `git rev-parse HEAD` and keep the result as `BASE`. The wave's review always
diffs against `BASE`, capturing every commit in the wave.`` замінити на:
     ```
     Run `git rev-parse HEAD` and keep the result as `BASE`. In waves 1, 4, 7… it
     is also the group's `GROUP_BASE`; see `references/grouped-review.md`.
     ```
  4. **Step 4:** заголовок `### 4. Review the wave` і перший абзац (від `One reviewer on` до `and quality.`) замінити на:
     ```
     ### 4. Review schedule

     Wave 0 is reviewed now, before its commit. Waves 1…N are reviewed in groups
     of three, one review for every third wave: after wave k when `k mod 3 = 0`
     and k is not the plan's last wave, over waves k−2…k, once step 6 has
     committed wave k. Every other wave skips steps 4–5 and goes from step 3 to
     step 6. The last group, of one to three waves, is covered by the
     whole-branch review in **Finish**, so with three waves or fewer after
     Wave 0 there is no grouped review.

     Before the first grouped review, read `references/grouped-review.md` in this
     skill's directory, and read it again after a compaction.

     One reviewer on `sonnet` at `effort: "high"` examines the diff with
     `reviewer-prompt.md`. Before it goes out, run `git add -N` on the new files
     in the reviewed tasks' `**Writes:**` sets and hand it `git diff <base>` —
     `BASE` for Wave 0, `GROUP_BASE` for a group — so uncommitted work is in the
     diff. A complete report contains both verdicts: spec compliance and quality.
     ```
     Абзаци `Codex does not review waves…`, `The controller's verification result…`, `Decide every \`Declined to judge\`…` лишити без змін.
  5. **Step 5:** між пунктом `- **Round 3:** …here is what was tried."` і абзацом `Findings still open after three rounds are parked.` вставити:
     ```
     After each round, run the verification, then send the reviewer the fix diff
     through `SendMessage` — `git diff HEAD` after `git add -N` on the fix's new
     files. Its new findings are the next round. A grouped review's fix loop
     follows `references/grouped-review.md`.
     ```
  6. **Step 6:** після речення `stays one-commit-per-task, which is what makes it reviewable.` дописати в той самий абзац: `Fixes from a grouped review land later as their own commits, per `references/grouped-review.md`.`
     **Step 8:** пункт `2. Update \`## Now\`: …with a file and a command.` доповнити реченням: `Inside a group, keep the line `GROUP_BASE: <sha>`.`
  7. **Finish:** у кроці 1 абзац від `**Whole-branch review** over` до `This is the single whole-branch fix wave.` замінити на:
     ```
        **Three reviews at once.** In one message, dispatch the **whole-branch
        review** over `git merge-base origin/<trunk> HEAD..HEAD` on `sonnet` at
        `effort: "xhigh"` in the background, and start the Codex review below.
        Then, while the reviews run, invoke the `security-review` skill with the
        Skill tool on the branch diff; when the skill is unavailable, say so once
        and note the skip in the PR comment.
     ```
     Абзац `When \`codex.sh available\` exits 0, write a prompt file…` (до `…in the final PR comment.`) лишити без змін. Весь крок `2. **Security review.** …note the skip in the PR comment.` замінити на:
     ```
     2. **Findings.** When all three have returned: a security finding fixable
        inside the branch's own code goes to the fix wave like a review finding;
        a finding that needs a decision beyond the code — credentials or secrets
        to rotate, permissions or access policy, data already exposed — is the
        security-sensitive stop gate: pause and put it to the user before the fix
        wave. All findings go to one fix wave, per `references/two-dispatch.md`:
        findings that need a new or changed test go first to one test writer,
        then one implementer receives every finding under Gate green; when none
        needs a test, one implementer receives them all. This is the single
        whole-branch fix wave. Commit its changes in one commit,
        `fix(<scope>): whole-branch and security review findings`.
     ```
     **Decision rules:** після рядка `| A wave closes | …same session. |` вставити:
     ```
     | A wave closes no group, or closes the last one | Skip steps 4–5; the next grouped review or the whole-branch review covers it. |
     ```
- [ ] **Step 3: run the tests** — `bash skills/skills.test.sh`; жодного FAIL з `wolowitz:` чи `20000 bytes`; `wc -c skills/wolowitz/SKILL.md` < 20000.

### Task 2: `grouped-review.md`, шаблон рев'юера, references

**Writes:** `skills/wolowitz/references/grouped-review.md`, `skills/wolowitz/reviewer-prompt.md`, `skills/wolowitz/references/two-dispatch.md`, `skills/wolowitz/references/codex-tasks.md`
**Reads:** `docs/sdd/specs/2026-11-02-faster-review.md`, `skills/wolowitz/SKILL.md`, `skills/skills.test.sh`
**Depends on:** Task 0
**Executor:** claude
**Complexity:** complex
**Satisfies:** `Grouped review`: три `require_ref grouped-review.md`, два `review when the schedule has one`, два перевірки `reviewer-prompt.md`.
**Interfaces:**
- Produces: `skills/wolowitz/references/grouped-review.md`, на який посилається `SKILL.md` (Task 1) у кроках 1, 4, 5, 6.
- Consumes: назви кроків `SKILL.md` — step 3 (verify), step 5 (fix loop), step 6 (commit), step 7 (PR comment), step 8 (close), `## Now`.

- [ ] **Step 1: run the tests, watch the task's checks fail** — `bash skills/skills.test.sh`; серед FAIL є `references/grouped-review.md: missing "GROUP_BASE: <sha>"`.
- [ ] **Step 2: implement.**
  1. Створити `skills/wolowitz/references/grouped-review.md` дослівно:
     ```markdown
     # Grouped review

     A grouped review covers waves k−2…k. It runs after wave k when `k mod 3 = 0`
     and wave k is not the plan's last wave.

     ## GROUP_BASE

     `GROUP_BASE` is `BASE` from step 1 of the group's first wave — wave 1, 4, 7….
     At step 8 of every wave in the group, keep the line `GROUP_BASE: <sha>` in
     `## Now`. After a compaction, read it from `## Now`; when the line is
     missing, take the parent of the first commit of the group's first-wave tasks
     from `git log`.

     ## Order for wave k

     Verify (step 3), commit wave k's tasks (step 6), grouped review, fix loop,
     fix commits, PR comment (step 7), close (step 8). Wave k's checkboxes are
     ticked only after the fix commits, so a resumed session that finds wave k's
     commits with unticked boxes runs the grouped review first.

     ## The review

     Run `git add -N` on the new files in the group's `**Writes:**` sets, then
     dispatch one reviewer on `sonnet` at `effort: "high"` with
     `reviewer-prompt.md`, filled in for waves k−2…k and all their tasks, over
     `git diff <GROUP_BASE>`.

     ## Fix loop

     Step 5 applies: findings on code go to the task's implementer, findings on
     tests to its test writer, through `SendMessage` in rounds 1–2; round 3 is a
     fresh pair per `two-dispatch.md`; Codex tasks follow `codex-tasks.md`. The
     addressee may come from a wave two waves back.

     When the addressee is not reachable, a test fix goes to a fresh test writer
     per `two-dispatch.md`, and a code fix goes to a fresh implementer whose
     dispatch says under **Context** that it may write only that task's
     `**Writes:**` set; the round number stays the same. When a Codex thread is
     not reachable, the task goes to a fresh Claude implementer per the round-3
     rule in `codex-tasks.md`.

     Fixes stay uncommitted while the loop runs. After each round run the
     verification, then send the reviewer the fix diff through `SendMessage` —
     `git diff HEAD` after `git add -N` on the fix's new files. When the reviewer
     is not reachable, a fresh one on `sonnet` at `effort: "high"` reviews that
     diff with `reviewer-prompt.md`. Its new findings are the next round; after
     round 3 they are parked.

     ## Fix commits

     When the loop closes, for each task with fixes, in task order: stage exactly
     that task's `**Writes:**` set and commit
     `fix(<scope>): review findings for task N`, with a 30–40 word description.

     ## PR comment

     Wave k's comment adds one line: the waves covered, the number of findings,
     the fix commits' shas, and the rulings and parked items from the review.
     ```
  2. `skills/wolowitz/reviewer-prompt.md`:
     - `One reviewer per wave, over the wave's diff. Fill the angle brackets.` → `One reviewer for Wave 0 and one for each group of three waves, over their diff. Fill the angle brackets.`
     - ``Review one wave of an approved plan. `<K>` tasks were implemented in parallel;
you are reviewing all of them together.`` → ``Review waves `<a>`–`<b>` of an approved plan (`<a>` = `<b>` = 0 for Wave 0).
`<K>` tasks were implemented, in parallel within each wave; you are reviewing
all of them together.``
     - ``**The diff:** `git diff <BASE>..HEAD` — review the diff, not the files.`` → ``**The diff:** `git diff <BASE>` — commits plus the working tree; review the diff, not the files.``
     - `## Two things this wave specifically risks` → `## Two things these waves specifically risk`
     - Пункт **Cross-task collisions**: `These tasks were run in parallel because their
  declared file sets were disjoint. Check that the diff bears that out — a file
  touched by two tasks, or by a task that did not declare it, is a real finding.` → `Tasks of one wave ran in parallel because their
  declared file sets were disjoint. Check that the diff bears that out within
  each wave — a file touched by two tasks of one wave, or by a task that did not
  declare it, is a real finding.`
     - Пункт **Interface drift**: після `must match in name and signature.` дописати ` Check it across every wave under review: later waves consume what earlier ones produce.`
     - `Do not soften a real finding because the wave is otherwise clean.` → `Do not soften a real finding because the waves are otherwise clean.`
  3. `skills/wolowitz/references/two-dispatch.md` і `skills/wolowitz/references/codex-tasks.md`: рядок `5. The rest of the wave — suite, review, commit, PR comment — is unchanged.` → `5. The rest of the wave — suite, review when the schedule has one, commit, PR comment — is unchanged.`
- [ ] **Step 3: run the tests** — `bash skills/skills.test.sh`; жодного FAIL з `references/` чи `reviewer-prompt.md`.

### Task 3: README і версія

**Writes:** `README.md`, `README.uk.md`, `.claude-plugin/plugin.json`, `.claude-plugin/marketplace.json`
**Reads:** `skills/skills.test.sh`
**Depends on:** Task 0
**Executor:** claude
**Complexity:** routine
**Satisfies:** `Grouped review`: шість перевірок README; `Model routing`: два `not on 0.16.0`; `Manifest versions`.

- [ ] **Step 1: run the tests, watch the task's checks fail** — `bash skills/skills.test.sh`; серед FAIL є `.claude-plugin/plugin.json: not on 0.16.0`.
- [ ] **Step 2: implement.**
  1. `README.md`, рядок 22: `| \`wolowitz\` | Runs each wave, verifies it, reviews the diff, commits every task, and records progress on the PR. |` → `| \`wolowitz\` | Runs each wave, verifies it, commits every task, reviews every third wave and the whole branch, and records progress on the PR. |`
  2. `README.md`, таблиця dispatch: рядок ``| Reviews, `Explore` fallback | `sonnet` | `xhigh` |`` замінити двома:
     ```
     | Wave 0 and grouped wave reviews | `sonnet` | `high` |
     | Whole-branch review, `Explore` fallback | `sonnet` | `xhigh` |
     ```
  3. `README.uk.md`, рядок 22: `| \`wolowitz\` | Виконує кожну хвилю, перевіряє результат, рев'ює diff, комітить задачі й пише прогрес у PR. |` → `| \`wolowitz\` | Виконує кожну хвилю, перевіряє результат, комітить задачі, рев'ює кожну третю хвилю і всю гілку, пише прогрес у PR. |`
  4. `README.uk.md`, таблиця dispatch: рядок ``| Ревʼю, fallback `Explore` | `sonnet` | `xhigh` |`` замінити двома:
     ```
     | Ревʼю Wave 0 і груп хвиль | `sonnet` | `high` |
     | Ревʼю всієї гілки, fallback `Explore` | `sonnet` | `xhigh` |
     ```
  5. `.claude-plugin/plugin.json` і `.claude-plugin/marketplace.json`: `"version": "0.15.0"` → `"version": "0.16.0"`.
- [ ] **Step 3: run the tests** — `bash skills/skills.test.sh`; жодного FAIL з `README` чи `0.16.0`; після всіх трьох задач — `All checks passed.`

## Verification (end-to-end)

1. `bash skills/skills.test.sh && bash hooks/journal.test.sh && bash hooks/codex.test.sh && bash hooks/nudge.test.sh` → `All checks passed.`
2. `wc -c skills/wolowitz/SKILL.md` < 20000.
3. Вручну, після встановлення `0.16.0`: на гілці з N ≥ 4 за транскриптами субагентів — рев'ю Wave 0 і групове на `sonnet/high`, whole-branch на `sonnet/xhigh`, `security-review` стартує до повернення whole-branch review.
