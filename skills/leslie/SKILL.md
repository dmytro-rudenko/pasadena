---
name: leslie
description: Use when the user reports a bug, a test fails for an unexpected reason, a build or verification is red, or behaviour differs from what was expected. Finds the root cause in four phases before any fix
allowed-tools:
  - Bash(bash ${CLAUDE_PLUGIN_ROOT}/hooks/codex.sh *)
---
<!-- Adapted from obra/superpowers systematic-debugging (MIT); modified. See THIRD_PARTY_NOTICES.md. -->

# Systematic debugging

Find the root cause. Then fix it, once.

**Core principle:** random fixes waste time and create new bugs. A fix aimed
at a symptom moves the failure somewhere else; a fix aimed at the cause
removes it.

This skill declares no tool rules. It is a technique applied inside whichever
skill or implementer is already running, and it hands the fix to `amy` in the
same turn; a scope declared here would narrow the caller's for the rest of the
turn and block that hand-off.

## The Iron Law

```
NO FIX WITHOUT A ROOT CAUSE
```

Until Phase 1 has produced a cause you can state in one sentence, no change to
production code is proposed or made.

## When it applies

**Always:** test failures, bugs, unexpected behaviour, build failures, red
verification runs.

**Especially when:**

- Time is short and guessing feels faster.
- One quick fix looks obvious.
- A fix has already been tried and did not work.
- You do not fully understand why the failure happens.

A simple-looking bug still has a root cause, and Phase 1 finds it quickly.

## Phase 1 — Root cause

1. **Read the error in full.** The whole message, every warning, the complete
   stack trace. Note file paths, line numbers and error codes; the answer is
   often already printed.
2. **Reproduce it reliably.** Write down the exact steps. If it does not
   happen every time, gather more data until it does; a failure you cannot
   trigger cannot be confirmed fixed.
3. **Check what changed.** `git diff`, `git log`, new dependencies, config and
   environment differences. A recent change is the cheapest suspect.
4. **Instrument component boundaries.** When the failure crosses several
   components (CI, build script, service, database), add diagnostics at each
   boundary: what enters, what leaves, which config and environment arrived.
   Run once. The output shows which boundary breaks; investigate that
   component only.
5. **Trace the bad value backwards.** From where it surfaces, ask what passed
   it in, and keep going up the call chain to the place where it is first
   wrong. That place is where the fix goes, not where the error is thrown.

## Phase 2 — Pattern

1. **Find a working analogue** in the same repository: similar code, a sibling
   test, a configuration that works.
2. **List every difference** between the working case and the broken one,
   however small. "That cannot matter" is an assumption, and assumptions are
   what this phase exists to remove.
3. When the code follows a reference implementation, read the reference
   completely rather than skimming it.

In both phases, when the session-start digest says `Codex: available` (no
digest: run `codex.sh available` beside `journal.sh` once), hand the reading
past two or three pinpoint lookups — where the code lives, the call chain,
working analogues and their differences, anything you would otherwise send to
`Explore` or a read-only fork — to `codex.sh explore <prompt-file>`,
asking for facts with `file:line`. Reproducing and instrumenting stay yours,
and so does the hypothesis: confirm each fact it rests on with one `Read` or
`grep`. When `codex.sh explore` exits non-zero, do the reading yourself; on
exit `75` also tell the user once that Codex is off and Claude usage is no
longer being saved.

## Phase 3 — Hypothesis

1. **Write one hypothesis down:** "X is the cause because Y". Say it before
   touching code.
2. **Test it with one minimal change**, one variable at a time.
3. **Confirmed** — go to Phase 4. **Not confirmed** — revert the change and
   form a new hypothesis. A second change stacked on the first leaves you
   unable to tell which one did what.

If you do not understand something, say so and gather more data. Pretending
to know produces a guess with a confident label.

## When a controller invokes you

When a `wolowitz` controller that dispatches implementers invokes you, stop
after Phase 3. Hand back the root cause in one sentence, the evidence that
confirmed it, and the fix the implementer should make. Phase 4 then runs
inside that implementer, who has amy loaded, so the fix goes through review.
When the session has no subagents, the controller is the implementer and
Phase 4 runs as written.

Under a controller, Phases 1–3 stay read-only: read, run commands, and add a
temporary diagnostic only if it is removed before handing back. The
hypothesis is tested by evidence, not by a code change.

## Phase 4 — Fix

Run this phase yourself unless a controller invoked you; see
`## When a controller invokes you`.

1. **Invoke amy** with the Skill tool, as `pasadena:amy`, and follow her for the
   fix.
2. **Write a test that reproduces the bug.** Watch it fail for the reason the
   hypothesis predicts. A different failure means the hypothesis is wrong;
   return to Phase 3.
3. **Make one fix** that addresses the root cause. No bundled refactors, no
   "while I am here" improvements.
4. **Verify** under amy's `## Verify before claiming`: run the reproduction
   test and the full suite, read the output, and show it before saying the bug
   is fixed.

## The rule of three

Count fix attempts. After three failed fixes, stop. Each fix revealing a new
problem somewhere else is the signature of an architectural problem, not of
three unlucky guesses. Tell the user that the design is the likely cause, show
what the three attempts revealed, and ask before trying a fourth.

## Decision rules

| Situation | Rule |
|---|---|
| The cause looks obvious | Phase 1 still runs; for an obvious cause it takes a minute and confirms it. |
| Several fixes at once would save time | One variable per change; otherwise nothing is learned from the result. |
| The error message is long | Read it in full; the answer is often in it. |
| The failure cannot be reproduced | Gather data and add instrumentation; no guessing. |
| Three fixes failed and one more seems close | Stop and ask the user; the problem is likely architectural. |
| The fix works but the cause is unclear | Not done; return to Phase 1 until the cause can be stated. |
| The hypothesis was not confirmed | Revert the change before forming the next hypothesis. |
| The error surfaces deep in the call stack | Trace back to where the value is first wrong and fix there. |
| A working analogue differs in many small ways | List all of them; test them one at a time. |

## Red flags

Any of these thoughts means returning to Phase 1:

- "Quick fix for now, investigate later."
- "Just try changing X and see if it works."
- "It is probably X, let me fix that."
- "I do not fully understand it, but this might work."
- "One more fix attempt" after three have failed.

## Before calling it fixed

- [ ] The root cause is stated in one sentence
- [ ] The reproduction test failed for the predicted reason
- [ ] One fix addressed that cause
- [ ] The full suite is green, with the output shown

Each box is ticked before the bug is called fixed. Otherwise, return to the
phase that is missing.
