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
1. Building: Wave 0 закрита (1fb6fa8), acceptance tests червоні як треба: skills FAILED: 22, codex.test.sh FAILED: 41.
2. Зупинились на: старт Wave 1 (Tasks 1–5 паралельно).
3. Далі: dispatch Tasks 1–5; після — `bash hooks/codex.test.sh && bash skills/skills.test.sh` → All checks passed. Тести в codex.test.sh після fix-раунду суворіші за код у плані (nothread, trailing `-`, empty -o) — Task 1 має їх пройти. Зберегти: перевірка «Claude Code only» тепер ловить лише артефакти хоста (список шаблонів — у skills/skills.test.sh).

## Timeline

### 2026-10-23
- 13:09 ✎ Shaping: задачу класифіковано як Architectural, журнал відкрито
- 13:28 ✎ Спека погоджена посекційно: hooks/codex.sh (idle-таймаут 120/600 с, код 75 на ліміт), TDD через red/green gate'и, Executor у leonard; codex exec review відкинуто, бо порівнює через GitHub MCP
- 13:28 ● fb50e05 docs(spec): delegate explore, review and simple tasks to codex exec
- 13:35 ● efaeae0 docs(plan): codex exec delegation implementation plan
- 13:35 ✎ План затверджено: 7 задач у 3 хвилі; усі Executor: claude, бо codex.sh ще не встановлений у плагіні
- 13:45 ● 1fb6fa8 test: acceptance tests for codex exec delegation
