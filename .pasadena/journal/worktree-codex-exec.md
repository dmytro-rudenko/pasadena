---
branch: worktree-codex-exec
spec: docs/sdd/specs/2026-10-23-codex-exec-delegation.md
plan: docs/sdd/plans/2026-10-23-codex-exec-delegation.md
status: in-progress
started: 2026-10-23
---

## Goal
Дати skills Pasadena змогу делегувати прості explore/read задачі в `codex exec`,
щоб економити ліміти Claude; Claude лишається оркестратором.
Готово, коли є погоджена специфікація, реалізація за планом і перевірка.

## Now
1. Building: усі хвилі закриті; E2E зі справжнім codex пройшов red → gate → green → gate.
2. Зупинились на: Finish.
3. Далі: whole-branch review на fable, security-review, journal finish, `gh pr ready`. Зберегти: перевірка «Claude Code only» тепер ловить лише артефакти хоста (список шаблонів — у skills/skills.test.sh).

## Timeline

### 2026-10-23
- 13:09 ✎ Shaping: задачу класифіковано як Architectural, журнал відкрито
- 13:28 ✎ Спека погоджена посекційно: hooks/codex.sh (idle-таймаут 120/600 с, код 75 на ліміт), TDD через red/green gate'и, Executor у leonard; codex exec review відкинуто, бо порівнює через GitHub MCP
- 13:28 ● fb50e05 docs(spec): delegate explore, review and simple tasks to codex exec
- 13:35 ● efaeae0 docs(plan): codex exec delegation implementation plan
- 13:35 ✎ План затверджено: 7 задач у 3 хвилі; усі Executor: claude, бо codex.sh ще не встановлений у плагіні
- 13:45 ● 1fb6fa8 test: acceptance tests for codex exec delegation
- 13:45 ● b3406e7 docs(plan): close wave 0
- 13:45 ✎ Wave 0: acceptance tests червоні з передбаченої причини; review додав перевірки thread id, trailing '-', порожнього -o
- 14:06 ● 3cf7818 feat(hooks): codex.sh wrapper for delegating to codex exec
- 14:06 ● 0f93f7c feat(wolowitz): run Codex tasks through red and green gates
- 14:06 ● 972ee59 feat(leonard): mark plan tasks with an Executor and delegate explore
- 14:06 ● 7aa744a feat(leslie,sheldon): delegate bulk reading to codex.sh explore
- 14:06 ● f5bdb55 docs: document Codex delegation and bump to 0.10.0
- 14:06 ● 6b3515d docs(spec): record wave 1 review rulings
- 14:07 ● 48cfc77 docs(plan): close wave 1
- 14:07 ✎ Wave 1: codex.sh + 4 skills + README зелені; ревʼю довело, що review мусить читати незакомічене дерево, а idle/TERM мають вбивати групу процесів Codex
- 14:10 ● 0e8e9ec fix(hooks): end codex.sh output with a newline
