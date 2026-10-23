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
Shaping завершено: погоджено Codex CLI, спільний workflow з адаптерами, контракт із обмеженням StopFailure та критерії приймання. Спеку записано, перечитано й закомічено: 2a35194. Структурна перевірка та git diff --cached --check пройшли.
Push до origin (git@github.com:dmytro-rudenko/pasadena.git), гілка spec/codex-parity, відхилено automatic approval review: потрібна окрема згода на передачу спеки й журналу зовнішньому GitHub remote через можливі приватні деталі. Push не виконано, draft PR не створено. Підготовлений PR body: /tmp/pasadena-codex-parity-pr-body.md; його можна відтворити зі спеки. Реалізація та runtime acceptance не виконувались.
Наступний крок: отримати явний дозвіл користувача на push цих двох файлів до зазначеної гілки й створення draft PR; до цього не повторювати export іншим способом. Потім перегляд записаної спеки перед leonard. Перед продовженням: git status --short і git log -2 --oneline. Зберегти обмеження StopFailure; не починати реалізацію до погодженого плану.

## Timeline

### 2026-10-23
- 15:02 ✎ Shaping: створено ізольований worktree; перевірено видалення Codex у bde598c та залежності hooks, планування й моделей агентів. Потрібно погодити цільові середовища Codex.
- 15:04 ✎ Ціль підтверджено: Codex CLI. Перевірено 0.164.0, plugin add, stable hooks/multi_agent, /plan та події hooks. Потрібно погодити спільний workflow з адаптерами; StopFailure лишається розривом сумісності.
- 15:07 ✎ Погоджено варіант 1: спільний workflow з адаптерами Claude/Codex. Перевірено межі hooks: SessionEnd reason=other; Stop не є StopFailure; Interrupt не передає error_type. Наступне погодження — контракт сумісності.
- 15:09 ✎ Користувач погодив контракт Codex CLI та обмеження StopFailure. Зіставлено наявні test scripts; залишилось останнє погодження критеріїв перевірки перед записом специфікації.
- 15:14 ✎ Користувач погодив критерії приймання. Специфікацію Codex CLI записано й перечитано; код і тести не змінено. Наступний етап після перегляду файлу — leonard.
- 15:16 ✎ Спеку закомічено: 2a35194, структурна перевірка і diff check пройшли. Automatic approval review відхилив push спеки й журналу до origin через відсутність окремої згоди на external export; draft PR не створено.
