---
branch: worktree-review-slow
spec: docs/sdd/specs/2026-11-02-faster-review.md
plan: docs/sdd/plans/2026-11-02-faster-review.md
status: in-progress
started: 2026-11-02
---

## Goal
Скоротити час рев'ю у `wolowitz` (зараз 20–35 хв на гілку). Wave review переходить на `high`,
одне рев'ю на кожні 3 хвилі (при 1–3 хвилях лише whole-branch review), а security review
запускається паралельно з whole-branch review. Готово, коли зміну злито і версію плагіна піднято.

## Now
Building (wolowitz). Spec і план затверджено, draft PR #24. Хвилі: 0 (Task 0, acceptance-тести
в skills/skills.test.sh), 1 (Tasks 1–3 паралельно). Далі: Wave 0 — Task 0, потім
`bash skills/skills.test.sh`, очікується `FAILED: 22`.

## Timeline

### 2026-11-02
- 12:46 ✎ Shaping: рев'ю займає 20–35 хв на гілку через thinking sonnet xhigh; обрано wave review на high, рев'ю раз на 3 хвилі, security паралельно з whole-branch
- 13:13 ✎ Spec узгоджено: рев'ю Wave 0 і груп по три хвилі на sonnet/high, whole-branch xhigh, security паралельно; builder check закрито п'ятьма власними рішеннями
- 13:13 ● 1fd091f docs(sdd): spec for faster wolowitz review
