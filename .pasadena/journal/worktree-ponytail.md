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
Building: план затверджено (wave 0 = Task 0 acceptance tests; wave 1 = Tasks 1, 2, 3 паралельно). Далі: wolowitz, wave 0 — `bash hooks/reuse.test.sh` має впасти з `FAILED:`. Зберегти без змін: hooks/journal.sh має чужі незакомічені зміни — не комітити їх у цій гілці.

## Timeline

### 2026-11-03
- 17:41 ✎ Shaping: обрано repomap з tokeneconomizer замість власної карти; pasadena додає правило й передачу субагентам
- 17:43 ✎ Spec reuse-first написано; builder check зроблено вручну: te config читається через jq .other.repomap, timeout опційний
- 17:43 ● 5035f55 docs(spec): reuse-first rule and repomap for subagents
- 17:49 ● 845da3a docs(spec): skip read-only subagents in reuse hook
