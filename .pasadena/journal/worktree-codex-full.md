---
branch: worktree-codex-full
spec: docs/sdd/specs/2026-11-03-codex-mode.md
plan: -
status: in-progress
started: 2026-11-03
---

## Goal
Команда `/codex-mode` з режимами `explore` (поточна поведінка), `full` (Codex виконує задачі, Claude лише планує, гейтить і рев'юїть) та `auto` (sheldon обирає режим за класифікацією і ризиками задачі).
Готово, коли режими зберігаються (глобально + поле `codex-mode:` журналу), skills їх дотримуються, тести зелені, README оновлено, версію піднято.

## Now
Spec написано: `docs/sdd/specs/2026-11-03-codex-mode.md`, draft PR відкрито. Чекаю на відгук користувача щодо специфікації.
Next: після схвалення — `leonard` пише план у `docs/sdd/plans/2026-11-03-codex-mode.md`.

## Timeline

### 2026-11-03
- 17:23 ✎ Shaping: дизайн codex-mode (explore/full/auto) затверджено в чаті
