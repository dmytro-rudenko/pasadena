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
Building (wolowitz). Wave 0 закрита: Task 0 `d8360a0`, `bash skills/skills.test.sh` → `FAILED: 27`
(22 з плану + 3 перевірки графіка/diff у SKILL.md + 2 негативні README після рев'ю), хуки зелені.
Далі: Wave 1 — Tasks 1, 2, 3 паралельно (implementer-и без test writer), потім
`bash skills/skills.test.sh` → `All checks passed.`

## Timeline

### 2026-11-02
- 12:46 ✎ Shaping: рев'ю займає 20–35 хв на гілку через thinking sonnet xhigh; обрано wave review на high, рев'ю раз на 3 хвилі, security паралельно з whole-branch
- 13:13 ✎ Spec узгоджено: рев'ю Wave 0 і груп по три хвилі на sonnet/high, whole-branch xhigh, security паралельно; builder check закрито п'ятьма власними рішеннями
- 13:13 ● 1fd091f docs(sdd): spec for faster wolowitz review
- 13:17 ✎ План затверджено: Wave 0 — acceptance-перевірки, Wave 1 — SKILL.md, grouped-review.md+reviewer-prompt, README+0.16.0 паралельно
- 13:17 ● 21041ee docs(sdd): plan for faster wolowitz review
- 13:27 ● d8360a0 test(skills): add acceptance checks for grouped review
