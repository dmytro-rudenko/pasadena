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
Building хвиля 2 (wolowitz): Task 7 (hooks/nudge.sh, nudge.test.sh, реєстрація) і Task 8 (README). Верифікація: `bash skills/skills.test.sh && bash hooks/journal.test.sh && bash proto/server.test.sh && bash hooks/nudge.test.sh`. Потім whole-branch review, security pass, повторний headless-сценарій 2 ×3 (запускає користувач), journal finish, ready.

## Timeline

### 2026-10-21
- 12:53 ✎ Старт shaping: задача класифікована як Architectural; у сесії 1a8549de wolowitz без субагентів не викликав amy
- 13:09 ✎ Спека погоджена по розділах: вбудовуємо адаптовані копії (MIT/Apache), trailofbits відкинуто через CC-BY-SA, безпека = вбудований security-review
- 13:09 ● 8b98483 docs(spec): testing skills — leslie, bernie, stuart, verify-before-claiming in amy
- 13:14 ✎ План затверджено: 6 задач з неперетинними Writes, одна хвиля; README-перевірка пропускає pasadena/journal (ruling)
- 13:14 ● 40742c5 docs(plan): testing skills — six tasks in one wave
- 13:22 ● 12429f2 chore(plugin): bump to 0.7.0, credit adapted skills, check READMEs and versions
- 13:22 ● 620a72f feat(amy): require fresh evidence before any claim of done
- 13:22 ● 77eee53 feat(leslie): add four-phase root-cause debugging skill
- 13:22 ● 6bf745b feat(bernie): add browser e2e skill with one-off and lasting modes
- 13:22 ● baa4d09 feat(stuart): add visual layout check across breakpoints
- 13:22 ● d3ede95 feat(wolowitz): amy without subagents, leslie on red, security review
- 13:22 ✎ Хвиля 1: 6 задач зелені; рев'ю знайшло, що leslie і wolowitz обидва фіксили — тепер під контролером leslie лише діагностує
- 13:22 ● 3eb24cb docs(plan): tick wave 1
- 13:28 ● f0cc294 fix(skills): resolve whole-branch review findings
- 13:28 ● 0076811 fix(skills): limit pre-approved curl to localhost in bernie and stuart
- 13:29 ✎ Finish: security pass знайшов Bash(curl *) поруч із недовіреним вмістом сторінок — звужено до localhost; grep-тести не доводять поведінку агента
- 13:42 ✎ Headless-прогони 0.7.0: фолбек wolowitz кличе amy до першої правки (PASS); на «полагодь» leslie/amy не тригеряться (FAIL, n=1) → хук
- 13:52 ✎ Спека 3.7: nudge-хук на ключові слова uk/en, бо description-тригер не ловить «полагодь»
- 13:52 ● 2117b23 docs(spec): add nudge hook so leslie and amy fire on casual requests
