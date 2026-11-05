---
branch: worktree-benchmark
spec: docs/sdd/specs/2026-11-05-benchmark-harness.md
plan: -
status: in-progress
started: 2026-11-05
---

## Goal
Пілот benchmark harness для Pasadena: replay власних задач із docs/sdd (spec → claude -p у worktree батьківського коміту, оракул — тести з коміту), кілька конфігурацій-перемикачів, JSONL на прогін і таблиця звіту (якість, токени, USD, час). Готово, коли пілот показує різницю між конфігураціями з повторами.

## Now
Shaping завершено: spec записана і пройшла builder check, чекає рев'ю користувача в draft PR. Рішення: 5 комірок (baseline off/plain; plugin, noreuse, codexfull, haiku — workflow-промпт), Codex вимкнений скрізь, крім codexfull; ізоляція історії через git archive; калібрування оракула. Наступне: правки до spec від користувача, потім leonard. Задача 0 плану — сухий прогін, що звіряє формат stream-json і завантаження --plugin-dir поверх enabledPlugins:false.

## Timeline

### 2026-11-05
- 13:32 ✎ Спайк: benchmarkів немає; з DOU 62922 беремо оракул із тестів, одну зміну за раз, повтори, діагностику за місцем втрати
- 13:32 ● 42f8e3a feat: add plugin icon for the Claude directory listing
- 13:32 ● 79a4198 Merge pull request #32 from dmytro-rudenko/fix/nudge-validator
- 13:32 ● 074f8e0 chore: clear Claude directory validator findings
- 13:32 ● f381be7 chore(wolowitz): keep SKILL.md under the 20 KB compaction limit
- 13:32 ● b1e8a5c chore: keep the icon's red nucleus in the palette PNG
- 13:32 ● 474a1d2 Merge pull request #33 from dmytro-rudenko/chore/directory-clean
- 13:32 ● 729eaef docs: add listing links and a privacy note for the Claude directory
- 13:32 ● 5444d62 Merge pull request #34 from dmytro-rudenko/chore/listing-links
- 13:32 ● b1af99a feat(hooks): set per-call reasoning effort and model overrides for Codex delegation
- 13:32 ● a0d543f Merge pull request #35 from dmytro-rudenko/worktree-codex-model
- 13:46 ✎ Spec погоджено в діалозі: workflow-промпт для plugin-комірок, Codex лише в codexfull, оракул — кінчик гілки PR з калібруванням, ізоляція історії
- 13:46 ● 95e3e28 docs(spec): benchmark harness pilot for measuring Pasadena against plain Claude Code
- 13:51 ✎ Spec: пілот іде етапами 0–5, після кожного — звіт report.sh у PR і зупинка до погодження користувача
