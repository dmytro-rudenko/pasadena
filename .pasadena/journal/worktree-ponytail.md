---
branch: worktree-ponytail
spec: docs/sdd/specs/2026-11-03-reuse-first.md
plan: -
status: in-progress
started: 2026-11-03
---

## Goal
Змусити агента перевикористовувати наявні компоненти, хелпери й шаблони сторінок замість писати з нуля.
Готово, коли pasadena в кожній сесії й у кожному субагенті дає правило «спершу знайди готове», а субагенти отримують кешовану repomap з tokeneconomizer.

## Now
Spec написано й закомічено, draft PR відкрито; чекаємо на відгук користувача щодо spec. Далі: після погодження — leonard (план у docs/sdd/plans/2026-11-03-reuse-first.md). Зберегти без змін: hooks/journal.sh має чужі незакомічені зміни — не комітити їх у цій гілці.

## Timeline

### 2026-11-03
- 17:41 ✎ Shaping: обрано repomap з tokeneconomizer замість власної карти; pasadena додає правило й передачу субагентам
- 17:43 ✎ Spec reuse-first написано; builder check зроблено вручну: te config читається через jq .other.repomap, timeout опційний
