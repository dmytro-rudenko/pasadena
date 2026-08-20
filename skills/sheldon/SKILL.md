---

name: sheldon
description: Use when the user asks to write a specification, design a feature, define project scope, add functionality, or change behavior. Classifies the work, explores intent through questions, and produces an agreed specification before implementation begins
----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------

# Shaping

Turn an idea into an agreed design through dialogue, then write the specification that the implementation plan will be based on.

<HARD-GATE>
Until you have fully explained to the user what you intend to do and received their explicit approval, work exclusively in shaping mode: exploration, questions, design, and specification. The codebase remains unchanged, no scaffolding is created, and implementation skills remain outside this phase. This rule applies to every path below. The amount of ceremony scales with the task; explicit approval is always required.
</HARD-GATE>

## Classify first — and say it out loud

Before the first question, name the path you have selected so the user can correct it:

* **Spike** — a feasibility question. "Can we…", "is it possible…",
  "quick and dirty is fine". The outcome of this path is an answer and a
  recommendation. In two or three sentences, state the question and explain
  what you intend to try, get approval, investigate it as cheaply as correctness
  allows, and report the recommendation. The specification and plan remain
  outside this path. Anything created during the investigation remains labelled
  as throwaway.

* **Bounded** — a clearly limited change to a flow that already exists in this
  repository: a flag, a small endpoint, a one-file fix.
  **Bounded is determined by the repository, not by your familiarity** — this
  path applies only when the repository already contains the relevant flow that
  can be inspected. Ask the questions that genuinely matter, present a short
  design *in chat*, and complete the shaping phase. For this path, the shaping
  outcome is the design in chat; a separate specification file and planning
  document remain outside its scope. Implementation begins after explicit user
  approval.

* **Architectural** — a new project, a new subsystem, a change that restructures
  how parts fit together, or a change to an interface that other components
  depend on. Full path: worktree, questions, approaches, sectioned design,
  prototype when there is a user-facing surface, specification, draft PR.

When choosing between two paths, take the heavier one. Classification moves
toward greater rigor: hidden complexity discovered during the task moves the
work to the heavier path. In that case, tell the user about the change and
continue under the rules of the new level. The selected level of rigor can only
stay the same or increase.

## Step 0, architectural only: somewhere to work

Before the first question:

1. Create an isolated worktree using the available Codex workflow; when only
   standard Git is available, use `git worktree add`. All subsequent dialogue
   and work take place in the isolated worktree.
2. Start the journal — `skill raj`. At this stage, `spec:` and `plan:` should
   both be `-`; this tells a resumed session that shaping is still in progress.

Shaping spans multiple sessions more often than any other phase — a long
Socratic dialogue can easily exhaust the available context halfway through.
Creating the worktree and journal at the start makes the process resumable and
ensures that the future specification commit lands in a PR that already exists.

## Understand the idea

First, inspect the current state — files, documentation, and recent commits.
Good questions about code are based on code that has already been read and on
the existing repository context.

**Check the scope before moving into details.** If the request describes several
independent subsystems ("a platform with chat, storage, billing, and analytics"),
state that immediately and help decompose the work. Each part then goes through
its own shaping → planning → building cycle. Establish the correct boundaries
first, then refine the details of each individual part.

Then ask questions:

* **One question per message.** Each additional question gets its own message.
* Use multiple-choice questions when possible; use open-ended questions where
  they provide more useful context.
* Focus on purpose, constraints, and completion criteria. Form your own
  implementation proposals from the context you have gathered.
* Finish the questioning phase when you can clearly state what is being built
  and why. Ask one more important question when necessary: an extra clarification
  is cheaper than a wrong specification. At the same time, keep the dialogue
  focused and concise enough to remain productive.

## Propose approaches

Propose two or three approaches with their trade-offs. Lead with the approach
you recommend and explain why. Apply YAGNI strictly: keep only what is necessary
for the stated goal in each approach, and explicitly name everything that is
intentionally left outside the current scope.

## Present the design

Break the design into sections, scaling each one to its complexity — a few
sentences for straightforward parts and a few paragraphs for more complex ones.
**After each section, ask whether everything looks right so far.** Cover the
architecture, components and their boundaries, data flow, failure handling, and
how the result will be tested.

Design modules so that each one has a single responsibility, communicates
through a clearly defined interface, and can be understood and tested in
isolation. For each module, state three things: what it does, how it is used,
and what it depends on.

In an existing codebase, follow the patterns already present. If the existing
code genuinely makes this specific work harder — for example, a file has grown
too large or a component boundary has become tangled — include a targeted fix
directly related to the current task in the design. Refactoring included in the
design should apply only to code touched by this work.

## The prototype gate

**If the work has a UI or interactive surface, `penny` runs before the
specification is written, and the specification references its `decision.md`.**

This ordering is a fixed part of the framework. First, the interactive
prototype is validated and debugged; then the verified findings are captured
in the specification. This ensures that problems discovered while using the
prototype are accounted for before the design is committed to a document.

For work without a user-facing surface, the equivalent is a spike: the cheapest
investigation that answers the open question, with its result remaining
throwaway afterwards. In both cases, **the specification records only what has
been validated and confirmed.**

## Write the specification

`docs/sdd/specs/YYYY-MM-DD-<slug>.md`. The structure used by this repository:

```markdown
# <Topic> — design

**Date:** YYYY-MM-DD
**Status:** agreed
**Prototype:** docs/sdd/proto/<slug>/decision.md   (when there was one)

## 1. Problem
A concrete description of the current state and the problem, supported by
evidence and observable consequences.

## 2. Constraint that shapes the solution
The factor that determines the chosen approach and explains why the obvious
alternative was rejected. This is often the most valuable section — it
preserves the context behind the decision for future planning.

## 3. Solution
Sections as required by the design. Exact values, exact names.

## 4. Out of scope
What is deliberately left outside this work so the implementation boundaries
remain unambiguous.

## 5. Trade-offs accepted
What becomes worse or less convenient after this change, and why that trade-off
is correct for the stated goal.

## 6. Verification
How anyone can verify that it works.
```

Write the prose in the user's language. Keep paths, identifiers, and commands
verbatim.

Then read the entire specification once with fresh eyes and apply any necessary
fixes immediately:

* **Completeness:** every field and requirement has a concrete final value;
  `TBD` has been replaced with a defined decision.
* **Consistency:** every section supports the same model of the solution.
* **Scope:** the specification fits within one implementation plan; larger
  tasks have already been decomposed.
* **Unambiguity:** every requirement has one clearly documented interpretation.

## Open the PR

Commit the specification, push the branch, and open a **draft** PR whose body
contains the problem and solution from the specification:

```
gh pr create --draft --title "<type>(<scope>): <what>" --body-file <file>
```

The PR is created before the first line of implementation. Every subsequent
wave of work comments on it, so the review receives the reasoning in the right
order and the context behind the decision accumulates gradually. If `gh` or a
remote is unavailable, mention it to the user once and continue the process:
all later phases remain functional regardless of whether the PR exists.

## Then complete the shaping phase

> The spec has been written and committed at `<path>`, and draft PR #N is open.
> Read it and tell me whether anything should change before we move on to the plan.

At this stage, work only with feedback on the specification. If the user asks
for changes, apply them and repeat the self-review. After explicit user
approval, hand the work over to `leonard`.

## Decision rules for ambiguous situations

| Situation                                                        | Rule                                                                                                                                                                                                                     |
| ---------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ |
| The task looks very simple                                       | Simplicity means a short design. Even for a simple task, provide two sentences of design in chat and get approval.                                                                                                       |
| There is uncertainty about whether the task qualifies as bounded | Take the heavier path. Bounded applies only when its boundaries are clearly confirmed by the structure of the repository.                                                                                                |
| The design seems obvious                                         | Implementation begins after explicit approval of the design. Until then, the work remains in shaping mode.                                                                                                               |
| The task resembles a familiar type of application                | Bounded is determined by an existing flow in the repository. Personal familiarity helps analysis, while the structure of the current code determines the classification.                                                 |
| A UI or interactive surface requires validation                  | Validate the prototype first, then transfer the confirmed decisions into the specification. This ensures the specification reflects a validated design from the start.                                                   |
| A spike produces a working result                                | The outcome of a spike is an answer and recommendation, while anything created during the investigation remains throwaway. Moving to a permanent implementation is treated as a separate task with a new classification. |
| Additional complexity is discovered during the work              | Increase the classification immediately, communicate the new scope to the user, and continue under the rules of the heavier path.                                                                                        |
| New work appears after an approved spike                         | Each separate task receives its own classification and its own explicit approval before moving into implementation.                                                                                                      |
