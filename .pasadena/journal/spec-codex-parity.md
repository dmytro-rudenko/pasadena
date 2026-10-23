---
branch: spec/codex-parity
spec: docs/sdd/specs/2026-10-23-codex-cli-parity.md
plan: -
status: in-progress
started: 2026-10-23
---

## Goal
Підготувати погоджену специфікацію адаптації Pasadena для Codex зі збереженням поведінки плагіна.
Визначити відповідність скілів, hooks, журналу, worktree, планування та перевірок.

## Now
Спеку явно затверджено; користувач дозволив push спеки й журналу та доручив планування через skills/leonard/SKILL.md. Гілку опубліковано, draft PR #16: https://github.com/dmytro-rudenko/pasadena/pull/16. EnterPlanMode у сесії відсутній; застосовано chat fallback leonard.
План підготовлено для погодження в чаті: Task 0 acceptance, Task 1 packaging/adapters/self-check, Tasks 2–6 core skills/builder/browser/nudge/journal, Task 7 README, Task 8 runtime verification. 5 хвиль (0; 1; 2–6; 7; 8), 33 неперетинні Writes. Запропонований lock: flock -x -w 2 у per-worktree Git dir, залежність явно документується. Baseline: journal/nudge/proto — All checks passed.; skills — FAILED: 1 через стару перевірку Claude Code only, яка зачіпає цей журнал; Task 1 усуває її. Код і тести не змінено.
Наступний крок: дочекатися затвердження плану. Після нього записати docs/sdd/plans/2026-10-23-codex-cli-parity.md, через raj встановити plan:, закомітити й завантажити wolowitz для Wave 0. До цього plan: лишається -. Зберегти погоджене обмеження StopFailure й окрему реальну runtime-перевірку; shell fixtures не замінюють перевірку CLI.

## Timeline

### 2026-10-23
- 15:02 ✎ Shaping: створено ізольований worktree; перевірено видалення Codex у bde598c та залежності hooks, планування й моделей агентів. Потрібно погодити цільові середовища Codex.
- 15:04 ✎ Ціль підтверджено: Codex CLI. Перевірено 0.164.0, plugin add, stable hooks/multi_agent, /plan та події hooks. Потрібно погодити спільний workflow з адаптерами; StopFailure лишається розривом сумісності.
- 15:07 ✎ Погоджено варіант 1: спільний workflow з адаптерами Claude/Codex. Перевірено межі hooks: SessionEnd reason=other; Stop не є StopFailure; Interrupt не передає error_type. Наступне погодження — контракт сумісності.
- 15:09 ✎ Користувач погодив контракт Codex CLI та обмеження StopFailure. Зіставлено наявні test scripts; залишилось останнє погодження критеріїв перевірки перед записом специфікації.
- 15:14 ✎ Користувач погодив критерії приймання. Специфікацію Codex CLI записано й перечитано; код і тести не змінено. Наступний етап після перегляду файлу — leonard.
- 15:16 ✎ Спеку закомічено: 2a35194, структурна перевірка і diff check пройшли. Automatic approval review відхилив push спеки й журналу до origin через відсутність окремої згоди на external export; draft PR не створено.
- 15:26 ✎ Спеку затверджено, push явно дозволено й виконано; відкрито draft PR #16. План leonard: 9 задач, 5 хвиль, 33 файли, очікує погодження в чаті; plan: не встановлено. Baseline journal/nudge/proto green; skills має одну відому помилку Claude Code only через журнал.
