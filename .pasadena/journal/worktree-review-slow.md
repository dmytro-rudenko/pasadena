---
branch: worktree-review-slow
spec: docs/sdd/specs/2026-11-02-faster-review.md
plan: -
status: in-progress
started: 2026-11-02
---

## Goal
Скоротити час рев'ю у `wolowitz` (зараз 20–35 хв на гілку). Wave review переходить на `high`,
одне рев'ю на кожні 3 хвилі (при 1–3 хвилях лише whole-branch review), а security review
запускається паралельно з whole-branch review. Готово, коли зміну злито і версію плагіна піднято.

## Now
Shaping (sheldon, Architectural). Виміряно: час рев'ю пропорційний вихідним токенам sonnet xhigh
(50–170 тис. на рев'ю, ~16 тис./хв); Codex review (1–4 хв) не є вузьким місцем. Користувач обрав
три зміни. Далі: зібрати місця, які зачіпає зміна, уточнити fix loop і нумерацію хвиль, написати
spec у docs/sdd/specs/2026-11-02-faster-review.md.

## Timeline

### 2026-11-02
- 12:46 ✎ Shaping: рев'ю займає 20–35 хв на гілку через thinking sonnet xhigh; обрано wave review на high, рев'ю раз на 3 хвилі, security паралельно з whole-branch
- 13:13 ✎ Spec узгоджено: рев'ю Wave 0 і груп по три хвилі на sonnet/high, whole-branch xhigh, security паралельно; builder check закрито п'ятьма власними рішеннями
