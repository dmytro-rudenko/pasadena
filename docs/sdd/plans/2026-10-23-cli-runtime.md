# CLI runtime arithmetic — implementation plan

**Goal:** Demonstrate tests-first, concurrent independent implementation and recovery in disposable draft PR #19.
**Spec:** docs/sdd/specs/2026-10-23-cli-runtime.md
**Verification:** `node tests/cli-runtime/acceptance.cjs`; final line `All checks passed.`, exit 0 after Wave1. Wave0 intentionally exits nonzero for missing modules.

## Waves
| Wave | Tasks | Why together |
|---|---|---|
| 0 | 0 | Acceptance runner alone establishes RED before production files exist. |
| 1 | 1, 2 | Disjoint Writes; neither function consumes the other. Dispatch concurrently. |

## Global constraints
Use only test/codex-cli-runtime-20261023 and dmytro-rudenko/pasadena. Keep PR #19 draft; no merge/publish. Do not edit existing Pasadena implementation files. No dependencies or UI. Inputs satisfy Number.isInteger, invalid operands throw TypeError, results use direct Number arithmetic without safe-integer restrictions. Direct CommonJS function exports. Fully load installed Amy and Codex adapter before any test/code edit. Implementers return uncommitted changes; controller verifies, independently reviews including task-owned untracked contents, and commits tasks separately. All tasks read this plan and the spec. Record actual concurrent Wave1 execution. User explicitly requests a recovery pause after committed Wave0, before dispatching Wave1; this is not another approval gate.

### Task 0: acceptance runner (RED only)
**Writes:** tests/cli-runtime/acceptance.cjs
**Reads:** docs/sdd/specs/2026-10-23-cli-runtime.md, docs/sdd/plans/2026-10-23-cli-runtime.md
**Depends on:** none
**Interfaces:** Produces selected `sum` and `double` suites; no argument runs both. Uses node:assert/strict. Reports failure for each missing module; full success ends `All checks passed.`.
**Covers:** positive, negative and zero results for both functions; TypeError for fractions, NaN, infinities, strings, null, undefined, booleans, objects and BigInt; sum validates either operand. Direct exports and Number arithmetic.
- [x] Write acceptance runner with independent selected suites and explicit behavioral assertions.
- [x] Run `node tests/cli-runtime/acceptance.cjs` before either production module exists; expect nonzero and missing-module evidence for both suites.
- [x] Controller verifies RED, reviewer inspects all task-owned untracked contents, controller commits Task0.
**Commit:** test(cli-runtime): add arithmetic acceptance runner before implementation to establish independent sum and double contracts, reject invalid operands, support focused verification, and preserve genuine red evidence for the disposable workflow recovery fixture

### Task 1: sum
**Writes:** tests/cli-runtime/sum.js
**Reads:** docs/sdd/specs/2026-10-23-cli-runtime.md, docs/sdd/plans/2026-10-23-cli-runtime.md, tests/cli-runtime/acceptance.cjs
**Depends on:** Task 0
**Interfaces:** Produces `module.exports = sum`; `sum(a,b)` validates both operands with Number.isInteger, throws TypeError for invalid input, returns `a + b`. No module dependencies.
**Satisfies:** sum suite from Task0.
- [x] Run `node tests/cli-runtime/acceptance.cjs sum`; observe RED before writing sum.js.
- [x] Implement only sum.js with the specified direct export and behavior.
- [x] Run `node tests/cli-runtime/acceptance.cjs sum`; expect `All checks passed.`, exit 0; return uncommitted changes and exact output.
**Commit:** feat(cli-runtime): implement independent sum function with integer operand validation and direct Number addition so the focused acceptance contract passes while preserving isolated file ownership for concurrent workflow verification in the disposable fixture

### Task 2: double
**Writes:** tests/cli-runtime/double.js
**Reads:** docs/sdd/specs/2026-10-23-cli-runtime.md, docs/sdd/plans/2026-10-23-cli-runtime.md, tests/cli-runtime/acceptance.cjs
**Depends on:** Task 0
**Interfaces:** Produces `module.exports = double`; `double(n)` validates Number.isInteger, throws TypeError for invalid input, returns `n * 2`. No module dependencies.
**Satisfies:** double suite from Task0.
- [x] Run `node tests/cli-runtime/acceptance.cjs double`; observe RED before writing double.js.
- [x] Implement only double.js with the specified direct export and behavior.
- [x] Run `node tests/cli-runtime/acceptance.cjs double`; expect `All checks passed.`, exit 0; return uncommitted changes and exact output.
**Commit:** feat(cli-runtime): implement independent double function with integer operand validation and direct Number multiplication so the focused acceptance contract passes while preserving isolated file ownership for concurrent workflow verification in the disposable fixture

## Controller verification, review and finish
- [x] Verify full runner, reconcile Writes and record actual overlapping Wave1 execution; independently review before sequential Task1 and Task2 commits.
- [x] Whole-branch review in a separate context with spec, plan, diff and verification evidence; resolve findings and repeat affected checks.
- [x] Reconcile journal Now, plan checkboxes and git log for recovery; summarize evidence and unavailable security-review skill in PR.

## Requested pre-finish checkpoint
All implementation and review tasks are complete. Per the user's second explicit checkpoint, journal closure is a deferred lifecycle action, not an incomplete implementation task: pause before journal finish; the next fresh Pasadena entry routes all-checked state to journal finish. Keep the active journal in-progress and PR #19 draft until that entry. Security-review skill is unavailable; no substitute security review is claimed.
