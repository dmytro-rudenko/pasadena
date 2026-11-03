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
Building. Wave 0 закрита (`ebe8b4f`): `skills.test.sh` червоний рівно на 23 acceptance-перевірках. GROUP_BASE: (запишеться на старті Wave 1).
Next: Wave 1 — задачі 1, 5–11 паралельно; перевірка `bash hooks/codex.test.sh`, `bash skills/skills.test.sh`.

## Timeline

### 2026-11-03
- 17:23 ✎ Shaping: дизайн codex-mode (explore/full/auto) затверджено в чаті
- 17:24 ● 5818fd3 docs(spec): codex-mode command with explore, full and auto modes
- 17:31 ● ca1abbd docs(spec): fit codex-mode full into the Codex usage budget
- 17:31 ✎ Spec: full/auto розподіляє завдання Codex у межах тижневого ліміту (codex.sh budget + cost estimate), сторож перед кожним Codex-завданням
- 17:43 ● 400fe7e docs(plan): codex-mode implementation plan
- 17:43 ✎ Plan: 12 задач у 4 хвилях; codex.sh mode/budget/cost, journal.sh codex-mode, /codex-mode, правки sheldon/raj/leonard/wolowitz/amy, README, 0.21.0
- 17:46 ● ebe8b4f test(codex-mode): acceptance checks for codex modes
