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
1. Building: план затверджено, хвилі 0 → 1 (Tasks 1–5 паралельно) → 2 (E2E зі справжнім codex).
2. Зупинились на: старт Wave 0 (acceptance tests: hooks/codex.test.sh, skills/skills.test.sh).
3. Далі: `bash skills/skills.test.sh` → очікувано `FAILED: 22`. Зберегти: перевірка «Claude Code only» тепер ловить лише артефакти хоста (.codex-plugin|Codex plan mode|Codex workflow).

## Timeline

### 2026-10-23
- 13:09 ✎ Shaping: задачу класифіковано як Architectural, журнал відкрито
- 13:28 ✎ Спека погоджена посекційно: hooks/codex.sh (idle-таймаут 120/600 с, код 75 на ліміт), TDD через red/green gate'и, Executor у leonard; codex exec review відкинуто, бо порівнює через GitHub MCP
- 13:28 ● fb50e05 docs(spec): delegate explore, review and simple tasks to codex exec
