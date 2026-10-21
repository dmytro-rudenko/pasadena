---
branch: worktree-tdd
spec: docs/sdd/specs/2026-10-21-testing-skills.md
plan: -
status: in-progress
started: 2026-10-21
---

## Goal
Посилити тестування в pasadena: зробити amy надійнішою (включно з випадком, коли wolowitz працює без субагентів) і додати навички для тестування, взявши корисне з зовнішніх skills (superpowers, trailofbits, webapp-testing тощо). Готово, коли є погоджена спека, план і реалізація в цьому плагіні.

## Now
Спека записана (amy+verify, leslie, bernie, stuart, wolowitz: фолбек/leslie/security-review), draft PR відкрито. Чекаємо фідбек користувача на спеку. Далі: leonard → план у docs/sdd/plans/.

## Timeline

### 2026-10-21
- 12:53 ✎ Старт shaping: задача класифікована як Architectural; у сесії 1a8549de wolowitz без субагентів не викликав amy
- 13:09 ✎ Спека погоджена по розділах: вбудовуємо адаптовані копії (MIT/Apache), trailofbits відкинуто через CC-BY-SA, безпека = вбудований security-review
