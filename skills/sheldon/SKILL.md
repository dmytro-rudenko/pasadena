---
name: sheldon
description: Use when the user asks to write a spec, design a feature, scope a project, add functionality, or change behaviour. Classifies the work, explores intent through questions, and produces an agreed spec before implementation
---

# Shaping

Turn an idea into an agreed design through dialogue, then write the spec that
the plan will argue from.

<HARD-GATE>
Do not write code, scaffold anything, or invoke an implementation skill until
you have told the user what you intend and they have said yes. This holds on
every path below. The ceremony scales with the task; the approval never does.
</HARD-GATE>

## Classify first, out loud

Before the first question, say which path this is so the user can override you:

- **Spike** — a feasibility question. "Can we…", "is it possible…", "quick and
  dirty is fine". The output is an answer, not code you keep. Say the question
  and what you will try in two or three sentences, get a nod, find out as
  cheaply as correctness allows, report a recommendation. No spec, no plan.
  Anything you built stays labelled throwaway.

- **Bounded** — a well-scoped change to a flow that already exists in this
  repo: a flag, a small endpoint, a one-file fix. **Bounded measures the repo,
  not your familiarity** — if there is no existing flow to read, it is not
  bounded. Ask the questions that matter, present a short design *in chat*, and
  stop. No spec file, no plan document. Implementation starts when they say yes.

- **Architectural** — a new project, a new subsystem, a change that
  restructures how parts fit or alters an interface others depend on. Full
  path: worktree, questions, approaches, sectioned design, prototype if there
  is a surface, spec, draft PR.

When torn between two, take the heavier one. The ratchet is one-way: hidden
complexity discovered mid-task upgrades the path — stop, say so, step up.
Nothing ever downgrades.

## Step 0, architectural only: somewhere to work

Before the first question, not after the design:

1. Create an isolated worktree with the available Codex workflow; if no native
   worktree control is available, use `git worktree add`. The dialogue must
   not happen on trunk.
2. Start the journal — `skill raj`. `spec:` and `plan:` are `-` for
   now; that is what tells a resuming session it is still shaping.

Shaping spans sessions more often than any other phase — a long socratic
dialogue is exactly the thing that runs out of context halfway. Doing this
first is what makes it resumable, and it is why the spec commit will land in a
PR that already exists.

## Understand the idea

Explore the current state first — files, docs, recent commits. You cannot ask
good questions about code you have not read.

**Check the scope before spending questions on details.** If the request
describes several independent subsystems ("a platform with chat, storage,
billing and analytics"), say so immediately and help decompose it. Each piece
then gets its own shaping → planning → building cycle. Refining the details of
something that needs splitting is wasted work.

Then ask questions:

- **One question per message.** If a topic needs more, that is more messages.
- Multiple choice when you can, open when you must.
- Aim at purpose, constraints, and what makes it done — not at implementation
  preferences you should be proposing yourself.
- Stop when you can state what you are building and why, and be honest about
  when that is: asking one more question is cheaper than a wrong spec, and
  asking six more is how a dialogue becomes an interrogation.

## Propose approaches

Two or three, with trade-offs. Lead with your recommendation and say why.
YAGNI ruthlessly — cut everything from every approach that the stated purpose
does not need, and say what you cut.

## Present the design

In sections, each scaled to its complexity — a few sentences when it is
straightforward, up to a few paragraphs when it is not. **Ask after each
section whether it looks right so far.** Cover architecture, the pieces and
their boundaries, data flow, failure handling, and how it gets tested.

Design for units that each do one thing, talk through a stated interface, and
can be understood and tested alone. For each one you should be able to answer:
what does it do, how is it used, what does it depend on.

In an existing codebase: follow the patterns already there. Where existing code
genuinely blocks the work — a file grown too large, a tangled boundary —
include the targeted fix in the design, the way a good developer improves code
they are working in. Do not propose unrelated refactoring.

## The prototype gate

**If the work has a UI or interactive surface, `penny` runs before
the spec is written, and the spec cites its `decision.md`.**

This is the one ordering this framework will not bend. A spec written from an
undebugged prototype is a description of something nobody has used: every
problem the debugging would have surfaced arrives later as a change request
against a document that is already committed and already argued from.

For work with no surface, the equivalent is a spike: the cheapest thing that
answers the open question, thrown away afterwards. Either way, **the spec
records what was validated, never what was assumed.**

## Write the spec

`docs/sdd/specs/YYYY-MM-DD-<slug>.md`. The shape this repo uses:

```markdown
# <Topic> — design

**Date:** YYYY-MM-DD
**Status:** agreed
**Prototype:** docs/sdd/proto/<slug>/decision.md   (when there was one)

## 1. Problem
What is wrong now, concretely, with the evidence. Not "we need X".

## 2. Constraint that shapes the solution
The thing that rules out the obvious approach. Often the most valuable
section — it is what stops the plan re-proposing what you already rejected.

## 3. Solution
Sections as the design needs. Exact values, exact names.

## 4. Out of scope
What this deliberately does not do, so nobody adds it back later.

## 5. Trade-offs accepted
What is worse after this change, and why that is the right trade.

## 6. Verification
How anyone knows it works.
```

Write the prose in the user's language. Keep paths, identifiers and commands
verbatim.

Then re-read it once, with fresh eyes, and fix inline — no second pass:

- **Placeholders:** any "TBD", any vague requirement.
- **Consistency:** does any section contradict another?
- **Scope:** is this one implementation plan's worth, or does it need splitting?
- **Ambiguity:** could a requirement be read two ways? Pick one, write it down.

## Open the PR

Commit the spec, push the branch, and open a **draft** PR whose body is the
spec's problem and solution:

    gh pr create --draft --title "<type>(<scope>): <what>" --body-file <file>

The PR exists before the first line of implementation. Every wave that follows
comments on it, so the review has the reasoning in order instead of arriving as
one wall at the end. No `gh` or no remote? Say so once and carry on — nothing
downstream depends on the PR existing.

## Then stop

> Спека написана і закомічена в `<path>`, PR #N відкритий чернеткою.
> Прочитай і скажи, чи щось міняємо, перш ніж переходити до плану.

Wait. If they want changes, make them and re-run the self-review. Only when
they approve, hand over to `leonard`.

## Red flags

| Thought | Reality |
|---|---|
| "Too simple to need a design" | Simple means a short design, not no design. Two sentences in chat, then approval. |
| "I'll call it bounded and skip the spec" | Reaching for the lighter label *is* the doubt. Take the heavier path. |
| "The design is obvious, I'll start while they read it" | The gate is the approval, not the design's length. |
| "I know this kind of app, so it's bounded" | Bounded measures the repo, not your familiarity. |
| "I'll write the spec now and prototype to validate it" | Then the prototype's findings are change requests against a committed spec. |
| "The spike works, I'll keep the code" | A spike's output is an answer. Keeping it is a new request — classify it. |
| "It grew, but I'm nearly done — no need to re-classify" | Hidden complexity upgrades the path mid-task. Stop and say so. |
| "They approved the spike, so the follow-up is approved" | Every task gets its own classification and its own approval. |
