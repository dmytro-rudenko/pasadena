---
name: amy
description: Use when the user asks to run a failing test first, write the failing test first, use TDD, implement a feature, or fix a bug. Before implementation, write one test, watch it fail, then write the minimum that passes
---

# Test-driven development

Write the test first. Watch it fail. Write the minimum that passes.

**Core principle:** if you did not watch the test fail, you do not know that it
tests the right thing.

Violating the letter of these rules is violating their spirit.

## The Iron Law

```
NO PRODUCTION CODE WITHOUT A FAILING TEST FIRST
```

Wrote code before the test? Delete it and start over. Not "keep it as
reference", not "adapt it while writing the test", not "look at it once".
Delete means delete — anything else is testing after, wearing a disguise.

## When it applies

**Always:** new features, bug fixes, refactors, behaviour changes.

**Exceptions, and you say them out loud rather than deciding quietly:**

- **Prototypes.** A `penny` variant is thrown away by design — it
  exists to answer a question, not to be maintained. Do not TDD it. When a
  prototype's *behaviour* graduates into the real implementation, that
  implementation is TDD'd from scratch.
- **Generated code and configuration.** Test what consumes them, not them.

Thinking "skip TDD just this once"? That thought is the rationalization, not
the exception.

## Any runner counts

TDD is a sequence, not a framework. Use whatever the repo already runs. If it
has no test framework at all, a script that exits non-zero on a failed
assertion is a test — `hooks/journal.test.sh` in this repo is exactly that,
and it is not a lesser one. Never add a test framework as a side effect of
writing a test; that is a dependency decision, and it belongs to the plan.

## Red → Green → Refactor

### RED — write one failing test

One behaviour. A name that describes that behaviour. Real code, not mocks,
unless a mock is unavoidable.

**Before you write it, name the production change that would make this test
fail.** Say it in one sentence. If you cannot name one, the test asserts
something the code cannot get wrong — it will pass forever and prove nothing.
This single question kills more useless tests than every other rule here.

Three more rules that keep a test honest:

- **Assert on real behaviour, never on mock behaviour.** `expect(mock).toHaveBeenCalledTimes(3)`
  tests your mock. `expect(attempts).toBe(3)` tests the code.
- **Test-only helpers live in test utilities**, never as a hook or a flag on
  the production class. Production code that knows it is under test is lying
  to you in both directions.
- **Understand a dependency's side effects before mocking it.** A mock that
  omits the write, the retry or the throw makes the test pass for a system
  that does not exist.

### Verify RED — watch it fail

**Mandatory. Never skipped, never assumed.** Run it and read the output.

- It must **fail**, not error. An error is usually a typo, not a missing feature.
- The failure message must be the one you predicted.
- It passes already? Then you are testing behaviour that exists. The test is
  wrong — fix the test, not the code.

### GREEN — the minimum that passes

The simplest thing that makes this test pass. No extra parameters, no options
object, no error paths the test does not demand. Those are the next test's job,
if they are anyone's.

### Verify GREEN — watch it pass

Run it again. The new test passes, every other test still passes, and the
output is clean — no stack traces, no warnings you have learned to ignore.

Test still fails? Fix the code, never the test.
Another test broke? Fix it now, not later.

### REFACTOR

Only once green. Remove duplication, improve names, extract helpers. Keep the
tests green and add no behaviour. Then the next failing test.

## Rationalizations

| Excuse | Reality |
|---|---|
| "Too simple to test" | Simple code breaks. The test costs thirty seconds. |
| "I'll test after" | Tests written after pass immediately, which proves nothing. You never watched it fail, so you never proved it can catch the bug. |
| "Tests after achieve the same thing — spirit, not ritual" | Tests-after answer "what does this do?". Tests-first answer "what should this do?". After-the-fact tests are biased by the code you already wrote: you cover the cases you remembered, not the ones you would have discovered. |
| "I already tested it manually" | No record of what you covered, no way to re-run it, easy to forget a case under pressure. "Worked when I tried it" is not coverage. |
| "Deleting X hours of work is wasteful" | Sunk cost. That time is spent either way. The real choice is rewrite with TDD, or keep code you cannot trust and bolt tests onto it. |
| "I'll keep it as reference and write tests first" | You will adapt it. That is testing after. |
| "I need to explore first" | Fine — explore, then throw the exploration away and start with TDD. |
| "This is hard to test" | Listen to that. Hard to test is hard to use; the design is telling you something. |
| "TDD will slow me down" | It is the fast path: bugs caught before the commit, regressions prevented, refactoring without fear. The shortcut is debugging in production. |
| "The existing code has no tests" | You are improving it. Add the test for the part you touch. |

## Red flags — stop and start over

Code before test · test written after implementation · a test that passes the
first time you run it · you cannot explain why it failed · "tests will come
later" · "just this once" · "keep it as reference" · "already spent hours,
deleting is wasteful" · "TDD is dogma, I'm being pragmatic" · "this case is
different because…"

All of these mean the same thing: delete the code, start again with the test.

## When stuck

| Problem | What it means |
|---|---|
| Don't know how to test it | Write the API you wish existed, then the assertion. |
| The test is complicated | The design is complicated. Simplify the interface. |
| I have to mock everything | The code is too coupled. Inject the dependency. |
| The setup is enormous | Extract helpers. Still enormous? The design is wrong. |

## Bug fixes

Never fix a bug without a test. Write the test that reproduces it, watch it
fail — that failure is your proof you found the actual bug and not a
neighbouring one — then fix. The test now also prevents the regression.

## Before calling the work done

- [ ] Every new behaviour has a test
- [ ] You watched each one fail, and the failure was the expected one
- [ ] You wrote the minimum that passed
- [ ] Everything is green and the output is clean
- [ ] Tests assert on real behaviour, not on mocks
- [ ] Edge cases and error paths are covered

Cannot tick them all? You skipped TDD. Start over.
