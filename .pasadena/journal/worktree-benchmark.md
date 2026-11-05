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
Building. Waves 0–2 закриті (Task 0–5, 7): червоні лише 8 приймальних перевірок report. GROUP_BASE: dae81ba. Наступне: Wave 3 — Task 6 (report.sh), потім групове рев'ю хвиль 1–3 (git diff dae81ba; окремо — порядок no events/timeout у score.sh); перевірка `bash bench/bench.test.sh && bash skills/skills.test.sh`. Зберегти: --settings вимикає обидва ключі pasadena@pasadena і pasadena@synced; збірка закінчується етапом 0 і зупинкою до погодження етапу 1.

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
- 13:57 ● cb9e526 docs(plan): benchmark harness implementation plan
- 14:00 ▶ start · worktree-benchmark @ cb9e526
- 14:00 ⏸ pause · exit · HEAD=cb9e526
  ↳ Building. План погоджено (9 задач, 5 хвиль), wolowitz стартує з Wave 0. Task 0 — реальний сухий прогін claude -p (формат stream-json, --plugin-dir поверх enabledPlugins:false), фікстури й приймальні т
- 14:01 ✎ Сухий прогін: встановлена Pasadena має джерело pasadena@synced — вимикаємо обидва ключі; --plugin-dir бере worktree; при бюджет-стопі usage=0, токени з modelUsage
- 14:01 ● afb3d6b docs(spec): disable both Pasadena sources in the baseline and read budget-stop tokens from modelUsage
- 14:05 ● ba971a4 test(bench): acceptance tests and stream-json fixtures from a real dry run
- 14:06 ✎ Wave 0: приймальні тести й фікстури з реального сухого прогону; червоні рівно 21 перевірка з передбачених причин
- 14:06 ● dae81ba chore(plan): close wave 0
- 14:10 ● cbb5a15 feat(bench): shared library, task and config tables
- 14:10 ● 4852d27 feat(bench): score a stored run without regenerating it
- 14:10 ● 629ee61 docs: document the benchmark harness and bump to 0.24.0
- 14:10 ✎ Wave 1: lib.sh, score.sh і README/0.24.0 зелені; score детермінований і бере токени з modelUsage при бюджет-стопі
- 14:10 ● 0188519 chore(plan): close wave 1
- 14:16 ● 2774cb8 feat(bench): run one task in one cell end to end
- 14:16 ● 4b753d5 feat(bench): calibrate oracles before the pilot
- 14:16 ● 7616227 feat(bench): resumable matrix of tasks, cells and reps
- 14:16 ✎ Wave 2: run.sh, calibrate.sh, matrix.sh зелені; приймальні 1–3 зелені; холдаут переходить на останню збережену задачу
