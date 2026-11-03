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
Building: хвиля 0 закрита (9735ec2, acceptance tests червоні, FAILED: 35, лише через відсутній reuse.sh і реєстрацію). Baseline: journal.test.sh FAILED: 3 через чужу незакомічену правку hooks/journal.sh — не наше. Далі: хвиля 1, Tasks 1, 2, 3 паралельно; перевірка `bash hooks/reuse.test.sh` → All checks passed. Зберегти без змін: hooks/journal.sh має чужі незакомічені зміни — не комітити їх у цій гілці.

## Timeline

### 2026-11-03
- 17:41 ✎ Shaping: обрано repomap з tokeneconomizer замість власної карти; pasadena додає правило й передачу субагентам
- 17:43 ✎ Spec reuse-first написано; builder check зроблено вручну: te config читається через jq .other.repomap, timeout опційний
- 17:43 ● 5035f55 docs(spec): reuse-first rule and repomap for subagents
- 17:49 ● 845da3a docs(spec): skip read-only subagents in reuse hook
- 17:58 ● b748313 docs(plan): reuse-first hook implementation plan
- 17:58 ✎ План затверджено: 4 задачі, 2 хвилі (0 → 1,2,3 паралельно); усі executor claude, бо Codex off
- 18:05 ● 9735ec2 test(hooks): acceptance tests for the reuse-first hook
