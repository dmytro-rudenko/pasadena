---
branch: worktree-codex-full
spec: docs/sdd/specs/2026-11-03-codex-mode.md
plan: docs/sdd/plans/2026-11-03-codex-mode.md
status: in-progress
started: 2026-11-03
---

## Goal
Команда `/codex-mode` з режимами `explore` (поточна поведінка), `full` (Codex виконує задачі, Claude лише планує, гейтить і рев'юїть) та `auto` (sheldon обирає режим за класифікацією і ризиками задачі).
Готово, коли режими зберігаються (глобально + поле `codex-mode:` журналу), skills їх дотримуються, тести зелені, README оновлено, версію піднято.

## Now
Building. План затверджено: 12 задач у 4 хвилях, усі `claude` (Codex вичерпано). Wave 0 — acceptance-перевірки в `skills/skills.test.sh`.
Next: wolowitz, Wave 0; перевірка `bash skills/skills.test.sh` → `FAILED: 23`.

## Timeline

### 2026-11-03
- 17:23 ✎ Shaping: дизайн codex-mode (explore/full/auto) затверджено в чаті
- 17:24 ● 5818fd3 docs(spec): codex-mode command with explore, full and auto modes
- 17:31 ● ca1abbd docs(spec): fit codex-mode full into the Codex usage budget
- 17:31 ✎ Spec: full/auto розподіляє завдання Codex у межах тижневого ліміту (codex.sh budget + cost estimate), сторож перед кожним Codex-завданням
