---
branch: worktree-tdd
spec: docs/sdd/specs/2026-10-21-testing-skills.md
plan: docs/sdd/plans/2026-10-21-testing-skills.md
status: in-progress
started: 2026-10-21
---

## Goal
Посилити тестування в pasadena: зробити amy надійнішою (включно з випадком, коли wolowitz працює без субагентів) і додати навички для тестування, взявши корисне з зовнішніх skills (superpowers, trailofbits, webapp-testing тощо). Готово, коли є погоджена спека, план і реалізація в цьому плагіні.

## Now
Building (wolowitz). План: 6 задач в одній хвилі (метадані+тест, amy, leslie, bernie, stuart, wolowitz). Далі: хвиля 1, потім whole-branch review, security-review, journal finish. Верифікація: `bash skills/skills.test.sh && bash hooks/journal.test.sh && bash proto/server.test.sh`.

## Timeline

### 2026-10-21
- 12:53 ✎ Старт shaping: задача класифікована як Architectural; у сесії 1a8549de wolowitz без субагентів не викликав amy
- 13:09 ✎ Спека погоджена по розділах: вбудовуємо адаптовані копії (MIT/Apache), trailofbits відкинуто через CC-BY-SA, безпека = вбудований security-review
- 13:09 ● 8b98483 docs(spec): testing skills — leslie, bernie, stuart, verify-before-claiming in amy
