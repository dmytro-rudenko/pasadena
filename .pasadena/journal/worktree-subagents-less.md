---
branch: worktree-subagents-less
spec: docs/sdd/specs/2026-11-17-fold-subagents.md
plan: -
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
Spec написано й погоджено в чаті (підхід A: SendMessage-чекпоінт + mutation на Gate green, модель за Complexity, однозадачна хвиля inline, sheldon без fan-out). Чекаємо рев'ю spec у draft PR. Далі: leonard → план.

## Timeline

### 2026-11-17
- 14:37 ✎ codex-mode: explore
- 14:55 ✎ Shaping: обрано SendMessage-чекпоінт + mutator на Gate green проти підгонки тестів; модель злитого агента за Complexity
