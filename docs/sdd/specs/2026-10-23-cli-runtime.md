# CLI runtime arithmetic — design

**Date:** 2026-10-23
**Status:** agreed

## 1. Problem
This disposable architectural acceptance fixture must demonstrate the installed
Pasadena Codex workflow: tests first, concurrent independent tasks, controller
verification, independent review, and journal recovery and finish in a test PR.
The checkout currently has no tests/cli-runtime/ subsystem.

## 2. Constraint that shapes the solution
Reuse the isolated branch test/codex-cli-runtime-20261023. Only the remote
repository dmytro-rudenko/pasadena is authorized, for a disposable draft PR.
No merge or publish. Existing Pasadena implementation files remain untouched.
The architectural classification intentionally exercises the full workflow.

## 3. Solution
Create two independent CommonJS modules with direct function exports:
- tests/cli-runtime/sum.js: module.exports = sum; sum(a,b) returns a + b.
- tests/cli-runtime/double.js: module.exports = double; double(n) returns n * 2.
Each operand must satisfy Number.isInteger; otherwise throw TypeError.
Use direct JavaScript Number arithmetic without extra safe-integer restrictions.
Neither module depends on the other or any third-party package.

Use tests/cli-runtime/acceptance.cjs with node:assert/strict. Task0/Wave0
creates acceptance tests only and records a genuine RED run before either module
exists. Wave1 runs two implementers concurrently, with disjoint Writes for
sum.js and double.js. The controller verifies the full runner and commits each
task separately. Review runs in a separate context with only the spec, plan,
diff and verification evidence. Preserve recovery state in the journal and
finish with the test PR remaining a draft, as explicitly required by the user.

## 4. Out of scope
UI, dependencies, changes to Pasadena implementation, safe-integer enforcement,
merging, publishing, and modifications on any other branch or remote.

## 5. Trade-offs accepted
Direct Number arithmetic follows JavaScript rounding and overflow behavior.
This keeps the arithmetic tiny so workflow evidence remains the fixture's focus.
Rejecting invalid input with TypeError provides a consistent interface.

## 6. Verification
- sum handles positive, negative and zero operands with the expected Number sum.
- double handles positive, negative and zero operands with the expected product.
- Both reject fractions, NaN, infinities, strings, null, undefined, booleans,
  objects and BigInt with TypeError; sum validates either operand.
- node tests/cli-runtime/acceptance.cjs exits nonzero before implementation and
  exits zero with final line "All checks passed." after both modules exist.
- Record real overlapping implementer execution, disjoint Writes, per-task
  commits, controller full verification, and independent review evidence.
- Recover from journal Now, plan checkboxes and git log before journal finish;
  summarize evidence in the draft PR and remove the active journal on finish.
