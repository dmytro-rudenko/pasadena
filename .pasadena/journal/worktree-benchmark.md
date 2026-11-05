---
branch: worktree-benchmark
spec: docs/sdd/specs/2026-11-05-benchmark-harness.md
plan: docs/sdd/plans/2026-11-05-benchmark-harness.md
status: in-progress
started: 2026-11-05
---

## Goal
Пілот benchmark harness для Pasadena: replay власних задач із docs/sdd (spec → claude -p у worktree батьківського коміту, оракул — тести з коміту), кілька конфігурацій-перемикачів, JSONL на прогін і таблиця звіту (якість, токени, USD, час). Готово, коли пілот показує різницю між конфігураціями з повторами.

## Now
Building. План погоджено (9 задач, 5 хвиль), wolowitz стартує з Wave 0. Task 0 — реальний сухий прогін claude -p (формат stream-json, --plugin-dir поверх enabledPlugins:false), фікстури й приймальні тести; стоп-умова: Pasadena не з BENCH_PLUGIN → питання користувачу. Наступне: Wave 0, перевірка `bash bench/bench.test.sh` (очікувано FAILED). Зберегти: збірка закінчується етапом 0 (калібрування) і зупинкою до погодження етапу 1.

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
- 13:51 ● 342150f docs(spec): run the benchmark pilot in gated stages with a report after each
- 13:57 ✎ План погоджено: 9 задач у 5 хвилях; паралельно 1/2/7 і 3/4/5; збірка завершується етапом 0 і зупинкою
