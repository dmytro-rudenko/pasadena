---
name: penny
description: Use when the user asks to prototype the UI, build a browser prototype, compare UI options, or make a design question visible. Shows 2-4 working variants, debugs the chosen one with the user, and records sign-off for the spec
---

# Prototyping

Put working variants in front of the user, then debug the one they pick until
it is actually right. The record of what that produced is what the spec is
written from — **not the other way round**.

<HARD-GATE>
A spec for work with a UI surface is not written until this skill has signed
off. A spec written from an undebugged prototype describes a design nobody has
used yet: every problem the debugging would have found becomes a change request
against a spec that is already committed.
</HARD-GATE>

## When

Offer this the moment the work has a visual or interactive surface. Do not wait
for a question so obviously visual that it forces the offer — that is how
superpowers' visual companion ended up never appearing.

The test is still per-question: **would the user understand this better by
seeing it than by reading it?** A question about a UI topic is not automatically
a visual question. "What does 'compact' mean for this list?" is conceptual — ask
it in the terminal. "Which of these three list densities reads better?" is
visual — show it.

Skip it entirely for work with no surface: a hook, a parser, a migration.
For those, the equivalent evidence is a spike — cheapest thing that answers the
question, thrown away afterwards.

## The offer

One message, nothing else in it:

> Це буде швидше показати, ніж описати. Зберу 2–4 робочі варіанти в браузері —
> покликаєш, поламаєш, скажеш що не так. Відкривати?

Wait for the answer. If they decline, continue in the terminal and do not ask
again unless they raise it.

## Start the server

The session-start digest hands you the absolute path to the plugin's
`hooks/journal.sh`. The server sits beside it:

    bash "<plugin root>/proto/start.sh" --content-dir docs/sdd/proto/<slug> --open

It prints one line of JSON: `url`, `content_dir`, `state_dir`, `events`.

**Give the user the complete URL, `?key=` and all.** Without the key every
request is refused. Stop it when the phase is over:
`bash "<plugin root>/proto/stop.sh"`.

If the digest is absent, the bundled hooks were likely not trusted yet. Ask the
user to review and trust Pasadena's hook definition through `/hooks`, then
start a new session instead of guessing an installed-plugin path.

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
working HTML/CSS/JS you can click through. These do **not** link `frame.css`:
they carry their own design, and that design is the thing under review.

`/` always serves the newest `.html` in the content directory, so writing a new
screen moves the user's open tab to it. An explicit path is never redirected —
a variant the user is clicking through stays put.

## Rules that keep it useful

- **2–4 variants, never more.** More than four is a menu, not a decision.
- **Genuinely different approaches.** Three colour schemes of one layout is one
  variant. If you cannot name what each one trades away, you have one variant.
- **Real content where it matters.** Placeholder text hides the design problems
  that only long names, empty states and eight-item lists reveal.
- **Never `cat` or heredoc the HTML into the terminal.** Write the file. The
  user reads it in the browser; dumping it in chat costs tokens and shows less.
- **Never reuse a filename.** `layout.html` → `layout-v2.html`. The history of
  the iteration is worth as much as its result.
- **Scale fidelity to the question.** A wireframe answers "where does it go";
  only a real prototype answers "does this feel right to use".

## The debug loop — this is the point

A picked variant is not a finished one. Drive it yourself before asking the
user to judge it again:

1. Open it with Playwright or Chrome MCP and **use** it — click through the
   real flow, not just the landing state.
2. Read the console. The server answers `/favicon.ico` with 204 precisely so
   that the only errors there are the prototype's own.
3. Screenshot the states that matter: empty, full, error, narrow viewport.
4. Fix what you find, write the next version, tell the user what changed and
   what to look at.

Loop until the user stops finding problems. Every loop you skip becomes a
change request against a committed spec.

Read the clicks between turns — they are in the `events` file from the startup
JSON, one JSON object per line:

    {"type":"click","choice":"b","text":"Top bar…","screen":"/","selected":true,"ts":"…"}

Merge them with what the user typed. A click is a signal, not a decision: ask
about anything the click leaves ambiguous.

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

## Red flags

| Thought | Reality |
|---|---|
| "The design is obvious, I'll write the spec" | Then the prototype costs you ten minutes and confirms it. If it does not confirm it, you just saved a rewrite. |
| "They picked B, we're done" | Picking is the start of this phase, not the end. Debugging is what the spec needs. |
| "I'll prototype after the spec, to validate it" | Then the spec is a guess and the prototype is a change request against it. |
| "One variant is enough, I know what they want" | One variant is a proposal you cannot compare. Two is the minimum that lets them choose. |
| "It looks right in the screenshot" | A screenshot is not a click. Use the flow. |
