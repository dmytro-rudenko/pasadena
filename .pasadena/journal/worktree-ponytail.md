---
branch: worktree-ponytail
spec: docs/sdd/specs/2026-11-03-reuse-first.md
plan: docs/sdd/plans/2026-11-03-reuse-first.md
status: in-progress
started: 2026-11-03
---

## Goal
Змусити агента перевикористовувати наявні компоненти, хелпери й шаблони сторінок замість писати з нуля.
Готово, коли pasadena в кожній сесії й у кожному субагенті дає правило «спершу знайди готове», а субагенти отримують кешовану repomap з tokeneconomizer.

## Now
Building: усі хвилі закриті (Task 1 ff0084c, Task 2 ec3fb4f, Task 3 a297a8b); reuse/nudge/skills тести зелені, journal.test.sh FAILED: 3 — baseline від чужої правки hooks/journal.sh. Далі: Finish — whole-branch review + security-review над `git merge-base origin/main HEAD..HEAD`, потім journal finish і `gh pr ready 30`. Зберегти без змін: hooks/journal.sh має чужі незакомічені зміни — не комітити їх у цій гілці.

## Timeline

### 2026-11-03
- 17:41 ✎ Shaping: обрано repomap з tokeneconomizer замість власної карти; pasadena додає правило й передачу субагентам
- 17:43 ✎ Spec reuse-first написано; builder check зроблено вручну: te config читається через jq .other.repomap, timeout опційний
- 17:43 ● 5035f55 docs(spec): reuse-first rule and repomap for subagents
- 17:49 ● 845da3a docs(spec): skip read-only subagents in reuse hook
- 17:58 ● b748313 docs(plan): reuse-first hook implementation plan
- 17:58 ✎ План затверджено: 4 задачі, 2 хвилі (0 → 1,2,3 паралельно); усі executor claude, бо Codex off
- 18:05 ● 9735ec2 test(hooks): acceptance tests for the reuse-first hook
- 18:05 ● 4c2c46f docs(plan): close wave 0 and fix test counts
- 18:05 ✎ Хвиля 0: acceptance tests після 2 раундів рев'ю ловлять пропущений cd "$cwd", виклик refresh, запасний шлях до te і точні exit-коди
- 18:08 ● ff0084c feat(hooks): reuse-first rule and repomap for subagents
- 18:08 ● ec3fb4f feat(hooks): register reuse.sh for SessionStart and SubagentStart
- 18:08 ● a297a8b chore(release): 0.21.0 and document the reuse hook
