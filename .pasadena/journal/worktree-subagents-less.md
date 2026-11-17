---
branch: worktree-subagents-less
spec: docs/sdd/specs/2026-11-17-fold-subagents.md
plan: docs/sdd/plans/2026-11-17-fold-subagents.md
codex-mode: explore
status: in-progress
started: 2026-11-17
---

## Goal
Згорнути субагентів у Pasadena за статтею Anthropic «when to fold subagents into your main agent loop»:
sheldon пише дизайн inline без fan-out, wolowitz виконує хвилю з однією задачею сам через amy,
пара test writer + implementer зливається в одного субагента із захистом від підгонки тестів.
Готово, коли скіли змінено, skills.test.sh зелений, версію плагіна піднято.

## Now
Building. План погоджено: Wave 0 (Task 0, acceptance у skills/skills.test.sh, очікується FAILED: 37), Wave 1 (Tasks 1–5 паралельно). Далі: Wave 0, потім `bash skills/skills.test.sh`.

## Timeline

### 2026-11-17
- 14:37 ✎ codex-mode: explore
- 14:55 ✎ Shaping: обрано SendMessage-чекпоінт + mutator на Gate green проти підгонки тестів; модель злитого агента за Complexity
- 14:55 ● 350130a docs(sdd): spec for folding subagents into the main loop
