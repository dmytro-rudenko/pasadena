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
Finish. Усі хвилі закриті (остання — Task 4 `202c3ac`), усі три набори тестів зелені.
Next: whole-branch review (`sonnet` xhigh) + `security-review` над `git merge-base origin/main HEAD..HEAD`; Codex-рев'ю пропущено, бо `codex.sh available` повертає 1.

## Timeline

### 2026-11-03
- 17:23 ✎ Shaping: дизайн codex-mode (explore/full/auto) затверджено в чаті
- 17:24 ● 5818fd3 docs(spec): codex-mode command with explore, full and auto modes
- 17:31 ● ca1abbd docs(spec): fit codex-mode full into the Codex usage budget
- 17:31 ✎ Spec: full/auto розподіляє завдання Codex у межах тижневого ліміту (codex.sh budget + cost estimate), сторож перед кожним Codex-завданням
- 17:43 ● 400fe7e docs(plan): codex-mode implementation plan
- 17:43 ✎ Plan: 12 задач у 4 хвилях; codex.sh mode/budget/cost, journal.sh codex-mode, /codex-mode, правки sheldon/raj/leonard/wolowitz/amy, README, 0.21.0
- 17:46 ● ebe8b4f test(codex-mode): acceptance checks for codex modes
- 17:46 ● a5f16f6 chore(plan): close wave 0
- 17:46 ✎ Wave 0: 23 acceptance-перевірки червоні з передбаченої причини, рев'ю чисте
- 17:51 ● 5c13aaf feat(codex): codex.sh mode get/set for the global Codex mode
- 17:51 ● 1b3d566 feat(sheldon): resolve codex-mode auto from the classification
- 17:51 ● 2faba02 feat(raj): record the branch codex-mode through journal.sh
- 17:51 ● 3eed0f9 feat(leonard): plan codex-mode full within the Codex budget
- 17:51 ● adc3b3a feat(wolowitz): build codex-mode full with a budget guard
- 17:51 ● ee8c452 feat(amy): run a bounded change through Codex in codex-mode full
- 17:51 ● 7d138f2 docs(readme): document codex modes and the usage budget
- 17:51 ● 11ead3d chore(release): bump pasadena to 0.21.0
- 17:51 ● 6963065 chore(plan): close wave 1
- 17:51 ✎ Wave 1: 8 задач; два дефекти плану вирішено ухвалами — raj без літерала journal.sh codex-mode, wolowitz >20000 байт (блок full перенесено в codex-tasks.md)
- 17:55 ● ab47f43 feat(codex): codex.sh budget and cost for the Codex usage limit
- 17:55 ● f71c2ba feat(journal): branch codex-mode field and digest line
- 17:56 ● 84a3f75 chore(plan): close wave 2
- 17:56 ✎ Wave 2: budget/cost і journal codex-mode зелені; ізоляція XDG_STATE_HOME прибрала 3 базові падіння; budget на реальних даних дає weekly_left=0
- 17:57 ● 202c3ac feat(commands): /codex-mode shows and sets the Codex mode
