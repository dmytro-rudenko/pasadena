---
name: pasadena
description: Use when the user asks to start, resume, plan, or run a Pasadena spec-driven development workflow. Inspects the task journal and routes to the next workflow skill.
---

# Pasadena workflow

Use this skill as the entry point for the full Pasadena workflow.

1. Inspect the current branch, `.pasadena/journal/<branch>.md`, and then the
   legacy `.claude/journal/<branch>.md` only when the canonical file is absent.
2. Route by the persisted state:
   - no journal: `sheldon`;
   - `spec: -`: `sheldon`;
   - `spec:` set and `plan: -`: `leonard`;
   - both set with unchecked plan tasks: `wolowitz`;
   - all tasks checked: `journal` with `finish`.
3. State the detected phase before continuing. Do not restart completed work:
   the journal, plan checkboxes, and git log are the source of truth.
4. For a small one-session fix, let `sheldon` classify it before creating a
   journal. Do not create ceremony merely because this skill was invoked.
