---
branch: worktree-advisor
spec: docs/sdd/specs/2026-11-01-skill-model-routing.md
plan: docs/sdd/plans/2026-11-01-skill-model-routing.md
status: in-progress
started: 2026-11-01
---

## Goal
Переглянути розподіл моделей та effort у skills Pasadena: Sonnet xhigh, Opus medium, Opus high (тести — Opus high), без Haiku, з урахуванням advisor-режиму Claude Code.
Готово, коли є узгоджена специфікація і skills оновлені за нею з підвищенням version.

## Now
Фаза shaping завершується: spec написано, draft PR відкрито. Очікуємо рев'ю spec користувачем. Далі: після явного схвалення передати роботу в `leonard`.

## Timeline

### 2026-11-01
- 09:20 ● 3f598a7 chore(journal): close codex exec delegation
- 09:20 ● 9fd8932 Merge pull request #15 from dmytro-rudenko/worktree-codex-exec
- 09:20 ● 50092d7 fix: surface Codex availability in the session digest
- 09:20 ● 2abeb95 Merge pull request #17 from dmytro-rudenko/worktree-codex-discoverability
- 09:20 ● a556a85 feat(hooks): stream a live Codex session log to the console
- 09:20 ● 04f4986 Merge pull request #18 from dmytro-rudenko/worktree-codex-log
- 09:20 ● 99abcf2 feat(wolowitz): switch wave and whole-branch review to sonnet at effort xhigh
- 09:20 ● 94e70da Merge pull request #20 from dmytro-rudenko/feature/wolowitz-sonnet-reviewer
- 09:20 ● 150a640 feat(wolowitz): move Codex review from each wave to whole-branch finish
- 09:20 ● d2f48e3 Merge pull request #21 from dmytro-rudenko/feature/wolowitz-codex-review-finish
- 09:32 ✎ Shaping: маршрутизація лише через явні model/effort у dispatch; Complexity у leonard; advisor і frontmatter відкинуто
- 09:33 ● 4ab6c1c docs(sdd): spec for per-task model and effort routing
