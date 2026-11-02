---
branch: worktree-model-effort
spec: docs/sdd/specs/2026-11-02-skill-frontmatter-models.md
plan: docs/sdd/plans/2026-11-02-skill-frontmatter-models.md
status: in-progress
started: 2026-11-02
---

## Goal
Зняти заборону `model`/`effort` у frontmatter `SKILL.md`: кожен skill явно задає обидва поля.
У `wolowitz` прибрати `amy` з implementer-субагентів: тести пише окремий test writer через `amy`, код — окремий implementer без `amy`.
Готово, коли спец, план і build пройдені, `skills/skills.test.sh` зелений, версія `0.15.0`.

## Now
1. Building. Wave 0 закрита: `31c23ec`, `bash skills/skills.test.sh` показує `FAILED: 50` (групи 20 / 21 / 6 / 3).
2. Зупинок немає.
3. Далі: Wave 1 — Tasks 1, 3, 4 (routine, sonnet/xhigh) і Task 2 (complex: red на opus/high, потім green на opus/medium); перевірка — `bash skills/skills.test.sh | tail -1`, очікується `All checks passed.`

## Timeline

### 2026-11-02
- 12:06 ✎ Shaping: погоджено frontmatter model/effort для всіх skills і поділ test writer (amy) / implementer (без amy)
- 12:15 ✎ Spec написаний: frontmatter model/effort у 11 skills, test writer (amy) і implementer (без amy) для всіх Claude-задач, round 3 і Finish — пара
- 12:15 ● ab745d2 docs(sdd): spec for frontmatter model/effort and a separate test writer
- 12:23 ✎ План затверджено: Task 0 — acceptance-тести, Wave 1 — Tasks 1–4 паралельно (frontmatter, wolowitz, README, версія)
- 12:23 ● a557964 docs(sdd): plan for frontmatter model/effort and a separate test writer
- 12:31 ● 31c23ec test(skills): add acceptance checks for frontmatter models and test writer
- 12:31 ✎ Wave 0: acceptance-тести червоні рівно в 50 перевірках; рев'ю знайшло розірване рядком речення про Complexity — перевірка тепер читає flattened текст
