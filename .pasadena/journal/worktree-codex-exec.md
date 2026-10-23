---
branch: worktree-codex-exec
spec: docs/sdd/specs/2026-10-23-codex-exec-delegation.md
plan: -
status: in-progress
started: 2026-10-23
---

## Goal
Дати skills Pasadena змогу делегувати прості explore/read задачі в `codex exec`,
щоб економити ліміти Claude; Claude лишається оркестратором.
Готово, коли є погоджена специфікація, реалізація за планом і перевірка.

## Now
1. Shaping завершено: спека docs/sdd/specs/2026-10-23-codex-exec-delegation.md написана, усі 4 секції погоджено.
2. Зупинились на: користувач має переглянути спеку і draft PR.
3. Далі: після схвалення спеки — leonard (план). Зберегти: TDD для Codex забезпечує контролер (red/green + gate'и), review — через локальний git diff у stdin, не `codex exec review`.

## Timeline

### 2026-10-23
- 13:09 ✎ Shaping: задачу класифіковано як Architectural, журнал відкрито
- 13:28 ✎ Спека погоджена посекційно: hooks/codex.sh (idle-таймаут 120/600 с, код 75 на ліміт), TDD через red/green gate'и, Executor у leonard; codex exec review відкинуто, бо порівнює через GitHub MCP
