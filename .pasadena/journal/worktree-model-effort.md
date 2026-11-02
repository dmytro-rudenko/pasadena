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
1. Building. Обидві хвилі закриті: `9b59766` `cec6aa4` `cb8b35d` `d862e78`, чотири набори тестів зелені, рев'ю Wave 1 закрите за два раунди виправлень.
2. Зупинок немає.
3. Далі: Finish у `wolowitz` — whole-branch review від `git merge-base origin/main HEAD` (sonnet/xhigh, а також Codex), потім security-review, `journal finish`, `gh pr ready`.

## Timeline

### 2026-11-02
- 12:06 ✎ Shaping: погоджено frontmatter model/effort для всіх skills і поділ test writer (amy) / implementer (без amy)
- 12:15 ✎ Spec написаний: frontmatter model/effort у 11 skills, test writer (amy) і implementer (без amy) для всіх Claude-задач, round 3 і Finish — пара
- 12:15 ● ab745d2 docs(sdd): spec for frontmatter model/effort and a separate test writer
- 12:23 ✎ План затверджено: Task 0 — acceptance-тести, Wave 1 — Tasks 1–4 паралельно (frontmatter, wolowitz, README, версія)
- 12:23 ● a557964 docs(sdd): plan for frontmatter model/effort and a separate test writer
- 12:31 ● 31c23ec test(skills): add acceptance checks for frontmatter models and test writer
- 12:31 ✎ Wave 0: acceptance-тести червоні рівно в 50 перевірках; рев'ю знайшло розірване рядком речення про Complexity — перевірка тепер читає flattened текст
- 12:31 ● 3302e9b docs(sdd): tick Wave 0
- 12:48 ● 9b59766 feat(skills): set model and effort in skill frontmatter
- 12:48 ● cec6aa4 feat(wolowitz): split every task into test writer and implementer
- 12:48 ● cb8b35d docs: describe skill frontmatter models and the dispatch matrix
- 12:48 ● d862e78 chore: bump plugin to 0.15.0
- 12:48 ✎ Wave 1: frontmatter, wolowitz split, README, 0.15.0 зелені; рев'ю прибрало залишки старого flow (leslie, wolowitz) і закрило round 3 після Gate red, Codex hand-off, scope Finish
