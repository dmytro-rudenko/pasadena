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
Finish (wolowitz). Усі хвилі закриті: `8c232ca` `c50579b` `00646df`, чотири suite зелені,
SKILL.md 19775 байтів. Далі: whole-branch review (sonnet xhigh) + Codex review + security-review
над `git merge-base origin/main HEAD`, одна fix wave, фінальний коментар, journal finish, `gh pr ready`.

## Timeline

### 2026-11-02
- 12:46 ✎ Shaping: рев'ю займає 20–35 хв на гілку через thinking sonnet xhigh; обрано wave review на high, рев'ю раз на 3 хвилі, security паралельно з whole-branch
- 13:13 ✎ Spec узгоджено: рев'ю Wave 0 і груп по три хвилі на sonnet/high, whole-branch xhigh, security паралельно; builder check закрито п'ятьма власними рішеннями
- 13:13 ● 1fd091f docs(sdd): spec for faster wolowitz review
- 13:17 ✎ План затверджено: Wave 0 — acceptance-перевірки, Wave 1 — SKILL.md, grouped-review.md+reviewer-prompt, README+0.16.0 паралельно
- 13:17 ● 21041ee docs(sdd): plan for faster wolowitz review
- 13:27 ● d8360a0 test(skills): add acceptance checks for grouped review
- 13:27 ✎ Wave 0: 27 acceptance-перевірок червоні як очікувано; рев'ю додало перевірки межі графіка і diff Wave 0
- 13:27 ● df24b97 docs(sdd): tick Wave 0
- 13:39 ● 8c232ca feat(wolowitz): review waves in groups of three
- 13:39 ● c50579b feat(wolowitz): add grouped review reference and range reviewer template
- 13:39 ● 00646df docs: describe grouped wave review and bump plugin to 0.16.0
