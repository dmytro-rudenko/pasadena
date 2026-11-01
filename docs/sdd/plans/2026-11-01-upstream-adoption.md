# Перенесення з obra/superpowers — implementation plan

**Goal:** усі `SKILL.md` менші за 20 000 байтів і це перевіряється тестом; `sheldon` має builder check і питання про технічні вибори; ревʼю рахує базу від `origin/<trunk>`; плани мають `## Review Focus`, а ревʼюер оцінює поведінку поза специфікацією.
**Spec:** окремої специфікації немає: рішення узгоджені в чаті й зафіксовані в `## Global constraints`. Поле `spec:` у журналі вказує на цей план.
**Verification:** `bash skills/skills.test.sh && bash hooks/journal.test.sh && bash hooks/codex.test.sh`, останній рядок `All checks passed.`

## Global constraints

- Усе йде в гілку `worktree-advisor` і PR #22. Версія лишається `0.14.0`: її ще не випущено.
- Skills, шаблони й reference-файли написані англійською. Текст задач вставляти дослівно.
- Жодних коментарів у коді.
- Не додавати `model:` чи `effort:` у frontmatter.
- Винесений текст переноситься без змін, крім названих у задачі місць.
- Запуск builder check: `sonnet`, `effort: "xhigh"`.
- Плани без повного коду (v6.4.2) поза цією роботою.

## Review Focus

- Skill, що лежить рівно на 20 000 байтів: тест має падати, бо межа upstream — «reaches 20,000».
- Compaction під час збірки: винесені правила мають лишатися доступними, тому заглушка вимагає перечитати reference-файл.
- Локальна `main` позаду `origin/main`: база ревʼю не має залежати від локальної гілки.

## Waves

| Wave | Tasks | Why together |
|---|---|---|
| 0 | 0 | alone — acceptance tests, red until the last wave |
| 1 | 1, 2, 3, 4 | disjoint: `skills/wolowitz/`, `skills/sheldon/`, `skills/leonard/`, `THIRD_PARTY_NOTICES.md` |

Серіалізувати нічого не довелось: задачі пишуть різні файли, а назву `## Review Focus` Task 1 і Task 3 беруть із тексту задач.

### Task 0: acceptance tests

**Writes:** `skills/skills.test.sh`
**Executor:** claude
**Covers:** розмір кожного `SKILL.md`; винесення `Codex tasks` і `Complex tasks`; база ревʼю від `origin/<trunk>`; builder check; питання про технічні вибори; `## Review Focus`; правила ревʼюера; атрибуція.

- [x] **Step 1: додати helper** — одразу після функції `require()` вставити:

```bash
require_ref() {
  grep -qF -- "$2" "$SKILLS/wolowitz/references/$1" 2>/dev/null || fail "references/$1: missing \"$2\""
}
```

- [x] **Step 2: перенести наявні перевірки** — у блоці `Codex delegation` замінити рядки:

```bash
require wolowitz "codex.sh red"
require wolowitz "codex.sh green"
require wolowitz "Gate red"
require wolowitz "Gate green"
require wolowitz "implementer-prompt-codex.md"
```

на:

```bash
require_ref codex-tasks.md "codex.sh red"
require_ref codex-tasks.md "codex.sh green"
require_ref codex-tasks.md "Gate red"
require_ref codex-tasks.md "Gate green"
require_ref codex-tasks.md "implementer-prompt-codex.md"
```

- [x] **Step 3: додати новий блок** — перед рядком `echo "Manifest versions"` вставити:

```bash
echo "Upstream adoption"
before=$fails
for file in "$SKILLS"/*/SKILL.md; do
  [ "$(wc -c <"$file")" -lt 20000 ] || fail "$file: 20000 bytes or more, compaction cuts it off"
done
require wolowitz 'references/codex-tasks.md'
require wolowitz 'references/complex-tasks.md'
require_ref complex-tasks.md 'Gate red'
require_ref complex-tasks.md 'Gate green'
require_ref complex-tasks.md '**Red dispatch**'
require_ref complex-tasks.md '**Green dispatch**'
require wolowitz 'git merge-base origin/<trunk> HEAD'
! grep -qF 'git merge-base <trunk>' "$SKILLS/wolowitz/SKILL.md" || fail "wolowitz: merge-base on a local trunk"
require wolowitz 'Declined to judge'
require sheldon '## Builder check'
require sheldon '**Who owns the technical choices.**'
[ -f "$SKILLS/sheldon/builder-check-prompt.md" ] || fail "sheldon: builder-check-prompt.md missing"
grep -qF 'skills/sheldon/builder-check-prompt.md' "$ROOT/THIRD_PARTY_NOTICES.md" || fail "builder check: not credited"
require leonard '## Review Focus'
grep -qF 'reasonable person' "$SKILLS/wolowitz/reviewer-prompt.md" || fail "reviewer-prompt.md: missing reasonable person rule"
grep -qF '## Declined to judge' "$SKILLS/wolowitz/reviewer-prompt.md" || fail "reviewer-prompt.md: missing Declined to judge"
[ "$fails" -eq "$before" ] && ok "upstream adoption checked"

```

- [x] **Step 4: run them, watch them fail** — `bash skills/skills.test.sh | tail -1`, expect `FAILED: 22`. Склад: `references/codex-tasks.md` 5, `references/complex-tasks.md` 4, розмір 1, заглушки 2, база 2, `Declined to judge` у `wolowitz` 1, `sheldon` 3, атрибуція 1, `leonard` 1, `reviewer-prompt.md` 2.

### Task 1: `wolowitz` менший за ліміт, база від origin, правила ревʼюера

**Writes:** `skills/wolowitz/SKILL.md`, `skills/wolowitz/references/codex-tasks.md`, `skills/wolowitz/references/complex-tasks.md`, `skills/wolowitz/reviewer-prompt.md`
**Depends on:** Task 0
**Executor:** claude
**Complexity:** routine
**Satisfies:** перевірки `references/*`, розміру, бази, заглушок і `reviewer-prompt.md`.

- [x] **Step 1: перевірити red** — `bash skills/skills.test.sh | grep -cE 'FAIL — (references/|.*wolowitz/SKILL.md: 20000|wolowitz: |reviewer-prompt.md: )'`, expect `17`.
- [x] **Step 2: винести Codex tasks** — створити `references/codex-tasks.md` із заголовком `# Codex tasks` і дослівним тілом розділу `## Codex tasks` зі `SKILL.md`. У `SKILL.md` тіло розділу замінити на:

```markdown
A task with `**Executor:** codex` runs as two Codex calls with your own gates
between them. Before a wave's first such task, read
`references/codex-tasks.md` in this skill's directory, and read it again after a
compaction.
```

- [x] **Step 3: винести Complex tasks** — створити `references/complex-tasks.md` із заголовком `# Complex tasks` і всім тілом розділу `## Complex tasks` від абзацу `Two shapes stay one implementer` до кінця розділу. Перші абзаци лишаються в `SKILL.md` у такому вигляді:

```markdown
`**Complexity:**` decides how a Claude task runs. `routine` is one implementer
through the whole `amy` cycle. `complex` is two dispatches with your own gates
between them. A task with no `**Complexity:**` line is `complex`. Task 0 is
outside this section: one implementer, per **Models**, stopping on red. A task
with `**Executor:** codex` runs through **Codex tasks**. A Codex task handed to
Claude before Round 3 runs on the `routine` row. A session with no subagents
skips this section.

Before a wave's first `complex` task, read `references/complex-tasks.md` in this
skill's directory, and read it again after a compaction.
```

- [x] **Step 4: база ревʼю** — у `## Finish` замінити `git merge-base <trunk> HEAD..HEAD` на `git merge-base origin/<trunk> HEAD..HEAD` і `$(git merge-base <trunk> HEAD)` на `$(git merge-base origin/<trunk> HEAD)`.
- [x] **Step 5: `### 4. Review the wave`** — після абзацу про авторитетність controller's verification додати:

```markdown
Decide every `Declined to judge` item yourself: it becomes a finding or a
one-line ruling in the wave's PR comment.
```

- [x] **Step 6: `reviewer-prompt.md`** — наприкінці абзацу `**2. Quality.**` додати речення, а перед `## Do not` додати розділ:

```markdown
Where the spec is silent, judge behaviour by what a reasonable person using this
software would expect, starting with the plan's `## Review Focus`.
```

```markdown
## Declined to judge

List anything you could not judge from the diff, the plan and the spec, with the
reason. The controller decides each item.
```

- [x] **Step 7: перевірити green** — команда зі Step 1, expect `0`; `wc -c skills/wolowitz/SKILL.md` показує менше за `20000`.

### Task 2: `sheldon`: builder check і технічні вибори

**Writes:** `skills/sheldon/SKILL.md`, `skills/sheldon/builder-check-prompt.md`
**Depends on:** Task 0
**Executor:** claude
**Complexity:** routine
**Satisfies:** три перевірки `sheldon`.

- [x] **Step 1: перевірити red** — `bash skills/skills.test.sh | grep -cE 'FAIL — sheldon: '`, expect `3`.
- [x] **Step 2: frontmatter** — додати `  - Agent` після `  - Skill` в `allowed-tools`.
- [x] **Step 3: створити `skills/sheldon/builder-check-prompt.md`:**

```markdown
# Builder check dispatch template

Fill the angle brackets. Dispatch one fresh subagent on `sonnet` at
`effort: "xhigh"`.

---

You are a talented `<domain, e.g. "software engineer">`. You have been handed a
specification and asked to plan the build it describes. You will not be able to
talk to the person who wrote it.

Read `<absolute path to the spec>`.

Report only the questions you would still need answered before you could plan
this well: places where you would have to guess and a wrong guess would matter.
For each, give the question and why the answer changes the plan. Rank them by
importance.

Skip anything the spec explicitly leaves to the builder, and anything you could
reasonably decide yourself. Skip nitpicks about wording.

If nothing important is left, say "nothing important left".
```

- [x] **Step 4: питання про вибори** — у `## Understand the idea`, після пункту `Finish the questioning phase…`, перед `## Propose approaches` вставити:

```markdown
**Who owns the technical choices.** Find out which choices about how the thing
gets made the user wants to own: platform, language, libraries, medium. Talk
through the ones they care about. For the ones they hand over, pick a sensible
default and say what you picked.
```

- [x] **Step 5: builder check** — перед `## Open the PR` вставити:

```markdown
## Builder check

Architectural path only. After the self-review, dispatch a fresh subagent with
`builder-check-prompt.md` from this skill's directory. Without a subagent tool,
read the spec as that builder yourself. Sort what comes back into three piles:

- **Answered already** by the conversation or the repository: put the answer in
  the spec.
- **Minor:** a sensible builder could settle it without changing what gets
  built. Settle it and mark it in the spec as your call.
- **Theirs:** only the user can answer it, and the answer changes what gets
  built. Ask these in one message, most important first, then update the spec.

This is the only round of questions the check produces. Hand the spec over with
a short list of the calls you made.
```

- [x] **Step 6: перевірити green** — команда зі Step 1, expect `0`.

### Task 3: `leonard`: Review Focus

**Writes:** `skills/leonard/SKILL.md`
**Depends on:** Task 0
**Executor:** claude
**Complexity:** routine
**Satisfies:** перевірка `leonard` на `## Review Focus`.

- [x] **Step 1: перевірити red** — `bash skills/skills.test.sh | grep -cE 'FAIL — leonard: '`, expect `1`.
- [x] **Step 2: шаблон заголовка** — у блоці Header після абзацу `## Global constraints` усередині того самого блоку коду додати:

```markdown
## Review Focus
Up to five inputs or failure modes the spec implies but no task's tests exercise,
one line each: the condition and what a reasonable person would expect, most
likely first. Add a test for each line to the task that owns the code.
```

- [x] **Step 3: перевірити green** — команда зі Step 1, expect `0`.

### Task 4: атрибуція

**Writes:** `THIRD_PARTY_NOTICES.md`
**Depends on:** Task 0
**Executor:** claude
**Complexity:** routine
**Satisfies:** перевірка `builder check: not credited`.

- [x] **Step 1: перевірити red** — `bash skills/skills.test.sh | grep -c 'builder check: not credited'`, expect `1`.
- [x] **Step 2: implement** — у списку розділу `## obra/superpowers` додати рядки:

```markdown
- `skills/sheldon/builder-check-prompt.md` and `skills/sheldon/SKILL.md` section "Builder check" from `skills/brainstorming/`
- `skills/leonard/SKILL.md` section "Review Focus" from `skills/writing-plans/SKILL.md`
- `skills/wolowitz/reviewer-prompt.md` section "Declined to judge" from `skills/requesting-code-review/code-reviewer.md`
```

- [x] **Step 3: перевірити green** — команда зі Step 1, expect `0`.
