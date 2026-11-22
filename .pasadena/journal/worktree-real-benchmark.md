---
branch: worktree-real-benchmark
spec: docs/sdd/specs/2026-11-22-real-benchmark.md
plan: -
codex-mode: full
status: in-progress
started: 2026-11-22
---

## Goal
Виміряти, наскільки skills pasadena впливають на якість результату: знайти або
придумати складний SWE + Agentic Coding бенчмарк із відомим baseline без skills,
реалізувати його з pasadena і порівняти. Перезапуск бенчмарку через `npm run`.

## Now
Shaping завершено: спеку docs/sdd/specs/2026-11-22-real-benchmark.md
погоджено в чаті, builder-check закрито власними рішеннями. Чекаємо на
відгук на спеку і draft PR. Далі: leonard → план. Зберегти без змін: обидва
arm на одному config.json; жодного тихого деградування arm pasadena.

## Timeline


### 2026-11-22
- 11:25 ✎ codex-mode: full
- 11:37 ✎ Spec: Terminal-Bench 2.0 via Harbor 0.27, baseline vs pasadena arm, npm run bench:*; builder-check 7 calls settled
