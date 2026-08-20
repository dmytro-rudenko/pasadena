---
name: amy
description: Use when the user asks to run a failing test first, write the failing test first, use TDD, implement a feature, or fix a bug. Before implementation, write one test, watch it fail, then write the minimum that passes
---

# Test-driven development

Write the test first. Watch it fail. Write the minimum that passes.

**Core principle:** watching the test fail for the predicted reason proves that
it tests the right thing.

Following the full sequence preserves both the letter and the spirit of these
rules.

## The Iron Law

```
A FAILING TEST ALWAYS PRECEDES PRODUCTION CODE
```

Production code written before its test is discarded, and the cycle starts
again with the failing test. A fresh start keeps the test independent of the
implementation and preserves the tests-first sequence.

## When it applies

**Always:** new features, bug fixes, refactors, behaviour changes.

**Exceptions are always stated out loud:**

- **Prototypes.** A `penny` variant is thrown away by design — it
  exists to answer a question and remains outside the maintained product. TDD
  begins from scratch when a prototype's *behaviour* graduates into the real
  implementation.
- **Generated code and configuration.** Tests cover the code that consumes
  them.

Only the stated exceptions alter the TDD sequence.

## Any runner counts

TDD is a sequence that works with any framework. Use whatever the repo already
runs. If it has yet to adopt a test framework, a script that exits non-zero on
a failed assertion is a test — `hooks/journal.test.sh` in this repo is exactly
that, and it counts equally. The repository's existing runner remains in use;
a new test framework enters through an explicit dependency decision in the
plan.

## Red → Green → Refactor

### RED — write one failing test

One behaviour. A name that describes that behaviour. Use real code, with mocks
reserved for unavoidable boundaries.

**Before you write it, name the production change that would make this test
fail.** Say it in one sentence. A valid test always names a production change
that could make it fail; this keeps the assertion tied to behaviour the code
can get wrong.

Three more rules that keep a test honest:

- **Assert on real behaviour.** `expect(attempts).toBe(3)` tests the code;
  `expect(mock).toHaveBeenCalledTimes(3)` describes the substitute.
- **Test-only helpers live in test utilities.** Production classes remain free
  of test hooks and flags, so their behaviour stays identical in every
  environment.
- **Understand a dependency's side effects before mocking it.** A faithful mock
  reproduces the write, retry and throw that affect the behaviour under test.

### Verify RED — watch it fail

**Mandatory. Always run it and read the output.**

- The missing behaviour must produce a **failure**. Runtime and syntax errors
  are corrected first so the test reaches its assertion.
- The failure message must be the one you predicted.
- An initial pass proves that the behaviour already exists. Choose a test that
  exposes the missing behaviour while production code remains unchanged.

### GREEN — the minimum that passes

The simplest thing that makes this test pass. The change includes only the
parameters, options and error paths the current test demands. Later tests can
expand that scope when the behaviour requires it.

### Verify GREEN — watch it pass

Run it again. The new test passes, every other test still passes, and the
output is clean and expected.

If the test still fails, continue changing the production code while the test
remains fixed. If another test breaks, restore the full suite immediately.

### REFACTOR

Only once green. Remove duplication, improve names, extract helpers. Keep the
tests green and keep behaviour unchanged. Then the next failing test.

## Decision rules

| Situation | Rule |
|---|---|
| The behaviour looks simple | Write the small test; simple code still benefits from a thirty-second regression check. |
| Implementation exists before its test | Discard the implementation and restart with the failing test so the test proves it can catch the bug. |
| Tests-after appears equivalent | Tests-first answers "what should this do?" before implementation can bias which cases are covered. |
| A manual check already passed | Add a repeatable automated record that runs consistently under pressure. |
| Significant implementation time is already spent | Treat that time as sunk cost and choose the trustworthy TDD rewrite. |
| Early code seems useful as a reference | Discard it so the test remains independent of the implementation. |
| Exploration is needed first | Explore freely, discard the exploration, and begin maintained work with TDD. |
| The behaviour is hard to test | Simplify the interface; test difficulty exposes design difficulty. |
| TDD appears slower | Use the fast path that catches bugs before commit, prevents regressions and supports safe refactoring. |
| The existing area lacks tests | Add the test for the part being changed. |

## Sequence acceptance gate

A valid cycle has a test written first, an initial failure for the predicted
reason, a clear explanation of that failure, and only then the minimum
production change. Every test remains part of the maintained suite. When any
part of this sequence is missing, discard the production change and restart
with the test.

## When stuck

| Problem | What it means |
|---|---|
| The test shape is unclear | Write the API you wish existed, then the assertion. |
| The test is complicated | The design is complicated. Simplify the interface. |
| The test requires mocks for every dependency | The code is too coupled. Inject the dependency. |
| The setup is enormous | Extract helpers. If it stays enormous, simplify the design. |

## Bug fixes

Every bug fix begins with a test that reproduces it. Watch it fail — that
failure proves you found the actual bug rather than a neighbouring one — then
fix it. The test now also prevents the regression.

## Before calling the work done

- [ ] Every new behaviour has a test
- [ ] You watched each one fail, and the failure was the expected one
- [ ] You wrote the minimum that passed
- [ ] Everything is green and the output is clean
- [ ] Tests assert on real behaviour
- [ ] Edge cases and error paths are covered

Completion begins after every box is ticked. Otherwise, restart with the test.
