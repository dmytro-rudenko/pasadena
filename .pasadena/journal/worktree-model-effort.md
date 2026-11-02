---
branch: worktree-model-effort
spec: docs/sdd/specs/2026-11-02-skill-frontmatter-models.md
plan: -
status: in-progress
started: 2026-11-02
---

## Goal
Зняти заборону `model`/`effort` у frontmatter `SKILL.md`: кожен skill явно задає обидва поля.
У `wolowitz` прибрати `amy` з implementer-субагентів: тести пише окремий test writer через `amy`, код — окремий implementer без `amy`.
Готово, коли спец, план і build пройдені, `skills/skills.test.sh` зелений, версія `0.15.0`.

## Now
1. Shaping (sheldon, Architectural): усі три секції дизайну погоджені, spec написаний, builder check зроблено вручну (Agent заборонений правилом дозволів).
2. Чекаємо, поки користувач перегляне spec у draft PR.
3. Далі: після погодження spec запустити `pasadena:leonard`, який напише план у `docs/sdd/plans/2026-11-02-skill-frontmatter-models.md`.

## Timeline

### 2026-11-02
- 12:06 ✎ Shaping: погоджено frontmatter model/effort для всіх skills і поділ test writer (amy) / implementer (без amy)
- 12:15 ✎ Spec написаний: frontmatter model/effort у 11 skills, test writer (amy) і implementer (без amy) для всіх Claude-задач, round 3 і Finish — пара
