---
name: penny
description: Use when the user asks to prototype the UI, build a browser prototype, compare UI options, or make a design question visible. Shows 2-4 working variants, debugs the chosen one with the user, and records sign-off for the spec
---

# Prototyping

Put working variants in front of the user, then debug the one they pick until
it is right. The specification draws from the resulting record of validated
choices and debug findings.

<HARD-GATE>
A spec for work with a UI surface is written only after this skill has signed
off. The spec therefore describes a design the user has exercised and includes
every issue found during prototype debugging.
</HARD-GATE>

## When

Offer this as soon as the work has a visual or interactive surface. An early
offer ensures visual questions reach the browser while they can still shape the
design.

The test is still per-question: **would the user understand this better by
seeing it than by reading it?** Use the terminal for conceptual UI questions
such as "What does 'compact' mean for this list?" Use the browser for visual
comparisons such as "Which of these three list densities reads better?"

Backend-only work, such as a hook, parser, or migration, uses a spike as its
equivalent evidence: the cheapest investigation that answers the question,
with throwaway output.

## The offer

Send one message containing only this offer:

> Це буде швидше показати, ніж описати. Зберу 2–4 робочі варіанти в браузері —
> покликаєш, поламаєш, скажеш що не так. Відкривати?

Wait for the answer. If they decline, continue in the terminal and offer again
only when they raise it.

## Start the server

The session-start digest hands you the absolute path to the plugin's
`hooks/journal.sh`. The server sits beside it:

    bash "<plugin root>/proto/start.sh" --content-dir docs/sdd/proto/<slug> --open

It prints one line of JSON: `url`, `content_dir`, `state_dir`, `events`.

**Give the user the complete URL, `?key=` and all.** The key authorizes every
request. Stop the server when the phase is over:
`bash "<plugin root>/proto/stop.sh"`.

The digest becomes available after the bundled hooks are trusted. While hook
trust is pending, ask the user to review and trust Pasadena's hook definition
through `/hooks`, then start a new session with the path supplied by the
digest.

The content directory is committed — the variants are the evidence. The state
directory (`.sdd/`) is git-ignored: pid, log, port, key, click events.

## Two shapes of content

**Choice screens** — `docs/sdd/proto/<slug>/screens/<name>.html`. For comparing
approaches: A/B/C options, pros and cons, side-by-side wireframes. Link the
shared stylesheet and write only content:

```html
<!doctype html><html><head><meta charset="utf-8"><title>Layout</title>
<link rel="stylesheet" href="/_sdd/frame.css"></head><body>
<h2>Which layout?</h2>
<div class="options">
  <div class="option" data-choice="a"><span class="letter">A</span>
    <div class="content"><h3>Sidebar</h3><p>Nav stays visible; costs 240px.</p></div></div>
  <div class="option" data-choice="b"><span class="letter">B</span>
    <div class="content"><h3>Top bar</h3><p>Full width; nav truncates on mobile.</p></div></div>
</div></body></html>
```

Classes available from `frame.css`: `.options`/`.option`/`.letter` (add
`data-multiselect` to the container for multi-select), `.cards`/`.card`/`.card-image`,
`.mockup`/`.mockup-header`/`.mockup-body`, `.split`, `.pros-cons`, `.placeholder`,
and the wireframe primitives `.mock-nav`/`.mock-sidebar`/`.mock-content`/`.mock-button`/`.mock-input`.

**Live variants** — `docs/sdd/proto/<slug>/variants/{a,b,c}/index.html`. Real
working HTML/CSS/JS you can click through. Each carries its own design in place
of `frame.css`, and that design is the thing under review.

`/` always serves the newest `.html` in the content directory, so writing a new
screen moves the user's open tab to it. An explicit path remains fixed so a
variant the user is clicking through stays put.

## Rules that keep it useful

- **Always show 2–4 variants.** This range keeps the set focused on one
  decision.
- **Genuinely different approaches.** Each variant names its trade-off. Three
  colour schemes of one layout count as one variant.
- **Real content where it matters.** Placeholder text hides the design problems
  that only long names, empty states and eight-item lists reveal.
- **Write HTML to the file.** The user reads it in the browser, while the
  terminal remains for commands and concise updates.
- **Always use a fresh filename.** `layout.html` → `layout-v2.html`. The history
  of the iteration is worth as much as its result.
- **Scale fidelity to the question.** A wireframe answers "where does it go";
  only a real prototype answers "does this feel right to use".

## The debug loop — this is the point

A picked variant enters the debug loop. Drive it yourself before asking the
user to judge it again:

1. Open it with Playwright or Chrome MCP and **use** it — click through the
   complete flow, including the states beyond the landing view.
2. Read the console. The server answers `/favicon.ico` with 204 precisely so
   every remaining console error belongs to the prototype.
3. Screenshot the states that matter: empty, full, error, narrow viewport.
4. Fix what you find, write the next version, tell the user what changed and
   what to look at.

Loop until the user confirms the problems are resolved. Complete every
necessary iteration before committing the spec.

Read the clicks between turns — they are in the `events` file from the startup
JSON, one JSON object per line:

    {"type":"click","choice":"b","text":"Top bar…","screen":"/","selected":true,"ts":"…"}

Merge them with what the user typed. Treat a click as a signal and ask the user
to resolve any ambiguity it leaves.

## Sign-off

The phase ends when the user says the prototype is right. Write
`docs/sdd/proto/<slug>/decision.md` — short, and the only durable artifact this
phase owes anyone:

```markdown
# <slug> — prototype decision

**Chosen:** variant B (top bar).
**Why:** the sidebar cost 240px that the table needed at 1280px, which only
showed up with real column counts.
**Changed while debugging:** nav collapses to icons under 900px — the original
wrapped to two rows; empty state needed its own copy, the generic one read as
an error.
**Ruled out:** variant C (command palette only) — fast for us, undiscoverable
for a first-time user in testing.
**Open:** the mobile breakpoint is untested below 380px.
```

Then update `## Now`, write a `✎` note, commit the prototype directory, and
hand back to `sheldon`. The spec cites this file and argues from it.

## Decision and acceptance rules

| Situation | Rule |
|---|---|
| The design appears obvious | A ten-minute prototype confirms it or exposes changes before the spec is written. |
| The user picks a variant | The selection starts the debug loop; user sign-off completes the phase. |
| The spec needs visual evidence | Prototype, debug, and sign-off happen before specification writing. |
| The user needs a comparison | Present at least two and at most four genuinely different variants. |
| The prototype looks right in a screenshot | Exercise the live flow and inspect all relevant states before sign-off. |
